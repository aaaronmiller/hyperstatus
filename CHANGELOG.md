# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Integrated Antigravity CLI status bar support into `scripts/setup.sh` (automatic detection, installation, backup, and restore).

### Fixed
- **Pi extension (v4.0):** ported from the removed class-based `@pi/core` StatusBar API to the pi >=0.79 function-based `ExtensionAPI` / `pi.setFooter()` widget API. The old `import ... from "@pi/core"` crashed pi at launch with `Cannot find module '@pi/core'`. Truecolor Catppuccin powerline preserved; metrics now sourced from the live session only (`getContextUsage`, `sessionManager` usage, `footerData` git branch, quota file, RTK/headroom) — segments the new API does not expose are omitted rather than faked.

### Changed
- `scripts/setup.sh` `install_pi()` now **symlinks** `pi/hyperstatus-extension.ts` → `~/.pi/agent/extensions/hyperstatus/index.ts` (and `powerline-config.ts`) instead of copying, so edits in `/code/HYPERSTATUS_v3` propagate to the running extension live. Bumped extension `package.json` to `4.0.0`.
- Removed redundant context window absolute capacity display from all agent status bars (Claude Code, Codex CLI, Hermes, Pi, Antigravity) to avoid redundancy with the percentage display.
