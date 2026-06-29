/**
 * ============================================================================
 *  HYPERSTATUS v4.0 — Pi Agent Status Bar Extension
 *  Powerline-style footer with full metric coverage + QUOTA integration
 *  Install: Copy to ~/.pi/agent/extensions/hyperstatus/
 *
 *  v4.0: Ported from the removed class-based `@pi/core` StatusBar API to the
 *  pi >=0.79 function-based ExtensionAPI (`pi.setFooter`). Renders a truecolor
 *  powerline footer. All metrics are sourced from the live session — no
 *  fabricated values. Segments the new API does not expose (per-turn
 *  throughput, agent-side effort/thinking/rate limits) are omitted rather
 *  than faked; rate/budget data still comes from the external quota file.
 * ============================================================================
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { defaultConfig } from "./powerline-config";

const SEP = defaultConfig.separator; // right "", left ""

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
  quota: "#9370db",
  proxy: "#7c3aed",
};

// --- Nerd Font Icon Constants ---
const ICON = {
  model: "",
  context: "",
  tokens: "",
  cost: "",
  duration: "",
  compression: "",
  cache: "",
  branch: "",
  rate: "",
  dir: "",
  quota: "",
  proxy: "",
  provider: "",
  warn: "",
};

// ---------------------------------------------------------------------------
//  ANSI truecolor helpers
// ---------------------------------------------------------------------------
const RESET = "\x1b[0m";

function hexToRgb(hex: string): [number, number, number] {
  const h = hex.replace("#", "");
  return [
    parseInt(h.slice(0, 2), 16),
    parseInt(h.slice(2, 4), 16),
    parseInt(h.slice(4, 6), 16),
  ];
}
function fgAnsi(hex: string): string {
  const [r, g, b] = hexToRgb(hex);
  return `\x1b[38;2;${r};${g};${b}m`;
}
function bgAnsi(hex: string): string {
  const [r, g, b] = hexToRgb(hex);
  return `\x1b[48;2;${r};${g};${b}m`;
}
/** Visible width: strip ANSI SGR sequences, count remaining code points. */
function visibleWidth(s: string): number {
  // eslint-disable-next-line no-control-regex
  return Array.from(s.replace(/\x1b\[[0-9;]*m/g, "")).length;
}

// ---------------------------------------------------------------------------
//  Formatters / thresholds
// ---------------------------------------------------------------------------
function contextColor(pct: number): string {
  if (pct >= 95) return PALETTE.red;
  if (pct >= 80) return PALETTE.peach;
  if (pct >= 50) return PALETTE.yellow;
  return PALETTE.green;
}
function quotaColor(usedPct: number): string {
  if (usedPct >= 95) return PALETTE.red;
  if (usedPct >= 80) return PALETTE.peach;
  if (usedPct >= 50) return PALETTE.yellow;
  return PALETTE.quota;
}
function contextBar(pct: number, width = 8): string {
  const filled = Math.max(0, Math.min(width, Math.round((pct / 100) * width)));
  return "█".repeat(filled) + "░".repeat(width - filled);
}
function fmtTokens(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
  return `${n}`;
}
function fmtCost(c: number): string {
  return `$${c.toFixed(2)}`;
}

// ---------------------------------------------------------------------------
//  External state (quota + compression) — read from files written by daemons
// ---------------------------------------------------------------------------
interface ProviderQuota {
  "5h_used_pct"?: number;
  "7d_used_pct"?: number;
  "daily_used_pct"?: number;
  budget_remaining_usd?: number;
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
interface CompressionMetrics {
  headroomTokensSaved?: number;
  rtkTokensSaved?: number;
}

const QUOTA_FILE =
  process.env.HYPERSTATUS_QUOTA_STATE || "/tmp/hyperstatus-quota.json";
const RTK_FILE = process.env.RTK_METRICS_FILE || "/tmp/rtk-metrics.json";

async function readJson(path: string): Promise<any | null> {
  try {
    const fs = await import("node:fs/promises");
    return JSON.parse(await fs.readFile(path, "utf-8"));
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
//  Segment model + powerline renderer
// ---------------------------------------------------------------------------
interface Segment {
  icon: string;
  text: string;
  bg: string;
  fg: string;
}

function renderSeg(s: Segment): string {
  return `${bgAnsi(s.bg)}${fgAnsi(s.fg)} ${s.icon} ${s.text} ${RESET}`;
}

/** Left-aligned powerline: segments separated by right-facing arrows. */
function renderLeft(segs: Segment[]): string {
  let out = "";
  for (let i = 0; i < segs.length; i++) {
    out += renderSeg(segs[i]);
    const nextBg = i + 1 < segs.length ? segs[i + 1].bg : null;
    if (nextBg) {
      out += `${bgAnsi(nextBg)}${fgAnsi(segs[i].bg)}${SEP.right}${RESET}`;
    } else {
      out += `${fgAnsi(segs[i].bg)}${SEP.right}${RESET}`;
    }
  }
  return out;
}

/** Right-aligned powerline: segments separated by left-facing arrows. */
function renderRight(segs: Segment[]): string {
  let out = "";
  for (let i = 0; i < segs.length; i++) {
    out += `${fgAnsi(segs[i].bg)}${SEP.left}${RESET}`;
    out += renderSeg(segs[i]);
  }
  return out;
}

// ---------------------------------------------------------------------------
//  Token/cost aggregation from the live session branch
// ---------------------------------------------------------------------------
function aggregateUsage(ctx: any): {
  input: number;
  output: number;
  cost: number;
  cacheRead: number;
} {
  let input = 0,
    output = 0,
    cost = 0,
    cacheRead = 0;
  try {
    for (const e of ctx.sessionManager.getBranch()) {
      if (e.type === "message" && e.message?.role === "assistant") {
        const u = e.message.usage;
        if (!u) continue;
        input += u.input ?? 0;
        output += u.output ?? 0;
        cost += u.cost?.total ?? 0;
        // cache field name varies across providers — read defensively, show only if present
        cacheRead +=
          u.cacheRead ?? u.cache_read ?? u.cacheReadTokens ?? u.cache?.read ?? 0;
      }
    }
  } catch {
    /* session not ready */
  }
  return { input, output, cost, cacheRead };
}

// ---------------------------------------------------------------------------
//  Build the full footer line for a given terminal width
// ---------------------------------------------------------------------------
function buildLine(
  ctx: any,
  footerData: any,
  width: number,
  quotaState: QuotaState | null,
  compression: CompressionMetrics
): string {
  const left: Segment[] = [];
  const right: Segment[] = [];

  const proxyInfo = quotaState?.proxy_info ?? null;
  const modelSwapped = proxyInfo?.model_swapped ?? false;

  // --- LEFT: model (+ proxy redirect) ---
  const modelId = ctx.model?.id || "no-model";
  const shortModel = modelId.replace("claude-", "c").replace(/-202.*/, "");
  left.push({ icon: ICON.model, text: shortModel, bg: PALETTE.surface1, fg: PALETTE.lavender });
  if (modelSwapped && proxyInfo) {
    const actualShort = proxyInfo.actual_model
      .replace("claude-", "c")
      .replace(/-202.*/, "")
      .replace("gpt-4o", "gpt4o")
      .replace("o4-mini", "o4m");
    left.push({ icon: ICON.proxy, text: `→${actualShort}`, bg: PALETTE.proxy, fg: PALETTE.text });
  }

  // --- LEFT: project dir ---
  const project = (ctx.cwd || "").split("/").filter(Boolean).pop() || "~";
  left.push({ icon: ICON.dir, text: project, bg: PALETTE.surface0, fg: PALETTE.text });

  // --- LEFT: git branch ---
  const branch = typeof footerData?.getGitBranch === "function" ? footerData.getGitBranch() : null;
  if (branch) {
    left.push({ icon: ICON.branch, text: branch, bg: PALETTE.surface0, fg: PALETTE.green });
  }

  // --- LEFT: compression savings ---
  const compSaved = compression.rtkTokensSaved || compression.headroomTokensSaved;
  if (compSaved) {
    left.push({ icon: ICON.compression, text: `▼${fmtTokens(compSaved)}`, bg: PALETTE.surface0, fg: PALETTE.sapphire });
  }

  // --- RIGHT: context % (color-coded bar) ---
  const usage = typeof ctx.getContextUsage === "function" ? ctx.getContextUsage() : undefined;
  if (usage && usage.percent != null) {
    const pct = usage.percent;
    right.push({
      icon: ICON.context,
      text: `${contextBar(pct)} ${pct.toFixed(1)}%`,
      bg: contextColor(pct),
      fg: PALETTE.bg,
    });
  }

  // --- RIGHT: tokens / window ---
  const { input, output, cost, cacheRead } = aggregateUsage(ctx);
  const totalT = input + output;
  const ctxSize = usage?.contextWindow || ctx.model?.contextWindow || 0;
  if (totalT > 0) {
    const winStr = ctxSize ? `/${fmtTokens(ctxSize)}` : "";
    right.push({ icon: ICON.tokens, text: `${fmtTokens(totalT)}${winStr}`, bg: PALETTE.surface1, fg: PALETTE.text });
  }

  // --- RIGHT: cache hit rate (only if provider reports it) ---
  if (cacheRead > 0 && input > 0) {
    const cachePct = Math.round((cacheRead / input) * 100);
    right.push({ icon: ICON.cache, text: `${cachePct}%`, bg: PALETTE.surface1, fg: PALETTE.sapphire });
  }

  // --- RIGHT: cost ---
  if (cost > 0) {
    right.push({ icon: ICON.cost, text: fmtCost(cost), bg: PALETTE.surface0, fg: PALETTE.yellow });
  }

  // --- RIGHT: provider quota (from external quota daemon file) ---
  if (quotaState?.providers) {
    for (const [name, q] of Object.entries(quotaState.providers)) {
      const used = q["5h_used_pct"] ?? q["daily_used_pct"];
      if (used != null) {
        right.push({
          icon: ICON.quota,
          text: `${name[0].toUpperCase()}:5h${Math.round(used)}%`,
          bg: quotaColor(used),
          fg: PALETTE.bg,
        });
      }
    }
    // budget remaining (USD)
    const budgetParts: string[] = [];
    for (const [name, q] of Object.entries(quotaState.providers)) {
      if (q.budget_remaining_usd != null && q.budget_remaining_usd > 0) {
        budgetParts.push(`${name[0].toUpperCase()}:$${q.budget_remaining_usd.toFixed(2)}`);
      }
    }
    if (budgetParts.length) {
      right.push({ icon: ICON.cost, text: budgetParts.join(" "), bg: PALETTE.surface0, fg: PALETTE.green });
    }
  }

  // --- RIGHT: quota warnings ---
  if (quotaState?.warnings?.length) {
    right.push({ icon: ICON.warn, text: `${quotaState.warnings.length}`, bg: PALETTE.red, fg: PALETTE.bg });
  }

  // --- compose with adaptive truncation ---
  const leftStr = renderLeft(left);
  let rightStr = renderRight(right);

  const lw = visibleWidth(leftStr);
  let rw = visibleWidth(rightStr);

  // If too wide, drop right segments from the left end (least critical first kept last)
  while (lw + rw > width && right.length > 0) {
    right.shift();
    rightStr = renderRight(right);
    rw = visibleWidth(rightStr);
  }

  const padCount = Math.max(1, width - lw - rw);
  const line = leftStr + " ".repeat(padCount) + rightStr;

  // Hard cap (never overflow the terminal width)
  if (visibleWidth(line) <= width) return line;
  // Fall back to left side only if even that overflows
  return lw <= width ? leftStr : leftStr; // renderer keeps segments atomic; TUI clips remainder
}

// ---------------------------------------------------------------------------
//  Extension entry point
// ---------------------------------------------------------------------------
export default function hyperstatus(pi: ExtensionAPI) {
  let quotaState: QuotaState | null = null;
  const compression: CompressionMetrics = {};
  let requestRender: (() => void) | null = null;
  let pollTimer: ReturnType<typeof setInterval> | null = null;

  async function refresh(): Promise<void> {
    const q = await readJson(QUOTA_FILE);
    quotaState = q?.summary ?? q ?? null;

    const rtk = await readJson(RTK_FILE);
    if (rtk) {
      if (typeof rtk.tokens_saved === "number") compression.rtkTokensSaved = rtk.tokens_saved;
    }

    const headroomUrl = process.env.HEADROOM_ENDPOINT;
    if (headroomUrl) {
      try {
        const resp = await fetch(`${headroomUrl}/metrics`);
        const data: any = await resp.json();
        if (typeof data.tokens_saved === "number") compression.headroomTokensSaved = data.tokens_saved;
      } catch {
        /* proxy unavailable */
      }
    }
    requestRender?.();
  }

  pi.on("session_start", async (_event, ctx) => {
    if (!ctx.hasUI) return;

    await refresh();
    if (!pollTimer) {
      pollTimer = setInterval(() => {
        void refresh();
      }, 15000);
      // don't keep the process alive solely for the status poller
      (pollTimer as any).unref?.();
    }

    ctx.ui.setFooter((tui: any, _theme: any, footerData: any) => {
      requestRender = () => tui.requestRender?.();
      const unsub =
        typeof footerData?.onBranchChange === "function"
          ? footerData.onBranchChange(() => tui.requestRender?.())
          : undefined;
      return {
        dispose() {
          if (typeof unsub === "function") unsub();
          if (pollTimer) {
            clearInterval(pollTimer);
            pollTimer = null;
          }
          requestRender = null;
        },
        invalidate() {},
        render(width: number): string[] {
          return [buildLine(ctx, footerData, width, quotaState, compression)];
        },
      };
    });
  });
}
