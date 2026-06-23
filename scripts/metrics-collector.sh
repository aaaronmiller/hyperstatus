#!/usr/bin/env bash
# ============================================================================
#  HYPERSTATUS v3.0 — Metrics & Quota Collector
#  This script runs as a background daemon that collects:
#    1. Compression metrics from RTK and/or Headroom
#    2. Quota data from onWatch, ccusage, LiteLLM, LLM-API-Key-Proxy
#    3. Proxy model detection
#
#  All data is written to shared JSON state files that status bar scripts read.
#
#  Usage: ./metrics-collector.sh [OPTIONS]
#  Options:
#    --rtk              Enable RTK metrics collection
#    --headroom         Enable Headroom proxy metrics
#    --quota            Enable quota data collection (onWatch, ccusage, proxy)
#    --port PORT        Headroom proxy port (default: 8787)
#    --interval SECS    Poll interval (default: 10)
#    --state FILE       Metrics state file (default: /tmp/hyperstatus-metrics.json)
#    --quota-state FILE Quota state file (default: /tmp/hyperstatus-quota.json)
# ============================================================================

set -euo pipefail

STATE_FILE="${HYPERSTATUS_STATE:-/tmp/hyperstatus-metrics.json}"
QUOTA_STATE="${HYPERSTATUS_QUOTA_STATE:-/tmp/hyperstatus-quota.json}"
RTK_ENABLED=false
HEADROOM_ENABLED=false
QUOTA_ENABLED=false
HEADROOM_PORT=8787
INTERVAL=10
QUOTA_INTERVAL=30  # Quota queries are more expensive, poll less often

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rtk) RTK_ENABLED=true; shift ;;
    --headroom) HEADROOM_ENABLED=true; shift ;;
    --quota) QUOTA_ENABLED=true; shift ;;
    --port) HEADROOM_PORT="${2:-8787}"; shift 2 ;;
    --interval) INTERVAL="${2:-10}"; shift 2 ;;
    --state) STATE_FILE="${2:-}"; shift 2 ;;
    --quota-state) QUOTA_STATE="${2:-}"; shift 2 ;;
    *) echo "Unknown option: $1"; shift ;;
  esac
done

# Auto-detect
if command -v rtk &>/dev/null; then RTK_ENABLED=true; fi
if curl -s "http://localhost:${HEADROOM_PORT}/metrics" > /dev/null 2>&1; then
  HEADROOM_ENABLED=true
fi
# Auto-detect quota tools
if command -v ccusage &>/dev/null; then QUOTA_ENABLED=true; fi
if [ -f "${HOME:-/home/chetaz}/.onwatch/data/onwatch.db" ]; then QUOTA_ENABLED=true; fi
if [ -n "${LITELLM_ENDPOINT:-}" ] || [ -n "${LLM_KEY_PROXY_ENDPOINT:-}" ]; then QUOTA_ENABLED=true; fi

echo "HYPERSTATUS Metrics & Quota Collector v3.0"
echo "============================================"
echo "Metrics state: ${STATE_FILE}"
echo "Quota state:   ${QUOTA_STATE}"
echo "Interval:      ${INTERVAL}s (metrics), ${QUOTA_INTERVAL}s (quota)"
echo "RTK:           ${RTK_ENABLED}"
echo "Headroom:      ${HEADROOM_ENABLED} (port ${HEADROOM_PORT})"
echo "Quota:         ${QUOTA_ENABLED}"
echo ""

# Initialize state files
echo '{}' > "$STATE_FILE"
if [ ! -f "$QUOTA_STATE" ]; then
  echo '{}' > "$QUOTA_STATE"
fi

# ============================================================================
#  COMPRESSION METRICS (RTK + Headroom)
# ============================================================================
collect_rtk() {
  if [ "$RTK_ENABLED" != "true" ]; then return; fi
  if ! command -v rtk &>/dev/null; then return; fi

  RTK_DATA=$(rtk gain --json 2>/dev/null || echo '{}')

  RTK_TOTAL_SAVED=$(echo "$RTK_DATA" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('total_tokens_saved', d.get('aggregate', {}).get('tokens_saved', 0)))
except: print(0)
" 2>/dev/null || echo "0")

  RTK_EFFICIENCY=$(echo "$RTK_DATA" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('efficiency_percentage', d.get('aggregate', {}).get('efficiency', 0)))
except: print(0)
" 2>/dev/null || echo "0")

  RTK_COMMANDS=$(echo "$RTK_DATA" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('total_commands', d.get('aggregate', {}).get('commands', 0)))
except: print(0)
" 2>/dev/null || echo "0")

  python3 -c "
import json
with open('$STATE_FILE', 'r') as f: state = json.load(f)
state['rtk_tokens_saved'] = $RTK_TOTAL_SAVED
state['rtk_efficiency'] = $RTK_EFFICIENCY
state['rtk_commands'] = $RTK_COMMANDS
with open('$STATE_FILE', 'w') as f: json.dump(state, f)
" 2>/dev/null

  export RTK_TOKENS_SAVED="$RTK_TOTAL_SAVED"
}

collect_headroom() {
  if [ "$HEADROOM_ENABLED" != "true" ]; then return; fi

  HEADROOM_DATA=$(curl -s "http://localhost:${HEADROOM_PORT}/metrics" 2>/dev/null || echo '{}')

  HEADROOM_SAVED=$(echo "$HEADROOM_DATA" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tokens_saved', d.get('tokensSaved', 0)))
except: print(0)
" 2>/dev/null || echo "0")

  HEADROOM_RATIO=$(echo "$HEADROOM_DATA" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('compression_ratio', d.get('compressionRatio', 0)))
except: print(0)
" 2>/dev/null || echo "0")

  HEADROOM_CACHE_OPT=$(echo "$HEADROOM_DATA" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('cache_optimization_pct', d.get('cacheOptimization', 0)))
except: print(0)
" 2>/dev/null || echo "0")

  python3 -c "
import json
with open('$STATE_FILE', 'r') as f: state = json.load(f)
state['headroom_tokens_saved'] = $HEADROOM_SAVED
state['headroom_compression_ratio'] = $HEADROOM_RATIO
state['headroom_cache_optimization'] = $HEADROOM_CACHE_OPT
with open('$STATE_FILE', 'w') as f: json.dump(state, f)
" 2>/dev/null

  export HEADROOM_TOKENS_SAVED="$HEADROOM_SAVED"
  export HEADROOM_COMPRESSION_RATIO="$HEADROOM_RATIO"
}

# ============================================================================
#  QUOTA COLLECTION
#  Delegates to quota-fetch.sh for the heavy lifting, but we trigger it
#  from our main loop so everything runs in one process.
# ============================================================================
collect_quota() {
  if [ "$QUOTA_ENABLED" != "true" ]; then return; fi

  # Call quota-fetch.sh in one-shot mode
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [ -f "${script_dir}/quota-fetch.sh" ]; then
    bash "${script_dir}/quota-fetch.sh" --state "$QUOTA_STATE" 2>/dev/null || true
  elif command -v quota-fetch &>/dev/null; then
    quota-fetch --state "$QUOTA_STATE" 2>/dev/null || true
  fi
}

# Write env-file format for shell scripts to source
write_env_file() {
  ENV_FILE="/tmp/hyperstatus-env.sh"
  python3 -c "
import json
try:
    with open('$STATE_FILE', 'r') as f: state = json.load(f)
    with open('$ENV_FILE', 'w') as f:
        f.write('# HYPERSTATUS metrics env - sourced by statusline scripts\n')
        for k, v in state.items():
            f.write(f'export {k.upper()}=\"{v}\"\n')
except:
    pass
" 2>/dev/null
}

# --- Main loop ---
echo "Collecting metrics every ${INTERVAL}s, quota every ${QUOTA_INTERVAL}s... (Ctrl+C to stop)"
trap 'echo ""; echo "Stopped."; echo "  Metrics: $STATE_FILE"; echo "  Quota:   $QUOTA_STATE"; exit 0' INT

CYCLE=0
while true; do
  collect_rtk
  collect_headroom
  write_env_file

  # Quota collection is more expensive, do it less often
  if [ $((CYCLE % (QUOTA_INTERVAL / INTERVAL) )) -eq 0 ]; then
    collect_quota
  fi

  CYCLE=$((CYCLE + 1))
  sleep "$INTERVAL"
done
