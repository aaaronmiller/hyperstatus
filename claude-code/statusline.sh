#!/usr/bin/env bash
# ============================================================================
#  HYPERSTATUS v3.2 — Claude Code Status Bar
#  Powerline-style status bar with 2-line mode + full metric coverage + QUOTA
#
#  v3.2 NEW: 2-line mode when terminal width >= 80 columns
#    Line 1: model | project | git | context | tokens | cost | duration | effort | perm
#    Line 2: cache | t/s | rate limits | budget | bg_tasks | compression | proxy
#  Narrow mode (<80 cols): single compact line with smart segment hiding
# ============================================================================

set -euo pipefail

# --- Read JSON input from stdin ---
INPUT=$(cat)

# --- Color Palette (Claude Code Default — deep navy/purple TUI theme) ---
# Matches Claude Code's native TUI: dark purple bg, lavender/white text
C_BG='\033[48;5;53m'        # Deep royal purple (#2D1B69)
C_BG2='\033[48;5;55m'       # Purple (#3D2B79)
C_BG3='\033[48;5;92m'       # Violet accent (#6C47B4)
C_BG_WARN='\033[48;5;130m'  # Orange warning
C_BG_CRIT='\033[48;5;160m'  # Red critical
C_BG_OK='\033[48;5;70m'     # Green healthy
C_BG_QUOTA='\033[48;5;97m'  # Mauve for quota segments
C_BG_PROXY='\033[48;5;54m'  # Purple for proxy segments
C_FG='\033[38;5;255m'       # White text
C_FG_DIM='\033[38;5;182m'   # Lavender dimmed
C_FG_BRIGHT='\033[38;5;183m' # Bright lavender
C_FG_GREEN='\033[38;5;150m'
C_FG_YELLOW='\033[38;5;220m'
C_FG_SAPPHIRE='\033[38;5;116m'
C_FG_LAVENDER='\033[38;5;183m'
C_FG_PEACH='\033[38;5;215m'
C_FG_RED='\033[38;5;210m'
C_FG_DARK='\033[38;5;59m'   # Muted for secondary line prefixes
C_RESET='\033[0m'

# Powerline separators (Nerd Font codepoints)
PL_RIGHT='\ue0b0'    # 
PL_LEFT='\ue0b2'      # 
PL_RIGHT_THIN='\ue0b1'  # 
PL_LEFT_THIN='\ue0b3'   # 
PL_DOWN='\ue0bc'       #  — line 2 connector

# Nerd Font icons
IC_MODEL='\ue716'       # 󰜖 AI/Model
IC_CTX='\uf6cf'         # 
IC_COST='\uf155'        # 
IC_GIT='\ue725'         # 
IC_BRANCH='\uf418'      # 󰐘 Git branch
IC_TIME='\uf017'        # 
IC_TOKEN='\uf1c9'      # 
IC_CACHE='\uf021'       # 
IC_RATE5='\uf252'       # 
IC_RATE7='\uf254'       # 
IC_DIR='\uf07b'         # 
IC_COMPRESS='\uf410'    # 
IC_BG_TASK='\uf44e'     # 
IC_THINK='\uf7b4'       # 
IC_EFFORT='\uf58c'      # 
IC_VIM='\uf62a'         # 
IC_PERM='\uf132'        # 
IC_LATENCY='\uf9ee'     # 
IC_PR='\ue728'          # 
IC_LINES='\uf1dc'       # 
IC_WORKTREE='\uf77a'    # 
IC_SESSION='\uf2db'     # 
IC_QUOTA='\uf0ec'       #  Quota/gauge icon
IC_PROXY='\uf6ff'       # 
IC_PROVIDER='\uf1c0'    # 
IC_WARN='\uf071'        # 
IC_VOICE='\uf130'       # Microphone — voice/DeepSeek input active
IC_YOLO='\uf714'        # Skull — YOLO danger mode indicator
IC_TURN='\uf252'        # Turn duration counter

# --- Helper: JSON value extraction ---
jval() {
  echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
keys = '$1'.split('.')
v = d
for k in keys:
  if isinstance(v, dict) and k in v:
    v = v[k]
  elif isinstance(v, list) and k.isdigit():
    v = v[int(k)]
  else:
    v = None
    break
if v is None:
  print('')
else:
  print(str(v))
" 2>/dev/null || echo ""
}

# --- Helper: Context color based on percentage ---
ctx_color() {
  local pct="$1"
  if (( $(echo "$pct >= 95" | bc -l) )); then echo -e "$C_BG_CRIT"
  elif (( $(echo "$pct >= 80" | bc -l) )); then echo -e "$C_BG_WARN"
  elif (( $(echo "$pct >= 50" | bc -l) )); then echo -e "$C_BG3"
  else echo -e "$C_BG_OK"
  fi
}

# --- Helper: Quota color ---
quota_color() {
  local used_pct="$1"
  if (( $(echo "$used_pct >= 95" | bc -l) )); then echo -e "$C_BG_CRIT"
  elif (( $(echo "$used_pct >= 80" | bc -l) )); then echo -e "$C_BG_WARN"
  elif (( $(echo "$used_pct >= 50" | bc -l) )); then echo -e "$C_BG3"
  else echo -e "$C_BG_QUOTA"
  fi
}

# --- Helper: Context progress bar ---
ctx_bar() {
  local pct="$1"
  local width=10
  local filled=$(echo "$pct * $width / 100" | bc | cut -d. -f1)
  local empty=$((width - filled))
  local bar=""
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done
  echo "$bar"
}

# --- Helper: Format duration ---
fmt_duration() {
  local ms="$1"
  if [ -z "$ms" ] || [ "$ms" = "0" ]; then echo "0s"; return; fi
  local s=$((ms / 1000))
  local m=$((s / 60))
  local h=$((m / 60))
  if [ "$h" -gt 0 ]; then echo "${h}h$((m % 60))m"
  elif [ "$m" -gt 0 ]; then echo "${m}m"
  else echo "${s}s"
  fi
}

# --- Helper: Format tokens with K/M suffix ---
fmt_tokens() {
  local t="$1"
  if [ -z "$t" ] || [ "$t" = "0" ]; then echo "0"; return; fi
  if [ "$t" -ge 1000000 ]; then
    echo "$(echo "scale=1; $t/1000000" | bc)M"
  elif [ "$t" -ge 1000 ]; then
    echo "$(echo "scale=1; $t/1000" | bc)K"
  else
    echo "$t"
  fi
}

# --- Helper: Format cost ---
fmt_cost() {
  local c="$1"
  if [ -z "$c" ] || [ "$c" = "0" ]; then echo "\$0.00"; return; fi
  printf "\$%.2f" "$c"
}

# --- Helper: Read quota state from shared JSON ---
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

# ==============================================================================
#  EXTRACT AGENT DATA (from Claude's statusline JSON on stdin)
# ==============================================================================
MODEL=$(jval "model.display_name")
MODEL_ID=$(jval "model.id")
CWD=$(jval "cwd")
PROJECT_DIR=$(jval "workspace.project_dir")
GIT_BRANCH=$(jval "workspace.git_worktree")
REPO_NAME=$(jval "workspace.repo.name")
REPO_OWNER=$(jval "workspace.repo.owner")
TOTAL_COST=$(jval "cost.total_cost_usd")
DURATION_MS=$(jval "cost.total_duration_ms")
API_DURATION_MS=$(jval "cost.total_api_duration_ms")
LINES_ADD=$(jval "cost.total_lines_added")
LINES_REM=$(jval "cost.total_lines_removed")
INPUT_TOKENS=$(jval "context_window.total_input_tokens")
OUTPUT_TOKENS=$(jval "context_window.total_output_tokens")
CTX_SIZE=$(jval "context_window.context_window_size")
CTX_PCT=$(jval "context_window.used_percentage")
EXCEEDS=$(jval "exceeds_200k_tokens")
EFFORT=$(jval "effort.level")
THINKING=$(jval "thinking.enabled")
RATE5_PCT=$(jval "rate_limits.five_hour.used_percentage")
RATE5_RESET=$(jval "rate_limits.five_hour.resets_at")
RATE7_PCT=$(jval "rate_limits.seven_day.used_percentage")
RATE7_RESET=$(jval "rate_limits.seven_day.resets_at")
SESSION_ID=$(jval "session_id")
SESSION_NAME=$(jval "session_name")
VIM_MODE=$(jval "vim.mode")
PR_NUM=$(jval "pr.number")
PR_STATE=$(jval "pr.review_state")
WORKTREE=$(jval "worktree.name")
VERSION=$(jval "version")
TERM_WIDTH=$(jval "terminal_width")

# Cache tokens
CACHE_CREATE=$(jval "context_window.current_usage.cache_creation")
CACHE_READ=$(jval "context_window.current_usage.cache_read")

# --- Calculate derived metrics ---
TOTAL_TOKENS=$((INPUT_TOKENS + OUTPUT_TOKENS))
if [ -n "$CTX_SIZE" ] && [ "$CTX_SIZE" -gt 0 ] && [ -n "$INPUT_TOKENS" ]; then
  CACHE_PCT=$(echo "scale=0; $CACHE_READ * 100 / $INPUT_TOKENS" | bc 2>/dev/null || echo "0")
else
  CACHE_PCT="0"
fi

# Latency / tokens per second
if [ -n "$API_DURATION_MS" ] && [ "$API_DURATION_MS" -gt 0 ] && [ -n "$OUTPUT_TOKENS" ] && [ "$OUTPUT_TOKENS" -gt 0 ]; then
  TOK_PER_S=$(echo "scale=1; $OUTPUT_TOKENS * 1000 / $API_DURATION_MS" | bc 2>/dev/null || echo "0")
else
  TOK_PER_S="0"
fi

# Short model name
if [ -n "$MODEL" ]; then
  SHORT_MODEL=$(echo "$MODEL" | sed 's/claude-/c/' | sed 's/-202.*//')
else
  SHORT_MODEL="unknown"
fi

# Short project path
if [ -n "$REPO_NAME" ]; then
  PROJECT_DISPLAY="$REPO_NAME"
elif [ -n "$PROJECT_DIR" ]; then
  PROJECT_DISPLAY=$(basename "$PROJECT_DIR")
else
  PROJECT_DISPLAY="~"
fi

# ==============================================================================
#  COMPRESSION METRICS (from collector daemon)
# ==============================================================================
if [ -f /tmp/hyperstatus-env.sh ]; then
  source /tmp/hyperstatus-env.sh 2>/dev/null || true
fi
if [ -f /tmp/hyperstatus-metrics.json ] && command -v python3 &>/dev/null; then
  _RTK_SAVED=$(python3 -c "import json; d=json.load(open('/tmp/hyperstatus-metrics.json')); print(d.get('rtk_tokens_saved',0))" 2>/dev/null || echo "0")
  _HEADROOM_SAVED=$(python3 -c "import json; d=json.load(open('/tmp/hyperstatus-metrics.json')); print(d.get('headroom_tokens_saved',0))" 2>/dev/null || echo "0")
  _HEADROOM_RATIO=$(python3 -c "import json; d=json.load(open('/tmp/hyperstatus-metrics.json')); print(d.get('headroom_compression_ratio',0))" 2>/dev/null || echo "0")
else
  _RTK_SAVED="0"
  _HEADROOM_SAVED="0"
  _HEADROOM_RATIO="0"
fi
COMP_SAVED="${HEADROOM_TOKENS_SAVED:-$_HEADROOM_SAVED}"
RTK_SAVED="${RTK_TOKENS_SAVED:-$_RTK_SAVED}"
COMP_RATIO="${HEADROOM_COMPRESSION_RATIO:-$_HEADROOM_RATIO}"

# ==============================================================================
#  QUOTA DATA (from quota-fetch.sh / shared state)
# ==============================================================================
PROXY_ACTIVE=$(quota_val "summary.proxy_info" "")
PROXY_MODEL_SWAPPED=$(quota_val "summary.proxy_info.model_swapped" "false")
PROXY_AGENT_MODEL=$(quota_val "summary.proxy_info.agent_model" "")
PROXY_ACTUAL_MODEL=$(quota_val "summary.proxy_info.actual_model" "")

# Proxy model detection
SEG_PROXY=""
if [ "$PROXY_MODEL_SWAPPED" = "True" ] || [ "$PROXY_MODEL_SWAPPED" = "true" ]; then
  PROXY_ACTUAL_SHORT=$(echo "$PROXY_ACTUAL_MODEL" | sed 's/claude-/c/' | sed 's/-202.*//' | sed 's/gpt-4o/gpt4o/' | sed 's/o4-mini/o4m')
  SEG_PROXY=" ${IC_PROXY}${SHORT_MODEL}→${PROXY_ACTUAL_SHORT}"
  SHORT_MODEL="${SHORT_MODEL}↗"
fi

# Read per-provider quota
ANTHROPIC_5H_PCT=$(quota_val "summary.providers.anthropic.5h_used_pct" "")
ANTHROPIC_7D_PCT=$(quota_val "summary.providers.anthropic.7d_used_pct" "")
OPENAI_5H_PCT=$(quota_val "summary.providers.openai.5h_used_pct" "")
OPENAI_7D_PCT=$(quota_val "summary.providers.openai.7d_used_pct" "")
GEMINI_DAILY_PCT=$(quota_val "summary.providers.gemini.daily_used_pct" "")
ANTHROPIC_BUDGET_REMAIN=$(quota_val "summary.providers.anthropic.budget_remaining_usd" "")
OPENAI_BUDGET_REMAIN=$(quota_val "summary.providers.openai.budget_remaining_usd" "")
OPENAI_REQ_REMAIN=$(quota_val "openai_headers.requests_remaining" "")
CCUSAGE_ANTHROPIC_COST=$(quota_val "summary.providers.anthropic.ccusage_cost" "")
CCUSAGE_OPENAI_COST=$(quota_val "summary.providers.openai.ccusage_cost" "")

# --- Build quota segments ---
AGENT_RATE5_PCT="${RATE5_PCT:-0}"
AGENT_RATE7_PCT="${RATE7_PCT:-0}"

if [ "$PROXY_MODEL_SWAPPED" = "True" ] || [ "$PROXY_MODEL_SWAPPED" = "true" ]; then
  QUOTA_PROVIDER=""
  if echo "$PROXY_ACTUAL_MODEL" | grep -qi "gpt\|o4\|o3\|dall"; then
    QUOTA_PROVIDER="openai"
    DISPLAY_RATE5="${OPENAI_5H_PCT:-$AGENT_RATE5_PCT}"
    DISPLAY_RATE7="${OPENAI_7D_PCT:-$AGENT_RATE7_PCT}"
  elif echo "$PROXY_ACTUAL_MODEL" | grep -qi "gemini"; then
    QUOTA_PROVIDER="gemini"
    DISPLAY_RATE5="${GEMINI_DAILY_PCT:-$AGENT_RATE5_PCT}"
    DISPLAY_RATE7="0"
  else
    QUOTA_PROVIDER="anthropic"
    DISPLAY_RATE5="${ANTHROPIC_5H_PCT:-$AGENT_RATE5_PCT}"
    DISPLAY_RATE7="${ANTHROPIC_7D_PCT:-$AGENT_RATE7_PCT}"
  fi
else
  QUOTA_PROVIDER=""
  DISPLAY_RATE5="$AGENT_RATE5_PCT"
  DISPLAY_RATE7="$AGENT_RATE7_PCT"
fi

# Budget segments
SEG_BUDGET=""
if [ -n "$ANTHROPIC_BUDGET_REMAIN" ] && [ "$ANTHROPIC_BUDGET_REMAIN" != "0" ] && [ "$ANTHROPIC_BUDGET_REMAIN" != "" ]; then
  SEG_BUDGET+=" A:\$$(printf '%.2f' "$ANTHROPIC_BUDGET_REMAIN")"
fi
if [ -n "$OPENAI_BUDGET_REMAIN" ] && [ "$OPENAI_BUDGET_REMAIN" != "0" ] && [ "$OPENAI_BUDGET_REMAIN" != "" ]; then
  SEG_BUDGET+=" O:\$$(printf '%.2f' "$OPENAI_BUDGET_REMAIN")"
fi

# --- Permission level detection ---
PERM_LEVEL="ask"
if [ "${CLAUDE_YOLO_MODE:-}" = "1" ] || [ "${HERMES_YOLO_MODE:-}" = "1" ]; then
  PERM_LEVEL="yolo"
elif [ "${CLAUDE_AUTO_ACCEPT:-}" = "1" ]; then
  PERM_LEVEL="auto"
fi

# --- Context color ---
CTX_CLR=$(ctx_color "${CTX_PCT:-0}")
BAR=$(ctx_bar "${CTX_PCT:-0}")

# Background tasks
BG_TASK_COUNT="${CLAUDE_BG_TASKS:-0}"

# ==============================================================================
#  BUILD SEGMENTS
# ==============================================================================

# --- LEFT SIDE (shared between both modes) ---
SEG_MODEL="${IC_MODEL} ${SHORT_MODEL}"
SEG_PROJECT="${IC_DIR} ${PROJECT_DISPLAY}"
SEG_GIT=""
if [ -n "$GIT_BRANCH" ]; then
  SEG_GIT=" ${IC_BRANCH} ${GIT_BRANCH}"
fi
if [ -n "$WORKTREE" ] && [ "$WORKTREE" != "$GIT_BRANCH" ]; then
  SEG_WORKTREE=" ${IC_WORKTREE} ${WORKTREE}"
else
  SEG_WORKTREE=""
fi
SEG_PR=""
if [ -n "$PR_NUM" ] && [ "$PR_NUM" != "0" ]; then
  SEG_PR=" ${IC_PR} #${PR_NUM}"
fi
SEG_LINES=""
if [ -n "$LINES_ADD" ] && [ "$LINES_ADD" != "0" ]; then
  SEG_LINES=" +${LINES_ADD}/-${LINES_REM}"
fi

# Compression display
if [ -n "$RTK_SAVED" ] && [ "$RTK_SAVED" != "0" ]; then
  COMP_DISPLAY=" ${IC_COMPRESS}▼$(fmt_tokens "$RTK_SAVED")"
elif [ -n "$COMP_SAVED" ] && [ "$COMP_SAVED" != "0" ]; then
  COMP_DISPLAY=" ${IC_COMPRESS}▼$(fmt_tokens "$COMP_SAVED")"
else
  COMP_DISPLAY=""
fi

# --- RIGHT SIDE PRIMARY (Line 1) ---
CTX_PCT_FMT=$(printf "%5.1f" "${CTX_PCT:-0}")
SEG_CTX="${IC_CTX} ${BAR} ${CTX_PCT_FMT}%%"
TOTAL_FMT=$(fmt_tokens "${TOTAL_TOKENS:-0}")
SEG_TOKENS="${IC_TOKEN} ${TOTAL_FMT}"
COST_FMT=$(fmt_cost "${TOTAL_COST:-0}")
SEG_COST="${IC_COST} ${COST_FMT}"
DUR_FMT=$(fmt_duration "${DURATION_MS:-0}")
SEG_DURATION="${IC_TIME} ${DUR_FMT}"

# Turn duration (per-turn timing)
TURN_DURATION_MS="${HERMES_TURN_DURATION_MS:-${CLAUDE_TURN_DURATION_MS:-0}}"
SEG_TURN=""
if [ "$TURN_DURATION_MS" -gt 0 ]; then
  TURN_FMT=$(fmt_duration "$TURN_DURATION_MS")
  SEG_TURN=" ${IC_TURN}${TURN_FMT}"
fi

# YOLO usage counter
YOLO_COUNT=$(cat /tmp/hyperstatus-yolo-count 2>/dev/null || echo "0")
SEG_YOLO_COUNT=""
if [ "$PERM_LEVEL" = "yolo" ] && [ "$YOLO_COUNT" -gt 0 ]; then
  SEG_YOLO_COUNT=" ${IC_YOLO}${YOLO_COUNT}"
fi

# Effort icon
SEG_EFFORT=""
if [ -n "$EFFORT" ]; then
  case "$EFFORT" in
    max|xhigh) SEG_EFFORT="${IC_EFFORT}⚡" ;;
    high) SEG_EFFORT="${IC_EFFORT}▲" ;;
    medium) SEG_EFFORT="${IC_EFFORT}●" ;;
    low) SEG_EFFORT="${IC_EFFORT}▼" ;;
  esac
fi

# Thinking
SEG_THINK=""
if [ "$THINKING" = "true" ]; then
  SEG_THINK=" ${IC_THINK}✦"
fi

# Permission
SEG_PERM=""
case "$PERM_LEVEL" in
  yolo) SEG_PERM=" ${IC_YOLO}Y" ;;
  auto) SEG_PERM=" ${IC_PERM}A" ;;
esac

# --- RIGHT SIDE SECONDARY (Line 2) ---
# Cache
CACHE_PCT_FMT=$(printf "%3d" "${CACHE_PCT:-0}")
SEG_CACHE="${IC_CACHE} ${CACHE_PCT_FMT}%%"

# Throughput
SEG_SPEED=""
if [ "$TOK_PER_S" != "0" ]; then
  SEG_SPEED="${IC_LATENCY} ${TOK_PER_S}t/s"
fi

# Rate limits
SEG_RATE5=""
SEG_RATE7=""
SEG_QUOTA=""
if [ "$PROXY_MODEL_SWAPPED" = "True" ] || [ "$PROXY_MODEL_SWAPPED" = "true" ]; then
  # Proxy mode: dual quota segment
  _a5=""; _a7=""
  if [ -n "$AGENT_RATE5_PCT" ] && [ "$AGENT_RATE5_PCT" != "0" ]; then _a5=$(printf "%3d" "$AGENT_RATE5_PCT"); fi
  if [ -n "$AGENT_RATE7_PCT" ] && [ "$AGENT_RATE7_PCT" != "0" ]; then _a7=$(printf "%3d" "$AGENT_RATE7_PCT"); fi
  _r5=""; _r7=""
  if [ -n "$DISPLAY_RATE5" ] && [ "$DISPLAY_RATE5" != "0" ] && [ "$DISPLAY_RATE5" != "" ]; then _r5=$(printf "%3d" "$DISPLAY_RATE5"); fi
  if [ -n "$DISPLAY_RATE7" ] && [ "$DISPLAY_RATE7" != "0" ] && [ "$DISPLAY_RATE7" != "" ]; then _r7=$(printf "%3d" "$DISPLAY_RATE7"); fi
  SEG_QUOTA="${IC_QUOTA}"
  if [ -n "$_a5" ]; then SEG_QUOTA+=" 5h${_a5}%%"; fi
  if [ -n "$_a7" ]; then SEG_QUOTA+="/7d${_a7}%%"; fi
  if [ -n "$_r5" ] || [ -n "$_r7" ]; then SEG_QUOTA+="|${QUOTA_PROVIDER}"; fi
  if [ -n "$_r5" ]; then SEG_QUOTA+=":5h${_r5}%%"; fi
  if [ -n "$_r7" ]; then SEG_QUOTA+="/7d${_r7}%%"; fi
else
  if [ "$DISPLAY_RATE5" != "0" ] && [ -n "$DISPLAY_RATE5" ]; then
    R5_FMT=$(printf "%3d" "$DISPLAY_RATE5")
    SEG_RATE5="${IC_RATE5}5h${R5_FMT}%%"
  fi
  if [ "$DISPLAY_RATE7" != "0" ] && [ -n "$DISPLAY_RATE7" ]; then
    R7_FMT=$(printf "%3d" "$DISPLAY_RATE7")
    SEG_RATE7="${IC_RATE7}7d${R7_FMT}%%"
  fi
  SEG_QUOTA=""  # not used in direct mode
fi

# Open remaining quota
SEG_OPENAI_QUOTA=""
if [ -n "$OPENAI_REQ_REMAIN" ] && [ "$OPENAI_REQ_REMAIN" != "0" ] && [ "$OPENAI_REQ_REMAIN" != "" ]; then
  SEG_OPENAI_QUOTA=" OAI:${OPENAI_REQ_REMAIN}req"
fi

# Background tasks segment (for line 2)
SEG_BG=""
if [ "$BG_TASK_COUNT" -gt 0 ]; then
  SEG_BG="${IC_BG_TASK}${BG_TASK_COUNT}"
fi

# Vim mode
SEG_VIM=""
if [ -n "$VIM_MODE" ] && [ "$VIM_MODE" != "NORMAL" ]; then
  SEG_VIM=" ${IC_VIM}${VIM_MODE}"
fi

# ==============================================================================
#  DETERMINE DISPLAY MODE
# ==============================================================================
# Default width if not provided
if [ -z "$TERM_WIDTH" ] || [ "$TERM_WIDTH" -lt 50 ]; then
  TERM_WIDTH=$(tput cols 2>/dev/null || echo "120")
fi

# 2-line mode when width >= 80
USE_TWO_LINES=false
if [ "$TERM_WIDTH" -ge 80 ]; then
  USE_TWO_LINES=true
fi

# ==============================================================================
#  RENDER
# ==============================================================================

if [ "$USE_TWO_LINES" = true ]; then
  # -------------------------------------------------------
  # 2-LINE MODE
  # Line 1: model  project  git  context  tokens  cost  duration  effort  perm
  # Line 2: cache  t/s  rate5/7  quota  budget  bg_tasks  compression  proxy
  # -------------------------------------------------------
  LEFT_PART="${SEG_MODEL}${SEG_PROXY} │ ${SEG_PROJECT}${SEG_GIT}${SEG_WORKTREE}${SEG_PR}${SEG_LINES}"

  # Primary line (right side)
  L1_RIGHT="${SEG_CTX} │ ${SEG_TOKENS} │ ${SEG_COST} │ ${SEG_DURATION}${SEG_TURN}${SEG_EFFORT}${SEG_THINK}${SEG_PERM}${SEG_YOLO_COUNT}"

  # Secondary line (full, centered on dim bg)
  L2_ITEMS=""
  if [ -n "$SEG_CACHE" ]; then
    L2_ITEMS+="${SEG_CACHE} │ "
  fi
  if [ -n "$SEG_SPEED" ]; then
    L2_ITEMS+="${SEG_SPEED} │ "
  fi
  if [ -n "$SEG_RATE5" ]; then
    L2_ITEMS+="${SEG_RATE5} "
  fi
  if [ -n "$SEG_RATE7" ]; then
    L2_ITEMS+="${SEG_RATE7} │ "
  fi
  if [ -n "$SEG_QUOTA" ]; then
    L2_ITEMS+="${SEG_QUOTA} "
  fi
  if [ -n "$SEG_BUDGET" ]; then
    L2_ITEMS+="${IC_COST}${SEG_BUDGET} │ "
  fi
  if [ -n "$SEG_BG" ]; then
    L2_ITEMS+="${SEG_BG} │ "
  fi
  if [ -n "$COMP_DISPLAY" ]; then
    L2_ITEMS+="${COMP_DISPLAY} │ "
  fi
  if [ -n "$SEG_PROXY" ]; then
    L2_ITEMS+="${SEG_PROXY} │ "
  fi
  if [ -n "$SEG_OPENAI_QUOTA" ]; then
    L2_ITEMS+="${SEG_OPENAI_QUOTA} "
  fi
  if [ -n "$SEG_VIM" ]; then
    L2_ITEMS+="${SEG_VIM} "
  fi

  # Remove trailing │
  L2_ITEMS="${L2_ITEMS% │ }"

  # Render line 1 (full powerline bar)
  echo -e "${C_BG}${C_FG_BRIGHT} ${LEFT_PART} ${C_FG_DIM}${PL_RIGHT_THIN}${C_BG2}${C_FG} ${L1_RIGHT} ${C_RESET}"

  # Render line 2 (dim background, secondary info)
  if [ -n "$L2_ITEMS" ]; then
    echo -e "${C_BG_QUOTA}${C_FG_DIM}  ${L2_ITEMS} ${C_RESET}"
  fi
else
  # -------------------------------------------------------
  # 1-LINE MODE (narrow terminal)
  # -------------------------------------------------------
  LEFT_PART="${SEG_MODEL}${SEG_PROXY} │ ${SEG_PROJECT}${SEG_GIT}${SEG_WORKTREE}${SEG_LINES}"

  # Right side: context, tokens, cost, duration + anything that fits
  RIGHT_PART="${SEG_CTX} │ ${SEG_TOKENS} │ ${SEG_COST}${SEG_EFFORT}${SEG_DURATION}${SEG_TURN}${SEG_PERM}${SEG_YOLO_COUNT}${SEG_THINK}"

  echo -e "${C_BG}${C_FG_BRIGHT} ${LEFT_PART} ${C_FG_DIM}${PL_RIGHT_THIN}${C_BG2}${C_FG} ${RIGHT_PART} ${C_RESET}"
fi
