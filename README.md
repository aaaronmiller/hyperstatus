# HYPERSTATUS v3.0

**Universal Powerline-Style Status Bar for Coding Agents**

A comprehensive status bar solution providing real-time metrics, cost tracking, quota monitoring, and compression integration across multiple AI coding agents.

![HyperStatus](https://img.shields.io/badge/status-active-brightgreen) ![License](https://img.shields.io/badge/license-MIT-blue) ![Version](https://img.shields.io/badge/version-3.0-purple)

---

## 🎯 Features

| Feature | Description |
|---------|-------------|
| **Context Window %** | Visual progress bar with color thresholds |
| **Current Model** | Model name with reasoning indicator |
| **Token Count** | Input/output/total tokens with formatting |
| **Session Cost** | Real-time cost calculation per model pricing |
| **Git Branch + Status** | Branch name, staged/unstaged/untracked counts |
| **Rate Limits** | 5-hour and 7-day quota percentages |
| **Cache Hit Rate** | Read/write cache efficiency |
| **Compression Count** | Headroom/RTK token savings |
| **Model Latency** | Tokens per second throughput |
| **Background Tasks** | Running async task count |
| **Quota Monitoring** | Multi-provider (Anthropic, OpenAI, Gemini) |
| **Proxy Detection** | Model swap detection via proxy |

---

## 🤖 Supported Agents

| Agent | Installation Method | Features |
|-------|---------------------|----------|
| **Claude Code** | `settings.json` + shell script | Full feature set |
| **Codex CLI** | `config.toml` (built-in items) | Subset (API limited) |
| **Hermes Agent** | YAML config + shell script | Full feature set |
| **Pi Agent** | TypeScript extension | Full feature set |

---

## 🚀 Quick Install

```bash
# Clone the repository
git clone https://github.com/yourusername/HYPERSTATUS_v3.git
cd HYPERSTATUS_v3

# Run universal installer (detects all agents automatically)
./scripts/setup.sh install all
```

### Manual Install (per agent)

```bash
# Claude Code
./scripts/setup.sh install claude

# Codex CLI
./scripts/setup.sh install codex

# Hermes Agent
./scripts/setup.sh install hermes

# Pi Agent
./scripts/setup.sh install pi
```

---

## 📋 Requirements

- **Bash 4.0+** (for statusline scripts)
- **bc** (for floating point math)
- **python3** (for JSON parsing & config merging)
- **git** (for git status metrics)
- **Nerd Font** (for Powerline icons)

### Optional: Compression Proxies

| Proxy | Purpose | Install |
|-------|---------|---------|
| **RTK** | Token optimization | `curl -fsSL https://rtk.ai/install \| bash` |
| **Headroom** | Prompt compression | `pip install headroom-ai` |

Enable with:
```bash
source ./compression-env.sh both  # or headroom / rtk
```

---

## 📁 Project Structure

```
HYPERSTATUS_v3/
├── scripts/
│   ├── setup.sh              # Universal installer
│   ├── metrics-collector.sh  # Background metrics daemon
│   └── quota-fetch.sh        # Quota API polling
├── claude-code/
│   ├── settings.json         # Claude Code statusLine config
│   └── statusline.sh         # Main status bar script
├── codex/
│   └── config.toml           # Codex status_line config
├── hermes/
│   ├── config.yaml           # Hermes gateway + status_bar config
│   └── statusline.sh         # Full-featured status bar
├── pi/
│   ├── hyperstatus-extension.ts  # Pi extension entry
│   ├── powerline-config.ts       # Powerline rendering
│   └── package.json              # Extension manifest
├── mockups/                  # Visual mockups (PDF/PNG)
├── generate_mockups.py       # Mockup generator
├── generate_pdf.py           # PDF documentation generator
├── compression-env.sh        # Proxy environment helper
├── INSTALL.md                # Detailed installation guide
├── LICENSE                   # MIT License
└── README.md                 # This file
```

---

## ⚙️ Configuration

### Claude Code (`~/.claude/settings.json`)
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

### Codex CLI (`~/.codex/config.toml`)
```toml
[tui]
status_line = [
  "model-with-reasoning",
  "current-dir",
  "git-branch",
  "context-used",
  "context-remaining",
  "context-window-size",
  "used-tokens",
  "total-output-tokens",
  "five-hour-limit",
  "weekly-limit"
]
```

### Hermes Agent (`~/.hermes/config.yaml`)
```yaml
gateway:
  status_bar: true
  status_bar_style: "powerline"
  export_env:
    - HERMES_MODEL
    - HERMES_CONTEXT_PCT
    - HERMES_SESSION_COST
    # ... all HERMES_* vars
  status_bar:
    command: "~/.hermes/statusline.sh"
```

### Pi Agent
Run `/reload` in Pi after install to activate the `hyperstatus` extension.

---

## 🎨 Color Thresholds

| Metric | Green | Yellow | Orange | Red |
|--------|-------|--------|--------|-----|
| Context % | < 50% | 50-79% | 80-94% | ≥ 95% |
| Rate Limits | < 50% | 50-79% | 80-94% | ≥ 95% |
| Quota | < 50% | 50-79% | 80-94% | ≥ 95% |

---

## 📊 Metrics Collected

The status bar reads from multiple sources:

1. **Agent Internal State** — Context, tokens, cost, duration via env vars
2. **Git** — Branch, status, worktree, lines changed
3. **Compression Proxies** — RTK/Headroom token savings
4. **Quota APIs** — Anthropic, OpenAI, Gemini rate limits
5. **System** — Working directory, permissions, background tasks

---

## 🔧 Advanced Usage

### Backup & Restore
```bash
# Backup all agent configs
./scripts/setup.sh backup all

# Restore from specific backup
./scripts/setup.sh restore all --restore /path/to/backup
```

### Compression Integration
```bash
# Enable both RTK and Headroom
source ./compression-env.sh both

# Enable only Headroom
source ./compression-env.sh headroom

# Enable only RTK
source ./compression-env.sh rtk
```

### Verify Installation
```bash
./scripts/setup.sh status
```

### Generate Documentation
```bash
python3 generate_pdf.py      # Full PDF docs
python3 generate_mockups.py  # Visual mockups
```

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with `./scripts/setup.sh install all`
5. Submit a PR

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

---

## 🙏 Acknowledgments

- **Catppuccin Mocha** color palette
- **Nerd Fonts** for Powerline icons
- **RTK** and **Headroom** for compression integration
- All four agent teams for excellent extensibility

---

## 📞 Support

- **Issues**: GitHub Issues
- **Discussions**: GitHub Discussions
- **Wiki**: See `INSTALL.md` for detailed guides

---

**Made with ❤️ for the coding agent ecosystem**