#!/usr/bin/env bash
# ============================================================================
#  HYPERSTATUS v3.2 — Antigravity CLI Status Bar
#  Powerline-style status bar with 2-line mode
#
#  Reads JSON from stdin (Antigravity CLI statusline protocol)
#  Configure: ~/.gemini/antigravity-cli/settings.json
#    "statusLine": { "type": "command", "command": "~/.gemini/antigravity-cli/statusline.sh" }
# ============================================================================

set -euo pipefail

INPUT=$(cat)

# --- Color Palette (Catppuccin Mocha) ---
C_BG='\033[48;5;30m'        # Deep teal
C_BG2='\033[48;5;24m'       # Darker teal
C_BG3='\033[48;5;60m'       # Purple accent
C_BG_WARN='\033[48;5;130m'  # Orange
C_BG_CRIT='\033[48;5;160m'  # Red
C_BG_OK='\033[48;5;70m'     # Green
C_BG_QUOTA='\033[48;5;97m'  # Mauve
C_BG_PROXY='\033[48;5;54m'  # Purple
C_FG='\033[38;5;230m'       # Light text
C_FG_DIM='\033[38;5;180m'   # Dimmed
C_FG_BRIGHT='\033[38;5;255m'
C_FG_GREEN='\033[38;5;150m'
C_FG_YELLOW='\033[38;5;220m'
C_FG_RED='\033[38;5;210m'
C_RESET='\033[0m'

PL_RIGHT='\ue0b0'
PL_RIGHT_THIN='\ue0b1'

# Nerd Font icons
IC_MODEL='\ue716'
IC_CTX='\uf6cf'
IC_BRANCH='\uf418'
IC_DIR='\uf07b'
IC_TIME='\uf017'
IC_TOKEN='\uf1c9'
IC_BG_TASK='\uf44e'
IC_PERM='\uf132'
IC_LATENCY='\uf9ee'
IC_SANDBOX='\uf132'
IC_WARN='\uf071'

# --- JSON value extraction ---
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
  # Handle booleans
  if isinstance(v, bool):
    print(str(v).lower())
  else:
    print(str(v))
" 2>/dev/null || echo ""
}

# --- Helpers ---
ctx_color() {
  local pct="$1"
  if (( $(echo "$pct >= 95" | bc -l) )); then echo -e "$C_BG_CRIT"
  elif (( $(echo "$pct >= 80" | bc -l) )); then echo -e "$C_BG_WARN"
  elif (( $(echo "$pct >= 50" | bc -l) )); then echo -e "$C_BG3"
  else echo -e "$C_BG_OK"
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

# ==============================================================================
#  EXTRACT DATA
# ==============================================================================
MODEL=$(jval "model.display_name")
if [ -z "$MODEL" ]; then MODEL=$(jval "model.id"); fi
CWD=$(jval "cwd")
PROJECT_DIR=$(jval "workspace.current_dir")
if [ -z "$PROJECT_DIR" ]; then PROJECT_DIR=$(jval "cwd"); fi
PROJECT_DISPLAY=$(basename "${PROJECT_DIR:-~}")
VCS_TYPE=$(jval "vcs.type")
VCS_BRANCH=$(jval "vcs.branch")
VCS_DIRTY=$(jval "vcs.dirty")
AGENT_STATE=$(jval "agent_state")
PLAN_TIER=$(jval "plan_tier")
TERM_WIDTH=$(jval "terminal_width")

# Context window
INPUT_TOKENS=$(jval "context_window.total_input_tokens")
OUTPUT_TOKENS=$(jval "context_window.total_output_tokens")
CTX_SIZE=$(jval "context_window.context_window_size")
CTX_PCT=$(jval "context_window.used_percentage")
CACHE_CREATE=$(jval "context_window.current_usage.cache_creation_input_tokens")
CACHE_READ=$(jval "context_window.current_usage.cache_read_input_tokens")

# Background tasks count
_BG_TASKS=$(jval "background_tasks")
BG_TASK_COUNT=0
if [ -n "$_BG_TASKS" ]; then
  BG_TASK_COUNT=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('background_tasks',[])))" 2>/dev/null || echo "0")
fi

# Subagents count
_SUBAGENTS=$(jval "subagents")
SUBAGENT_COUNT=0
if [ -n "$_SUBAGENTS" ]; then
  SUBAGENT_COUNT=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('subagents',[])))" 2>/dev/null || echo "0")
fi

# Pending input
PENDING_INPUT=$(jval "pending_input_count")
SANDBOX=$(jval "sandbox.enabled")

# --- Derived ---
TOTAL_TOKENS=$((INPUT_TOKENS + OUTPUT_TOKENS))
if [ -n "$CTX_SIZE" ] && [ "$CTX_SIZE" -gt 0 ] && [ -n "$INPUT_TOKENS" ] && [ "$INPUT_TOKENS" -gt 0 ]; then
  CACHE_PCT=$(echo "scale=0; $CACHE_READ * 100 / $INPUT_TOKENS" | bc 2>/dev/null || echo "0")
else
  CACHE_PCT="0"
fi

# Short model name
SHORT_MODEL=$(echo "$MODEL" | sed 's/gemini/gm/' | sed 's/claude-/c/' | sed 's/gpt-/g/' | sed 's/-202.*//' | sed 's/-latest//' | sed 's/ [0-9]*[KMB].*//')
if [ -z "$SHORT_MODEL" ]; then SHORT_MODEL="unknown"; fi

# Agent state icon
STATE_ICON=""
case "$AGENT_STATE" in
  thinking) STATE_ICON="${IC_TIME}⟐" ;;
  working|tool_use) STATE_ICON="${IC_TIME}⚙" ;;
  idle) STATE_ICON="" ;;
  initializing) STATE_ICON="${IC_TIME}○" ;;
  *) STATE_ICON="" ;;
esac

# Dirty indicator
DIRTY_INDICATOR=""
if [ "$VCS_DIRTY" = "true" ]; then DIRTY_INDICATOR="±"; fi

# ==============================================================================
#  BUILD SEGMENTS
# ==============================================================================
SEG_MODEL="${IC_MODEL} ${SHORT_MODEL}"
SEG_PROJECT="${IC_DIR} ${PROJECT_DISPLAY}"

GIT_DISPLAY=""
if [ -n "$VCS_BRANCH" ]; then
  GIT_DISPLAY=" ${IC_BRANCH} ${VCS_BRANCH}${DIRTY_INDICATOR}"
fi

# Plan tier
PLAN_DISPLAY=""
if [ -n "$PLAN_TIER" ] && [ "$PLAN_TIER" != "Free" ]; then
  PLAN_DISPLAY=" ${PLAN_TIER}"
fi

# Context
CTX_CLR=$(ctx_color "${CTX_PCT:-0}")
BAR=$(ctx_bar "${CTX_PCT:-0}")
CTX_PCT_FMT=$(printf "%5.1f" "${CTX_PCT:-0}")
SEG_CTX="${IC_CTX} ${BAR} ${CTX_PCT_FMT}%%"

# Tokens
TOTAL_FMT=$(fmt_tokens "${TOTAL_TOKENS:-0}")
CTX_SIZE_FMT=$(fmt_tokens "${CTX_SIZE:-0}")
SEG_TOKENS="${IC_TOKEN} ${TOTAL_FMT}/${CTX_SIZE_FMT}"

# Cache
SEG_CACHE=""
if [ "$CACHE_PCT" != "0" ] && [ -n "$CACHE_PCT" ]; then
  CACHE_PCT_FMT=$(printf "%3d" "${CACHE_PCT}")
  SEG_CACHE="${IC_CTX} cache ${CACHE_PCT_FMT}%%"
fi

# Background tasks
SEG_BG=""
if [ "$BG_TASK_COUNT" -gt 0 ]; then
  SEG_BG="${IC_BG_TASK}${BG_TASK_COUNT}"
fi

# Subagents
SEG_SUB=""
if [ "$SUBAGENT_COUNT" -gt 0 ]; then
  SEG_SUB="⊞${SUBAGENT_COUNT}"
fi

# Pending input indicator
SEG_PENDING=""
if [ -n "$PENDING_INPUT" ] && [ "$PENDING_INPUT" -gt 0 ]; then
  SEG_PENDING="${IC_WARN}${PENDING_INPUT}"
fi

# Sandbox
SEG_SANDBOX=""
if [ "$SANDBOX" = "true" ]; then
  SEG_SANDBOX="${IC_PERM}SB"
fi

# ==============================================================================
#  DISPLAY MODE
# ==============================================================================
if [ -z "$TERM_WIDTH" ] || [ "$TERM_WIDTH" -lt 50 ]; then
  TERM_WIDTH=$(tput cols 2>/dev/null || echo "120")
fi

USE_TWO_LINES=false
if [ "$TERM_WIDTH" -ge 80 ]; then
  USE_TWO_LINES=true
fi

# ==============================================================================
#  RENDER
# ==============================================================================
if [ "$USE_TWO_LINES" = true ]; then
  # Line 1: model │ project │ git │ context │ tokens │ state │ plan
  LEFT_PART="${SEG_MODEL} │ ${SEG_PROJECT}${GIT_DISPLAY}"
  L1_RIGHT="${SEG_CTX} │ ${SEG_TOKENS}${STATE_ICON}${PLAN_DISPLAY}"

  echo -e "${C_BG}${C_FG_BRIGHT} ${LEFT_PART} ${C_FG_DIM}${PL_RIGHT_THIN}${C_BG2}${C_FG} ${L1_RIGHT} ${C_RESET}"

  # Line 2: cache │ bg tasks │ subagents │ pending │ sandbox
  L2_ITEMS=""
  if [ -n "$SEG_CACHE" ]; then         L2_ITEMS+="${SEG_CACHE} │ "; fi
  if [ -n "$SEG_BG" ]; then            L2_ITEMS+="${SEG_BG} │ "; fi
  if [ -n "$SEG_SUB" ]; then           L2_ITEMS+="${SEG_SUB} │ "; fi
  if [ -n "$SEG_PENDING" ]; then       L2_ITEMS+="${SEG_PENDING} │ "; fi
  if [ -n "$SEG_SANDBOX" ]; then       L2_ITEMS+="${SEG_SANDBOX} │ "; fi

  L2_ITEMS="${L2_ITEMS% │ }"
  if [ -n "$L2_ITEMS" ]; then
    echo -e "${C_BG_QUOTA}${C_FG_DIM}  ${L2_ITEMS} ${C_RESET}"
  fi
else
  # 1-line mode
  LEFT_PART="${SEG_MODEL} │ ${SEG_PROJECT}${GIT_DISPLAY}"
  RIGHT_PART="${SEG_CTX} │ ${SEG_TOKENS}${STATE_ICON}"
  echo -e "${C_BG}${C_FG_BRIGHT} ${LEFT_PART} ${C_FG_DIM}${PL_RIGHT_THIN}${C_BG2}${C_FG} ${RIGHT_PART} ${C_RESET}"
fi
