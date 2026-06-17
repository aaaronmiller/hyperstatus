#!/usr/bin/env bash
# ============================================================================
#  HYPERSTATUS v3.0 — Compression & Quota Proxy Environment Helper
#  Source this file before launching your coding agent CLI
#  Usage: source ./compression-env.sh [headroom|rtk|quota|all]
#
#  Sets up:
#    - Headroom proxy URL (prompt compression)
#    - RTK metrics polling (terminal compression)
#    - Quota fetcher daemon (onWatch, ccusage, LiteLLM, proxy quotas)
#    - LLM-API-Key-Proxy / LiteLLM proxy endpoints
# ============================================================================

# Resolve home directory
if [ -z "${HOME:-}" ] || [ "$HOME" = "/" ]; then
  HOME_DIR="/home/chetaz"
else
  HOME_DIR="$HOME"
fi

# Environment defaults
export HEADROOM_ENDPOINT="${HEADROOM_ENDPOINT:-http://localhost:8787}"
export RTK_METRICS_FILE="${RTK_METRICS_FILE:-/tmp/rtk-metrics.json}"
export HEADROOM_TOKENS_SAVED="${HEADROOM_TOKENS_SAVED:-}"
export HEADROOM_COMPRESSION_RATIO="${HEADROOM_COMPRESSION_RATIO:-}"
export RTK_TOKENS_SAVED="${RTK_TOKENS_SAVED:-}"

# Quota state file (shared by all status bar scripts)
export HYPERSTATUS_QUOTA_STATE="${HYPERSTATUS_QUOTA_STATE:-/tmp/hyperstatus-quota.json}"
export HYPERSTATUS_STATE="${HYPERSTATUS_STATE:-/tmp/hyperstatus-metrics.json}"

# Quota source configuration
export ONWATCH_DB="${ONWATCH_DB:-$HOME_DIR/.onwatch/data/onwatch.db}"
export LITELLM_ENDPOINT="${LITELLM_ENDPOINT:-}"
export LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-}"
export LLM_KEY_PROXY_ENDPOINT="${LLM_KEY_PROXY_ENDPOINT:-}"
export PROXY_QUOTA_ENDPOINT="${PROXY_QUOTA_ENDPOINT:-}"

# If a proxy is actively swapping models, set this explicitly
# so the status bar can detect the mismatch
export PROXY_ACTUAL_MODEL="${PROXY_ACTUAL_MODEL:-}"

MODE="${1:-all}"

echo "HYPERSTATUS v3.0 — Compression & Quota Environment"
echo "===================================================="

# --- Headroom proxy mode ---
if [ "$MODE" = "headroom" ] || [ "$MODE" = "all" ]; then
  export ANTHROPIC_BASE_URL="${HEADROOM_ENDPOINT}/v1"
  export OPENAI_BASE_URL="${HEADROOM_ENDPOINT}/v1"
  echo "[Headroom] API proxy: ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL"
  echo "[Headroom] Start proxy: headroom proxy --port 8787"
  echo "[Headroom] Metrics: ${HEADROOM_ENDPOINT}/metrics"
else
  echo "[Headroom] Skipped (use 'headroom' or 'all' mode)"
fi

# --- RTK metrics mode ---
if [ "$MODE" = "rtk" ] || [ "$MODE" = "all" ]; then
  if command -v rtk &>/dev/null; then
    # Start RTK metrics polling in background
    (
      while true; do
        rtk gain --json > "$RTK_METRICS_FILE" 2>/dev/null || echo '{}' > "$RTK_METRICS_FILE"
        sleep 5
      done
    ) &
    RTK_POLL_PID=$!
    echo "[RTK] Metrics polling started (PID: $RTK_POLL_PID)"
    echo "[RTK] Metrics file: $RTK_METRICS_FILE"
    echo "[RTK] Initialize: rtk init --global"

    # Read initial savings
    if [ -f "$RTK_METRICS_FILE" ]; then
      RTK_SAVED=$(python3 -c "import json; d=json.load(open('$RTK_METRICS_FILE')); print(d.get('total_tokens_saved', 0))" 2>/dev/null || echo "0")
      if [ "$RTK_SAVED" != "0" ]; then
        export RTK_TOKENS_SAVED="$RTK_SAVED"
        echo "[RTK] Current savings: $RTK_SAVED tokens"
      fi
    fi
  else
    echo "[RTK] Not installed. Install: curl -fsSL https://rtk.ai/install | bash"
  fi
else
  echo "[RTK] Skipped (use 'rtk' or 'all' mode)"
fi

# --- Quota collection mode ---
if [ "$MODE" = "quota" ] || [ "$MODE" = "all" ]; then
  echo ""
  echo "[Quota] Configuration:"

  # Check for onWatch
  if [ -f "$ONWATCH_DB" ]; then
    echo "[Quota] onWatch DB found: $ONWATCH_DB"
  else
    echo "[Quota] onWatch DB not found at $ONWATCH_DB"
    echo "[Quota]   Install onWatch: https://github.com/onllm-dev/onwatch"
  fi

  # Check for ccusage
  if command -v ccusage &>/dev/null; then
    echo "[Quota] ccusage detected: $(ccusage --version 2>/dev/null || echo 'installed')"
  else
    echo "[Quota] ccusage not installed. Install: pip install ccusage"
    echo "[Quota]   or: npm install -g ccusage"
  fi

  # Check for LiteLLM proxy
  if [ -n "$LITELLM_ENDPOINT" ]; then
    echo "[Quota] LiteLLM proxy: $LITELLM_ENDPOINT"
    if [ -n "$LITELLM_MASTER_KEY" ]; then
      echo "[Quota]   Master key: configured"
    else
      echo "[Quota]   Master key: NOT SET (set LITELLM_MASTER_KEY for key/budget tracking)"
    fi
  else
    echo "[Quota] LiteLLM proxy: not configured (set LITELLM_ENDPOINT)"
  fi

  # Check for LLM-API-Key-Proxy
  if [ -n "$LLM_KEY_PROXY_ENDPOINT" ]; then
    echo "[Quota] LLM-API-Key-Proxy: $LLM_KEY_PROXY_ENDPOINT"
  else
    echo "[Quota] LLM-API-Key-Proxy: not configured (set LLM_KEY_PROXY_ENDPOINT)"
  fi

  # Check for proxy model override
  if [ -n "$PROXY_ACTUAL_MODEL" ]; then
    echo "[Quota] Proxy model override: $PROXY_ACTUAL_MODEL"
    echo "[Quota]   Status bar will show dual quota (agent-facing + real provider)"
  fi

  # Start quota fetcher daemon if any sources are available
  _HAS_SOURCE=false
  [ -f "$ONWATCH_DB" ] && _HAS_SOURCE=true
  command -v ccusage &>/dev/null && _HAS_SOURCE=true
  [ -n "$LITELLM_ENDPOINT" ] && _HAS_SOURCE=true
  [ -n "$LLM_KEY_PROXY_ENDPOINT" ] && _HAS_SOURCE=true

  if [ "$_HAS_SOURCE" = true ]; then
    # Find quota-fetch.sh
    _SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    _QUOTA_FETCH=""
    if [ -f "${_SCRIPT_DIR}/scripts/quota-fetch.sh" ]; then
      _QUOTA_FETCH="${_SCRIPT_DIR}/scripts/quota-fetch.sh"
    elif [ -f "${_SCRIPT_DIR}/quota-fetch.sh" ]; then
      _QUOTA_FETCH="${_SCRIPT_DIR}/quota-fetch.sh"
    fi

    if [ -n "$_QUOTA_FETCH" ]; then
      # Start quota fetcher daemon in background
      (
        while true; do
          bash "$_QUOTA_FETCH" --state "$HYPERSTATUS_QUOTA_STATE" 2>/dev/null || true
          sleep 30
        done
      ) &
      QUOTA_POLL_PID=$!
      echo "[Quota] Fetcher daemon started (PID: $QUOTA_POLL_PID)"
      echo "[Quota] State file: $HYPERSTATUS_QUOTA_STATE"
    else
      echo "[Quota] quota-fetch.sh not found. Run manually:"
      echo "[Quota]   ./scripts/quota-fetch.sh --daemon"
    fi
  else
    echo "[Quota] No quota sources detected. Install onWatch, ccusage, or configure a proxy."
  fi
fi

echo ""
echo "Environment configured. Start your agent CLI."
echo "  claude   # or: codex, hermes, pi"
echo ""
echo "Status bar will automatically read quota data from:"
echo "  Metrics:  $HYPERSTATUS_STATE"
echo "  Quota:    $HYPERSTATUS_QUOTA_STATE"
echo ""
echo "To stop background processes:"
echo "  kill $RTK_POLL_PID $QUOTA_POLL_PID 2>/dev/null"
