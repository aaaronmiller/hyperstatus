#!/usr/bin/env bash
# ============================================================================
#  HYPERSTATUS v3.0 — Hermes Agent Status Bar Script
#  Powerline-style status bar with full metric coverage + QUOTA integration
#
#  This script can be used as:
#    1. A standalone renderer alongside Hermes (background process → tmux)
#    2. The command specified in Hermes config.yaml status_bar.command
#
#  Data sources:
#    1. Hermes internal state (via HERMES_* env vars)
#    2. Git (branch, status, worktree)
#    3. Environment variables (compression, permissions)
#    4. RTK/Headroom proxy metrics
#    5. onWatch/ccusage/LiteLLM quota data (v3.0)
# ============================================================================

set -euo pipefail

# --- Color Palette (Catppuccin Mocha — identical to Claude Code version) ---
C_BG='\033[48;5;30m'        # Deep teal
C_BG2='\033[48;5;24m'       # Darker teal
C_BG3='\033[48;5;60m'       # Purple accent
C_BG_WARN='\033[48;5;130m'  # Orange warning
C_BG_CRIT='\033[48;5;160m'  # Red critical
C_BG_OK='\033[48;5;70m'     # Green healthy
C_BG_QUOTA='\033[48;5;97m'  # Mauve for quota segments
C_BG_PROXY='\033[48;5;54m'  # Purple for proxy segments
C_FG='\033[38;5;230m'       # Light text
C_FG_DIM='\033[38;5;180m'   # Dimmed text
C_FG_BRIGHT='\033[38;5;255m' # Bright white
C_FG_GREEN='\033[38;5;150m'
C_FG_YELLOW='\033[38;5;220m'
C_FG_SAPPHIRE='\033[38;5;116m'
C_FG_LAVENDER='\033[38;5;183m'
C_FG_PEACH='\033[38;5;215m'
C_FG_RED='\033[38;5;210m'
C_RESET='\033[0m'

# Powerline separators
PL_RIGHT='\ue0b0'
PL_RIGHT_THIN='\ue0b1'

# Nerd Font icons (SAME set as Claude Code version)
IC_MODEL='\ue716'
IC_CTX='\uf6cf'
IC_COST='\uf155'
IC_BRANCH='\uf418'
IC_TIME='\uf017'
IC_TOKEN='\uf1c9'
IC_CACHE='\uf021'
IC_RATE5='\uf252'
IC_RATE7='\uf254'
IC_DIR='\uf07b'
IC_COMPRESS='\uf410'
IC_BG_TASK='\uf44e'
IC_THINK='\uf7b4'
IC_EFFORT='\uf58c'
IC_PERM='\uf132'
IC_LATENCY='\uf9ee'
IC_LINES='\uf1dc'
IC_WORKTREE='\uf77a'
IC_GIT_STATUS='\uf418'
IC_QUOTA='\uf0ec'
IC_PROXY='\uf6ff'
IC_PROVIDER='\uf1c0'
IC_WARN='\uf071'

# --- Helpers ---
ctx_color() {
  local pct="$1"
  if (( $(echo "$pct >= 95" | bc -l) )); then echo -e "$C_BG_CRIT"
  elif (( $(echo "$pct >= 80" | bc -l) )); then echo -e "$C_BG_WARN"
  elif (( $(echo "$pct >= 50" | bc -l) )); then echo -e "$C_BG3"
  else echo -e "$C_BG_OK"
  fi
}

quota_color() {
  local used_pct="$1"
  if (( $(echo "$used_pct >= 95" | bc -l) )); then echo -e "$C_BG_CRIT"
  elif (( $(echo "$used_pct >= 80" | bc -l) )); then echo -e "$C_BG_WARN"
  elif (( $(echo "$used_pct >= 50" | bc -l) )); then echo -e "$C_BG3"
  else echo -e "$C_BG_QUOTA"
  fi
}

ctx_bar() {
  local pct="$1" width=10
  local filled=$(echo "$pct * $width / 100" | bc | cut -d. -f1)
  local empty=$((width - filled))
  local bar=""
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done
  echo "$bar"
}

fmt_tokens() {
  local t="$1"
  if [ -z "$t" ] || [ "$t" = "0" ]; then echo "0"; return; fi
  if [ "$t" -ge 1000000 ]; then echo "$(echo "scale=1; $t/1000000" | bc)M"
  elif [ "$t" -ge 1000 ]; then echo "$(echo "scale=1; $t/1000" | bc)K"
  else echo "$t"; fi
}

fmt_cost() {
  local c="$1"
  if [ -z "$c" ] || [ "$c" = "0" ]; then echo "\$0.00"; return; fi
  printf "\$%.2f" "$c"
}

fmt_duration() {
  local ms="$1"
  if [ -z "$ms" ] || [ "$ms" = "0" ]; then echo "0s"; return; fi
  local s=$((ms / 1000)) m=$((s / 60)) h=$((m / 60))
  if [ "$h" -gt 0 ]; then echo "${h}h${m}m"
  elif [ "$m" -gt 0 ]; then echo "${m}m"
  else echo "${s}s"; fi
}

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

# --- Gather agent data ---

# Model
MODEL="${HERMES_MODEL:-}"
if [ -z "$MODEL" ] && command -v hermes &>/dev/null; then
  MODEL=$(hermes config get model 2>/dev/null || echo "")
fi
if [ -n "$MODEL" ]; then
  SHORT_MODEL=$(echo "$MODEL" | sed 's/claude-/c/' | sed 's/-202.*//' | sed 's/gpt-4o/gpt4o/' | sed 's/o4-mini/o4m')
else
  SHORT_MODEL="unknown"
fi

# Context metrics
CTX_PCT="${HERMES_CONTEXT_PCT:-0}"
CTX_SIZE="${HERMES_CONTEXT_SIZE:-200000}"
INPUT_TOKENS="${HERMES_INPUT_TOKENS:-0}"
OUTPUT_TOKENS="${HERMES_OUTPUT_TOKENS:-0}"
CACHE_READ="${HERMES_CACHE_READ:-0}"
CACHE_CREATE="${HERMES_CACHE_CREATE:-0}"
TOTAL_TOKENS=$((INPUT_TOKENS + OUTPUT_TOKENS))

# Cache hit rate
if [ "$INPUT_TOKENS" -gt 0 ] && [ "$CACHE_READ" -gt 0 ]; then
  CACHE_PCT=$(echo "scale=0; $CACHE_READ * 100 / $INPUT_TOKENS" | bc 2>/dev/null || echo "0")
else
  CACHE_PCT="0"
fi

# Cost
TOTAL_COST="${HERMES_SESSION_COST:-0}"

# Duration
SESSION_START="${HERMES_SESSION_START:-}"
if [ -n "$SESSION_START" ]; then
  NOW_MS=$(date +%s%3N)
  DURATION_MS=$((NOW_MS - SESSION_START))
else
  DURATION_MS="${HERMES_DURATION_MS:-0}"
fi

# API duration for throughput
API_DURATION_MS="${HERMES_API_DURATION_MS:-0}"
if [ "$API_DURATION_MS" -gt 0 ] && [ "$OUTPUT_TOKENS" -gt 0 ]; then
  TOK_PER_S=$(echo "scale=1; $OUTPUT_TOKENS * 1000 / $API_DURATION_MS" | bc 2>/dev/null || echo "0")
else
  TOK_PER_S="0"
fi

# Agent rate limits
RATE5_PCT="${HERMES_RATE5_PCT:-0}"
RATE7_PCT="${HERMES_RATE7_PCT:-0}"

# Working directory / Project
PROJECT_DIR="${HERMES_PROJECT_DIR:-$(pwd)}"
PROJECT_DISPLAY=$(basename "$PROJECT_DIR")

# Git branch + status
GIT_BRANCH=""
GIT_STAGED=0; GIT_UNSTAGED=0; GIT_UNTRACKED=0
if command -v git &>/dev/null; then
  GIT_BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [ -n "$GIT_BRANCH" ]; then
    GIT_STAGED=$(git -C "$PROJECT_DIR" diff --cached --numstat 2>/dev/null | wc -l || echo "0")
    GIT_UNSTAGED=$(git -C "$PROJECT_DIR" diff --numstat 2>/dev/null | wc -l || echo "0")
    GIT_UNTRACKED=$(git -C "$PROJECT_DIR" ls-files --others --exclude-standard 2>/dev/null | wc -l || echo "0")
  fi
fi

# Worktree
WORKTREE="${HERMES_WORKTREE:-}"
if [ -z "$WORKTREE" ] && [ -n "$GIT_BRANCH" ]; then
  WORKTREE=$(git -C "$PROJECT_DIR" worktree list 2>/dev/null | head -2 | tail -1 | awk '{print $3}' 2>/dev/null || echo "")
fi

# Lines changed
LINES_ADD="${HERMES_LINES_ADDED:-0}"
LINES_REM="${HERMES_LINES_REMOVED:-0}"

# Compression
RTK_SAVED="${RTK_TOKENS_SAVED:-}"
HEADROOM_SAVED="${HEADROOM_TOKENS_SAVED:-}"
if [ -n "$RTK_SAVED" ] && [ "$RTK_SAVED" != "0" ]; then
  COMP_DISPLAY=" ${IC_COMPRESS} ▼$(fmt_tokens "$RTK_SAVED")"
elif [ -n "$HEADROOM_SAVED" ] && [ "$HEADROOM_SAVED" != "0" ]; then
  COMP_DISPLAY=" ${IC_COMPRESS} ▼$(fmt_tokens "$HEADROOM_SAVED")"
else
  COMP_DISPLAY=""
fi

COMPRESS_COUNT="${HERMES_COMPRESS_COUNT:-0}"

# Background tasks
BG_TASKS="${HERMES_BG_TASKS:-0}"

# Permission level
PERM_LEVEL="ask"
if [ "${HERMES_YOLO_MODE:-}" = "1" ]; then PERM_LEVEL="yolo"
elif [ "${HERMES_AUTO_ACCEPT:-}" = "1" ]; then PERM_LEVEL="auto"
fi

# Effort level
EFFORT="${HERMES_EFFORT_LEVEL:-}"
THINKING="${HERMES_THINKING_ENABLED:-false}"

# ==============================================================================
#  QUOTA DATA (v3.0)
# ==============================================================================
PROXY_MODEL_SWAPPED=$(quota_val "summary.proxy_info.model_swapped" "false")
PROXY_AGENT_MODEL=$(quota_val "summary.proxy_info.agent_model" "")
PROXY_ACTUAL_MODEL=$(quota_val "summary.proxy_info.actual_model" "")

# Proxy model detection
if [ "$PROXY_MODEL_SWAPPED" = "True" ] || [ "$PROXY_MODEL_SWAPPED" = "true" ]; then
  PROXY_ACTUAL_SHORT=$(echo "$PROXY_ACTUAL_MODEL" | sed 's/claude-/c/' | sed 's/-202.*//' | sed 's/gpt-4o/gpt4o/' | sed 's/o4-mini/o4m')
  SEG_PROXY=" ${IC_PROXY}${SHORT_MODEL}→${PROXY_ACTUAL_SHORT}"
  SHORT_MODEL="${SHORT_MODEL}↗"
else
  SEG_PROXY=""
fi

# External quota data
ANTHROPIC_5H_PCT=$(quota_val "summary.providers.anthropic.5h_used_pct" "")
ANTHROPIC_7D_PCT=$(quota_val "summary.providers.anthropic.7d_used_pct" "")
OPENAI_5H_PCT=$(quota_val "summary.providers.openai.5h_used_pct" "")
OPENAI_7D_PCT=$(quota_val "summary.providers.openai.7d_used_pct" "")
GEMINI_DAILY_PCT=$(quota_val "summary.providers.gemini.daily_used_pct" "")
ANTHROPIC_BUDGET_REMAIN=$(quota_val "summary.providers.anthropic.budget_remaining_usd" "")
OPENAI_BUDGET_REMAIN=$(quota_val "summary.providers.openai.budget_remaining_usd" "")
OPENAI_REQ_REMAIN=$(quota_val "openai_headers.requests_remaining" "")

# Determine display rates
if [ "$PROXY_MODEL_SWAPPED" = "True" ] || [ "$PROXY_MODEL_SWAPPED" = "true" ]; then
  if echo "$PROXY_ACTUAL_MODEL" | grep -qi "gpt\|o4\|o3"; then
    DISPLAY_RATE5="${OPENAI_5H_PCT:-$RATE5_PCT}"
    DISPLAY_RATE7="${OPENAI_7D_PCT:-$RATE7_PCT}"
  elif echo "$PROXY_ACTUAL_MODEL" | grep -qi "gemini"; then
    DISPLAY_RATE5="${GEMINI_DAILY_PCT:-$RATE5_PCT}"
    DISPLAY_RATE7="0"
  else
    DISPLAY_RATE5="${ANTHROPIC_5H_PCT:-$RATE5_PCT}"
    DISPLAY_RATE7="${ANTHROPIC_7D_PCT:-$RATE7_PCT}"
  fi
else
  DISPLAY_RATE5="$RATE5_PCT"
  DISPLAY_RATE7="$RATE7_PCT"
fi

# Budget display
SEG_BUDGET=""
if [ -n "$ANTHROPIC_BUDGET_REMAIN" ] && [ "$ANTHROPIC_BUDGET_REMAIN" != "0" ] && [ "$ANTHROPIC_BUDGET_REMAIN" != "" ]; then
  SEG_BUDGET+=" A:\$$(printf '%.2f' "$ANTHROPIC_BUDGET_REMAIN")"
fi
if [ -n "$OPENAI_BUDGET_REMAIN" ] && [ "$OPENAI_BUDGET_REMAIN" != "0" ] && [ "$OPENAI_BUDGET_REMAIN" != "" ]; then
  SEG_BUDGET+=" O:\$$(printf '%.2f' "$OPENAI_BUDGET_REMAIN")"
fi
if [ -n "$SEG_BUDGET" ]; then
  SEG_BUDGET=" ${IC_COST}${SEG_BUDGET}"
fi

SEG_OPENAI_QUOTA=""
if [ -n "$OPENAI_REQ_REMAIN" ] && [ "$OPENAI_REQ_REMAIN" != "0" ] && [ "$OPENAI_REQ_REMAIN" != "" ]; then
  SEG_OPENAI_QUOTA=" OAI:${OPENAI_REQ_REMAIN}req"
fi

# --- Build status bar ---
CTX_CLR=$(ctx_color "${CTX_PCT:-0}")
BAR=$(ctx_bar "${CTX_PCT:-0}")

# LEFT: model | proxy | project | branch | git status | worktree | lines | compression
SEG_MODEL="${IC_MODEL} ${SHORT_MODEL}"
SEG_PROJECT="${IC_DIR} ${PROJECT_DISPLAY}"

if [ -n "$GIT_BRANCH" ]; then
  SEG_GIT=" ${IC_BRANCH} ${GIT_BRANCH}"
  if [ "$GIT_STAGED" -ne 0 ] || [ "$GIT_UNSTAGED" -ne 0 ] || [ "$GIT_UNTRACKED" -ne 0 ]; then
    SEG_GIT+=" S:${GIT_STAGED} U:${GIT_UNSTAGED} ?:${GIT_UNTRACKED}"
  fi
else
  SEG_GIT=""
fi

SEG_WORKTREE=""
if [ -n "$WORKTREE" ] && [ "$WORKTREE" != "$GIT_BRANCH" ]; then
  SEG_WORKTREE=" ${IC_WORKTREE} ${WORKTREE}"
fi

SEG_LINES=""
if [ "$LINES_ADD" -ne 0 ] || [ "$LINES_REM" -ne 0 ]; then
  SEG_LINES=" +${LINES_ADD}/-${LINES_REM}"
fi

LEFT_PART="${SEG_MODEL}${SEG_PROXY} │ ${SEG_PROJECT}${SEG_GIT}${SEG_WORKTREE}${SEG_LINES}${COMP_DISPLAY}"

# RIGHT: context% | tokens | cache | cost | speed | quota/rate | budget | duration | effort | think | perm | bg | compress
CTX_PCT_FMT=$(printf "%5.1f" "${CTX_PCT:-0}")
SEG_CTX="${IC_CTX} ${BAR} ${CTX_PCT_FMT}%%"

TOTAL_FMT=$(fmt_tokens "${TOTAL_TOKENS:-0}")
CTX_SIZE_FMT=$(fmt_tokens "${CTX_SIZE:-0}")
SEG_TOKENS="${IC_TOKEN} ${TOTAL_FMT}/${CTX_SIZE_FMT}"

CACHE_PCT_FMT=$(printf "%3d" "${CACHE_PCT:-0}")
SEG_CACHE="${IC_CACHE} ${CACHE_PCT_FMT}%%"

COST_FMT=$(fmt_cost "${TOTAL_COST:-0}")
SEG_COST="${IC_COST} ${COST_FMT}"

SEG_SPEED=""
if [ "$TOK_PER_S" != "0" ]; then
  SEG_SPEED=" ${IC_LATENCY} ${TOK_PER_S}t/s"
fi

# Rate / Quota segments
if [ "$PROXY_MODEL_SWAPPED" = "True" ] || [ "$PROXY_MODEL_SWAPPED" = "true" ]; then
  # Dual quota in proxy mode
  AGENT_RATE5_FMT=""
  AGENT_RATE7_FMT=""
  if [ -n "$RATE5_PCT" ] && [ "$RATE5_PCT" != "0" ]; then
    AGENT_RATE5_FMT=$(printf "%3d" "$RATE5_PCT")
  fi
  if [ -n "$RATE7_PCT" ] && [ "$RATE7_PCT" != "0" ]; then
    AGENT_RATE7_FMT=$(printf "%3d" "$RATE7_PCT")
  fi
  REAL_RATE5_FMT=""
  REAL_RATE7_FMT=""
  if [ -n "$DISPLAY_RATE5" ] && [ "$DISPLAY_RATE5" != "0" ] && [ "$DISPLAY_RATE5" != "" ]; then
    REAL_RATE5_FMT=$(printf "%3d" "$DISPLAY_RATE5")
  fi
  if [ -n "$DISPLAY_RATE7" ] && [ "$DISPLAY_RATE7" != "0" ] && [ "$DISPLAY_RATE7" != "" ]; then
    REAL_RATE7_FMT=$(printf "%3d" "$DISPLAY_RATE7")
  fi
  SEG_QUOTA="${IC_QUOTA}"
  if [ -n "$AGENT_RATE5_FMT" ]; then SEG_QUOTA+=" 5h${AGENT_RATE5_FMT}%%"; fi
  if [ -n "$AGENT_RATE7_FMT" ]; then SEG_QUOTA+="/7d${AGENT_RATE7_FMT}%%"; fi
  SEG_QUOTA+="|real"
  if [ -n "$REAL_RATE5_FMT" ]; then SEG_QUOTA+=":5h${REAL_RATE5_FMT}%%"; fi
  if [ -n "$REAL_RATE7_FMT" ]; then SEG_QUOTA+="/7d${REAL_RATE7_FMT}%%"; fi
  SEG_RATE5=""
  SEG_RATE7=""
else
  SEG_RATE5=""
  if [ "$DISPLAY_RATE5" != "0" ] && [ -n "$DISPLAY_RATE5" ]; then
    RATE5_FMT=$(printf "%3d" "$DISPLAY_RATE5")
    SEG_RATE5="${IC_RATE5}5h${RATE5_FMT}%%"
  fi
  SEG_RATE7=""
  if [ "$DISPLAY_RATE7" != "0" ] && [ -n "$DISPLAY_RATE7" ]; then
    RATE7_FMT=$(printf "%3d" "$DISPLAY_RATE7")
    SEG_RATE7="${IC_RATE7}7d${RATE7_FMT}%%"
  fi
  SEG_QUOTA=""
fi

DUR_FMT=$(fmt_duration "${DURATION_MS:-0}")
SEG_DURATION="${IC_TIME} ${DUR_FMT}"

SEG_EFFORT=""
if [ -n "$EFFORT" ]; then
  case "$EFFORT" in
    max|xhigh) SEG_EFFORT="${IC_EFFORT}⚡" ;;
    high) SEG_EFFORT="${IC_EFFORT}▲" ;;
    medium) SEG_EFFORT="${IC_EFFORT}●" ;;
    low) SEG_EFFORT="${IC_EFFORT}▼" ;;
  esac
fi

SEG_THINK=""
if [ "$THINKING" = "true" ]; then
  SEG_THINK=" ${IC_THINK}✦"
fi

SEG_PERM=""
case "$PERM_LEVEL" in
  yolo) SEG_PERM=" ${IC_PERM}Y" ;;
  auto) SEG_PERM=" ${IC_PERM}A" ;;
esac

SEG_BG=""
if [ "$BG_TASKS" -gt 0 ]; then
  SEG_BG=" ${IC_BG_TASK}${BG_TASKS}"
fi

SEG_COMP_N=""
if [ "$COMPRESS_COUNT" -gt 0 ]; then
  SEG_COMP_N=" ${IC_COMPRESS}${COMPRESS_COUNT}"
fi

# Assemble
if [ "$PROXY_MODEL_SWAPPED" = "True" ] || [ "$PROXY_MODEL_SWAPPED" = "true" ]; then
  RIGHT_PART="${SEG_CTX} │ ${SEG_TOKENS} │ ${SEG_CACHE} │ ${SEG_COST}${SEG_SPEED} │ ${SEG_QUOTA}${SEG_BUDGET}${SEG_OPENAI_QUOTA} │ ${SEG_DURATION}${SEG_EFFORT}${SEG_THINK}${SEG_PERM}${SEG_BG}${SEG_COMP_N}"
else
  RIGHT_PART="${SEG_CTX} │ ${SEG_TOKENS} │ ${SEG_CACHE} │ ${SEG_COST}${SEG_SPEED} │ ${SEG_RATE5}${SEG_RATE7}${SEG_BUDGET}${SEG_OPENAI_QUOTA} │ ${SEG_DURATION}${SEG_EFFORT}${SEG_THINK}${SEG_PERM}${SEG_BG}${SEG_COMP_N}"
fi

# --- RENDER ---
echo -e "${C_BG}${C_FG_BRIGHT} ${LEFT_PART} ${C_FG_DIM}${PL_RIGHT_THIN}${C_BG2}${C_FG} ${RIGHT_PART} ${C_RESET}"

# Line 2 when context > 50%
if (( $(echo "${CTX_PCT:-0} >= 50" | bc -l) )); then
  CTX_REMAINING=$(echo "100 - ${CTX_PCT:-0}" | bc)
  echo -e "${CTX_CLR}${C_FG_BRIGHT} ${IC_CTX} CONTEXT: $(fmt_tokens "${INPUT_TOKENS:-0}") in / $(fmt_tokens "${CTX_SIZE:-0}") max │ Remaining: ${CTX_REMAINING}% │ Output: $(fmt_tokens "${OUTPUT_TOKENS:-0}") │ Cache R: $(fmt_tokens "${CACHE_READ:-0}") / Cache W: $(fmt_tokens "${CACHE_CREATE:-0}") ${C_RESET}"
fi

# Line 3: Quota detail (if proxy active or any provider > 50%)
_SHOW_QUOTA_DETAIL=false
if [ "$PROXY_MODEL_SWAPPED" = "True" ] || [ "$PROXY_MODEL_SWAPPED" = "true" ]; then
  _SHOW_QUOTA_DETAIL=true
fi
_QUOTA_WORST=$(quota_val "summary.total_remaining_pct" "0")
if [ -n "$_QUOTA_WORST" ] && [ "$_QUOTA_WORST" != "0" ] && [ "$_QUOTA_WORST" != "None" ]; then
  if (( $(echo "$_QUOTA_WORST >= 50" | bc -l) )); then
    _SHOW_QUOTA_DETAIL=true
  fi
fi

if [ "$_SHOW_QUOTA_DETAIL" = true ]; then
  _QUOTA_LINE="${IC_QUOTA} QUOTA:"
  if [ -n "$ANTHROPIC_5H_PCT" ] && [ "$ANTHROPIC_5H_PCT" != "" ]; then
    _QUOTA_LINE+=" Anthropic 5h:${ANTHROPIC_5H_PCT}%"
  fi
  if [ -n "$ANTHROPIC_7D_PCT" ] && [ "$ANTHROPIC_7D_PCT" != "" ]; then
    _QUOTA_LINE+="/7d:${ANTHROPIC_7D_PCT}%"
  fi
  if [ -n "$OPENAI_5H_PCT" ] && [ "$OPENAI_5H_PCT" != "" ]; then
    _QUOTA_LINE+=" │ OpenAI 5h:${OPENAI_5H_PCT}%"
  fi
  if [ -n "$OPENAI_7D_PCT" ] && [ "$OPENAI_7D_PCT" != "" ]; then
    _QUOTA_LINE+="/7d:${OPENAI_7D_PCT}%"
  fi
  if [ -n "$GEMINI_DAILY_PCT" ] && [ "$GEMINI_DAILY_PCT" != "" ]; then
    _QUOTA_LINE+=" │ Gemini daily:${GEMINI_DAILY_PCT}%"
  fi
  if [ -n "$SEG_BUDGET" ]; then
    _QUOTA_LINE+=" │ Budget:${SEG_BUDGET}"
  fi
  if [ "$PROXY_MODEL_SWAPPED" = "True" ] || [ "$PROXY_MODEL_SWAPPED" = "true" ]; then
    _QUOTA_LINE+=" │ ${IC_PROXY} ${PROXY_AGENT_MODEL}→${PROXY_ACTUAL_MODEL}"
  fi
  _QUOTA_CLR=$(quota_color "${_QUOTA_WORST:-0}")
  echo -e "${_QUOTA_CLR}${C_FG_BRIGHT} ${_QUOTA_LINE} ${C_RESET}"
fi
