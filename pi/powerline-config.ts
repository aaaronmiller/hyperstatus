/**
 * Powerline separator and theme configuration for Pi HyperStatus Extension
 */

export interface PowerlineSeparator {
  right: string;      // \ue0b0
  rightThin: string;  // \ue0b1
  left: string;       // \ue0b2
  leftThin: string;   // \ue0b3
}

export interface PowerlineConfig {
  separator: PowerlineSeparator;
  segmentPadding: number;    // px padding inside segments
  segmentGap: number;        // px gap between segments
  borderStyle: "none" | "thin" | "rounded";
  borderColor: string;
  maxLineWidth: number;      // Terminal width for adaptive layout
  adaptiveBreakpoints: {
    full: number;    // >= 76 cols: full layout
    compact: number; // 52-75 cols: compact
    minimal: number; // < 52 cols: minimal
  };
}

export const defaultConfig: PowerlineConfig = {
  separator: {
    right: "\ue0b0",      //  Powerline right
    rightThin: "\ue0b1",  //  Powerline right thin
    left: "\ue0b2",       //  Powerline left
    leftThin: "\ue0b3",   //  Powerline left thin
  },
  segmentPadding: 4,
  segmentGap: 0,
  borderStyle: "none",
  borderColor: "transparent",
  maxLineWidth: 120,
  adaptiveBreakpoints: {
    full: 76,
    compact: 52,
    minimal: 0,
  },
};

/** Determine which items to show based on terminal width */
export function getAdaptiveLayout(
  width: number,
  allItems: string[]
): string[] {
  if (width >= 76) return allItems; // Full layout

  if (width >= 52) {
    // Compact: drop rate limits, cache, PR, worktree, speed
    return allItems.filter(
      (item) =>
        !["rate5", "rate7", "cache", "pr", "worktree", "speed"].includes(item)
    );
  }

  // Minimal: only model, context, duration, YOLO
  return ["model", "context_pct", "duration", "yolo"];
}
