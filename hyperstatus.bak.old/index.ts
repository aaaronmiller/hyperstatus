/**
 * ============================================================================
 *  HYPERSTATUS v3.0 — Pi Agent Status Bar Extension
 *  Powerline-style status bar with full metric coverage + QUOTA integration
 *  Install: Copy to ~/.pi/extensions/hyperstatus/
 *
 *  v3.0 NEW: Multi-provider quota display from onWatch/ccusage/LiteLLM,
 *  proxy model detection, and dual quota when proxy swaps models.
 * ============================================================================
 */

import { Extension, StatusBarSegment, StatusBarConfig } from "@pi/core";
import { PowerlineSeparator, PowerlineConfig } from "./powerline-config";

// --- Color Palette (Catppuccin Mocha) ---
const PALETTE = {
  bg: "#1e1e2e",
  surface0: "#313244",
  surface1: "#45475a",
  surface2: "#585b70",
  overlay0: "#6c7086",
  text: "#cdd6f4",
  subtext0: "#a6adc8",
  subtext1: "#bac2de",
  lavender: "#b4befe",
  blue: "#89b4fa",
  sapphire: "#74c7ec",
  sky: "#89dceb",
  teal: "#94e2d5",
  green: "#a6e3a1",
  yellow: "#f9e2af",
  peach: "#fab387",
  maroon: "#eba0ac",
  red: "#f38ba8",
  mauve: "#cba6f7",
  pink: "#f5c2e7",
  quota: "#9370db",      // Medium purple for quota segments
  proxy: "#7c3aed",      // Violet for proxy segments
};

// --- Nerd Font Icon Constants ---
const ICON = {
  model: "\ue716",
  context: "\uf6cf",
  tokens: "\uf1c9",
  cost: "\uf155",
  duration: "\uf017",
  compression: "\uf410",
  bgTasks: "\uf44e",
  cache: "\uf021",
  git: "\ue725",
  branch: "\uf418",
  latency: "\uf9ee",
  effort: "\uf58c",
  dir: "\uf07b",
  think: "\uf7b4",
  perm: "\uf132",
  pr: "\ue728",
  worktree: "\uf77a",
  rate: "\uf252",
  speed: "\uf9ee",
  session: "\uf2db",
  quota: "\uf0ec",       //  Gauge/quota icon
  proxy: "\uf6ff",       //  Proxy/swap icon
  provider: "\uf1c0",    //  Database/provider icon
  warn: "\uf071",        //  Warning triangle
};

// --- Context Threshold Colors ---
function contextColor(pct: number): string {
  if (pct >= 95) return PALETTE.red;
  if (pct >= 80) return PALETTE.peach;
  if (pct >= 50) return PALETTE.yellow;
  return PALETTE.green;
}

// --- Quota Threshold Colors (high usage = bad) ---
function quotaColor(usedPct: number): string {
  if (usedPct >= 95) return PALETTE.red;
  if (usedPct >= 80) return PALETTE.peach;
  if (usedPct >= 50) return PALETTE.yellow;
  return PALETTE.quota;
}

// --- Context Progress Bar ---
function contextBar(pct: number, width: number = 10): string {
  const filled = Math.round((pct / 100) * width);
  const empty = width - filled;
  return "█".repeat(filled) + "░".repeat(empty);
}

// --- Format Tokens ---
function fmtTokens(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
  return `${n}`;
}

// --- Format Cost ---
function fmtCost(c: number): string {
  return `$${c.toFixed(2)}`;
}

// --- Format Duration ---
function fmtDuration(ms: number): string {
  const s = Math.floor(ms / 1000);
  const m = Math.floor(s / 60);
  const h = Math.floor(m / 60);
  if (h > 0) return `${h}h${m % 60}m`;
  if (m > 0) return `${m}m`;
  return `${s}s`;
}

// --- Compression Metrics Interface ---
interface CompressionMetrics {
  headroomTokensSaved?: number;
  headroomRatio?: number;
  rtkTokensSaved?: number;
  rtkEfficiency?: number;
}

// --- Quota Data Interface ---
interface ProviderQuota {
  // onWatch data
  "5h_used_pct"?: number;
  "7d_used_pct"?: number;
  "daily_used_pct"?: number;
  "5h_remaining"?: number;
  "7d_remaining"?: number;
  "5h_total"?: number;
  "7d_total"?: number;
  // LiteLLM data
  budget_used_pct?: number;
  budget_remaining_usd?: number;
  budget_total_usd?: number;
  // ccusage data
  ccusage_cost?: number;
  ccusage_input_tokens?: number;
  ccusage_output_tokens?: number;
  // LLM-API-Key-Proxy
  proxy_requests?: number;
  proxy_errors?: number;
  proxy_cooldown?: boolean;
}

interface ProxyInfo {
  model_swapped: boolean;
  agent_model: string;
  actual_model: string;
}

interface QuotaState {
  providers: Record<string, ProviderQuota>;
  warnings: string[];
  proxy_info: ProxyInfo | null;
  total_remaining_pct: number | null;
}

// --- Main Status Bar Extension ---
export default class HyperStatusExtension extends Extension {
  name = "hyperstatus";
  version = "3.0.0";
  description = "Powerline-style status bar with full metric coverage + quota";

  private compression: CompressionMetrics = {};
  private quotaState: QuotaState | null = null;
  private quotaFile = process.env.HYPERSTATUS_QUOTA_STATE || "/tmp/hyperstatus-quota.json";

  /**
   * Read quota state from shared JSON file
   * Updated by quota-fetch.sh daemon running in background
   */
  private async readQuotaState(): Promise<void> {
    try {
      const fs = await import("fs/promises");
      const data = await fs.readFile(this.quotaFile, "utf-8");
      const parsed = JSON.parse(data);
      this.quotaState = parsed.summary || null;
    } catch {
      // File doesn't exist or is invalid — no quota data available
      this.quotaState = null;
    }
  }

  /**
   * Build the status bar segments
   * LEFT: Variable-width items (model, project, branch, proxy, compression)
   * RIGHT: Fixed-width items (context, tokens, cache, cost, quota, duration)
   */
  async buildStatusBar(ctx: any): Promise<StatusBarSegment[]> {
    // Refresh quota data
    await this.readQuotaState();

    const segments: StatusBarSegment[] = [];
    const proxyInfo = this.quotaState?.proxy_info;
    const modelSwapped = proxyInfo?.model_swapped ?? false;

    // ====== LEFT SIDE (variable-width) ======

    // Model (with proxy indicator if model is swapped)
    const model = ctx.model?.display_name || "unknown";
    let shortModel = model
      .replace("claude-", "c")
      .replace(/-202.*/, "");
    let modelBg = PALETTE.surface1;
    let modelFg = PALETTE.lavender;

    if (modelSwapped && proxyInfo) {
      const actualShort = proxyInfo.actual_model
        .replace("claude-", "c")
        .replace(/-202.*/, "")
        .replace("gpt-4o", "gpt4o")
        .replace("o4-mini", "o4m");

      // Show proxy redirect: agent model → actual model
      segments.push({
        icon: ICON.model,
        text: shortModel,
        bg: modelBg,
        fg: modelFg,
        side: "left",
      });
      segments.push({
        icon: ICON.proxy,
        text: `→${actualShort}`,
        bg: PALETTE.proxy,
        fg: PALETTE.text,
        side: "left",
      });
      shortModel = `${shortModel}↗`;
    } else {
      segments.push({
        icon: ICON.model,
        text: shortModel,
        bg: modelBg,
        fg: modelFg,
        side: "left",
      });
    }

    // Project / Directory
    const project = ctx.project_dir
      ? ctx.project_dir.split("/").pop()
      : "~";
    segments.push({
      icon: ICON.dir,
      text: project,
      bg: PALETTE.surface0,
      fg: PALETTE.text,
      side: "left",
    });

    // Git Branch
    if (ctx.git_branch) {
      segments.push({
        icon: ICON.branch,
        text: ctx.git_branch,
        bg: PALETTE.surface0,
        fg: PALETTE.green,
        side: "left",
      });
    }

    // Worktree
    if (ctx.worktree && ctx.worktree !== ctx.git_branch) {
      segments.push({
        icon: ICON.worktree,
        text: ctx.worktree,
        bg: PALETTE.surface0,
        fg: PALETTE.teal,
        side: "left",
      });
    }

    // PR Number
    if (ctx.pr_number) {
      segments.push({
        icon: ICON.pr,
        text: `#${ctx.pr_number}`,
        bg: PALETTE.surface0,
        fg: PALETTE.mauve,
        side: "left",
      });
    }

    // Compression savings
    const compSaved =
      this.compression.rtkTokensSaved ||
      this.compression.headroomTokensSaved;
    if (compSaved) {
      segments.push({
        icon: ICON.compression,
        text: `▼${fmtTokens(compSaved)}`,
        bg: PALETTE.surface0,
        fg: PALETTE.sapphire,
        side: "left",
      });
    }

    // ====== RIGHT SIDE (fixed-width) ======

    // Context % with color-coded bar
    const ctxPct = ctx.context_pct || 0;
    const ctxClr = contextColor(ctxPct);
    segments.push({
      icon: ICON.context,
      text: `${contextBar(ctxPct)} ${ctxPct.toFixed(1)}%`,
      bg: ctxClr,
      fg: PALETTE.bg,
      side: "right",
      minWidth: 20,
    });

    // Token counts
    const inputT = ctx.input_tokens || 0;
    const outputT = ctx.output_tokens || 0;
    const totalT = inputT + outputT;
    const ctxSize = ctx.context_window_size || 200000;
    segments.push({
      icon: ICON.tokens,
      text: `${fmtTokens(totalT)}/${fmtTokens(ctxSize)}`,
      bg: PALETTE.surface1,
      fg: PALETTE.text,
      side: "right",
      minWidth: 14,
    });

    // Cache hit rate
    const cacheRead = ctx.cache_read_tokens || 0;
    const cachePct = inputT > 0 ? Math.round((cacheRead / inputT) * 100) : 0;
    if (cachePct > 0) {
      segments.push({
        icon: ICON.cache,
        text: `${cachePct}%`,
        bg: PALETTE.surface1,
        fg: PALETTE.sapphire,
        side: "right",
        minWidth: 7,
      });
    }

    // Cost
    const cost = ctx.cost || 0;
    segments.push({
      icon: ICON.cost,
      text: fmtCost(cost),
      bg: PALETTE.surface0,
      fg: PALETTE.yellow,
      side: "right",
      minWidth: 8,
    });

    // Throughput
    if (ctx.api_duration_ms > 0 && outputT > 0) {
      const tps = Math.round((outputT * 1000) / ctx.api_duration_ms);
      segments.push({
        icon: ICON.speed,
        text: `${tps}t/s`,
        bg: PALETTE.surface0,
        fg: PALETTE.subtext0,
        side: "right",
        minWidth: 8,
      });
    }

    // ====== QUOTA SEGMENTS (v3.0) ======
    // If proxy is swapping models, show DUAL quota:
    //   Agent's perceived rate limits | Real provider quota
    // If no proxy, show standard rate limits + external quota data

    if (modelSwapped && this.quotaState) {
      // DUAL QUOTA MODE
      const agentRate5 = ctx.rate5_pct || 0;
      const agentRate7 = ctx.rate7_pct || 0;

      // Determine real provider quota
      let realRate5 = agentRate5;
      let realRate7 = agentRate7;
      let realProvider = "unknown";

      if (proxyInfo!.actual_model.match(/gpt|o4|o3/i)) {
        realProvider = "openai";
        realRate5 = this.quotaState.providers.openai?.["5h_used_pct"] ?? agentRate5;
        realRate7 = this.quotaState.providers.openai?.["7d_used_pct"] ?? agentRate7;
      } else if (proxyInfo!.actual_model.match(/gemini/i)) {
        realProvider = "gemini";
        realRate5 = this.quotaState.providers.gemini?.["daily_used_pct"] ?? agentRate5;
        realRate7 = 0;
      } else {
        realProvider = "anthropic";
        realRate5 = this.quotaState.providers.anthropic?.["5h_used_pct"] ?? agentRate5;
        realRate7 = this.quotaState.providers.anthropic?.["7d_used_pct"] ?? agentRate7;
      }

      // Agent-facing quota segment
      const quotaClr = quotaColor(Math.max(agentRate5, realRate5));
      segments.push({
        icon: ICON.quota,
        text: `5h${agentRate5}%/7d${agentRate7}%|${realProvider}:5h${realRate5}%/7d${realRate7}%`,
        bg: quotaClr,
        fg: PALETTE.bg,
        side: "right",
        minWidth: 20,
      });
    } else {
      // STANDARD MODE: Agent's own rate limits
      if (ctx.rate5_pct > 0) {
        const rate5Clr = quotaColor(ctx.rate5_pct);
        segments.push({
          icon: ICON.rate,
          text: `5h${ctx.rate5_pct}%`,
          bg: ctx.rate5_pct >= 80 ? PALETTE.peach : PALETTE.surface0,
          fg: ctx.rate5_pct >= 80 ? PALETTE.bg : PALETTE.subtext0,
          side: "right",
          minWidth: 8,
        });
      }
      if (ctx.rate7_pct > 0) {
        segments.push({
          icon: ICON.rate,
          text: `7d${ctx.rate7_pct}%`,
          bg: ctx.rate7_pct >= 80 ? PALETTE.peach : PALETTE.surface0,
          fg: ctx.rate7_pct >= 80 ? PALETTE.bg : PALETTE.subtext0,
          side: "right",
          minWidth: 8,
        });
      }
    }

    // Budget remaining (from LiteLLM / onWatch)
    if (this.quotaState) {
      const providers = this.quotaState.providers;
      const budgetParts: string[] = [];

      if (providers.anthropic?.budget_remaining_usd !== undefined && providers.anthropic.budget_remaining_usd > 0) {
        budgetParts.push(`A:$${providers.anthropic.budget_remaining_usd.toFixed(2)}`);
      }
      if (providers.openai?.budget_remaining_usd !== undefined && providers.openai.budget_remaining_usd > 0) {
        budgetParts.push(`O:$${providers.openai.budget_remaining_usd.toFixed(2)}`);
      }

      if (budgetParts.length > 0) {
        segments.push({
          icon: ICON.cost,
          text: budgetParts.join(" "),
          bg: PALETTE.surface0,
          fg: PALETTE.green,
          side: "right",
          minWidth: 12,
        });
      }
    }

    // Duration
    segments.push({
      icon: ICON.duration,
      text: fmtDuration(ctx.duration_ms || 0),
      bg: PALETTE.surface1,
      fg: PALETTE.text,
      side: "right",
      minWidth: 6,
    });

    // Effort level
    const effort = ctx.effort_level;
    if (effort) {
      const effortIcon =
        effort === "max" || effort === "xhigh"
          ? "⚡"
          : effort === "high"
          ? "▲"
          : effort === "medium"
          ? "●"
          : "▼";
      segments.push({
        icon: ICON.effort,
        text: effortIcon,
        bg: PALETTE.surface0,
        fg: PALETTE.mauve,
        side: "right",
        minWidth: 3,
      });
    }

    // Thinking mode
    if (ctx.thinking_enabled) {
      segments.push({
        icon: ICON.think,
        text: "✦",
        bg: PALETTE.surface0,
        fg: PALETTE.lavender,
        side: "right",
        minWidth: 3,
      });
    }

    // Background tasks count
    const bgTasks = ctx.bg_tasks || parseInt(process.env.PI_BG_TASKS || "0");
    if (bgTasks > 0) {
      segments.push({
        icon: ICON.bgTasks,
        text: `${bgTasks}`,
        bg: PALETTE.surface0,
        fg: PALETTE.teal,
        side: "right",
        minWidth: 3,
      });
    }

    // Permission level
    const permLevel = this.detectPermission();
    if (permLevel === "yolo") {
      segments.push({
        icon: ICON.perm,
        text: "Y",
        bg: PALETTE.red,
        fg: PALETTE.bg,
        side: "right",
        minWidth: 3,
      });
    } else if (permLevel === "auto") {
      segments.push({
        icon: ICON.perm,
        text: "A",
        bg: PALETTE.yellow,
        fg: PALETTE.bg,
        side: "right",
        minWidth: 3,
      });
    }

    return segments;
  }

  /** Detect permission level from environment */
  private detectPermission(): "yolo" | "auto" | "ask" {
    if (process.env.HERMES_YOLO_MODE === "1" || process.env.PI_YOLO === "1") return "yolo";
    if (process.env.PI_AUTO_ACCEPT === "1") return "auto";
    return "ask";
  }

  /** Update compression metrics from headroom/RTK */
  updateCompression(metrics: CompressionMetrics): void {
    this.compression = { ...this.compression, ...metrics };
  }

  /** Called when extension is loaded */
  onActivate(): void {
    // Watch for RTK metrics file
    const rtkFile = process.env.RTK_METRICS_FILE || "/tmp/rtk-metrics.json";

    // Poll headroom proxy endpoint
    const headroomUrl = process.env.HEADROOM_ENDPOINT || "";
    if (headroomUrl) {
      setInterval(async () => {
        try {
          const resp = await fetch(`${headroomUrl}/metrics`);
          const data = await resp.json();
          this.updateCompression({
            headroomTokensSaved: data.tokens_saved,
            headroomRatio: data.compression_ratio,
          });
        } catch {
          // Silently fail if proxy unavailable
        }
      }, 5000);
    }

    // Poll quota state file (updated by quota-fetch.sh daemon)
    setInterval(async () => {
      await this.readQuotaState();
    }, 30000);  // Every 30 seconds
  }
}
