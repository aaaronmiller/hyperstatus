# HYPERSTATUS v3.0 — Installation & Integration Guide

> Powerline-style status bar for coding agent CLIs with full metric coverage,
> multi-provider quota tracking, compression proxy integration, and proxy-aware
> dual quota display.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Quick Start](#2-quick-start)
3. [Agent-Specific Installation](#3-agent-specific-installation)
   - [Claude Code](#31-claude-code)
   - [Codex CLI](#32-codex-cli)
   - [Hermes Agent](#33-hermes-agent)
   - [Pi Agent](#34-pi-agent)
   - [Antigravity CLI](#35-antigravity-cli)
4. [2-Line Display Mode](#-2-line-display-mode)
5. [Headroom Compression Integration](#4-headroom-compression-integration)
6. [RTK Terminal Compression Integration](#5-rtk-terminal-compression-integration)
7. [Quota Tracking Setup](#6-quota-tracking-setup)
   - [onWatch](#61-onwatch-daemon)
   - [ccusage](#62-ccusage-cli)
   - [LiteLLM Proxy](#63-litellm-proxy)
   - [LLM-API-Key-Proxy](#64-llm-api-key-proxy)
8. [Proxy Model Detection](#7-proxy-model-detection)
9. [Environment Variables Reference](#8-environment-variables-reference)
10. [Architecture & Data Flow](#9-architecture--data-flow)
11. [Troubleshooting](#10-troubleshooting)

---

## 1. Prerequisites

### Required

| Dependency | Purpose | Install |
|---|---|---|
| **Nerd Font** | Icons and Powerline separators | [nerdfonts.com](https://www.nerdfonts.com) — recommended: JetBrains Mono Nerd Font, FiraCode Nerd Font, or MesloLGS NF |
| **python3** | JSON parsing, metric computation | System package manager |
| **bc** | Arithmetic in shell scripts | System package manager (`bc`) |
| **curl** | API calls to proxy endpoints | System package manager |

### Optional (enables additional features)

| Dependency | Purpose | Install |
|---|---|---|
| **jq** | Faster JSON parsing (falls back to python3) | `brew install jq` / `apt install jq` |
| **git** | Branch, status, worktree display | System package manager |
| **sqlite3** | Reading onWatch quota database | System package manager |
| **tmux** | Codex CLI wrapper status bar | System package manager |

### Terminal Requirements

- 256-color support (or truecolor for best results)
- Unicode support for Nerd Font glyphs
- Minimum 76 columns for full layout; 52+ for compact; works down to ~30 in minimal mode

---

## 2. Quick Start

```bash
# Clone or extract the HYPERSTATUS package
cd ~/.local/share/hyperstatus   # or wherever you extracted it

# Run the universal setup script
./scripts/setup.sh install all

# Source the environment (compression + quota)
source ./compression-env.sh all

# Start your agent
claude
```

The setup script will:
1. Auto-detect which agent CLIs are installed
2. Back up any existing configurations
3. Install the status bar config for each detected agent
4. Report what was installed and what needs manual setup

---

## 3. Agent-Specific Installation

### 3.1 Claude Code

Claude Code has the **most customizable** status bar — it pipes JSON to a shell script on stdin every 3 seconds. This gives us full control over rendering.

#### Automatic Install

```bash
./scripts/setup.sh install claude
```

This copies `statusline.sh` to `~/.claude/statusline.sh` and merges the `statusLine` config into `~/.claude/settings.json`.

#### Manual Install

1. Copy the statusline script:

```bash
mkdir -p ~/.claude
cp claude-code/statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

2. Add the statusLine config to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 1,
    "refreshInterval": 3,
    "hideVimModeIndicator": true
  }
}
```

If `settings.json` already exists, merge the `statusLine` key into it — don't overwrite other settings.

3. Restart Claude Code. You should see the Powerline status bar immediately.

#### What You'll See

```
Line 1: 󰜖 csonnet │ 󰝷 myproject 󰐘 main +42/-7 │ ████░░░░░░  8.2% │ 15.5K/200K │ ⠿ 42% │ $1.23 │ 5h 42% 7d 28% │ 12m
Line 2: (appears when context >50%) Context detail with token breakdown
Line 3: (appears when quota >50% or proxy active) Multi-provider quota detail
```

---

### 3.2 Codex CLI

Codex CLI has the **most constrained** status bar — it only supports a fixed enum of built-in items. There is no custom script support (issues #17827, #16921 request this). No Nerd Font icons, no custom colors, no multi-line.

#### What Codex CAN Show (built-in enum)

- `model-with-reasoning` — Current model name
- `current-dir` — Working directory
- `git-branch` — Git branch name
- `context-used` — Context window % used
- `context-remaining` — Context remaining
- `context-window-size` — Total context window
- `used-tokens` — Token count
- `total-output-tokens` — Output token count
- `five-hour-limit` — 5-hour rate limit
- `weekly-limit` — Weekly rate limit

#### What Codex CANNOT Show (platform limitation)

- Session cost, duration, cache hit rate, git status, compression, latency, throughput, background tasks, quota from external tools — **none of these are possible inside the Codex TUI**.

#### Option A: Built-in Config Only

```bash
./scripts/setup.sh install codex
```

This maximizes the built-in `status_line` items in `~/.codex/config.toml`.

#### Option B: tmux Wrapper (Full Feature Parity)

The `codex-wrapper.sh` script runs Codex inside a tmux session with a custom status bar in the tmux status line that shows ALL features, including quota:

```bash
# Instead of running: codex
# Run:
./codex/codex-wrapper.sh

# Or with Codex arguments:
./codex/codex-wrapper.sh --model o4-mini
```

This gives you the same visual format as the Claude Code version, rendered as the tmux bottom status bar while Codex runs in the main pane.

---

### 3.3 Hermes Agent

Hermes supports both a native status bar (via `status_bar: true` in config.yaml) and a shell-script command override. The shell-script path gives full feature parity with Claude Code.

#### Automatic Install

```bash
./scripts/setup.sh install hermes
```

#### Manual Install

1. Copy the statusline script:

```bash
mkdir -p ~/.hermes
cp hermes/statusline.sh ~/.hermes/statusline.sh
chmod +x ~/.hermes/statusline.sh
```

2. Merge `hermes/config.yaml` into `~/.hermes/config.yaml`:

Key settings:
```yaml
gateway:
  status_bar: true
  status_bar_style: "powerline"
  export_env:
    - HERMES_MODEL
    - HERMES_CONTEXT_PCT
    - HERMES_CONTEXT_SIZE
    # ... (see config.yaml for full list)

status_bar:
  command: "~/.hermes/statusline.sh"
  context_thresholds:
    green: 50
    yellow: 80
    orange: 95
    red: 95
```

The `export_env` section tells the Hermes gateway to export these as environment variables that `statusline.sh` reads.

---

### 3.4 Pi Agent

Pi uses a TypeScript extension API (`@earendil-works/pi-coding-agent` v0.79.9+).
Hyperstatus replaces the built-in footer with a custom powerline-style status bar
via `ctx.ui.setFooter()`.

#### Automatic Install

```bash
./scripts/setup.sh install pi
```

#### Manual Install

1. Create the extension directory:

```bash
mkdir -p ~/.pi/agent/extensions/hyperstatus
```

2. Copy the extension files:

```bash
cp pi/hyperstatus-extension.ts ~/.pi/agent/extensions/hyperstatus/index.ts
cp pi/powerline-config.ts ~/.pi/agent/extensions/hyperstatus/powerline-config.ts
```

3. Create `~/.pi/agent/extensions/hyperstatus/package.json`:

```json
{
  "name": "hyperstatus",
  "version": "3.1.0",
  "description": "Powerline-style status bar with full metric coverage + quota",
  "main": "index.ts",
  "piExtension": true
}
```

4. Reload Pi: type `/reload` in the Pi agent CLI.

The extension automatically polls `/tmp/hyperstatus-quota.json` every 30 seconds for quota data.

---

### 3.5 Antigravity CLI

Antigravity CLI uses the same `statusLine` JSON-on-stdin protocol as Claude Code. HyperStatus v3.2 adds full Antigravity support with model, context, token, git, agent state, and plan tier display.

#### Automatic Install

```bash
./scripts/setup.sh install antigravity
```

#### Manual Install

1. Create the config directory:

```bash
mkdir -p ~/.config/antigravity-cli
```

2. Copy the status bar script:

```bash
cp antigravity/statusline.sh ~/.config/antigravity-cli/statusline.sh
chmod +x ~/.config/antigravity-cli/statusline.sh
```

3. Create `~/.config/antigravity-cli/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.config/antigravity-cli/statusline.sh"
  }
}
```

---

## 🖥️ 2-Line Display Mode

HyperStatus v3.2 introduces **intelligent 2-line rendering** for all supported agents. When the terminal is ≥80 columns wide, the status bar splits into two rows:

| Line | Background | Contents |
|------|------------|----------|
| **Line 1** | Deep teal | Model, project, git branch, context bar + %, tokens/capacity, cost, duration, effort, permission |
| **Line 2** | Mauve/dim | Cache hit %, throughput t/s, rate limit 5h/7d %, budget remaining, background tasks, compression savings, worktree, proxy model swap info |

When terminal width falls below 80 columns, all agents gracefully fall back to a compact **single-line** layout.

No configuration needed — it's automatic based on terminal width.

---

## 4. Headroom Compression Integration

**No modifications to Headroom are required.** HYPERSTATUS reads Headroom's existing `/metrics` endpoint.

### How It Works

Headroom is a prompt compression proxy that sits between your agent and the API provider. When you route requests through Headroom, it compresses prompts before forwarding them, saving tokens. It exposes a `/metrics` endpoint with:

```json
{
  "tokens_saved": 45200,
  "compression_ratio": 0.73,
  "cache_optimization_pct": 34
}
```

HYPERSTATUS reads this endpoint and displays the savings in the status bar as `▼45.2K`.

### Setup

**Step 1: Install Headroom**

```bash
# pip
pip install headroom-ai

# or npm
npm install -g headroom-ai
```

**Step 2: Start Headroom proxy**

```bash
headroom proxy --port 8787
```

**Step 3: Route agent traffic through Headroom**

```bash
# Source the compression environment helper
source ./compression-env.sh headroom

# This sets:
#   ANTHROPIC_BASE_URL=http://localhost:8787/v1
#   OPENAI_BASE_URL=http://localhost:8787/v1
#   HEADROOM_ENDPOINT=http://localhost:8787
```

Or set manually:

```bash
export ANTHROPIC_BASE_URL="http://localhost:8787/v1"
export OPENAI_BASE_URL="http://localhost:8787/v1"
export HEADROOM_ENDPOINT="http://localhost:8787"
```

**Step 4: Verify**

```bash
curl http://localhost:8787/metrics
# Should return JSON with tokens_saved, compression_ratio, etc.
```

**Step 5: Start the metrics collector**

```bash
./scripts/metrics-collector.sh --headroom --port 8787 &
```

Or the unified daemon:

```bash
./scripts/metrics-collector.sh --headroom --quota &
```

The collector polls Headroom's `/metrics` endpoint every 10 seconds and writes the data to `/tmp/hyperstatus-metrics.json`, which the status bar scripts read on every refresh.

### What You'll See

When Headroom is compressing, the status bar shows:

```
󰜖 csonnet │ 󰝷 myproject │ ... ▼45.2K │ ...
                        ^^^^^^^^
                        Compression savings
```

### Data Flow

```
Agent CLI → Headroom (compresses) → API Provider
                ↓
          /metrics endpoint
                ↓
      metrics-collector.sh (polls every 10s)
                ↓
     /tmp/hyperstatus-metrics.json
                ↓
       statusline.sh (reads on refresh)
                ↓
         Status bar display
```

---

## 5. RTK Terminal Compression Integration

**No modifications to RTK are required.** HYPERSTATUS reads RTK's existing `rtk gain --json` CLI output.

### How It Works

RTK is a terminal-level compression tool that reduces token usage for CLI interactions. It provides a CLI command `rtk gain --json` that outputs current savings metrics:

```json
{
  "total_tokens_saved": 128000,
  "efficiency_percentage": 34.5,
  "total_commands": 47
}
```

HYPERSTATUS runs this command periodically and displays the savings.

### Setup

**Step 1: Install RTK**

```bash
curl -fsSL https://rtk.ai/install | bash
```

**Step 2: Initialize RTK for your agent**

```bash
# Global initialization (works with Claude Code, Codex, etc.)
rtk init --global

# For Claude Code specifically, you can add RTK as a PreToolUse hook:
# In ~/.claude/settings.json:
# {
#   "hooks": {
#     "PreToolUse": [{"command": "rtk compress --json", "type": "command"}]
#   }
# }
```

**Step 3: Verify RTK is working**

```bash
rtk gain --json
# Should output JSON with total_tokens_saved, efficiency_percentage, etc.
```

**Step 4: Source the compression environment**

```bash
source ./compression-env.sh rtk

# This starts a background process that polls RTK every 5 seconds
# and writes results to /tmp/rtk-metrics.json
```

**Step 5: Start the unified metrics collector**

```bash
./scripts/metrics-collector.sh --rtk --quota &
```

### RTK as a PreToolUse Hook (Claude Code)

For the most accurate per-command compression data, add RTK as a Claude Code hook:

```json
// ~/.claude/settings.json
{
  "hooks": {
    "PreToolUse": [
      {
        "type": "command",
        "command": "rtk compress --json",
        "timeout": 5000
      }
    ]
  }
}
```

This runs RTK compression before each tool use, and the metrics are captured by the polling loop.

### What You'll See

```
󰜖 csonnet │ 󰝷 myproject │ ... ▼128K │ ...
                        ^^^^^^^
                        RTK savings
```

### Combining Headroom + RTK

When both are active, the status bar shows whichever has savings:

```bash
source ./compression-env.sh all    # Enables both headroom + rtk
./scripts/metrics-collector.sh --rtk --headroom --quota &
```

Priority: RTK savings shown first (terminal-level), then Headroom (API-level). If both have savings, RTK takes display priority since it captures more granular per-command data.

---

## 6. Quota Tracking Setup

Quota data comes from external tools that track remaining quota across providers. You can use any combination — the status bar reads from a shared state file.

### 6.1 onWatch Daemon

onWatch is a lightweight Go daemon that polls provider APIs every 60 seconds and stores quota snapshots in SQLite. **This is the most accurate source for multi-provider quota.**

#### Install

```bash
# Download binary from https://github.com/onllm-dev/onwatch
# Or via Go:
go install github.com/onllm-dev/onwatch@latest
```

#### Configure

onWatch auto-detects credentials from your CLI config files:

- Anthropic: reads `~/.claude/.credentials.json`
- Codex: reads `~/.codex/auth.json`
- Gemini: reads `~/.gemini/` credentials
- Copilot: reads GitHub OAuth tokens
- Antigravity: probes local language server port

Start the daemon:

```bash
onwatch serve --db ~/.onwatch/data/onwatch.db
```

#### HYPERSTATUS Integration

No configuration needed — the quota-fetch.sh script reads the SQLite database directly:

```bash
sqlite3 ~/.onwatch/data/onwatch.db "SELECT provider, remaining_quota, window FROM quota_snapshots ORDER BY timestamp DESC"
```

Just set the database path if non-default:

```bash
export ONWATCH_DB="$HOME/.onwatch/data/onwatch.db"
```

### 6.2 ccusage CLI

ccusage parses local JSONL session logs and outputs structured JSON. **Important accuracy caveat**: ccusage undercounts Claude Code token usage by 46x or more (the JSONL `input_tokens` field is a streaming placeholder that's never updated). For Codex and Gemini CLI, it's reasonably accurate. Use it as a secondary/confirmatory source, not primary for Claude Code.

#### Install

```bash
# npm
npm install -g ccusage

# or pip
pip install ccusage
```

#### Verify

```bash
ccusage --json
# Outputs JSON with per-source token counts and costs
```

#### HYPERSTATUS Integration

No configuration needed — quota-fetch.sh calls `ccusage --json` automatically when the `ccusage` binary is detected.

### 6.3 LiteLLM Proxy

LiteLLM is an enterprise-grade LLM gateway that provides 100+ provider support, virtual key management, budget tracking, and spend limits per key. If you're using LiteLLM as your proxy, HYPERSTATUS can read budget remaining per key.

#### Install

```bash
pip install litellm[proxy]
```

#### Start the proxy

```bash
litellm --config config.yaml --port 4000
```

With a config that defines keys and budgets:

```yaml
# litellm config.yaml
model_list:
  - model_name: claude-sonnet
    litellm_params:
      model: anthropic/claude-sonnet-4-20250514
      api_key: os.environ/ANTHROPIC_API_KEY

general_settings:
  master_key: sk-master-1234

litellm_settings:
  drop_params: true
  set_verbose: false
```

Create keys with budgets:

```bash
litellm --create-key --key-name "daily-key" --max-budget 50 --models "claude-sonnet"
```

#### HYPERSTATUS Integration

Set the endpoint and master key:

```bash
export LITELLM_ENDPOINT="http://localhost:4000"
export LITELLM_MASTER_KEY="sk-master-1234"
```

HYPERSTATUS reads:
- `/key/info` — budget remaining per key, spend, model access
- `/global/spend/logs` — per-model spend and token counts

### 6.4 LLM-API-Key-Proxy

LLM-API-Key-Proxy is a self-hosted gateway with the most sophisticated key rotation system — automatic rotation, failover, cooldown management, and model-aware key locking.

#### Install

```bash
# Docker
docker pull ghcr.io/mirrowel/llm-api-key-proxy
docker run -p 8080:8080 ghcr.io/mirrowel/llm-api-key-proxy

# Or from source
git clone https://github.com/Mirrowel/LLM-API-Key-Proxy
cd LLM-API-Key-Proxy && go build -o llm-proxy .
```

#### HYPERSTATUS Integration

```bash
export LLM_KEY_PROXY_ENDPOINT="http://localhost:8080"
```

HYPERSTATUS reads the `/stats` endpoint for per-credential usage, error counts, and cooldown status.

---

## 7. Proxy Model Detection

When a proxy (LiteLLM, LLM-API-Key-Proxy, gpt-load) is swapping models behind the scenes, the agent's reported model and rate limits are **wrong**. HYPERSTATUS detects this and shows dual quota.

### How Detection Works

HYPERSTATUS uses three detection methods, tried in order:

1. **Proxy metadata endpoint** — LiteLLM's `/model/list` or LLM-API-Key-Proxy's `/config/models` reveals the actual model being served
2. **Environment variable override** — You can explicitly tell HYPERSTATUS what model the proxy is actually using
3. **Comparison** — If the proxy's reported model differs from the agent's perceived model, a swap is flagged

### Setup: Explicit Override (Simplest)

If you know your proxy is routing to a different model, just set:

```bash
export PROXY_ACTUAL_MODEL="gpt-4o"
```

The status bar will then show dual quota: the agent's perceived limits AND the real provider's limits.

### Setup: Auto-Detection (LiteLLM)

```bash
export LITELLM_ENDPOINT="http://localhost:4000"
export LITELLM_MASTER_KEY="sk-master-1234"
```

The quota-fetch.sh daemon will query LiteLLM's model list and compare against the agent's reported model. If they differ, it automatically enables dual quota display.

### What Dual Quota Looks Like

When a swap is detected, the status bar shows:

```
Line 1: 󰜖 csonnet↗ →gpt4o │ ... │ 󰜦 5h 42%/7d 28%|openai:5h 67%/7d 45% │ ...
                            ^^^                                    ^^^^^^^^^^^^^^^^^^^
                     Proxy indicator                    Real provider quota
Line 3: 󰜦 QUOTA: Anthropic 5h:42%/7d:28% │ OpenAI 5h:67%/7d:45% │ 󰜖 claude-sonnet-4→gpt-4o
```

The `↗` arrow on the model name and the `→gpt4o` proxy segment make it immediately clear that the agent's reported rate limits are NOT the real ones.

---

## 8. Environment Variables Reference

### Core Configuration

| Variable | Default | Description |
|---|---|---|
| `HYPERSTATUS_STATE` | `/tmp/hyperstatus-metrics.json` | Compression metrics state file |
| `HYPERSTATUS_QUOTA_STATE` | `/tmp/hyperstatus-quota.json` | Quota data state file |

### Headroom

| Variable | Default | Description |
|---|---|---|
| `HEADROOM_ENDPOINT` | `http://localhost:8787` | Headroom proxy URL |
| `ANTHROPIC_BASE_URL` | (unset) | Set to `${HEADROOM_ENDPOINT}/v1` to route through Headroom |
| `OPENAI_BASE_URL` | (unset) | Set to `${HEADROOM_ENDPOINT}/v1` to route through Headroom |
| `HEADROOM_TOKENS_SAVED` | (auto) | Tokens saved by Headroom (read from metrics endpoint) |
| `HEADROOM_COMPRESSION_RATIO` | (auto) | Compression ratio (read from metrics endpoint) |

### RTK

| Variable | Default | Description |
|---|---|---|
| `RTK_METRICS_FILE` | `/tmp/rtk-metrics.json` | RTK metrics output file |
| `RTK_TOKENS_SAVED` | (auto) | Tokens saved by RTK (read from `rtk gain --json`) |

### Quota Sources

| Variable | Default | Description |
|---|---|---|
| `ONWATCH_DB` | `~/.onwatch/data/onwatch.db` | onWatch SQLite database path |
| `LITELLM_ENDPOINT` | (unset) | LiteLLM proxy URL (e.g. `http://localhost:4000`) |
| `LITELLM_MASTER_KEY` | (unset) | LiteLLM master key for API access |
| `LLM_KEY_PROXY_ENDPOINT` | (unset) | LLM-API-Key-Proxy URL (e.g. `http://localhost:8080`) |
| `PROXY_QUOTA_ENDPOINT` | (unset) | Generic proxy quota endpoint URL |
| `PROXY_ACTUAL_MODEL` | (unset) | Explicitly set the model the proxy is actually using |

### Agent-Specific

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_YOLO_MODE` | (unset) | Set to `1` for YOLO mode indicator |
| `CLAUDE_AUTO_ACCEPT` | (unset) | Set to `1` for auto-accept indicator |
| `HERMES_YOLO_MODE` | (unset) | Set to `1` for Hermes YOLO indicator |
| `HERMES_AUTO_ACCEPT` | (unset) | Set to `1` for Hermes auto-accept indicator |
| `CLAUDE_BG_TASKS` | `0` | Background task count for display |

---

## 9. Architecture & Data Flow

```
┌──────────────────────────────────────────────────────────────────────┐
│                        EXTERNAL DATA SOURCES                        │
│                                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │  onWatch     │  │  LiteLLM     │  │ LLM-API-Key  │              │
│  │  (SQLite DB) │  │  (/key/info) │  │  (/stats)    │              │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘              │
│         │                  │                  │                      │
│  ┌──────┴───────┐  ┌──────┴───────┐  ┌──────┴───────┐              │
│  │  ccusage     │  │  Headroom    │  │    RTK       │              │
│  │  (--json)    │  │  (/metrics)  │  │  (gain --json)│              │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘              │
│         │                  │                  │                      │
│  ┌──────┴───────┐  ┌──────┴───────┐  ┌──────┴───────┐              │
│  │  Anthropic   │  │  OpenAI      │  │  Any proxy   │              │
│  │  (/usage)    │  │  (headers)   │  │  (metadata)  │              │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘              │
│         │                  │                  │                      │
└─────────┼──────────────────┼──────────────────┼──────────────────────┘
          │                  │                  │
          ▼                  ▼                  ▼
┌──────────────────────────────────────────────────────────────────────┐
│                    COLLECTION LAYER                                   │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐     │
│  │  metrics-collector.sh / quota-fetch.sh                      │     │
│  │                                                              │     │
│  │  • Polls RTK every 10s:     rtk gain --json                 │     │
│  │  • Polls Headroom every 10s: curl /metrics                  │     │
│  │  • Polls quota every 30s:   onWatch + ccusage + proxy APIs  │     │
│  │  • Detects proxy swaps:     compare agent model vs proxy     │     │
│  │  • Probes Anthropic/OpenAI: every 5 min (shares rate budget)│     │
│  │                                                              │     │
│  │  Output:                                                     │     │
│  │    /tmp/hyperstatus-metrics.json  ← compression data        │     │
│  │    /tmp/hyperstatus-quota.json    ← quota + proxy detection │     │
│  │    /tmp/hyperstatus-env.sh        ← env vars for sourcing   │     │
│  └─────────────────────────────────────────────────────────────┘     │
│                                                                      │
└──────────────────────────────┬───────────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────────────┐
│                    RENDERING LAYER                                    │
│                                                                      │
│  ┌──────────────────┐  ┌──────────────────┐                         │
│  │  Claude Code     │  │  Hermes Agent    │                         │
│  │  statusline.sh   │  │  statusline.sh   │                         │
│  │  (reads stdin    │  │  (reads env vars │                         │
│  │   JSON + state   │  │   + state files) │                         │
│  │   files)         │  │                  │                         │
│  └──────────────────┘  └──────────────────┘                         │
│                                                                      │
│  ┌──────────────────┐  ┌──────────────────┐                         │
│  │  Codex CLI       │  │  Pi Agent        │                         │
│  │  codex-wrapper   │  │  TypeScript ext  │                         │
│  │  (tmux status)   │  │  (async fetches  │                         │
│  │                  │  │   state files)   │                         │
│  └──────────────────┘  └──────────────────┘                         │
│                                                                      │
│  All read from:                                                      │
│    /tmp/hyperstatus-metrics.json  ← compression                    │
│    /tmp/hyperstatus-quota.json    ← quota + proxy detection         │
│    /tmp/hyperstatus-env.sh        ← sourced env vars               │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

### Key Design Principle: No Modifications to External Tools

Every integration reads **existing** outputs from external tools:

| Tool | What HYPERSTATUS Reads | Modified? |
|---|---|---|
| Headroom | `GET /metrics` (built-in endpoint) | ❌ No |
| RTK | `rtk gain --json` (built-in CLI) | ❌ No |
| onWatch | SQLite DB (built-in storage) | ❌ No |
| ccusage | `ccusage --json` (built-in flag) | ❌ No |
| LiteLLM | `/key/info`, `/global/spend/logs` (built-in API) | ❌ No |
| LLM-API-Key-Proxy | `/stats` (built-in endpoint) | ❌ No |
| Anthropic API | Rate limit headers on responses (built-in) | ❌ No |
| OpenAI API | `x-ratelimit-*` headers (built-in) | ❌ No |

---

## 10. Troubleshooting

### Status bar not showing

1. **Verify Nerd Font is installed** — the status bar requires Nerd Font glyphs
2. **Check terminal color support** — run `echo $TERM` and ensure it supports 256 colors
3. **Claude Code**: Check `~/.claude/settings.json` has the `statusLine` key
4. **Hermes**: Check `~/.hermes/config.yaml` has `status_bar.command` set
5. **Pi**: Check `~/.pi/extensions/hyperstatus/` exists and run `/reload`

### Compression savings not appearing

1. **Headroom**: Verify the proxy is running: `curl http://localhost:8787/metrics`
2. **RTK**: Verify RTK is working: `rtk gain --json`
3. **Metrics collector**: Check it's running: `ps aux | grep metrics-collector`
4. **State files**: Check they exist and contain data:
   ```bash
   cat /tmp/hyperstatus-metrics.json
   cat /tmp/hyperstatus-env.sh
   ```

### Quota data not appearing

1. **onWatch**: Check the database exists: `ls ~/.onwatch/data/onwatch.db`
2. **ccusage**: Verify it works: `ccusage --json`
3. **LiteLLM**: Verify the API is accessible:
   ```bash
   curl http://localhost:4000/key/info -H "Authorization: Bearer $LITELLM_MASTER_KEY"
   ```
4. **quota-fetch.sh**: Run it manually:
   ```bash
   ./scripts/quota-fetch.sh
   cat /tmp/hyperstatus-quota.json
   ```

### Proxy model detection not working

1. Set `PROXY_ACTUAL_MODEL` explicitly if auto-detection fails:
   ```bash
   export PROXY_ACTUAL_MODEL="gpt-4o"
   ```
2. Verify LiteLLM endpoint is accessible:
   ```bash
   curl http://localhost:4000/model/list -H "Authorization: Bearer $LITELLM_MASTER_KEY"
   ```

### Rate limits showing as 0%

This happens when:
- The agent doesn't expose rate limit data (Codex CLI in some modes)
- The statusline JSON doesn't include `rate_limits` (older Claude Code versions)
- No external quota sources are configured

### Claude Code JSONL accuracy

ccusage and tokscale significantly undercount Claude Code usage because the JSONL `input_tokens` field is a streaming placeholder that's never updated. The accurate sources are:
- Claude Code's statusline JSON (piped via stdin) — **most accurate for current session**
- onWatch (polls provider APIs) — **most accurate for aggregate quota**
- API rate limit headers — **most accurate per-request**

---

## Quick Reference: Full Setup for All Features

```bash
# 1. Install HYPERSTATUS
./scripts/setup.sh install all

# 2. Install external tools (pick what you need)
pip install headroom-ai         # Prompt compression proxy
pip install ccusage             # JSONL token tracker
npm install -g ccusage          # Alternative install
go install github.com/onllm-dev/onwatch@latest  # Multi-provider quota daemon
# RTK: curl -fsSL https://rtk.ai/install | bash
# LiteLLM: pip install 'litellm[proxy]'

# 3. Start services
headroom proxy --port 8787 &        # Compression proxy
onwatch serve &                      # Quota daemon
litellm --config config.yaml &      # API gateway (optional)

# 4. Configure environment
source ./compression-env.sh all     # Sets all proxy URLs, starts RTK polling
export LITELLM_ENDPOINT="http://localhost:4000"
export LITELLM_MASTER_KEY="sk-master-1234"
export PROXY_ACTUAL_MODEL=""        # Set if proxy is swapping models

# 5. Start the unified collector
./scripts/metrics-collector.sh --rtk --headroom --quota &

# 6. Launch your agent
claude   # or: codex, hermes, pi
```
