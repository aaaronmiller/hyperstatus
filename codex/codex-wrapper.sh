#!/usr/bin/env bash
# ============================================================================
#  HYPERSTATUS v3.0 — Codex CLI tmux Wrapper
#  Provides a full-featured status bar AROUND the Codex TUI by running
#  Codex inside tmux with a custom status bar that shows ALL features + QUOTA.
#
#  v3.0 NEW: Multi-provider quota from onWatch/ccusage/LiteLLM,
#  proxy model detection, budget remaining display.
#
#  Usage: ./codex-wrapper.sh [codex arguments...]
# ============================================================================

set -euo pipefail

SESSION_NAME="codex-hyperstatus-$$"

# Resolve home
HOME_DIR="${HOME:-/home/chetaz}"

# --- Read quota state from shared JSON ---
quota_val() {
  local key="$1"
  local default="${2:-0}"
  if [ -f /tmp/hyperstatus-quota.json ]; then
    python3 -c "
import json
try:
    with open('/tmp/hyperstatus-quota.json') as f:
        d = json.load(f)
    keys = '$key'.split('.')
    v = d
    for k in keys:
        if isinstance(v, dict) and k in v:
            v = v[k]
        else:
            v = '$default'
            break
    print(v)
except:
    print('$default')
" 2>/dev/null || echo "$default"
  else
    echo "$default"
  fi
}

# --- tmux status bar renderer ---
render_status() {
  # Model
  MODEL="codex"
  SHORT_MODEL="o4-mini"
  if [ -n "${CODEX_MODEL:-}" ]; then
    SHORT_MODEL=$(echo "$CODEX_MODEL" | sed 's/claude-/c/' | sed 's/-202.*//')
  fi

  # Context
  CTX_PCT="${CODEX_CONTEXT_PCT:-0}"
  CTX_SIZE="${CODEX_CONTEXT_SIZE:-200000}"
  INPUT_TOKENS="${CODEX_INPUT_TOKENS:-0}"
  OUTPUT_TOKENS="${CODEX_OUTPUT_TOKENS:-0}"
  TOTAL_TOKENS=$((INPUT_TOKENS + OUTPUT_TOKENS))

  # Cache
  CACHE_READ="${CODEX_CACHE_READ:-0}"
  if [ "$INPUT_TOKENS" -gt 0 ] && [ "$CACHE_READ" -gt 0 ]; then
    CACHE_PCT=$(echo "scale=0; $CACHE_READ * 100 / $INPUT_TOKENS" | bc 2>/dev/null || echo "0")
  else
    CACHE_PCT="0"
  fi

  # Cost
  TOTAL_COST="${CODEX_SESSION_COST:-0}"

  # Duration
  if [ -n "${CODEX_SESSION_START:-}" ]; then
    NOW_MS=$(date +%s%3N)
    DURATION_MS=$((NOW_MS - CODEX_SESSION_START))
  else
    DURATION_MS="0"
  fi
  DUR_S=$((DURATION_MS / 1000))
  DUR_M=$((DUR_S / 60))
  DUR_H=$((DUR_M / 60))
  if [ "$DUR_H" -gt 0 ]; then DUR_FMT="${DUR_H}h$((DUR_M % 60))m"
  elif [ "$DUR_M" -gt 0 ]; then DUR_FMT="${DUR_M}m"
  else DUR_FMT="${DUR_S}s"
  fi

  # Agent rate limits
  RATE5="${CODEX_RATE5_PCT:-0}"
  RATE7="${CODEX_RATE7_PCT:-0}"

  # Throughput
  API_DUR="${CODEX_API_DURATION_MS:-0}"
  if [ "$API_DUR" -gt 0 ] && [ "$OUTPUT_TOKENS" -gt 0 ]; then
    TOK_PER_S=$(echo "scale=1; $OUTPUT_TOKENS * 1000 / $API_DUR" | bc 2>/dev/null || echo "0")
  else
    TOK_PER_S="0"
  fi

  # Project / Git
  PROJECT_DIR="$(pwd)"
  PROJECT_DISPLAY=$(basename "$PROJECT_DIR")
  GIT_BRANCH=""
  GIT_STAGED=0; GIT_UNSTAGED=0; GIT_UNTRACKED=0
  if command -v git &>/dev/null; then
    GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [ -n "$GIT_BRANCH" ]; then
      GIT_STAGED=$(git diff --cached --numstat 2>/dev/null | wc -l || echo "0")
      GIT_UNSTAGED=$(git diff --numstat 2>/dev/null | wc -l || echo "0")
      GIT_UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l || echo "0")
    fi
  fi

  # Compression
  RTK_SAVED="${RTK_TOKENS_SAVED:-}"
  COMP_DISPLAY=""
  if [ -n "$RTK_SAVED" ] && [ "$RTK_SAVED" != "0" ]; then
    if [ "$RTK_SAVED" -ge 1000 ]; then
      COMP_DISPLAY=" ▼$(echo "scale=1; $RTK_SAVED/1000" | bc)K"
    else
      COMP_DISPLAY=" ▼${RTK_SAVED}"
    fi
  fi

  # Permission
  PERM_DISPLAY=""
  if [ "${CODEX_YOLO:-}" = "1" ]; then PERM_DISPLAY=" Y"
  elif [ "${CODEX_AUTO_APPROVE:-}" = "1" ]; then PERM_DISPLAY=" A"
  fi

  # ==============================================================================
  #  QUOTA DATA (v3.0)
  # ==============================================================================
  PROXY_MODEL_SWAPPED=$(quota_val "summary.proxy_info.model_swapped" "false")
  PROXY_AGENT_MODEL=$(quota_val "summary.proxy_info.agent_model" "")
  PROXY_ACTUAL_MODEL=$(quota_val "summary.proxy_info.actual_model" "")

  ANTHROPIC_5H_PCT=$(quota_val "summary.providers.anthropic.5h_used_pct" "")
  ANTHROPIC_7D_PCT=$(quota_val "summary.providers.anthropic.7d_used_pct" "")
  OPENAI_5H_PCT=$(quota_val "summary.providers.openai.5h_used_pct" "")
  OPENAI_7D_PCT=$(quota_val "summary.providers.openai.7d_used_pct" "")
  GEMINI_DAILY_PCT=$(quota_val "summary.providers.gemini.daily_used_pct" "")
  ANTHROPIC_BUDGET_REMAIN=$(quota_val "summary.providers.anthropic.budget_remaining_usd" "")
  OPENAI_BUDGET_REMAIN=$(quota_val "summary.providers.openai.budget_remaining_usd" "")
  OPENAI_REQ_REMAIN=$(quota_val "openai_headers.requests_remaining" "")

  # Proxy model detection
  PROXY_INDICATOR=""
  if [ "$PROXY_MODEL_SWAPPED" = "True" ] || [ "$PROXY_MODEL_SWAPPED" = "true" ]; then
    PROXY_ACTUAL_SHORT=$(echo "$PROXY_ACTUAL_MODEL" | sed 's/claude-/c/' | sed 's/-202.*//' | sed 's/gpt-4o/gpt4o/' | sed 's/o4-mini/o4m')
    PROXY_INDICATOR=" #[fg=#7c3aed]→${PROXY_ACTUAL_SHORT}"
    SHORT_MODEL="${SHORT_MODEL}↗"
  fi

  # Format tokens
  fmt_t() {
    local t="$1"
    if [ "$t" -ge 1000000 ]; then echo "$(echo "scale=1; $t/1000000" | bc)M"
    elif [ "$t" -ge 1000 ]; then echo "$(echo "scale=1; $t/1000" | bc)K"
    else echo "$t"; fi
  }

  # Context bar
  BAR_WIDTH=8
  FILLED=$(echo "$CTX_PCT * $BAR_WIDTH / 100" | bc | cut -d. -f1)
  EMPTY=$((BAR_WIDTH - FILLED))
  BAR=""
  for ((i=0; i<FILLED; i++)); do BAR+="█"; done
  for ((i=0; i<EMPTY; i++)); do BAR+="░"; done

  # Context color
  CTX_COLOR="green"
  if (( $(echo "$CTX_PCT >= 95" | bc -l) )); then CTX_COLOR="red"
  elif (( $(echo "$CTX_PCT >= 80" | bc -l) )); then CTX_COLOR="yellow"
  elif (( $(echo "$CTX_PCT >= 50" | bc -l) )); then CTX_COLOR="yellow"; fi

  # Quota color for rate segments
  rate_color() {
    local pct="$1"
    if (( $(echo "$pct >= 95" | bc -l) )); then echo "red"
    elif (( $(echo "$pct >= 80" | bc -l) )); then echo "yellow"
    elif (( $(echo "$pct >= 50" | bc -l) )); then echo "yellow"
    else echo "white"; fi
  }

  # Git status string
  GIT_STATUS=""
  if [ "$GIT_STAGED" -ne 0 ] || [ "$GIT_UNSTAGED" -ne 0 ] || [ "$GIT_UNTRACKED" -ne 0 ]; then
    GIT_STATUS=" S:${GIT_STAGED} U:${GIT_UNSTAGED} ?:${GIT_UNTRACKED}"
  fi

  # Budget display
  BUDGET_DISPLAY=""
  if [ -n "$ANTHROPIC_BUDGET_REMAIN" ] && [ "$ANTHROPIC_BUDGET_REMAIN" != "0" ] && [ "$ANTHROPIC_BUDGET_REMAIN" != "" ]; then
    BUDGET_DISPLAY+=" A:\$$(printf '%.2f' "$ANTHROPIC_BUDGET_REMAIN")"
  fi
  if [ -n "$OPENAI_BUDGET_REMAIN" ] && [ "$OPENAI_BUDGET_REMAIN" != "0" ] && [ "$OPENAI_BUDGET_REMAIN" != "" ]; then
    BUDGET_DISPLAY+=" O:\$$(printf '%.2f' "$OPENAI_BUDGET_REMAIN")"
  fi

  # LINE 1 (top): model │ project │ branch │ git status │ compression
  LINE1="#[fg=#b4befe,bg=#1a6b5a] 󰜖 ${SHORT_MODEL}${PROXY_INDICATOR} #[fg=#1a6b5a,bg=#155044]#[fg=#cdd6f4,bg=#155044]  ${PROJECT_DISPLAY}"
  if [ -n "$GIT_BRANCH" ]; then
    LINE1+=" #[fg=#a6e3a1]󰐘 ${GIT_BRANCH}${GIT_STATUS}"
  fi
  LINE1+="${COMP_DISPLAY}"

  # LINE 2 (bottom): context bar │ tokens (left) │ cache │ cost │ t/s │ rate limits │ budget │ duration │ perm (right)
  LINE2="#[align=left]#[fg=#1e1e2e,bg=${CTX_COLOR}] ${BAR} ${CTX_PCT}% #[fg=#cdd6f4,bg=#45475a] $(fmt_t $TOTAL_TOKENS)/$(fmt_t $CTX_SIZE)"
  LINE2+="#[align=right]#[fg=#74c7ec]⠿ ${CACHE_PCT}% #[fg=#f9e2af,bg=#313244] \$$(printf '%.2f' ${TOTAL_COST})"
  if [ "$TOK_PER_S" != "0" ]; then
    LINE2+=" #[fg=#a6adc8]${TOK_PER_S}t/s"
  fi

  # Quota / Rate segments
  if [ "$PROXY_MODEL_SWAPPED" = "True" ] || [ "$PROXY_MODEL_SWAPPED" = "true" ]; then
    # Dual quota mode
    R5_CLR=$(rate_color "${RATE5:-0}")
    LINE2+=" #[fg=#9370db,bg=#1e1e2e]󰜦 5h${RATE5}%/7d${RATE7}%|real"
    if [ -n "$OPENAI_5H_PCT" ]; then
      LINE2+=":5h${OPENAI_5H_PCT}%"
    fi
    if [ -n "$OPENAI_7D_PCT" ]; then
      LINE2+="/7d${OPENAI_7D_PCT}%"
    fi
  else
    if [ "$RATE5" != "0" ]; then
      R5_CLR=$(rate_color "$RATE5")
      LINE2+=" #[fg=${R5_CLR}]5h${RATE5}%"
    fi
    if [ "$RATE7" != "0" ]; then
      R7_CLR=$(rate_color "$RATE7")
      LINE2+=" #[fg=${R7_CLR}]7d${RATE7}%"
    fi
    # External quota from onWatch (supplementary)
    if [ -n "$ANTHROPIC_5H_PCT" ]; then
      LINE2+=" #[fg=#9370db]A:${ANTHROPIC_5H_PCT}%"
    fi
    if [ -n "$OPENAI_5H_PCT" ]; then
      LINE2+=" #[fg=#9370db]O:${OPENAI_5H_PCT}%"
    fi
  fi

  # Budget remaining
  if [ -n "$BUDGET_DISPLAY" ]; then
    LINE2+=" #[fg=#a6e3a1]${BUDGET_DISPLAY}"
  fi

  # OpenAI request remaining
  if [ -n "$OPENAI_REQ_REMAIN" ] && [ "$OPENAI_REQ_REMAIN" != "0" ] && [ "$OPENAI_REQ_REMAIN" != "" ]; then
    LINE2+=" #[fg=#74c7ec]OAI:${OPENAI_REQ_REMAIN}req"
  fi

  LINE2+=" #[fg=#cdd6f4,bg=#45475a] ${DUR_FMT}"
  LINE2+="${PERM_DISPLAY}"

  # Set tmux two-line status bar (status-format[0] = top line, status-format[1] = bottom line)
  tmux set-option -t "$SESSION_NAME" status-format[0] "$LINE1" 2>/dev/null || true
  tmux set-option -t "$SESSION_NAME" status-format[1] "$LINE2" 2>/dev/null || true
}

# --- Launch ---
echo "Starting Codex with HYPERSTATUS v3.0 tmux wrapper..."
echo "Features: Full metrics + multi-provider quota + proxy detection"

# Create tmux session
tmux new-session -d -s "$SESSION_NAME" -x "$(tput cols)" -y "$(tput lines)" 2>/dev/null || {
  echo "tmux not available. Falling back to plain codex."
  exec codex "$@"
}

# Configure tmux status bar appearance
tmux set-option -t "$SESSION_NAME" status on
tmux set-option -t "$SESSION_NAME" status-position bottom
tmux set-option -t "$SESSION_NAME" status-style "bg=#1e1e2e,fg=#cdd6f4"
tmux set-option -t "$SESSION_NAME" status-interval 3
# Initialize two-line status bar (updated dynamically by render_status)
tmux set-option -t "$SESSION_NAME" status-format[0] " HYPERSTATUS v3.0 " 2>/dev/null || true
tmux set-option -t "$SESSION_NAME" status-format[1] " " 2>/dev/null || true

# Start background status updater
(
  export CODEX_SESSION_START="$(date +%s%3N)"
  while tmux has-session -t "$SESSION_NAME" 2>/dev/null; do
    render_status
    sleep 3
  done
) &
UPDATER_PID=$!

# Run Codex inside tmux
tmux send-keys -t "$SESSION_NAME" "codex $*" Enter

# Attach to tmux session
tmux attach-session -t "$SESSION_NAME"

# Cleanup
kill $UPDATER_PID 2>/dev/null || true
tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
