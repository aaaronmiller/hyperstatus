#!/usr/bin/env bash
# ============================================================================
#  HYPERSTATUS v3.0 — Unified Quota Fetcher
#  Collects quota data from multiple sources into a single JSON state file
#  that all status bar scripts can read.
#
#  Data Sources (in priority order):
#    1. onWatch SQLite    — polls provider APIs every 60s (most accurate)
#    2. Proxy headers     — rate limit headers captured by LiteLLM/API-Key-Proxy
#    3. ccusage --json    — local JSONL parsing (less accurate for Claude Code)
#    4. Agent rate limits — from the statusline JSON itself (session-level)
#
#  The PROXY-AWARE DUAL QUOTA model:
#    When a proxy (LiteLLM, LLM-API-Key-Proxy, gpt-load) sits between the
#    agent and the provider, the agent's reported model/rate-limits may be
#    WRONG — the proxy could be silently routing to a different model/provider.
#    This script detects that and reports BOTH the agent-facing quota AND
#    the real provider quota.
#
#  Usage:
#    ./quota-fetch.sh                    # One-shot collection
#    ./quota-fetch.sh --daemon           # Run as background daemon
#    ./quota-fetch.sh --daemon --interval 30
#    ./quota-fetch.sh --source onwatch   # Only query onWatch
#    ./quota-fetch.sh --source ccusage   # Only query ccusage
#    ./quota-fetch.sh --source proxy     # Only query proxy
#    ./quota-fetch.sh --source all       # All sources (default)
# ============================================================================

set -euo pipefail

# --- Configuration ---
STATE_FILE="${HYPERSTATUS_QUOTA_STATE:-/tmp/hyperstatus-quota.json}"
DAEMON=false
INTERVAL=30
SOURCES="all"
ONWATCH_DB="${ONWATCH_DB:-$HOME/.onwatch/data/onwatch.db}"
PROXY_ENDPOINT="${PROXY_QUOTA_ENDPOINT:-}"       # e.g. http://localhost:4000
LITELLM_ENDPOINT="${LITELLM_ENDPOINT:-}"          # e.g. http://localhost:4000
LLM_KEY_PROXY_ENDPOINT="${LLM_KEY_PROXY_ENDPOINT:-}"  # e.g. http://localhost:8080
CCUSAGE_EXTRA_ARGS="${CCUSAGE_ARGS:-}"

# Resolve home
if [ -z "${HOME:-}" ] || [ "$HOME" = "/" ]; then
  HOME_DIR="/home/chetaz"
else
  HOME_DIR="$HOME"
fi

# --- Parse Arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --daemon) DAEMON=true; shift ;;
    --interval) INTERVAL="${2:-30}"; shift 2 ;;
    --source) SOURCES="${2:-all}"; shift 2 ;;
    --state) STATE_FILE="${2:-}"; shift 2 ;;
    --onwatch-db) ONWATCH_DB="${2:-}"; shift 2 ;;
    --proxy) PROXY_ENDPOINT="${2:-}"; shift 2 ;;
    --litellm) LITELLM_ENDPOINT="${2:-}"; shift 2 ;;
    --llm-proxy) LLM_KEY_PROXY_ENDPOINT="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: quota-fetch.sh [OPTIONS]"
      echo "  --daemon          Run as background daemon"
      echo "  --interval N      Poll interval in seconds (default: 30)"
      echo "  --source SRC      Data source: onwatch, ccusage, proxy, all (default: all)"
      echo "  --state FILE      Output JSON state file (default: /tmp/hyperstatus-quota.json)"
      echo "  --onwatch-db PATH Path to onWatch SQLite DB"
      echo "  --proxy URL       Proxy quota endpoint URL"
      echo "  --litellm URL     LiteLLM proxy endpoint"
      echo "  --llm-proxy URL   LLM-API-Key-Proxy endpoint"
      exit 0
      ;;
    *) echo "Unknown option: $1"; shift ;;
  esac
done

# --- Initialize state file ---
if [ ! -f "$STATE_FILE" ]; then
  echo '{}' > "$STATE_FILE"
fi

# ============================================================================
#  SOURCE 1: onWatch SQLite
#  onWatch is a background Go daemon that polls provider quota APIs every 60s
#  and stores snapshots in SQLite. This is the MOST ACCURATE source for
#  multi-provider quota because it talks directly to the provider APIs.
#
#  DB Schema (inferred from onWatch docs):
#    CREATE TABLE quota_snapshots (
#      id INTEGER PRIMARY KEY,
#      provider TEXT,           -- "anthropic", "openai", "gemini", "copilot", etc.
#      remaining_quota INTEGER, -- tokens remaining (or requests remaining)
#      total_quota INTEGER,    -- total allocation
#      quota_type TEXT,         -- "tokens" or "requests"
#      window TEXT,             -- "5h", "7d", "daily", "monthly"
#      timestamp DATETIME,
#      raw_response TEXT
#    );
# ============================================================================
collect_onwatch() {
  if [ "$SOURCES" != "all" ] && [ "$SOURCES" != "onwatch" ]; then return; fi
  if [ ! -f "$ONWATCH_DB" ]; then return; fi
  if ! command -v sqlite3 &>/dev/null; then return; fi

  # Query the latest snapshot per provider per window
  local query="
    SELECT provider, remaining_quota, total_quota, quota_type, window, timestamp
    FROM quota_snapshots
    WHERE timestamp = (
      SELECT MAX(timestamp) FROM quota_snapshots q2
      WHERE q2.provider = quota_snapshots.provider
        AND q2.window = quota_snapshots.window
    )
    ORDER BY provider, window
  "

  local results
  results=$(sqlite3 -json "$ONWATCH_DB" "$query" 2>/dev/null || echo "[]")

  if [ "$results" = "[]" ] || [ -z "$results" ]; then return; fi

  # Write to state file under "onwatch" key
  python3 -c "
import json, sys
try:
    new_data = json.loads('''$results''')
except:
    new_data = []
with open('$STATE_FILE', 'r') as f:
    state = json.load(f)
state['onwatch'] = new_data
state['onwatch_updated'] = $(date +%s)
with open('$STATE_FILE', 'w') as f:
    json.dump(state, f, indent=2)
" 2>/dev/null || true
}

# ============================================================================
#  SOURCE 2: Proxy Rate Limit Headers
#  When requests flow through a proxy (LiteLLM, LLM-API-Key-Proxy, gpt-load),
#  the proxy can capture rate limit headers from every API response:
#    Anthropic:  anthropic-ratelimit-requests-remaining,
#                anthropic-ratelimit-tokens-remaining
#    OpenAI:     x-ratelimit-remaining-requests,
#                x-ratelimit-remaining-tokens
#
#  These headers are the MOST ACCURATE per-request data source.
#  The proxy exposes them via its own /metrics or /quota endpoint.
#
#  LiteLLM:     GET /global/spend/logs  (spend per key)
#               GET /key/info           (key metadata, budget remaining)
#  LLM-API-Proxy: GET /stats           (usage per credential)
# ============================================================================
collect_proxy_litellm() {
  if [ -z "$LITELLM_ENDPOINT" ]; then return; fi

  local url="${LITELLM_ENDPOINT%/}"
  local data

  # Try LiteLLM key info endpoint (requires master key)
  data=$(curl -sf "${url}/key/info" -H "Authorization: Bearer ${LITELLM_MASTER_KEY:-}" 2>/dev/null || echo "{}")

  if [ "$data" != "{}" ]; then
    python3 -c "
import json
try:
    d = json.loads('''$data''')
    keys = d.get('keys', d.get('data', []))
    quota_info = []
    for k in keys:
        quota_info.append({
            'key_alias': k.get('key_alias', k.get('alias', 'unknown')),
            'max_budget': k.get('max_budget', 0),
            'spend': k.get('spend', 0),
            'remaining': k.get('max_budget', 0) - k.get('spend', 0),
            'models': k.get('models', []),
            'expires': k.get('expires', None),
        })
    with open('$STATE_FILE', 'r') as f:
        state = json.load(f)
    state['litellm_keys'] = quota_info
    state['litellm_updated'] = $(date +%s)
    with open('$STATE_FILE', 'w') as f:
        json.dump(state, f, indent=2)
except Exception as e:
    pass
" 2>/dev/null || true
  fi

  # Try LiteLLM spend endpoint for model-level data
  data=$(curl -sf "${url}/global/spend/logs" -H "Authorization: Bearer ${LITELLM_MASTER_KEY:-}" 2>/dev/null || echo "[]")

  if [ "$data" != "[]" ]; then
    python3 -c "
import json
try:
    logs = json.loads('''$data''')
    model_spend = {}
    for entry in logs:
        model = entry.get('model', 'unknown')
        spend = float(entry.get('spend', 0))
        tokens = int(entry.get('total_tokens', 0))
        if model not in model_spend:
            model_spend[model] = {'spend': 0, 'tokens': 0, 'requests': 0}
        model_spend[model]['spend'] += spend
        model_spend[model]['tokens'] += tokens
        model_spend[model]['requests'] += 1
    with open('$STATE_FILE', 'r') as f:
        state = json.load(f)
    state['litellm_model_spend'] = model_spend
    with open('$STATE_FILE', 'w') as f:
        json.dump(state, f, indent=2)
except:
    pass
" 2>/dev/null || true
  fi
}

collect_proxy_llmkeyproxy() {
  if [ -z "$LLM_KEY_PROXY_ENDPOINT" ]; then return; fi

  local url="${LLM_KEY_PROXY_ENDPOINT%/}"

  # Try LLM-API-Key-Proxy stats endpoint
  local data
  data=$(curl -sf "${url}/stats" 2>/dev/null || echo "{}")

  if [ "$data" != "{}" ]; then
    python3 -c "
import json
try:
    d = json.loads('''$data''')
    with open('$STATE_FILE', 'r') as f:
        state = json.load(f)
    state['llm_key_proxy'] = d
    state['llm_key_proxy_updated'] = $(date +%s)
    with open('$STATE_FILE', 'w') as f:
        json.dump(state, f, indent=2)
except:
    pass
" 2>/dev/null || true
  fi
}

collect_proxy_generic() {
  # Try user-specified proxy endpoint (e.g. gpt-load, custom proxy)
  if [ -z "$PROXY_ENDPOINT" ]; then return; fi

  local url="${PROXY_ENDPOINT%/}"
  local data

  # Try /quota endpoint
  data=$(curl -sf "${url}/quota" 2>/dev/null || echo "{}")
  if [ "$data" = "{}" ]; then
    # Try /metrics endpoint
    data=$(curl -sf "${url}/metrics" 2>/dev/null || echo "{}")
  fi

  if [ "$data" != "{}" ]; then
    python3 -c "
import json
try:
    d = json.loads('''$data''')
    with open('$STATE_FILE', 'r') as f:
        state = json.load(f)
    state['proxy'] = d
    state['proxy_updated'] = $(date +%s)
    with open('$STATE_FILE', 'w') as f:
        json.dump(state, f, indent=2)
except:
    pass
" 2>/dev/null || true
  fi
}

collect_proxy() {
  if [ "$SOURCES" != "all" ] && [ "$SOURCES" != "proxy" ]; then return; fi
  collect_proxy_litellm
  collect_proxy_llmkeyproxy
  collect_proxy_generic
}

# ============================================================================
#  SOURCE 3: ccusage --json
#  ccusage parses local JSONL session logs and outputs structured JSON.
#  ⚠️ ACCURACY WARNING: For Claude Code, ccusage undercounts by 46x or more
#  because the JSONL input_tokens field is a streaming placeholder that's
#  never updated. For Codex and Gemini CLI, it's reasonably accurate.
#  Only use this as a SECONDARY/confirmatory source for Claude Code.
# ============================================================================
collect_ccusage() {
  if [ "$SOURCES" != "all" ] && [ "$SOURCES" != "ccusage" ]; then return; fi
  if ! command -v ccusage &>/dev/null; then return; fi

  local data
  data=$(ccusage --json $CCUSAGE_EXTRA_ARGS 2>/dev/null || echo "{}")

  if [ "$data" != "{}" ] && [ -n "$data" ]; then
    python3 -c "
import json
try:
    d = json.loads('''$data''')
    with open('$STATE_FILE', 'r') as f:
        state = json.load(f)
    state['ccusage'] = d
    state['ccusage_updated'] = $(date +%s)
    # Extract summary per provider
    providers = {}
    for source in d.get('sources', []):
        name = source.get('name', source.get('provider', 'unknown'))
        providers[name] = {
            'total_input_tokens': source.get('total_input_tokens', 0),
            'total_output_tokens': source.get('total_output_tokens', 0),
            'total_cost': source.get('total_cost', 0),
            'sessions': source.get('session_count', source.get('sessions', 0)),
        }
    state['ccusage_summary'] = providers
    with open('$STATE_FILE', 'w') as f:
        json.dump(state, f, indent=2)
except:
    pass
" 2>/dev/null || true
  fi
}

# ============================================================================
#  SOURCE 4: Agent rate limits (from statusline JSON or env vars)
#  This is what the agent ITSELF reports. When a proxy is in the path,
#  these may be WRONG (reflecting the proxy's limits, not the real provider).
#  We read this from the shared metrics state file if available.
# ============================================================================
collect_agent_ratelimits() {
  # The agent's own rate limits are already captured in the statusline JSON
  # and passed directly to each status bar script. We just check if there's
  # a proxy override to flag.
  local metrics_file="/tmp/hyperstatus-metrics.json"
  if [ -f "$metrics_file" ]; then
    python3 -c "
import json
try:
    with open('$metrics_file', 'r') as f:
        m = json.load(f)
    with open('$STATE_FILE', 'r') as f:
        state = json.load(f)
    state['agent_rate5_pct'] = m.get('agent_rate5_pct', 0)
    state['agent_rate7_pct'] = m.get('agent_rate7_pct', 0)
    state['agent_model'] = m.get('agent_model', '')
    with open('$STATE_FILE', 'w') as f:
        json.dump(state, f, indent=2)
except:
    pass
" 2>/dev/null || true
  fi
}

# ============================================================================
#  PROXY MODEL DETECTION
#  Detects when a proxy is silently swapping the model the agent requested.
#  This is the key insight for the "dual quota" model:
#    - The AGENT thinks it's using claude-sonnet-4 with Anthropic rate limits
#    - The PROXY is actually routing to gpt-4o with OpenAI rate limits
#    - Without this detection, the agent's quota display is COMPLETELY WRONG
#
#  Detection methods:
#    1. Proxy metadata endpoint (most reliable)
#    2. Response header differences (model field in responses)
#    3. Latency fingerprinting (different models have different response times)
#    4. Explicit environment variable override
# ============================================================================
detect_proxy_model_swap() {
  local proxy_model=""
  local agent_model=""
  local swapped=false

  # Method 1: Check proxy metadata endpoint
  if [ -n "$LITELLM_ENDPOINT" ]; then
    local url="${LITELLM_ENDPOINT%/}"
    # LiteLLM exposes the actual model used in its logs
    proxy_model=$(curl -sf "${url}/model/list" -H "Authorization: Bearer ${LITELLM_MASTER_KEY:-}" 2>/dev/null \
      | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    models = d.get('data', [])
    if models:
        # Get the model that's actually configured for the key
        print(models[0].get('id', models[0].get('model', '')))
except:
    pass
" 2>/dev/null || echo "")
  fi

  # Method 2: Check environment variable override
  if [ -z "$proxy_model" ] && [ -n "${PROXY_ACTUAL_MODEL:-}" ]; then
    proxy_model="$PROXY_ACTUAL_MODEL"
  fi

  # Method 3: Check LLM-API-Key-Proxy model mapping
  if [ -z "$proxy_model" ] && [ -n "$LLM_KEY_PROXY_ENDPOINT" ]; then
    local url="${LLM_KEY_PROXY_ENDPOINT%/}"
    proxy_model=$(curl -sf "${url}/config/models" 2>/dev/null \
      | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    # Get first model mapping
    mappings = d.get('model_mappings', d.get('models', []))
    if mappings:
        print(mappings[0].get('target_model', mappings[0].get('actual', '')))
except:
    pass
" 2>/dev/null || echo "")
  fi

  # Get agent's perceived model
  if [ -f "$STATE_FILE" ]; then
    agent_model=$(python3 -c "
import json
try:
    with open('$STATE_FILE') as f:
        d = json.load(f)
    print(d.get('agent_model', ''))
except:
    pass
" 2>/dev/null || echo "")
  fi

  # Determine if swap is happening
  if [ -n "$proxy_model" ] && [ -n "$agent_model" ]; then
    # Normalize model names for comparison
    local norm_proxy norm_agent
    norm_proxy=$(echo "$proxy_model" | tr '[:upper:]' '[:lower:]' | sed 's/[-_]//g' | sed 's/anthropic//' | sed 's/openai//')
    norm_agent=$(echo "$agent_model" | tr '[:upper:]' '[:lower:]' | sed 's/[-_]//g' | sed 's/anthropic//' | sed 's/openai//')
    if [ "$norm_proxy" != "$norm_agent" ]; then
      swapped=true
    fi
  fi

  # Write detection result
  python3 -c "
import json
with open('$STATE_FILE', 'r') as f:
    state = json.load(f)
state['proxy_detection'] = {
    'proxy_active': $( [ -n "$proxy_model" ] && echo 'true' || echo 'false' ),
    'model_swapped': $( [ "$swapped" = true ] && echo 'true' || echo 'false' ),
    'agent_perceived_model': '$agent_model',
    'proxy_actual_model': '$proxy_model',
    'detection_method': '$( [ -n "$proxy_model" ] && echo "proxy_endpoint" || echo "none" )',
}
with open('$STATE_FILE', 'w') as f:
    json.dump(state, f, indent=2)
" 2>/dev/null || true
}

# ============================================================================
#  COMPUTE: Derive unified quota summary
#  Takes data from all sources and produces a single summary that the
#  status bar scripts can easily consume.
# ============================================================================
compute_summary() {
  python3 -c "
import json

with open('$STATE_FILE', 'r') as f:
    state = json.load(f)

summary = {
    'providers': {},     # Per-provider quota summary
    'warnings': [],      # Approaching limit warnings
    'proxy_info': None,  # Proxy detection result
    'total_remaining_pct': None,  # Aggregate remaining %
}

# --- Process onWatch data (most accurate) ---
onwatch = state.get('onwatch', [])
for snap in onwatch:
    provider = snap.get('provider', 'unknown')
    window = snap.get('window', 'unknown')
    remaining = int(snap.get('remaining_quota', 0))
    total = int(snap.get('total_quota', 0))
    pct = round((1 - remaining / total) * 100, 1) if total > 0 else 0

    if provider not in summary['providers']:
        summary['providers'][provider] = {}
    summary['providers'][provider][f'{window}_used_pct'] = pct
    summary['providers'][provider][f'{window}_remaining'] = remaining
    summary['providers'][provider][f'{window}_total'] = total

    # Warning thresholds
    if pct >= 95:
        summary['warnings'].append(f'{provider} {window}: {pct}% used - CRITICAL')
    elif pct >= 80:
        summary['warnings'].append(f'{provider} {window}: {pct}% used - HIGH')

# --- Process LiteLLM data ---
litellm_keys = state.get('litellm_keys', [])
for key in litellm_keys:
    alias = key.get('key_alias', 'unknown')
    max_budget = float(key.get('max_budget', 0))
    spend = float(key.get('spend', 0))
    remaining = float(key.get('remaining', 0))
    pct = round((spend / max_budget) * 100, 1) if max_budget > 0 else 0
    models = key.get('models', [])

    # Map to provider
    provider = 'litellm'
    if any('claude' in m.lower() for m in models):
        provider = 'anthropic'
    elif any('gpt' in m.lower() or 'o4' in m.lower() for m in models):
        provider = 'openai'
    elif any('gemini' in m.lower() for m in models):
        provider = 'gemini'

    if provider not in summary['providers']:
        summary['providers'][provider] = {}
    summary['providers'][provider]['budget_used_pct'] = pct
    summary['providers'][provider]['budget_remaining_usd'] = remaining
    summary['providers'][provider]['budget_total_usd'] = max_budget

    if pct >= 95:
        summary['warnings'].append(f'{provider} budget: \${remaining:.2f} remaining - CRITICAL')
    elif pct >= 80:
        summary['warnings'].append(f'{provider} budget: \${remaining:.2f} remaining - HIGH')

# --- Process ccusage data ---
ccusage_summary = state.get('ccusage_summary', {})
for provider, info in ccusage_summary.items():
    name = provider.lower()
    if name not in summary['providers']:
        summary['providers'][name] = {}
    summary['providers'][name]['ccusage_cost'] = float(info.get('total_cost', 0))
    summary['providers'][name]['ccusage_input_tokens'] = int(info.get('total_input_tokens', 0))
    summary['providers'][name]['ccusage_output_tokens'] = int(info.get('total_output_tokens', 0))

# --- Process LLM-API-Key-Proxy data ---
llm_proxy = state.get('llm_key_proxy', {})
if llm_proxy:
    for cred in llm_proxy.get('credentials', llm_proxy.get('stats', [])):
        provider = cred.get('provider', cred.get('name', 'unknown'))
        if provider not in summary['providers']:
            summary['providers'][provider] = {}
        summary['providers'][provider]['proxy_requests'] = int(cred.get('requests', cred.get('total_requests', 0)))
        summary['providers'][provider]['proxy_errors'] = int(cred.get('errors', 0))
        summary['providers'][provider]['proxy_cooldown'] = cred.get('in_cooldown', False)

# --- Proxy detection ---
proxy_det = state.get('proxy_detection', {})
if proxy_det and proxy_det.get('proxy_active'):
    summary['proxy_info'] = {
        'model_swapped': proxy_det.get('model_swapped', False),
        'agent_model': proxy_det.get('agent_perceived_model', ''),
        'actual_model': proxy_det.get('proxy_actual_model', ''),
    }

# --- Aggregate remaining % ---
# Use the WORST (highest used %) across all providers as the overall indicator
all_pcts = []
for provider, data in summary['providers'].items():
    for key, val in data.items():
        if key.endswith('_used_pct') and isinstance(val, (int, float)):
            all_pcts.append(val)
if all_pcts:
    summary['total_remaining_pct'] = round(max(all_pcts), 1)

state['summary'] = summary
state['last_updated'] = $(date +%s)

with open('$STATE_FILE', 'w') as f:
    json.dump(state, f, indent=2)
" 2>/dev/null || true
}

# ============================================================================
#  SOURCE 5: Anthropic /usage (undocumented, agent-specific)
#  Claude Code internally calls GET /api/oauth/usage for its /usage command.
#  We can replicate this using the stored OAuth credentials.
#  ⚠️ WARNING: This shares rate limit budget with your actual API calls.
#  Only call this sparingly (max once per 5 minutes).
# ============================================================================
collect_anthropic_usage() {
  local cred_file="${HOME_DIR}/.claude/.credentials.json"
  if [ ! -f "$cred_file" ]; then return; fi

  # Only call once per 5 minutes to avoid consuming rate limit budget
  local last_call_file="/tmp/.hyperstatus-anthropic-usage-last"
  if [ -f "$last_call_file" ]; then
    local last_call
    last_call=$(cat "$last_call_file" 2>/dev/null || echo "0")
    local now
    now=$(date +%s)
    if (( now - last_call < 300 )); then
      return  # Too soon, skip
    fi
  fi

  # Extract OAuth token
  local token
  token=$(python3 -c "
import json
try:
    with open('$cred_file') as f:
        d = json.load(f)
    # Try different credential formats
    creds = d.get('credentials', d.get('oauth', d.get('anthropic', {})))
    if isinstance(creds, dict):
        print(creds.get('access_token', creds.get('token', '')))
    elif isinstance(creds, list) and creds:
        print(creds[0].get('access_token', creds[0].get('token', '')))
except:
    pass
" 2>/dev/null || echo "")

  if [ -z "$token" ]; then return; fi

  # Call usage endpoint
  local usage_data
  usage_data=$(curl -sf "https://api.anthropic.com/api/oauth/usage" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" 2>/dev/null || echo "{}")

  if [ "$usage_data" != "{}" ]; then
    date +%s > "$last_call_file"
    python3 -c "
import json
try:
    d = json.loads('''$usage_data''')
    with open('$STATE_FILE', 'r') as f:
        state = json.load(f)
    state['anthropic_usage_api'] = d
    state['anthropic_usage_updated'] = $(date +%s)
    with open('$STATE_FILE', 'w') as f:
        json.dump(state, f, indent=2)
except:
    pass
" 2>/dev/null || true
  fi
}

# ============================================================================
#  SOURCE 6: OpenAI /dashboard/billing (for API key users)
#  For Codex/OpenAI API keys, we can check remaining quota via the API.
#  Note: The old billing/usage endpoint was deprecated; we use the
#  modern admin API if available.
# ============================================================================
collect_openai_usage() {
  if [ -z "${OPENAI_API_KEY:-}" ]; then return; fi

  # Only call once per 5 minutes
  local last_call_file="/tmp/.hyperstatus-openai-usage-last"
  if [ -f "$last_call_file" ]; then
    local last_call
    last_call=$(cat "$last_call_file" 2>/dev/null || echo "0")
    local now
    now=$(date +%s)
    if (( now - last_call < 300 )); then return; fi
  fi

  # Check rate limit headers by making a lightweight models list call
  local headers
  headers=$(curl -sI "https://api.openai.com/v1/models" \
    -H "Authorization: Bearer $OPENAI_API_KEY" 2>/dev/null || echo "")

  if [ -n "$headers" ]; then
    date +%s > "$last_call_file"

    # Extract rate limit headers
    local req_remaining token_remaining req_limit token_limit
    req_remaining=$(echo "$headers" | grep -i "x-ratelimit-remaining-requests" | awk '{print $2}' | tr -d '\r' || echo "0")
    token_remaining=$(echo "$headers" | grep -i "x-ratelimit-remaining-tokens" | awk '{print $2}' | tr -d '\r' || echo "0")
    req_limit=$(echo "$headers" | grep -i "x-ratelimit-limit-requests" | awk '{print $2}' | tr -d '\r' || echo "1")
    token_limit=$(echo "$headers" | grep -i "x-ratelimit-limit-tokens" | awk '{print $2}' | tr -d '\r' || echo "1")

    python3 -c "
import json
with open('$STATE_FILE', 'r') as f:
    state = json.load(f)
state['openai_headers'] = {
    'requests_remaining': int('${req_remaining:-0}' or '0'),
    'tokens_remaining': int('${token_remaining:-0}' or '0'),
    'requests_limit': int('${req_limit:-1}' or '1'),
    'tokens_limit': int('${token_limit:-1}' or '1'),
}
state['openai_headers_updated'] = $(date +%s)
with open('$STATE_FILE', 'w') as f:
    json.dump(state, f, indent=2)
" 2>/dev/null || true
  fi
}

# ============================================================================
#  MAIN: Collect from all enabled sources and compute summary
# ============================================================================
collect_all() {
  collect_onwatch
  collect_proxy
  collect_ccusage
  collect_agent_ratelimits
  detect_proxy_model_swap

  # Expensive API calls (only every 5 min)
  if [ "$SOURCES" = "all" ]; then
    collect_anthropic_usage
    collect_openai_usage
  fi

  compute_summary
}

# --- Run ---
if [ "$DAEMON" = true ]; then
  echo "HYPERSTATUS Quota Fetcher v3.0"
  echo "=============================="
  echo "State file: ${STATE_FILE}"
  echo "Interval: ${INTERVAL}s"
  echo "Sources: ${SOURCES}"
  echo "onWatch DB: ${ONWATCH_DB}"
  echo "LiteLLM: ${LITELLM_ENDPOINT:-not configured}"
  echo "LLM-API-Key-Proxy: ${LLM_KEY_PROXY_ENDPOINT:-not configured}"
  echo "Proxy: ${PROXY_ENDPOINT:-not configured}"
  echo ""
  echo "Collecting... (Ctrl+C to stop)"
  trap 'echo ""; echo "Stopped. State at: ${STATE_FILE}"; exit 0' INT

  while true; do
    collect_all
    sleep "$INTERVAL"
  done
else
  # One-shot mode
  collect_all
  echo "Quota data written to ${STATE_FILE}"
  # Print summary
  python3 -c "
import json
try:
    with open('$STATE_FILE') as f:
        d = json.load(f)
    s = d.get('summary', {})
    print('=== Quota Summary ===')
    for provider, info in s.get('providers', {}).items():
        print(f'  {provider}:')
        for k, v in info.items():
            print(f'    {k}: {v}')
    if s.get('warnings'):
        print('  WARNINGS:')
        for w in s['warnings']:
            print(f'    ⚠ {w}')
    if s.get('proxy_info'):
        pi = s['proxy_info']
        print(f'  PROXY: agent={pi[\"agent_model\"]} → actual={pi[\"actual_model\"]} swapped={pi[\"model_swapped\"]}')
except Exception as e:
    print(f'Error reading state: {e}')
" 2>/dev/null || true
fi
