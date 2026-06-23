/**
 * ============================================================================
 *  HYPERSTATUS v3.0 — Pi Agent Status Bar Extension
 *  Powerline-style status bar for @earendil-works/pi-coding-agent v0.79.9+
 *
 *  Rewritten for Pi's current ExtensionAPI (factory function + setFooter).
 *  Install: Copy to ~/.pi/agent/extensions/hyperstatus/
 * ============================================================================
 */
import type { ExtensionAPI, ExtensionContext, ReadonlyFooterDataProvider } from "@earendil-works/pi-coding-agent";

// ---------------------------------------------------------------------------
// Visible-width helpers (pi-tui isn't importable from extensions)
// ---------------------------------------------------------------------------

export {};
function visibleWidth(str: string): number {
  let w = 0, inEsc = false;
  for (const ch of str) {
    if (inEsc) { if (ch === "m") inEsc = false; continue; }
    if (ch === "\x1b") { inEsc = true; continue; }
    const cp = ch.codePointAt(0)!;
    w += (cp >= 0x1100 && cp <= 0x115F) || (cp >= 0x2329 && cp <= 0x232A) ||
         (cp >= 0x2E80 && cp <= 0x303E) || (cp >= 0x3040 && cp <= 0x33FF) ||
         (cp >= 0x3400 && cp <= 0x4DBF) || (cp >= 0x4E00 && cp <= 0xA4CF) ||
         (cp >= 0xAC00 && cp <= 0xD7AF) || (cp >= 0xF900 && cp <= 0xFAFF) ||
         (cp >= 0xFE10 && cp <= 0xFE19) || (cp >= 0xFE30 && cp <= 0xFE6F) ||
         (cp >= 0xFF01 && cp <= 0xFF60) || (cp >= 0xFFE0 && cp <= 0xFFE6) ||
         (cp >= 0x1B000 && cp <= 0x1B0FF) || (cp >= 0x1D300 && cp <= 0x1D35F) ||
         (cp >= 0x20000 && cp <= 0x2FA1F) || (cp >= 0x30000 && cp <= 0x313AF)
         ? 2 : 1;
  }
  return w;
}

function truncateToWidth(str: string, maxW: number, ell = "…"): string {
  if (visibleWidth(str) <= maxW) return str;
  let res = "", w = 0, inEsc = false, buf = "";
  for (const ch of str) {
    if (inEsc) { buf += ch; if (ch === "m") { res += buf; buf = ""; inEsc = false; } continue; }
    if (ch === "\x1b") { inEsc = true; buf = ch; continue; }
    const cw = ch.codePointAt(0)! >= 0x4E00 ? 2 : 1;
    if (w + cw > maxW - 1) break;
    res += ch; w += cw;
  }
  return res + (buf.startsWith("\x1b") ? "\x1b[0m" : "") + ell;
}

// ---------------------------------------------------------------------------
// ANSI helpers + Catppuccin Mocha palette
// ---------------------------------------------------------------------------

const C = {
  bg: "#1e1e2e", s0: "#313244", s1: "#45475a", s2: "#585b70",
  text: "#cdd6f4", lav: "#b4befe", blue: "#89b4fa", sap: "#74c7ec",
  teal: "#94e2d5", grn: "#a6e3a1", yel: "#f9e2af", pch: "#fab387",
  red: "#f38ba8", mauv: "#cba6f7", pink: "#f5c2e7", quot: "#9370db",
  proxy: "#7c3aed",
} as const;

function bg(h: string) { const r=parseInt(h.slice(1,3),16),g=parseInt(h.slice(3,5),16),b=parseInt(h.slice(5,7),16); return `\x1b[48;2;${r};${g};${b}m`; }
function fg(h: string) { const r=parseInt(h.slice(1,3),16),g=parseInt(h.slice(3,5),16),b=parseInt(h.slice(5,7),16); return `\x1b[38;2;${r};${g};${b}m`; }
const R = "\x1b[0m";
const S = "\ue0b0"; // powerline separator

const I = { model:"\ue716", ctx:"\uf6cf", tok:"\uf1c9", cost:"\uf155", dur:"\uf017",
            comp:"\uf410", git:"\uf418", dir:"\uf07b", eff:"\uf58c", perm:"\uf132",
            quot:"\uf0ec", proxy:"\uf6ff", cache:"\uf021", bg:"\uf44e" };

function ctxClr(p: number) { return p>=95?C.red : p>=80?C.pch : p>=50?C.yel : C.grn; }
function bar(p: number, w=10) { const f=Math.round(p/100*w); return "█".repeat(f)+"░".repeat(w-f); }
function t(n: number) { return n>=1e6?`${(n/1e6).toFixed(1)}M` : n>=1e3?`${(n/1e3).toFixed(1)}K` : `${n}`; }
function c(n: number) { return `$${n.toFixed(2)}`; }

function dur(ms: number): string {
  const s=Math.floor(ms/1000), m=Math.floor(s/60), h=Math.floor(m/60);
  return h?`${h}h${m%60}m` : m?`${m}m` : `${s}s`;
}

// ---------------------------------------------------------------------------
// Extension factory
// ---------------------------------------------------------------------------

export default function (pi: ExtensionAPI) {
  const data: {
    ctx: ExtensionContext | null;
    compression: Record<string, number>;
  } = { ctx: null, compression: {} };

  // Token/cost from session
  function metrics(ctx: ExtensionContext) {
    let i=0, o=0, cost=0;
    try {
      const mgr = (ctx as any).sessionManager;
      if (mgr?.getBranch) {
        for (const e of mgr.getBranch()) {
          if (e.type==="message" && e.message?.role==="assistant") {
            const u=e.message.usage;
            if (u) { i+=u.input??0; o+=u.output??0; cost+=u.cost?.total??0; }
          }
        }
      }
    } catch { /* */ }
    return { input: i, output: o, cost };
  }

  // Quota polling
  const qPath = process.env.HYPERSTATUS_QUOTA ?? "/tmp/hyperstatus-quota.json";
  let quotaState: Record<string, any> = {};
  async function loadQuota() {
    try {
      const raw = await import("node:fs/promises").then(m => m.readFile(qPath, "utf-8"));
      quotaState = JSON.parse(raw)?.summary ?? {};
    } catch { /* */ }
  }
  loadQuota();
  const qTimer = setInterval(loadQuota, 30_000);

  // Headroom polling
  const hUrl = process.env.HEADROOM_ENDPOINT ?? "";
  let hTimer: ReturnType<typeof setInterval>;
  if (hUrl) {
    hTimer = setInterval(async () => {
      try {
        const r = await fetch(`${hUrl}/metrics`).then(r => r.json()) as any;
        data.compression = { saved: r.tokens_saved ?? 0, ratio: r.compression_ratio ?? 0 };
      } catch { /* */ }
    }, 5_000);
  }

  // Permission label
  function permLabel(): string | null {
    if (process.env.PI_YOLO === "1" || process.env.HERMES_YOLO_MODE === "1") return "Y";
    if (process.env.PI_AUTO_ACCEPT === "1") return "A";
    return null;
  }

  // Build primary footer line (line 1)
  function renderPrimaryLine(w: number, ctx: ExtensionContext): string {
    const model = (ctx as any).model ?? {};
    const mShort = (model.displayName??model.id??"?").replace(/claude-/g,"c").replace(/-202\d.*/,"");
    const {input, output, cost} = metrics(ctx);
    const tot = input + output;
    const cu = ctx.getContextUsage?.();
    const pct = cu?.percent ?? 0;
    const win = cu?.contextWindow ?? 0;

    const proxyInfo = quotaState?.proxy_info as any;
    const swapped = proxyInfo?.model_swapped ?? false;

    // Effort
    const eff = (model as any).reasoningLevel as string ?? "";
    const eIcon = eff.startsWith("x")||eff==="max"?"⚡" : eff==="high"?"▲" : eff==="medium"?"●" : "▼";

    // LEFT
    let l = "";
    if (swapped && proxyInfo) {
      const aShort = proxyInfo.actual_model.replace(/claude-/g,"c").replace(/-202\d.*/,"").replace(/gpt-4o/g,"gpt4o").replace(/o4-mini/g,"o4m");
      l += fg(C.lav)+bg(C.s1)+` ${I.model} ${mShort} `+R;
      l += fg(C.s1)+bg(C.proxy)+S+R;
      l += fg(C.text)+bg(C.proxy)+`${I.proxy}→${aShort} `+R;
    } else {
      l += fg(C.lav)+bg(C.s1)+` ${I.model} ${mShort} `+R;
    }

    let proj = "~";
    try { proj = String((ctx as any).cwd??"").split("/").pop()||"~"; } catch { /* */ }
    l += fg(C.text)+bg(C.s0)+`${S} ${I.dir}${proj} `+R;

    // RIGHT
    let r = "";
    if (pct > 0) {
      r += fg(C.bg)+bg(ctxClr(pct))+` ${I.ctx}${bar(pct)} ${pct.toFixed(1)}% `+R;
      r += fg(ctxClr(pct))+bg(C.s1)+S+R;
    }
    r += fg(C.text)+bg(C.s1)+` ${I.tok}${t(tot)}`+(win?`/${t(win)}`:"")+` `+R;
    r += fg(C.s1)+bg(C.s0)+S+R;

    if (cost > 0) {
      r += fg(C.yel)+bg(C.s0)+` ${I.cost}${c(cost)} `+R;
      r += fg(C.s0)+bg(C.s1)+S+R;
    }

    let durMs = 0;
    try { const s = (ctx as any).sessionManager; if (s?.getSessionStats) durMs = s.getSessionStats()?.duration??0; } catch { /* */ }
    r += fg(C.text)+bg(C.s1)+` ${I.dur}${dur(durMs)} `+R;

    if (eff) {
      r += fg(C.s1)+bg(C.s0)+S+R;
      r += fg(C.mauv)+bg(C.s0)+` ${I.eff}${eIcon} `+R;
    }

    const perm = permLabel();
    if (perm === "Y") r += fg(C.bg)+bg(C.red)+` ${I.perm}${perm} `+R;
    else if (perm === "A") r += fg(C.bg)+bg(C.yel)+` ${I.perm}${perm} `+R;

    // Join
    const lv = visibleWidth(l.replace(/\x1b\[[\d;]*m/g,""));
    const rv = visibleWidth(r.replace(/\x1b\[[\d;]*m/g,""));
    const gap = lv+rv < w ? " ".repeat(w-lv-rv) : " ";
    return truncateToWidth(l+gap+r, w);
  }

  // Build secondary footer line (line 2) — shown when terminal width >= 80
  function renderSecondaryLine(w: number, ctx: ExtensionContext): string {
    const qPct = quotaState?.total_remaining_pct != null ? quotaState.total_remaining_pct : null;
    const proxyInfo = quotaState?.proxy_info as any;
    const swapped = proxyInfo?.model_swapped ?? false;
    const saved = data.compression.saved;
    const perm = permLabel();

    // LEFT — proxy swap and/or compression
    let l = "";
    if (swapped && proxyInfo) {
      const aShort = proxyInfo.actual_model.replace(/claude-/g,"c").replace(/-202\d.*/,"").replace(/gpt-4o/g,"gpt4o").replace(/o4-mini/g,"o4m");
      l += fg(C.text)+bg(C.proxy)+` ${I.proxy}→${aShort} `+R;
      l += fg(C.proxy)+bg(C.s2)+S+R;
    }
    if (saved) {
      l += fg(C.sap)+bg(C.s2)+` ${I.comp}▼${t(saved)} `+R;
    }

    // RIGHT — quota (budget) and permission
    let r = "";
    if (qPct != null) {
      const qc = qPct>=95?C.red:qPct>=80?C.pch:qPct>=50?C.yel:C.quot;
      r += fg(C.bg)+bg(qc)+` ${I.quot}${qPct.toFixed(0)}% `+R;
      r += fg(qc)+bg(C.s1)+S+R;
    }
    if (perm === "Y") {
      r += fg(C.bg)+bg(C.red)+` ${I.perm}${perm} `+R;
    } else if (perm === "A") {
      r += fg(C.bg)+bg(C.yel)+` ${I.perm}${perm} `+R;
    }

    // If nothing to show, return empty
    if (!l && !r) return "";

    // Join
    const lv = visibleWidth(l.replace(/\x1b\[[\d;]*m/g,""));
    const rv = visibleWidth(r.replace(/\x1b\[[\d;]*m/g,""));
    const gap = lv+rv < w ? " ".repeat(w-lv-rv) : " ";
    return truncateToWidth(l+gap+r, w);
  }

  // Register
  pi.on("session_start", async (_event: any, ctx: ExtensionContext) => {
    data.ctx = ctx;
    ctx.ui.setFooter((_tui: any, _theme: any, _fData: any) => ({
      dispose: () => { clearInterval(qTimer); if (hTimer) clearInterval(hTimer); },
      invalidate() {},
      render(w: number) {
        const primary = renderPrimaryLine(w, data.ctx ?? ctx);
        if (w >= 80) {
          const secondary = renderSecondaryLine(w, data.ctx ?? ctx);
          return [primary, secondary].filter(Boolean);
        }
        return primary ? [primary] : [];
      },
    }));
  });

  pi.on("turn_end", (_event: any, ctx: ExtensionContext) => {
    data.ctx = ctx;
  });
}
