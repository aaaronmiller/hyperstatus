#!/usr/bin/env bash
# ============================================================================
#  HYPERSTATUS v2.0 — Universal Setup & Install Script
#  Supports: Claude Code, Codex CLI, Hermes Agent, Pi Agent
#  Features: Backup, restore, verification, agent auto-detection
#  Usage:    ./setup.sh [claude|codex|hermes|pi|all] [--backup] [--restore]
# ============================================================================

set -euo pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${BASE_DIR}/backups/$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${BASE_DIR}/setup.log"

# Resolve home directory (use chetaz fallback if $HOME fails)
if [ -z "${HOME:-}" ] || [ "$HOME" = "/" ]; then
  HOME_DIR="/home/chetaz"
else
  HOME_DIR="$HOME"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# --- Logging ---
log() {
  echo -e "${CYAN}[$(date '+%H:%M:%S')]${RESET} $*" | tee -a "$LOG_FILE"
}
log_success() {
  echo -e "${GREEN}[✓]${RESET} $*" | tee -a "$LOG_FILE"
}
log_warn() {
  echo -e "${YELLOW}[!]${RESET} $*" | tee -a "$LOG_FILE"
}
log_error() {
  echo -e "${RED}[✗]${RESET} $*" | tee -a "$LOG_FILE"
}
log_info() {
  echo -e "${BLUE}[i]${RESET} $*" | tee -a "$LOG_FILE"
}

# --- Agent Detection ---
detect_agents() {
  log_info "Detecting installed agents..."
  
  AGENTS_FOUND=()
  
  # Claude Code
  if command -v claude &>/dev/null; then
    AGENTS_FOUND+=("claude")
    log_success "Claude Code detected: $(claude --version 2>/dev/null || echo 'version unknown')"
  elif [ -d "${HOME_DIR}/.claude" ]; then
    AGENTS_FOUND+=("claude")
    log_success "Claude Code config found at ${HOME_DIR}/.claude/"
  else
    log_warn "Claude Code not found"
  fi
  
  # Codex CLI
  if command -v codex &>/dev/null; then
    AGENTS_FOUND+=("codex")
    log_success "Codex CLI detected: $(codex --version 2>/dev/null || echo 'version unknown')"
  elif [ -f "${HOME_DIR}/.codex/config.toml" ]; then
    AGENTS_FOUND+=("codex")
    log_success "Codex CLI config found at ${HOME_DIR}/.codex/"
  else
    log_warn "Codex CLI not found"
  fi
  
  # Hermes Agent
  if command -v hermes &>/dev/null; then
    AGENTS_FOUND+=("hermes")
    log_success "Hermes Agent detected"
  elif [ -d "${HOME_DIR}/.hermes" ]; then
    AGENTS_FOUND+=("hermes")
    log_success "Hermes config found at ${HOME_DIR}/.hermes/"
  else
    log_warn "Hermes Agent not found"
  fi
  
  # Pi Agent
  if command -v pi &>/dev/null; then
    AGENTS_FOUND+=("pi")
    log_success "Pi Agent detected"
  elif [ -d "${HOME_DIR}/.pi" ]; then
    AGENTS_FOUND+=("pi")
    log_success "Pi config found at ${HOME_DIR}/.pi/"
  else
    log_warn "Pi Agent not found"
  fi
  
  if [ ${#AGENTS_FOUND[@]} -eq 0 ]; then
    log_error "No coding agent CLI tools detected!"
    log_info "You can still install configurations for future use."
  fi
}

# --- Backup Functions ---
backup_claude() {
  local claude_dir="${HOME_DIR}/.claude"
  if [ ! -d "$claude_dir" ]; then
    log_warn "No Claude Code directory to backup"
    return 0
  fi
  
  mkdir -p "${BACKUP_DIR}/claude"
  
  # Backup settings.json
  if [ -f "${claude_dir}/settings.json" ]; then
    cp "${claude_dir}/settings.json" "${BACKUP_DIR}/claude/settings.json"
    log_success "Backed up claude/settings.json"
  fi
  
  # Backup existing statusline script
  if [ -f "${claude_dir}/statusline.sh" ]; then
    cp "${claude_dir}/statusline.sh" "${BACKUP_DIR}/claude/statusline.sh"
    log_success "Backed up claude/statusline.sh"
  fi
  
  # Backup any other custom scripts
  for f in "${claude_dir}/"*.sh; do
    [ -f "$f" ] && cp "$f" "${BACKUP_DIR}/claude/" && log_success "Backed up $(basename "$f")"
  done
}

backup_codex() {
  local codex_dir="${HOME_DIR}/.codex"
  if [ ! -d "$codex_dir" ]; then
    log_warn "No Codex directory to backup"
    return 0
  fi
  
  mkdir -p "${BACKUP_DIR}/codex"
  
  if [ -f "${codex_dir}/config.toml" ]; then
    cp "${codex_dir}/config.toml" "${BACKUP_DIR}/codex/config.toml"
    log_success "Backed up codex/config.toml"
  fi
}

backup_hermes() {
  local hermes_dir="${HOME_DIR}/.hermes"
  if [ ! -d "$hermes_dir" ]; then
    log_warn "No Hermes directory to backup"
    return 0
  fi
  
  mkdir -p "${BACKUP_DIR}/hermes"
  
  if [ -f "${hermes_dir}/config.yaml" ]; then
    cp "${hermes_dir}/config.yaml" "${BACKUP_DIR}/hermes/config.yaml"
    log_success "Backed up hermes/config.yaml"
  fi
}

backup_pi() {
  local pi_dir="${HOME_DIR}/.pi"
  if [ ! -d "$pi_dir" ]; then
    log_warn "No Pi directory to backup"
    return 0
  fi
  
  mkdir -p "${BACKUP_DIR}/pi"
  
  if [ -f "${pi_dir}/config.toml" ]; then
    cp "${pi_dir}/config.toml" "${BACKUP_DIR}/pi/config.toml"
    log_success "Backed up pi/config.toml"
  fi
  
  # Backup existing extensions
  if [ -d "${pi_dir}/extensions" ]; then
    cp -r "${pi_dir}/extensions" "${BACKUP_DIR}/pi/extensions"
    log_success "Backed up pi/extensions/"
  fi
}

# --- Install Functions ---
install_claude() {
  log "${BOLD}Installing HyperStatus for Claude Code...${RESET}"
  
  local claude_dir="${HOME_DIR}/.claude"
  mkdir -p "$claude_dir"
  
  # Install statusline script
  cp "${SCRIPT_DIR}/../claude-code/statusline.sh" "${claude_dir}/statusline.sh"
  chmod +x "${claude_dir}/statusline.sh"
  log_success "Installed statusline.sh to ${claude_dir}/"
  
  # Merge settings.json (preserve existing settings, add/update statusLine)
  local settings_file="${claude_dir}/settings.json"
  if [ -f "$settings_file" ]; then
    # Use python3 to merge JSON safely
    python3 -c "
import json, sys
with open('$settings_file', 'r') as f:
    existing = json.load(f)
with open('${SCRIPT_DIR}/../claude-code/settings.json', 'r') as f:
    new_statusline = json.load(f)
existing.update(new_statusline)
with open('$settings_file', 'w') as f:
    json.dump(existing, f, indent=2)
print('Merged statusLine into existing settings.json')
" 2>/dev/null && log_success "Merged statusLine config into settings.json" || {
      log_warn "Could not merge settings.json automatically"
      log_info "Manually add this to ${settings_file}:"
      cat "${SCRIPT_DIR}/../claude-code/settings.json"
    }
  else
    cp "${SCRIPT_DIR}/../claude-code/settings.json" "$settings_file"
    log_success "Created new settings.json"
  fi
  
  # Verify
  if [ -f "${claude_dir}/statusline.sh" ] && [ -x "${claude_dir}/statusline.sh" ]; then
    log_success "Claude Code HyperStatus installed!"
  else
    log_error "Installation verification failed"
    return 1
  fi
}

install_codex() {
  log "${BOLD}Installing HyperStatus for Codex CLI...${RESET}"
  
  local codex_dir="${HOME_DIR}/.codex"
  mkdir -p "$codex_dir"
  
  if [ -f "${codex_dir}/config.toml" ]; then
    # Merge TOML (basic approach - append if status_line not present)
    if grep -q "status_line" "${codex_dir}/config.toml"; then
      log_warn "Existing status_line found in config.toml"
      log_info "Review and update manually, or use --force to overwrite"
      log_info "Reference config:"
      cat "${SCRIPT_DIR}/../codex/config.toml"
    else
      # Append our [tui] section
      echo "" >> "${codex_dir}/config.toml"
      cat "${SCRIPT_DIR}/../codex/config.toml" >> "${codex_dir}/config.toml"
      log_success "Appended HyperStatus config to config.toml"
    fi
  else
    cp "${SCRIPT_DIR}/../codex/config.toml" "${codex_dir}/config.toml"
    log_success "Created new config.toml"
  fi
  
  log_success "Codex CLI HyperStatus installed!"
}

install_hermes() {
  log "${BOLD}Installing HyperStatus for Hermes Agent...${RESET}"
  
  local hermes_dir="${HOME_DIR}/.hermes"
  mkdir -p "$hermes_dir"
  
  if [ -f "${hermes_dir}/config.yaml" ]; then
    log_warn "Existing config.yaml found"
    log_info "Manual merge recommended. Reference config:"
    cat "${SCRIPT_DIR}/../hermes/config.yaml"
  else
    cp "${SCRIPT_DIR}/../hermes/config.yaml" "${hermes_dir}/config.yaml"
    log_success "Created new config.yaml"
  fi
  
  log_success "Hermes Agent HyperStatus installed!"
}

install_pi() {
  log "${BOLD}Installing HyperStatus for Pi Agent...${RESET}"
  
  local pi_dir="${HOME_DIR}/.pi"
  local ext_dir="${pi_dir}/extensions/hyperstatus"
  mkdir -p "$ext_dir"
  
  # Copy extension files
  cp "${SCRIPT_DIR}/../pi/hyperstatus-extension.ts" "${ext_dir}/index.ts"
  cp "${SCRIPT_DIR}/../pi/powerline-config.ts" "${ext_dir}/powerline-config.ts"
  
  # Create package.json for the extension
  cat > "${ext_dir}/package.json" << 'PKGJSON'
{
  "name": "hyperstatus",
  "version": "2.0.0",
  "description": "Powerline-style status bar with full metric coverage",
  "main": "index.ts",
  "piExtension": true,
  "permissions": ["statusbar", "filesystem", "network"]
}
PKGJSON
  
  log_success "Installed Pi extension to ${ext_dir}/"
  log_info "Run /reload in Pi to activate the extension"
}

# --- Restore Functions ---
restore_claude() {
  local backup_path="${1:-}"
  if [ -z "$backup_path" ]; then
    log_error "No backup path specified"
    return 1
  fi
  
  if [ -d "${backup_path}/claude" ]; then
    cp -r "${backup_path}/claude/"* "${HOME_DIR}/.claude/"
    log_success "Restored Claude Code from backup"
  else
    log_error "No Claude Code backup found at ${backup_path}"
  fi
}

restore_codex() {
  local backup_path="${1:-}"
  if [ -z "$backup_path" ]; then
    log_error "No backup path specified"
    return 1
  fi
  
  if [ -d "${backup_path}/codex" ]; then
    cp -r "${backup_path}/codex/"* "${HOME_DIR}/.codex/"
    log_success "Restored Codex CLI from backup"
  else
    log_error "No Codex CLI backup found at ${backup_path}"
  fi
}

restore_hermes() {
  local backup_path="${1:-}"
  if [ -z "$backup_path" ]; then
    log_error "No backup path specified"
    return 1
  fi
  
  if [ -d "${backup_path}/hermes" ]; then
    cp -r "${backup_path}/hermes/"* "${HOME_DIR}/.hermes/"
    log_success "Restored Hermes Agent from backup"
  else
    log_error "No Hermes Agent backup found at ${backup_path}"
  fi
}

restore_pi() {
  local backup_path="${1:-}"
  if [ -z "$backup_path" ]; then
    log_error "No backup path specified"
    return 1
  fi
  
  if [ -d "${backup_path}/pi" ]; then
    cp -r "${backup_path}/pi/"* "${HOME_DIR}/.pi/"
    log_success "Restored Pi Agent from backup"
  else
    log_error "No Pi Agent backup found at ${backup_path}"
  fi
}

# --- Compression Integration Setup ---
setup_compression() {
  log "${BOLD}Setting up compression proxy integration...${RESET}"
  
  # Check for RTK
  if command -v rtk &>/dev/null; then
    log_success "RTK detected: $(rtk --version 2>/dev/null || echo 'installed')"
    
    # Set up RTK metrics file
    RTK_METRICS="/tmp/rtk-metrics.json"
    log_info "RTK metrics will be written to ${RTK_METRICS}"
    
    # Add RTK hook to Claude Code if installed
    if [ -d "${HOME_DIR}/.claude" ]; then
      log_info "Consider adding RTK hook to Claude Code:"
      log_info "  rtk init --global"
    fi
  else
    log_warn "RTK not installed. Install: https://github.com/rtk-ai/rtk"
    log_info "  curl -fsSL https://rtk.ai/install | bash"
  fi
  
  # Check for Headroom
  if pip3 list 2>/dev/null | grep -q "headroom-ai" || npm list -g headroom-ai &>/dev/null; then
    log_success "Headroom detected"
    log_info "Start headroom proxy: headroom proxy --port 8787"
    log_info "Set ANTHROPIC_BASE_URL=http://localhost:8787/v1 for Claude Code"
  else
    log_warn "Headroom not installed. Install: pip install headroom-ai"
    log_info "  or: npm install -g headroom-ai"
  fi
  
  # Create environment helper script
  cat > "${BASE_DIR}/compression-env.sh" << 'ENVSCRIPT'
#!/usr/bin/env bash
# Source this file to enable compression proxy integration
# Usage: source ./compression-env.sh [headroom|rtk|both]

export HEADROOM_ENDPOINT="${HEADROOM_ENDPOINT:-http://localhost:8787}"
export RTK_METRICS_FILE="${RTK_METRICS_FILE:-/tmp/rtk-metrics.json}"

# Headroom proxy mode
if [ "$1" = "headroom" ] || [ "$1" = "both" ]; then
  export ANTHROPIC_BASE_URL="http://localhost:8787/v1"
  export OPENAI_BASE_URL="http://localhost:8787/v1"
  echo "Headroom proxy: ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL"
fi

# RTK metrics mode
if [ "$1" = "rtk" ] || [ "$1" = "both" ]; then
  if command -v rtk &>/dev/null; then
    rtk gain --json > "$RTK_METRICS_FILE" 2>/dev/null &
    echo "RTK metrics polling: $RTK_METRICS_FILE"
  else
    echo "RTK not installed"
  fi
fi

# Export compression variables for statusline scripts
export HEADROOM_TOKENS_SAVED=""
export HEADROOM_COMPRESSION_RATIO=""

echo "Compression environment configured. Start your agent CLI."
ENVSCRIPT
  chmod +x "${BASE_DIR}/compression-env.sh"
  log_success "Created compression-env.sh"
}

# --- Main ---
usage() {
  cat << 'EOF'
HYPERSTATUS v2.0 — Universal Coding Agent Status Bar

Usage: ./setup.sh [COMMAND] [TARGET] [OPTIONS]

Commands:
  install    Install status bar for target agent(s)
  backup     Backup current agent configurations
  restore    Restore from a backup
  detect     Detect installed agents
  compress   Set up compression proxy integration
  status     Show current installation status

Targets:
  claude     Claude Code only
  codex      Codex CLI only
  hermes     Hermes Agent only
  pi         Pi Agent only
  all        All detected agents

Options:
  --force    Overwrite existing configurations without prompt
  --backup   Create backup before installing (default behavior)
  --no-backup  Skip backup
  --restore PATH  Restore from specific backup path

Examples:
  ./setup.sh install all          # Install for all detected agents
  ./setup.sh install claude       # Install for Claude Code only
  ./setup.sh backup all           # Backup all agent configs
  ./setup.sh restore all /path    # Restore from specific backup
  ./setup.sh compress             # Set up RTK/Headroom integration
  ./setup.sh status               # Show current status
EOF
}

main() {
  local command="${1:-help}"
  local target="${2:-all}"
  local force=false
  local do_backup=true
  local restore_path=""
  
  # Parse options
  shift 2 2>/dev/null || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --force) force=true ;;
      --no-backup) do_backup=false ;;
      --restore) restore_path="${2:-}"; shift ;;
    esac
    shift
  done
  
  # Initialize log
  mkdir -p "$(dirname "$LOG_FILE")"
  echo "=== HyperStatus Setup - $(date) ===" > "$LOG_FILE"
  
  case "$command" in
    install)
      detect_agents
      
      # Backup first
      if [ "$do_backup" = true ]; then
        log "${BOLD}Creating backups...${RESET}"
        mkdir -p "$BACKUP_DIR"
        backup_claude
        backup_codex
        backup_hermes
        backup_pi
        log_success "Backups saved to ${BACKUP_DIR}"
      fi
      
      # Install
      case "$target" in
        claude) install_claude ;;
        codex) install_codex ;;
        hermes) install_hermes ;;
        pi) install_pi ;;
        all)
          for agent in "${AGENTS_FOUND[@]:-}"; do
            "install_${agent}" 2>/dev/null || log_warn "Install for $agent skipped"
          done
          # Install for agents not detected too (for future use)
          if [ ${#AGENTS_FOUND[@]} -eq 0 ]; then
            log_info "No agents detected. Installing all configs for future use..."
            install_claude
            install_codex
            install_hermes
            install_pi
          fi
          ;;
        *)
          log_error "Unknown target: $target"
          usage
          exit 1
          ;;
      esac
      
      echo ""
      log "${BOLD}${GREEN}Installation complete!${RESET}"
      log_info "Restart your agent CLI to see the new status bar"
      if [ "$do_backup" = true ]; then
        log_info "Backups at: ${BACKUP_DIR}"
      fi
      ;;
      
    backup)
      mkdir -p "$BACKUP_DIR"
      case "$target" in
        claude) backup_claude ;;
        codex) backup_codex ;;
        hermes) backup_hermes ;;
        pi) backup_pi ;;
        all)
          backup_claude
          backup_codex
          backup_hermes
          backup_pi
          ;;
      esac
      log_success "Backups saved to ${BACKUP_DIR}"
      ;;
      
    restore)
      if [ -z "$restore_path" ]; then
        log_error "Specify backup path with --restore PATH"
        # List available backups
        if [ -d "${BASE_DIR}/backups" ]; then
          log_info "Available backups:"
          ls -1 "${BASE_DIR}/backups/"
        fi
        exit 1
      fi
      
      case "$target" in
        claude) restore_claude "$restore_path" ;;
        codex) restore_codex "$restore_path" ;;
        hermes) restore_hermes "$restore_path" ;;
        pi) restore_pi "$restore_path" ;;
        all)
          restore_claude "$restore_path"
          restore_codex "$restore_path"
          restore_hermes "$restore_path"
          restore_pi "$restore_path"
          ;;
      esac
      log_success "Restore complete!"
      ;;
      
    detect)
      detect_agents
      echo ""
      log_info "Found ${#AGENTS_FOUND[@]} agent(s): ${AGENTS_FOUND[*]:-none}"
      ;;
      
    compress)
      setup_compression
      ;;
      
    status)
      log "${BOLD}HyperStatus Installation Status${RESET}"
      echo ""
      
      # Claude Code
      if [ -f "${HOME_DIR}/.claude/statusline.sh" ]; then
        log_success "Claude Code: HyperStatus installed"
      elif [ -f "${HOME_DIR}/.claude/settings.json" ]; then
        log_warn "Claude Code: Custom settings exist, no HyperStatus"
      else
        log_info "Claude Code: Not configured"
      fi
      
      # Codex CLI
      if [ -f "${HOME_DIR}/.codex/config.toml" ] && grep -q "status_line" "${HOME_DIR}/.codex/config.toml" 2>/dev/null; then
        log_success "Codex CLI: Status line configured"
      else
        log_info "Codex CLI: Not configured"
      fi
      
      # Hermes
      if [ -f "${HOME_DIR}/.hermes/config.yaml" ] && grep -q "status_bar" "${HOME_DIR}/.hermes/config.yaml" 2>/dev/null; then
        log_success "Hermes: Status bar configured"
      else
        log_info "Hermes: Not configured"
      fi
      
      # Pi
      if [ -d "${HOME_DIR}/.pi/extensions/hyperstatus" ]; then
        log_success "Pi Agent: HyperStatus extension installed"
      else
        log_info "Pi Agent: Not configured"
      fi
      
      # Backups
      if [ -d "${BASE_DIR}/backups" ]; then
        local backup_count
        backup_count=$(ls -1d "${BASE_DIR}/backups/"*/ 2>/dev/null | wc -l)
        log_info "Backups: ${backup_count} backup(s) available"
      fi
      ;;
      
    help|--help|-h)
      usage
      ;;
      
    *)
      log_error "Unknown command: $command"
      usage
      exit 1
      ;;
  esac
}

main "$@"
