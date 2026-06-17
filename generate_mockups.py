#!/usr/bin/env python3
"""
Generate visual status bar mockup images using Playwright
These show how the status bars would actually look in a terminal
"""
import asyncio
import os

async def generate_mockups():
    try:
        from playwright.async_api import async_playwright
    except ImportError:
        print("Playwright not available, skipping visual mockups")
        return
    
    output_dir = "/home/z/my-project/download/statusbar/mockups"
    os.makedirs(output_dir, exist_ok=True)
    
    html_content = """<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  @page { size: 900px 500px; margin: 0; }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { 
    background: #0d1117; 
    font-family: 'Sarasa Mono SC', 'DejaVu Sans Mono', monospace; 
    padding: 30px;
    width: 900px;
  }
  h2 { 
    color: #8b949e; 
    font-size: 11px; 
    text-transform: uppercase; 
    letter-spacing: 2px; 
    margin-bottom: 12px;
    font-weight: 400;
  }
  .terminal {
    background: #161b22;
    border: 1px solid #30363d;
    border-radius: 8px;
    overflow: hidden;
    margin-bottom: 24px;
    box-shadow: 0 4px 12px rgba(0,0,0,0.3);
  }
  .terminal-header {
    background: #1c2128;
    padding: 8px 12px;
    display: flex;
    gap: 6px;
    border-bottom: 1px solid #30363d;
  }
  .dot { width: 10px; height: 10px; border-radius: 50%; }
  .dot-red { background: #f38ba8; }
  .dot-yellow { background: #f9e2af; }
  .dot-green { background: #a6e3a1; }
  .terminal-title { color: #6c7086; font-size: 10px; margin-left: 8px; line-height: 10px; }
  
  .terminal-body {
    padding: 16px;
    color: #cdd6f4;
    font-size: 11px;
    line-height: 1.5;
    min-height: 120px;
  }
  .prompt { color: #a6e3a1; }
  .cmd { color: #89b4fa; }
  .output { color: #6c7086; }
  
  /* Status bar styles */
  .statusbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0;
    font-size: 11px;
    font-family: 'Sarasa Mono SC', 'DejaVu Sans Mono', monospace;
  }
  .statusbar-inner {
    display: flex;
    align-items: center;
    width: 100%;
  }
  
  .seg {
    display: inline-flex;
    align-items: center;
    padding: 3px 8px;
    white-space: nowrap;
    font-size: 11px;
    line-height: 1;
  }
  .seg-icon { margin-right: 4px; opacity: 0.8; }
  
  /* Powerline arrow */
  .pl-arrow {
    font-size: 14px;
    line-height: 1;
    margin: 0 -1px;
  }
  
  /* Left zone */
  .left-zone { display: inline-flex; align-items: center; }
  .right-zone { display: inline-flex; align-items: center; margin-left: auto; }
  
  /* Color scheme: Catppuccin Mocha */
  .bg-teal { background: #1a6b5a; color: #cdd6f4; }
  .bg-teal-dark { background: #155044; color: #cdd6f4; }
  .bg-purple { background: #45475a; color: #cdd6f4; }
  .bg-ok { background: #40a02b; color: #1e1e2e; }
  .bg-warn { background: #df8e1d; color: #1e1e2e; }
  .bg-crit { background: #d20f39; color: #1e1e2e; }
  .bg-surface0 { background: #313244; color: #cdd6f4; }
  .bg-surface1 { background: #45475a; color: #cdd6f4; }
  .bg-surface2 { background: #585b70; color: #cdd6f4; }
  
  .fg-lavender { color: #b4befe; }
  .fg-blue { color: #89b4fa; }
  .fg-sapphire { color: #74c7ec; }
  .fg-teal { color: #94e2d5; }
  .fg-green { color: #a6e3a1; }
  .fg-yellow { color: #f9e2af; }
  .fg-peach { color: #fab387; }
  .fg-red { color: #f38ba8; }
  .fg-mauve { color: #cba6f7; }
  .fg-text { color: #cdd6f4; }
  .fg-dim { color: #a6adc8; }
  
  /* Context bar */
  .ctx-bar { 
    font-size: 10px;
    letter-spacing: -0.5px;
  }
  .ctx-filled { color: #1e1e2e; }
  .ctx-empty { opacity: 0.3; }
  
  /* Line 2 context detail */
  .ctx-detail {
    display: flex;
    align-items: center;
    padding: 2px 8px;
    font-size: 10px;
    background: #df8e1d;
    color: #1e1e2e;
    border-radius: 0 0 4px 4px;
  }
  
  .separator { color: #585b70; margin: 0 4px; }
  
  /* Labels */
  .label {
    color: #6c7086;
    font-size: 9px;
    text-transform: uppercase;
    letter-spacing: 1px;
    margin-top: 4px;
    margin-bottom: 2px;
  }
</style>
</head>
<body>

<!-- Claude Code Mockup -->
<h2>Claude Code - HYPERSTATUS v2.0</h2>
<div class="terminal">
  <div class="terminal-header">
    <div class="dot dot-red"></div>
    <div class="dot dot-yellow"></div>
    <div class="dot dot-green"></div>
    <span class="terminal-title">chetaz@wsl2: ~/projects/my-app</span>
  </div>
  <div class="terminal-body">
    <div class="prompt">chetaz $</div>
    <div class="cmd">claude</div>
    <div class="output" style="margin: 8px 0 16px 0;">Welcome to Claude Code. Type your message...</div>
    <div class="prompt">></div>
    <div class="cmd">refactor the auth module to use JWT</div>
    <div class="output" style="margin: 4px 0;">I'll analyze the current auth module and refactor it...</div>
  </div>
  <div style="background: #1e1e2e; padding: 4px 8px;">
    <div class="statusbar">
      <div class="statusbar-inner">
        <!-- Left Zone -->
        <div class="left-zone">
          <span class="seg bg-teal"><span class="seg-icon">&#xe716;</span> c-sonnet-4</span>
          <span class="pl-arrow fg-teal-dark">&#xe0b0;</span>
          <span class="seg bg-teal-dark"><span class="seg-icon">&#xf07b;</span> my-app</span>
          <span class="seg bg-teal-dark fg-green"><span class="separator">|</span><span class="seg-icon">&#xf418;</span> feature/jwt</span>
          <span class="seg bg-teal-dark fg-peach"><span class="separator">|</span> +42/-7</span>
          <span class="seg bg-teal-dark fg-sapphire"><span class="separator">|</span><span class="seg-icon">&#xf410;</span> &#9660;12.4K</span>
        </div>
        <!-- Right Zone -->
        <div class="right-zone">
          <span class="seg bg-ok ctx-bar"><span class="seg-icon">&#xf6cf;</span> &#9608;&#9608;&#9608;&#9608;&#9617;&#9617;&#9617;&#9617;&#9617;&#9617; 23.6%</span>
          <span class="pl-arrow fg-ok" style="color:#40a02b;">&#xe0b0;</span>
          <span class="seg bg-surface1"><span class="seg-icon">&#xf1c9;</span> 49.3K/200K</span>
          <span class="separator">|</span>
          <span class="seg bg-surface1 fg-sapphire"><span class="seg-icon">&#xf021;</span> 97%</span>
          <span class="separator">|</span>
          <span class="seg bg-surface0 fg-yellow"><span class="seg-icon">&#xf155;</span> $0.06</span>
          <span class="separator">|</span>
          <span class="seg bg-surface0 fg-dim"><span class="seg-icon">&#xf9ee;</span> 45t/s</span>
          <span class="separator">|</span>
          <span class="seg bg-surface1 fg-dim"><span class="seg-icon">&#xf252;</span> 5h23%</span>
          <span class="seg bg-surface1 fg-dim"><span class="seg-icon">&#xf254;</span> 7d8%</span>
          <span class="separator">|</span>
          <span class="seg bg-surface0 fg-text"><span class="seg-icon">&#xf017;</span> 15m</span>
          <span class="seg bg-surface0 fg-mauve">&#9650;</span>
          <span class="seg bg-surface0 fg-lavender">&#10022;</span>
        </div>
      </div>
    </div>
  </div>
</div>

<!-- High Context Warning Mockup -->
<h2>Claude Code - High Context (80%+) with Detail Line</h2>
<div class="terminal">
  <div class="terminal-header">
    <div class="dot dot-red"></div>
    <div class="dot dot-yellow"></div>
    <div class="dot dot-green"></div>
    <span class="terminal-title">chetaz@wsl2: ~/projects/my-app</span>
  </div>
  <div class="terminal-body">
    <div class="prompt">></div>
    <div class="cmd">now add refresh token rotation</div>
    <div class="output" style="margin: 4px 0;">The context window is filling up. Consider /compact...</div>
  </div>
  <div style="background: #1e1e2e; padding: 4px 8px 0 8px;">
    <div class="statusbar">
      <div class="statusbar-inner">
        <div class="left-zone">
          <span class="seg bg-teal"><span class="seg-icon">&#xe716;</span> c-opus-4</span>
          <span class="pl-arrow fg-teal-dark">&#xe0b0;</span>
          <span class="seg bg-teal-dark"><span class="seg-icon">&#xf07b;</span> my-app</span>
          <span class="seg bg-teal-dark fg-green"><span class="separator">|</span><span class="seg-icon">&#xf418;</span> feature/jwt</span>
          <span class="seg bg-teal-dark fg-peach"><span class="separator">|</span> +156/-34</span>
          <span class="seg bg-teal-dark fg-sapphire"><span class="separator">|</span><span class="seg-icon">&#xf410;</span> &#9660;48.2K</span>
        </div>
        <div class="right-zone">
          <span class="seg bg-warn ctx-bar"><span class="seg-icon">&#xf6cf;</span> &#9608;&#9608;&#9608;&#9608;&#9608;&#9608;&#9608;&#9608;&#9617;&#9617; 83.4%</span>
          <span class="pl-arrow fg-warn" style="color:#df8e1d;">&#xe0b0;</span>
          <span class="seg bg-surface1"><span class="seg-icon">&#xf1c9;</span> 166.8K/200K</span>
          <span class="separator">|</span>
          <span class="seg bg-surface1 fg-sapphire"><span class="seg-icon">&#xf021;</span> 94%</span>
          <span class="separator">|</span>
          <span class="seg bg-surface0 fg-yellow"><span class="seg-icon">&#xf155;</span> $1.24</span>
          <span class="separator">|</span>
          <span class="seg bg-surface0 fg-dim"><span class="seg-icon">&#xf9ee;</span> 38t/s</span>
          <span class="separator">|</span>
          <span class="seg bg-surface1 fg-dim"><span class="seg-icon">&#xf252;</span> 5h67%</span>
          <span class="seg bg-surface1 fg-dim"><span class="seg-icon">&#xf254;</span> 7d12%</span>
          <span class="separator">|</span>
          <span class="seg bg-surface0 fg-text"><span class="seg-icon">&#xf017;</span> 47m</span>
          <span class="seg bg-surface0 fg-mauve">&#9889;</span>
          <span class="seg bg-surface0 fg-lavender">&#10022;</span>
        </div>
      </div>
    </div>
    <div class="ctx-detail">
      <span class="seg-icon">&#xf6cf;</span> CONTEXT: 158.2K in / 200K max | Remaining: 16.6% | Output: 8.6K | Cache R: 148.1K / Cache W: 3.2K
    </div>
  </div>
</div>

<!-- Hermes Agent Mockup -->
<h2>Hermes Agent - Adaptive Compact Layout</h2>
<div class="terminal">
  <div class="terminal-header">
    <div class="dot dot-red"></div>
    <div class="dot dot-yellow"></div>
    <div class="dot dot-green"></div>
    <span class="terminal-title">chetaz@wsl2: ~/api-server</span>
  </div>
  <div class="terminal-body">
    <div class="prompt">hermes></div>
    <div class="cmd">implement rate limiting middleware</div>
    <div class="output" style="margin: 4px 0;">Implementing rate limiter with sliding window...</div>
  </div>
  <div style="background: #1e1e2e; padding: 4px 8px;">
    <div class="statusbar">
      <div class="statusbar-inner">
        <div class="left-zone">
          <span class="seg bg-teal"><span class="seg-icon">&#x2695;</span> c-sonnet-4</span>
          <span class="separator" style="color:#585b70;">|</span>
          <span class="seg" style="background:transparent;color:#cdd6f4;"><span class="seg-icon">&#xf07b;</span> api-server</span>
          <span class="separator" style="color:#585b70;">|</span>
          <span class="seg" style="background:transparent;color:#a6e3a1;"><span class="seg-icon">&#xf418;</span> main</span>
        </div>
        <div class="right-zone">
          <span class="seg bg-ok ctx-bar"><span class="seg-icon">&#xf6cf;</span> &#9608;&#9608;&#9617;&#9617;&#9617;&#9617;&#9617;&#9617;&#9617;&#9617; 12.4%</span>
          <span class="separator">|</span>
          <span class="seg bg-surface1">12.4K/200K</span>
          <span class="separator">|</span>
          <span class="seg bg-surface0 fg-yellow">$0.06</span>
          <span class="separator">|</span>
          <span class="seg bg-surface0 fg-text">15m</span>
          <span class="seg bg-surface0 fg-sapphire"><span class="seg-icon">&#xf410;</span> 2</span>
          <span class="seg" style="background:#d20f39;color:#1e1e2e;font-weight:bold;">&#x26A0; YOLO</span>
        </div>
      </div>
    </div>
  </div>
</div>

<!-- Codex CLI Mockup -->
<h2>Codex CLI - Built-in Items (Limited Customization)</h2>
<div class="terminal">
  <div class="terminal-header">
    <div class="dot dot-red"></div>
    <div class="dot dot-yellow"></div>
    <div class="dot dot-green"></div>
    <span class="terminal-title">chetaz@wsl2: ~/data-pipeline</span>
  </div>
  <div class="terminal-body">
    <div class="prompt">codex></div>
    <div class="cmd">optimize the ETL pipeline for parallel processing</div>
    <div class="output" style="margin: 4px 0;">Analyzing current pipeline stages...</div>
  </div>
  <div style="background: #0d1117; border-top: 1px solid #30363d; padding: 4px 8px;">
    <div class="statusbar" style="font-size: 10px;">
      <div style="display:flex;align-items:center;gap:12px;color:#8b949e;">
        <span style="color:#58a6ff;">o4-mini+reasoning</span>
        <span>|</span>
        <span>/home/chetaz/data-pipeline</span>
        <span>|</span>
        <span style="color:#a6e3a1;">main</span>
        <span>|</span>
        <span>&#9608;&#9608;&#9617;&#9617; 23%</span>
        <span>|</span>
        <span>77% remaining</span>
        <span>|</span>
        <span>200K window</span>
        <span>|</span>
        <span>49.3K tokens</span>
        <span>|</span>
        <span>2.1K output</span>
        <span>|</span>
        <span style="color:#f9e2af;">5h:23%</span>
        <span>|</span>
        <span style="color:#f9e2af;">7d:8%</span>
      </div>
    </div>
  </div>
</div>

<!-- Pi Agent Mockup -->
<h2>Pi Agent - Powerline Extension (TypeScript)</h2>
<div class="terminal">
  <div class="terminal-header">
    <div class="dot dot-red"></div>
    <div class="dot dot-yellow"></div>
    <div class="dot dot-green"></div>
    <span class="terminal-title">chetaz@wsl2: ~/ml-service</span>
  </div>
  <div class="terminal-body">
    <div class="prompt">pi></div>
    <div class="cmd">add model versioning and A/B testing</div>
    <div class="output" style="margin: 4px 0;">I'll implement model versioning with traffic splitting...</div>
  </div>
  <div style="background: #1e1e2e; padding: 4px 8px;">
    <div class="statusbar">
      <div class="statusbar-inner">
        <div class="left-zone">
          <span class="seg" style="background:#45475a;color:#b4befe;"><span class="seg-icon">&#xe716;</span> c-sonnet-4</span>
          <span class="pl-arrow" style="color:#45475a;">&#xe0b0;</span>
          <span class="seg bg-surface0"><span class="seg-icon">&#xf07b;</span> ml-service</span>
          <span class="seg bg-surface0 fg-green"><span class="separator">|</span><span class="seg-icon">&#xf418;</span> ab-testing</span>
          <span class="seg bg-surface0 fg-sapphire"><span class="separator">|</span><span class="seg-icon">&#xf410;</span> &#9660;8.2K</span>
        </div>
        <div class="right-zone">
          <span class="seg bg-ok ctx-bar"><span class="seg-icon">&#xf6cf;</span> &#9608;&#9608;&#9608;&#9617;&#9617;&#9617;&#9617;&#9617;&#9617;&#9617; 31.2%</span>
          <span class="pl-arrow fg-ok" style="color:#40a02b;">&#xe0b0;</span>
          <span class="seg bg-surface1"><span class="seg-icon">&#xf1c9;</span> 62.4K/200K</span>
          <span class="separator">|</span>
          <span class="seg bg-surface1 fg-sapphire"><span class="seg-icon">&#xf021;</span> 95%</span>
          <span class="separator">|</span>
          <span class="seg bg-surface0 fg-yellow"><span class="seg-icon">&#xf155;</span> $0.18</span>
          <span class="separator">|</span>
          <span class="seg bg-surface0 fg-dim">42t/s</span>
          <span class="separator">|</span>
          <span class="seg bg-surface0 fg-text"><span class="seg-icon">&#xf017;</span> 23m</span>
          <span class="seg bg-surface0 fg-mauve">&#9650;</span>
        </div>
      </div>
    </div>
  </div>
</div>

<!-- Anti-Jitter Comparison -->
<h2>Anti-Jitter Design: Before vs After</h2>
<div class="terminal">
  <div class="terminal-header">
    <div class="dot dot-red"></div>
    <div class="dot dot-yellow"></div>
    <div class="dot dot-green"></div>
    <span class="terminal-title">Comparison</span>
  </div>
  <div class="terminal-body" style="font-size:10px;">
    <div class="label" style="color:#f38ba8;">BEFORE (naive left-to-right - items jitter when model changes):</div>
    <div style="background:#1e1e2e;padding:6px 10px;border-radius:4px;margin:4px 0 12px 0;color:#cdd6f4;font-family:monospace;font-size:11px;">
      [c-sonnet-4] my-app main &nbsp;&nbsp; 23.6% | $0.06 | 15m
    </div>
    <div style="background:#1e1e2e;padding:6px 10px;border-radius:4px;margin:4px 0 4px 0;color:#cdd6f4;font-family:monospace;font-size:11px;">
      [c-opus-4-xhigh] my-app main &nbsp;&nbsp; <span style="color:#f38ba8;">23.6% | $0.06 | 15m &larr; SHIFTED!</span>
    </div>
    
    <div class="label" style="color:#a6e3a1;margin-top:16px;">AFTER (HYPERSTATUS bipartite - fixed items never move):</div>
    <div style="background:#1e1e2e;padding:6px 10px;border-radius:4px;margin:4px 0 12px 0;color:#cdd6f4;font-family:monospace;font-size:11px;">
      [c-sonnet-4] my-app main &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; 23.6% | $0.06 | 15m
    </div>
    <div style="background:#1e1e2e;padding:6px 10px;border-radius:4px;margin:4px 0 4px 0;color:#cdd6f4;font-family:monospace;font-size:11px;">
      [c-opus-4-xhigh] my-app main &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; <span style="color:#a6e3a1;">23.6% | $0.06 | 15m &larr; SAME POSITION</span>
    </div>
  </div>
</div>

</body>
</html>
"""
    
    # Write HTML
    html_path = os.path.join(output_dir, "statusbar_mockups.html")
    with open(html_path, 'w') as f:
        f.write(html_content)
    
    # Render to PDF and PNG
    async with async_playwright() as p:
        browser = await p.chromium.launch()
        page = await browser.new_page()
        await page.set_viewport_size({"width": 900, "height": 1800})
        await page.goto(f"file://{html_path}")
        await page.wait_for_timeout(1000)
        
        # Screenshot
        png_path = os.path.join(output_dir, "statusbar_mockups.png")
        await page.screenshot(path=png_path, full_page=True)
        print(f"PNG mockup: {png_path}")
        
        # PDF
        pdf_path = os.path.join(output_dir, "statusbar_mockups.pdf")
        await page.pdf(path=pdf_path, width="900px", height="1800px", margin={"top": "0", "bottom": "0", "left": "0", "right": "0"}, print_background=True)
        print(f"PDF mockup: {pdf_path}")
        
        await browser.close()


if __name__ == "__main__":
    asyncio.run(generate_mockups())
