#!/usr/bin/env python3
"""
HYPERSTATUS v2.0 — Design Document Generator
Generates the comprehensive PDF design document with status bar mockups
"""
import os
import sys
from reportlab.lib.pagesizes import letter
from reportlab.lib.units import inch, mm
from reportlab.lib.colors import HexColor, white, black, Color
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_LEFT, TA_CENTER, TA_RIGHT, TA_JUSTIFY
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle,
    PageBreak, KeepTogether, Image, Flowable, HRFlowable
)
from reportlab.pdfgen import canvas
from reportlab.graphics.shapes import Drawing, Rect, String, Line
from reportlab.graphics import renderPDF

# ============================================================================
#  COLORS (Catppuccin Mocha-inspired)
# ============================================================================
C_BG = HexColor("#1e1e2e")
C_SURFACE0 = HexColor("#313244")
C_SURFACE1 = HexColor("#45475a")
C_SURFACE2 = HexColor("#585b70")
C_TEXT = HexColor("#cdd6f4")
C_SUBTEXT = HexColor("#a6adc8")
C_LAVENDER = HexColor("#b4befe")
C_BLUE = HexColor("#89b4fa")
C_SAPPHIRE = HexColor("#74c7ec")
C_TEAL = HexColor("#94e2d5")
C_GREEN = HexColor("#a6e3a1")
C_YELLOW = HexColor("#f9e2af")
C_PEACH = HexColor("#fab387")
C_MAROON = HexColor("#eba0ac")
C_RED = HexColor("#f38ba8")
C_MAUVE = HexColor("#cba6f7")
C_PINK = HexColor("#f5c2e7")

# Document colors
DOC_BG = white
DOC_TEXT = HexColor("#1e1e2e")
DOC_ACCENT = HexColor("#89b4fa")
DOC_HEADING = HexColor("#1e1e2e")
DOC_CODE_BG = HexColor("#f0f4f8")
DOC_BORDER = HexColor("#d0d7de")

# ============================================================================
#  CUSTOM FLOWABLE: Status Bar Mockup
# ============================================================================
class StatusBarMockup(Flowable):
    """Renders a visual mockup of a terminal status bar"""
    
    def __init__(self, left_items, right_items, width=468, bar_height=28,
                 bg_color=C_BG, context_pct=23.6, agent_name="Claude Code",
                 show_line2=False):
        Flowable.__init__(self)
        self.left_items = left_items
        self.right_items = right_items
        self.bar_width = width
        self.bar_height = bar_height
        self.bg_color = bg_color
        self.context_pct = context_pct
        self.agent_name = agent_name
        self.show_line2 = show_line2
        self.width = width
        self.height = bar_height + (24 if show_line2 else 0) + 8
    
    def draw(self):
        c = self.canv
        
        # Draw main bar background
        c.setFillColor(self.bg_color)
        c.roundRect(0, 0 if not self.show_line2 else 24, 
                    self.bar_width, self.bar_height, 4, fill=1, stroke=0)
        
        # Draw left items
        x = 8
        y_base = 8 if not self.show_line2 else 32
        
        for item in self.left_items:
            icon, text, color = item
            c.setFillColor(color)
            c.setFont("DejaVuSans", 8)
            # Draw icon placeholder
            c.drawString(x, y_base, f"[{icon}]", )
            x += len(f"[{icon}]") * 5.5 + 4
            c.drawString(x, y_base, text)
            x += len(text) * 5.5 + 8
            # Separator
            c.setFillColor(C_SURFACE2)
            c.drawString(x, y_base, "|")
            x += 12
        
        # Draw right items (right-aligned)
        x = self.bar_width - 8
        for item in reversed(self.right_items):
            icon, text, color = item
            c.setFillColor(color)
            c.setFont("DejaVuSans", 8)
            text_w = len(text) * 5.5 + 4
            icon_w = len(f"[{icon}]") * 5.5 + 2
            x -= text_w
            c.drawString(x, y_base, text)
            x -= icon_w
            c.drawString(x, y_base, f"[{icon}]")
            x -= 12
            # Separator
            c.setFillColor(C_SURFACE2)
            x -= 6
            c.drawString(x, y_base, "|")
            x -= 6
        
        # Draw line 2 (context detail)
        if self.show_line2:
            ctx_color = C_GREEN
            if self.context_pct >= 95: ctx_color = C_RED
            elif self.context_pct >= 80: ctx_color = C_PEACH
            elif self.context_pct >= 50: ctx_color = C_YELLOW
            
            c.setFillColor(ctx_color)
            c.roundRect(0, 0, self.bar_width, 22, 2, fill=1, stroke=0)
            c.setFillColor(C_BG)
            c.setFont("DejaVuSans", 7)
            c.drawString(8, 6, f"CONTEXT: 47.2K in / 200K max | Remaining: 76.4% | Output: 2.1K | Cache R: 45.8K / Cache W: 1.4K")


# ============================================================================
#  STYLES
# ============================================================================
def create_styles():
    styles = getSampleStyleSheet()
    
    styles.add(ParagraphStyle(
        'DocTitle',
        parent=styles['Title'],
        fontName='Helvetica-Bold',
        fontSize=28,
        textColor=DOC_HEADING,
        spaceAfter=6,
        spaceBefore=20,
        alignment=TA_LEFT,
    ))
    
    styles.add(ParagraphStyle(
        'DocSubtitle',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=14,
        textColor=C_BLUE,
        spaceAfter=20,
        spaceBefore=4,
        alignment=TA_LEFT,
    ))
    
    styles.add(ParagraphStyle(
        'H1',
        parent=styles['Heading1'],
        fontName='Helvetica-Bold',
        fontSize=18,
        textColor=DOC_HEADING,
        spaceAfter=8,
        spaceBefore=24,
        borderPadding=4,
    ))
    
    styles.add(ParagraphStyle(
        'H2',
        parent=styles['Heading2'],
        fontName='Helvetica-Bold',
        fontSize=14,
        textColor=HexColor("#45475a"),
        spaceAfter=6,
        spaceBefore=16,
    ))
    
    styles.add(ParagraphStyle(
        'H3',
        parent=styles['Heading3'],
        fontName='Helvetica-Bold',
        fontSize=12,
        textColor=HexColor("#585b70"),
        spaceAfter=4,
        spaceBefore=12,
    ))
    
    styles.add(ParagraphStyle(
        'BodyText2',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=10,
        textColor=DOC_TEXT,
        spaceAfter=8,
        spaceBefore=2,
        leading=14,
        alignment=TA_JUSTIFY,
    ))
    
    styles.add(ParagraphStyle(
        'CodeBlock',
        parent=styles['Code'],
        fontName='Courier',
        fontSize=8.5,
        textColor=HexColor("#1e1e2e"),
        backColor=DOC_CODE_BG,
        spaceAfter=8,
        spaceBefore=4,
        leftIndent=12,
        rightIndent=12,
        borderPadding=8,
        leading=12,
    ))
    
    styles.add(ParagraphStyle(
        'Caption',
        parent=styles['Normal'],
        fontName='Helvetica-Oblique',
        fontSize=9,
        textColor=HexColor("#6c7086"),
        spaceAfter=12,
        spaceBefore=4,
        alignment=TA_CENTER,
    ))
    
    styles.add(ParagraphStyle(
        'BulletItem',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=10,
        textColor=DOC_TEXT,
        spaceAfter=4,
        leftIndent=24,
        bulletIndent=12,
        leading=14,
    ))
    
    styles.add(ParagraphStyle(
        'RankNum',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=10,
        textColor=C_BLUE,
        alignment=TA_CENTER,
    ))

    return styles


# ============================================================================
#  PAGE TEMPLATE WITH HEADER/FOOTER
# ============================================================================
def page_template(canvas_obj, doc):
    canvas_obj.saveState()
    # Header line
    canvas_obj.setStrokeColor(C_BLUE)
    canvas_obj.setLineWidth(1.5)
    canvas_obj.line(72, letter[1] - 50, letter[0] - 72, letter[1] - 50)
    
    # Header text
    canvas_obj.setFont("Helvetica", 7)
    canvas_obj.setFillColor(HexColor("#6c7086"))
    canvas_obj.drawString(72, letter[1] - 45, "HYPERSTATUS v2.0")
    canvas_obj.drawRightString(letter[0] - 72, letter[1] - 45, "Coding Agent CLI Status Bar Design Document")
    
    # Footer
    canvas_obj.setStrokeColor(DOC_BORDER)
    canvas_obj.setLineWidth(0.5)
    canvas_obj.line(72, 50, letter[0] - 72, 50)
    canvas_obj.setFont("Helvetica", 7)
    canvas_obj.setFillColor(HexColor("#6c7086"))
    canvas_obj.drawString(72, 38, "June 2026 | Research + Design Reference")
    canvas_obj.drawRightString(letter[0] - 72, 38, f"Page {doc.page}")
    
    canvas_obj.restoreState()


# ============================================================================
#  MAIN DOCUMENT BUILDER
# ============================================================================
def build_document():
    output_path = "/home/z/my-project/download/HYPERSTATUS_v2_Design_Document.pdf"
    
    doc = SimpleDocTemplate(
        output_path,
        pagesize=letter,
        leftMargin=72,
        rightMargin=72,
        topMargin=72,
        bottomMargin=72,
    )
    
    styles = create_styles()
    story = []
    
    # ===========================================================================
    #  TITLE PAGE
    # ===========================================================================
    story.append(Spacer(1, 100))
    story.append(Paragraph("HYPERSTATUS v2.0", styles['DocTitle']))
    story.append(Paragraph("Coding Agent CLI Status Bar Design Document", styles['DocSubtitle']))
    story.append(Spacer(1, 20))
    story.append(HRFlowable(width="100%", thickness=2, color=C_BLUE))
    story.append(Spacer(1, 20))
    story.append(Paragraph(
        "A comprehensive research and design reference for building modern, "
        "information-dense status bars for coding agent CLIs. Covers Claude Code, "
        "Codex CLI, Hermes Agent, and Pi Agent with agent-specific configurations, "
        "Powerline-style visual designs, compression proxy integration methods, "
        "and automated setup tooling.",
        styles['BodyText2']
    ))
    story.append(Spacer(1, 12))
    
    # Metadata table
    meta_data = [
        ["Field", "Value"],
        ["Version", "2.0.0"],
        ["Date", "June 2, 2026"],
        ["Target Agents", "Claude Code, Codex CLI, Hermes Agent, Pi Agent"],
        ["Design Style", "Powerline + Catppuccin Mocha"],
        ["Font Requirements", "Nerd Font (e.g., MesloLGS NF, FiraCode NF)"],
        ["Platform", "Linux / WSL2"],
        ["Username", "chetaz (fallback if $HOME unavailable)"],
    ]
    meta_table = Table(meta_data, colWidths=[1.5*inch, 4.5*inch])
    meta_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), C_SURFACE1),
        ('TEXTCOLOR', (0, 0), (-1, 0), white),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 9),
        ('BACKGROUND', (0, 1), (0, -1), HexColor("#f0f4f8")),
        ('FONTNAME', (0, 1), (0, -1), 'Helvetica-Bold'),
        ('ALIGN', (0, 0), (0, -1), 'RIGHT'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('GRID', (0, 0), (-1, -1), 0.5, DOC_BORDER),
        ('ROWBACKGROUNDS', (1, 1), (-1, -1), [white, HexColor("#f8f9fa")]),
        ('TOPPADDING', (0, 0), (-1, -1), 6),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 6),
        ('LEFTPADDING', (0, 0), (-1, -1), 8),
    ]))
    story.append(meta_table)
    
    story.append(PageBreak())
    
    # ===========================================================================
    #  SECTION 1: TOP 25 STATUS BAR FEATURES
    # ===========================================================================
    story.append(Paragraph("1. Top 25 Status Bar Features", styles['H1']))
    story.append(Paragraph(
        "Based on extensive research across Reddit (r/ClaudeAI, r/ChatGPTCoding, r/LocalLLaMA), "
        "GitHub issue trackers, community tools (ccstatusline, pi-powerline-footer), and social media "
        "discussions through June 2026, these are the most popular and requested status bar features "
        "for coding agent CLIs, ranked by community demand and practical utility.",
        styles['BodyText2']
    ))
    
    # Feature ranking table
    features = [
        ("1", "Context Window %", "Visual bar + percentage of context used", "Critical", "All"),
        ("2", "Current Model Name", "Active model display (short form preferred)", "Critical", "All"),
        ("3", "Token Count", "Tokens used / max context window size", "Critical", "All"),
        ("4", "Session Cost (USD)", "Running total of API spend", "High", "Claude, Hermes, Pi"),
        ("5", "Git Branch", "Current branch name with icon", "High", "Claude, Codex, Pi"),
        ("6", "Session Duration", "Elapsed time since session start", "High", "Claude, Hermes, Pi"),
        ("7", "Rate Limits", "5-hour and 7-day usage caps with %", "High", "Claude, Codex"),
        ("8", "Working Directory", "Project/repo name", "Medium", "All"),
        ("9", "Cache Hit Rate", "% of tokens served from KV cache", "Medium", "Claude, Codex"),
        ("10", "Git Status", "Staged / unstaged / untracked file counts", "Medium", "Claude, Pi"),
        ("11", "Compression Count", "Number of auto-compaction events", "Medium", "Hermes, Claude"),
        ("12", "Model Latency", "API round-trip time or % of wall time", "Medium", "Claude, Pi"),
        ("13", "Background Tasks", "Count of active async/background tasks", "Medium", "Hermes"),
        ("14", "Permission Level", "YOLO / Auto / Ask mode indicator", "Medium", "Hermes, Claude"),
        ("15", "Tokens/Second", "Output throughput rate", "Medium", "Community request"),
        ("16", "Vim Mode", "NORMAL / INSERT / VISUAL indicator", "Low", "Claude, Codex"),
        ("17", "PR Information", "Open PR number and review state", "Low", "Claude"),
        ("18", "Worktree Name", "Git worktree for parallel sessions", "Low", "Claude"),
        ("19", "Output Tokens", "Separate output token counter", "Low", "Claude, Codex"),
        ("20", "Reasoning Effort", "Low / Medium / High / Max indicator", "Low", "Claude, Codex"),
        ("21", "Thinking Mode", "Extended thinking toggle indicator", "Low", "Claude"),
        ("22", "Lines Changed", "Lines added / removed in session", "Low", "Claude"),
        ("23", "API vs Wall Time", "Proportion of time spent waiting on API", "Low", "Community request"),
        ("24", "Compression Savings", "Tokens saved via Headroom/RTK proxy", "Emerging", "Via proxy"),
        ("25", "Session Name/ID", "Current session identifier", "Low", "Claude, Codex"),
    ]
    
    # Split into two parts for readability
    story.append(Paragraph("1.1 Features Ranked 1-13 (Critical and High Priority)", styles['H2']))
    
    feature_data_1 = [["#", "Feature", "Description", "Priority", "Agent Support"]] + [
        [f[0], f[1], f[2], f[3], f[4]] for f in features[:13]
    ]
    
    t1 = Table(feature_data_1, colWidths=[0.35*inch, 1.3*inch, 2.2*inch, 0.7*inch, 1.45*inch])
    t1.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), C_SURFACE1),
        ('TEXTCOLOR', (0, 0), (-1, 0), white),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 7.5),
        ('FONTNAME', (0, 1), (0, -1), 'Helvetica-Bold'),
        ('TEXTCOLOR', (0, 1), (0, -1), C_BLUE),
        ('ALIGN', (0, 0), (0, -1), 'CENTER'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('GRID', (0, 0), (-1, -1), 0.5, DOC_BORDER),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [white, HexColor("#f8f9fa")]),
        ('TOPPADDING', (0, 0), (-1, -1), 4),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
        ('LEFTPADDING', (0, 0), (-1, -1), 4),
        # Priority color coding
        ('TEXTCOLOR', (3, 1), (3, 3), C_RED),
        ('TEXTCOLOR', (3, 4), (3, 7), C_PEACH),
        ('TEXTCOLOR', (3, 8), (3, 13), C_YELLOW),
    ]))
    story.append(t1)
    story.append(Spacer(1, 12))
    
    story.append(Paragraph("1.2 Features Ranked 14-25 (Medium, Low, and Emerging Priority)", styles['H2']))
    
    feature_data_2 = [["#", "Feature", "Description", "Priority", "Agent Support"]] + [
        [f[0], f[1], f[2], f[3], f[4]] for f in features[13:]
    ]
    
    t2 = Table(feature_data_2, colWidths=[0.35*inch, 1.3*inch, 2.2*inch, 0.7*inch, 1.45*inch])
    t2.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), C_SURFACE1),
        ('TEXTCOLOR', (0, 0), (-1, 0), white),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 7.5),
        ('FONTNAME', (0, 1), (0, -1), 'Helvetica-Bold'),
        ('TEXTCOLOR', (0, 1), (0, -1), C_BLUE),
        ('ALIGN', (0, 0), (0, -1), 'CENTER'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('GRID', (0, 0), (-1, -1), 0.5, DOC_BORDER),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [white, HexColor("#f8f9fa")]),
        ('TOPPADDING', (0, 0), (-1, -1), 4),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
        ('LEFTPADDING', (0, 0), (-1, -1), 4),
        ('TEXTCOLOR', (3, 1), (3, 3), C_YELLOW),
        ('TEXTCOLOR', (3, 4), (3, 11), C_SUBTEXT),
        ('TEXTCOLOR', (3, 12), (3, 12), C_TEAL),
    ]))
    story.append(t2)
    
    story.append(Spacer(1, 8))
    story.append(Paragraph(
        "<b>Key Insight:</b> Context window percentage is universally the single most important piece "
        "of information across all tools. Research indicates model output quality degrades significantly "
        "past ~60% context usage, making a color-coded threshold indicator critical for practical use. "
        "The community has converged on green (&lt;50%), yellow (50-80%), orange (80-95%), and "
        "blinking red (&gt;95%) as the standard threshold palette.",
        styles['BodyText2']
    ))
    
    # ===========================================================================
    #  SECTION 2: AGENT FORMAT COMPARISON
    # ===========================================================================
    story.append(Paragraph("2. Agent Status Bar Format Comparison", styles['H1']))
    story.append(Paragraph(
        "Each coding agent implements its status bar differently. There is no shared format standard, "
        "configuration syntax, or rendering approach. The table below summarizes the key differences "
        "that affect status bar design and installation.",
        styles['BodyText2']
    ))
    
    comparison_data = [
        ["Aspect", "Claude Code", "Codex CLI", "Hermes Agent", "Pi Agent"],
        ["Config Format", "JSON (settings.json)", "TOML (config.toml)", "YAML (config.yaml)", "TypeScript (extension)"],
        ["Customization", "Arbitrary shell scripts\n(JSON on stdin)", "Fixed enum of\nbuilt-in items only", "YAML opt-in with\ngateway flags", "Full TypeScript\nextension API"],
        ["Multi-line", "Yes (each echo = row)", "No (issue #21653)", "Adaptive width\nmodes", "Yes (extension\ndriven)"],
        ["Position", "Bottom (like VS Code)", "Below input field", "Above input area", "Bottom footer"],
        ["Refresh Model", "Event-driven +\noptional interval", "Built-in refresh", "Real-time internal\nstate", "Extension hooks"],
        ["Color Support", "Full ANSI escape\ncodes", "Theme-based", "Color-coded\ncontext thresholds", "Full theme\naccess (CSS)"],
        ["Nerd Fonts", "Yes (via shell)", "Built-in icons", "Configurable\nUnicode glyphs", "Full icon\naccess"],
        ["Click Support", "Yes (OSC 8 links)", "No", "No", "No"],
        ["Max Bar Height", "Unlimited\n(multi-line)", "Single line", "2 lines (adaptive)", "Unlimited"],
        ["Data Pipeline", "JSON on stdin\n(complete schema)", "Internal TUI\nstate only", "Internal state\ndict", "Context object\npassed to extension"],
        ["Community Tools", "ccstatusline\n(10.1K+ stars)", "Built-in only\n(issues requesting\nshell support)", "Limited\n(new feature)", "pi-powerline-footer\n(14.3K/mo)"],
    ]
    
    ct = Table(comparison_data, colWidths=[1.0*inch, 1.4*inch, 1.3*inch, 1.3*inch, 1.2*inch])
    ct.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), C_SURFACE1),
        ('TEXTCOLOR', (0, 0), (-1, 0), white),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 7),
        ('FONTNAME', (0, 1), (0, -1), 'Helvetica-Bold'),
        ('BACKGROUND', (0, 1), (0, -1), HexColor("#f0f4f8")),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('GRID', (0, 0), (-1, -1), 0.5, DOC_BORDER),
        ('ROWBACKGROUNDS', (1, 1), (-1, -1), [white, HexColor("#f8f9fa")]),
        ('TOPPADDING', (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
        ('LEFTPADDING', (0, 0), (-1, -1), 5),
    ]))
    story.append(ct)
    
    story.append(Spacer(1, 8))
    story.append(Paragraph(
        "<b>Critical Finding:</b> These agents do NOT share the same status bar format or size. "
        "Claude Code is the most customizable (arbitrary shell scripts with JSON data), while Codex "
        "is the most constrained (fixed enum of built-in items with no shell script support). Each "
        "requires a distinct installation approach and configuration format. Agent-specific versions "
        "are necessary.",
        styles['BodyText2']
    ))
    
    # ===========================================================================
    #  SECTION 3: STATUS BAR DESIGN
    # ===========================================================================
    story.append(Paragraph("3. Status Bar Visual Design", styles['H1']))
    story.append(Paragraph(
        "The HYPERSTATUS design follows a Powerline-inspired aesthetic using the Catppuccin Mocha "
        "color palette. The layout strictly separates variable-width items (left-justified) from "
        "fixed-width items (right-justified) to prevent visual jitter when values like model names "
        "or paths change length. This is the single most important layout principle for status bars: "
        "items with static display widths (percentages, token counts, durations) must be anchored "
        "to a fixed position so they do not shift when preceding variable-width items change.",
        styles['BodyText2']
    ))
    
    # 3.1 Layout Architecture
    story.append(Paragraph("3.1 Layout Architecture", styles['H2']))
    story.append(Paragraph(
        "The status bar uses a two-zone architecture with a flexible spacer between left and right "
        "segments. This ensures that no matter how the model name, project path, or git branch "
        "changes in length, the right-side metrics remain locked to the terminal edge. The spacer "
        "absorbs all variable-width changes, providing a stable visual anchor for the metrics that "
        "users monitor most frequently (context percentage, cost, rate limits).",
        styles['BodyText2']
    ))
    
    # Layout diagram
    layout_diagram = """
    <b>Left Zone (variable-width, left-justified):</b>
        [Model] | [Project/Dir] | [Git Branch] | [Worktree] | [PR] | [Lines Changed] | [Compression Savings]
    
    <b>Flexible Spacer (absorbs width changes):</b>
        ......... (fills remaining terminal width)
    
    <b>Right Zone (fixed-width, right-justified):</b>
        [Context %] | [Tokens] | [Cache %] | [Cost] | [t/s] | [Rate 5h] | [Rate 7d] | [Duration] | [Effort] | [Think] | [Perm] | [Vim]
    """
    story.append(Paragraph(layout_diagram.replace("\n", "<br/>"), styles['CodeBlock']))
    
    # 3.2 Color System
    story.append(Paragraph("3.2 Color System and Thresholds", styles['H2']))
    story.append(Paragraph(
        "Colors serve a dual purpose: aesthetic consistency with the Catppuccin Mocha palette, and "
        "semantic signaling for threshold states. The context percentage bar dynamically changes "
        "background color as context fills, providing an instant visual warning without requiring "
        "the user to read the numeric value. This color-coding pattern is now the de facto standard "
        "across all major coding agent CLIs and community tools.",
        styles['BodyText2']
    ))
    
    threshold_data = [
        ["Threshold", "Color", "Hex", "Semantic Meaning"],
        ["< 50%", "Green", "#a6e3a1", "Healthy context - ample room remaining"],
        ["50-80%", "Yellow", "#f9e2af", "Moderate usage - quality may start to degrade"],
        ["80-95%", "Orange/Peach", "#fab387", "High usage - consider /compact or /compress"],
        ["> 95%", "Red (blinking)", "#f38ba8", "Critical - imminent context overflow"],
    ]
    
    tt = Table(threshold_data, colWidths=[0.9*inch, 1.1*inch, 0.9*inch, 3.1*inch])
    tt.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), C_SURFACE1),
        ('TEXTCOLOR', (0, 0), (-1, 0), white),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 8.5),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('GRID', (0, 0), (-1, -1), 0.5, DOC_BORDER),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [white, HexColor("#f8f9fa")]),
        ('TOPPADDING', (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
        ('LEFTPADDING', (0, 0), (-1, -1), 6),
        # Color swatches in column 2
        ('BACKGROUND', (1, 1), (1, 1), C_GREEN),
        ('BACKGROUND', (1, 2), (1, 2), C_YELLOW),
        ('BACKGROUND', (1, 3), (1, 3), C_PEACH),
        ('BACKGROUND', (1, 4), (1, 4), C_RED),
        ('TEXTCOLOR', (1, 1), (1, 4), C_BG),
        ('FONTNAME', (1, 1), (1, 4), 'Helvetica-Bold'),
    ]))
    story.append(tt)
    
    # 3.3 Nerd Font Icon Selection
    story.append(Paragraph("3.3 Nerd Font Icon Selection", styles['H2']))
    story.append(Paragraph(
        "Nerd Font icons provide visual anchoring that allows instant recognition of each metric "
        "without reading the label. The icon selections below prioritize distinguishability at small "
        "sizes (8-10pt terminal font) and semantic clarity. All codepoints are from the Nerd Fonts "
        "Symbols Only range, which is available in any Nerd Font-patched typeface. If Nerd Fonts "
        "are not installed, the system falls back to Unicode block characters and ASCII symbols.",
        styles['BodyText2']
    ))
    
    icon_data = [
        ["Metric", "Nerd Font Icon", "Codepoint", "Fallback"],
        ["Model/AI", "󰜖 (lf", "\\ue716", "[M]"],
        ["Context", "(db", "\\uf6cf", "[CTX]"],
        ["Tokens", "(file", "\\uf1c9", "[T]"],
        ["Cost", "(dollar", "\\uf155", "[$]"],
        ["Git Branch", "󰐘 (branch", "\\uf418", "[B]"],
        ["Clock/Duration", "(clock", "\\uf017", "[t]"],
        ["Cache", "(refresh", "\\uf021", "[C]"],
        ["Compression", "(compress", "\\uf410", "[Z]"],
        ["Background Tasks", "(tasks", "\\uf44e", "[BG]"],
        ["Permission/Lock", "(lock", "\\uf132", "[P]"],
        ["Latency/Speed", "(gauge", "\\uf9ee", "[L]"],
        ["Thinking Mode", "(brain", "\\uf7b4", "[+]"],
        ["Effort Level", "(mountain", "\\uf58c", "[E]"],
        ["PR Info", "(git-pull", "\\ue728", "[PR]"],
        ["Worktree", "(tree", "\\uf77a", "[W]"],
        ["Rate Limits", "(hourglass", "\\uf252", "[R]"],
        ["Folder/Project", "(folder", "\\uf07b", "[D]"],
        ["Powerline Right", "(pl-right", "\\ue0b0", ">"],
        ["Powerline Left", "(pl-left", "\\ue0b2", "<"],
    ]
    
    it = Table(icon_data, colWidths=[1.2*inch, 1.2*inch, 0.9*inch, 0.8*inch])
    it.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), C_SURFACE1),
        ('TEXTCOLOR', (0, 0), (-1, 0), white),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 7.5),
        ('FONTNAME', (0, 1), (0, -1), 'Helvetica-Bold'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('GRID', (0, 0), (-1, -1), 0.5, DOC_BORDER),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [white, HexColor("#f8f9fa")]),
        ('TOPPADDING', (0, 0), (-1, -1), 4),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
        ('LEFTPADDING', (0, 0), (-1, -1), 5),
    ]))
    story.append(it)
    
    # 3.4 Anti-Jitter Design Pattern
    story.append(Paragraph("3.4 Anti-Jitter Design Pattern", styles['H2']))
    story.append(Paragraph(
        "The most common design mistake in status bars is placing fixed-width metrics after "
        "variable-width items on the same side. When a model name changes from 'c-sonnet-4' (9 chars) "
        "to 'c-opus-4-xhigh' (13 chars), every subsequent item shifts right by 4 characters, causing "
        "the entire right portion of the bar to visually jitter. HYPERSTATUS solves this with a strict "
        "bipartite layout: all variable-width items are left-justified, all fixed-width items are "
        "right-justified, and the flexible spacer between them absorbs all size changes. This means "
        "that the context percentage, token count, cost, and duration always appear at exactly the "
        "same horizontal position regardless of what model, branch, or path is displayed.",
        styles['BodyText2']
    ))
    
    jitter_diagram = """
    BEFORE (naive left-to-right layout - items jitter):
    [c-sonnet-4] | my-project | main | [23.6%] | [$0.06] | [15m]
    [c-opus-4-xhigh] | my-project | main | [23.6%] | [$0.06] | [15m]
                              ^^^^^^^^ shifted right by 4 chars ^^^^^^^^
    
    AFTER (HYPERSTATUS bipartite layout - no jitter):
    [c-sonnet-4] | my-project | main |     [23.6%] | [$0.06] | [15m]
    [c-opus-4-xhigh] | my-project | main | [23.6%] | [$0.06] | [15m]
                                      ^^^^^ spacer absorbs change ^^^^^
    """
    story.append(Paragraph(jitter_diagram.replace("\n", "<br/>").replace(" ", "&nbsp;"), styles['CodeBlock']))
    
    # 3.5 Separator and Border Design
    story.append(Paragraph("3.5 Separator and Border Design", styles['H2']))
    story.append(Paragraph(
        "HYPERSTATUS uses a layered separator system that balances information density with visual "
        "clarity. The primary separators between major segments use the Powerline right arrow "
        "(U+E0B0) with alternating background colors, creating the characteristic Powerline look. "
        "Within segments, thin vertical bars (U+E0B1 or pipe character) separate individual metrics. "
        "The outer border of the status bar uses rounded corners (4px radius) with a subtle "
        "1px border in a muted color from the palette. This approach avoids the cluttered look of "
        "heavy borders while still providing clear visual containment for the status bar as a whole.",
        styles['BodyText2']
    ))
    
    # ===========================================================================
    #  SECTION 4: AGENT-SPECIFIC DESIGNS
    # ===========================================================================
    story.append(Paragraph("4. Agent-Specific Status Bar Designs", styles['H1']))
    story.append(Paragraph(
        "Each agent has a different configuration mechanism, data pipeline, and rendering approach. "
        "This section provides the complete design specification and terminal output format for each "
        "agent, along with installation instructions specific to that agent's configuration system.",
        styles['BodyText2']
    ))
    
    # 4.1 Claude Code
    story.append(Paragraph("4.1 Claude Code Status Bar", styles['H2']))
    story.append(Paragraph(
        "Claude Code provides the richest data pipeline of any agent: a complete JSON object is "
        "piped to a user-defined shell script on stdin, containing model info, workspace details, "
        "cost tracking, context window metrics, rate limits, session info, PR state, worktree data, "
        "and more. This makes Claude Code the primary platform for the most feature-rich status bar "
        "implementation. The HYPERSTATUS Claude Code configuration uses a shell script at "
        "~/.claude/statusline.sh that parses the JSON input and renders a two-line Powerline bar "
        "when context exceeds 50%, or a single compact line when context is below 50%.",
        styles['BodyText2']
    ))
    
    claude_mockup = """
    Line 1 (always shown):
    󰜖 c-sonnet-4 |  my-project | 󰐘 main | +42/-7 |  ▼12.4K
       |          |              |          |        |
       model     project        branch    lines    compression
                                             
    ......... spacer absorbs variable-width changes .........
                                             
     [████░░░░] 23.6% |  49.3K/200K |  97% |  $0.06 |  45t/s |  5h 23% |  7d 8% |  15m | ▲ | ✦
       context pct      tokens        cache   cost     speed    rate-limits  duration  effort  think
    
    Line 2 (shown when context > 50%):
     [CONTEXT: 47.2K in / 200K max | Remaining: 76.4% | Output: 2.1K | Cache R: 45.8K / Cache W: 1.4K]
    """
    story.append(Paragraph(claude_mockup.replace("\n", "<br/>").replace(" ", "&nbsp;"), styles['CodeBlock']))
    
    story.append(Paragraph(
        "<b>Configuration path:</b> ~/.claude/settings.json (statusLine key)<br/>"
        "<b>Script path:</b> ~/.claude/statusline.sh (must be executable)<br/>"
        "<b>Data source:</b> JSON on stdin (complete schema with 30+ fields)<br/>"
        "<b>Refresh:</b> Event-driven after each assistant message + optional 3s interval",
        styles['BodyText2']
    ))
    
    # 4.2 Codex CLI
    story.append(Paragraph("4.2 Codex CLI Status Bar", styles['H2']))
    story.append(Paragraph(
        "Codex CLI has the most constrained status bar system of the four agents. It only supports "
        "a fixed enum of built-in items arranged in a single line, with no shell script customization. "
        "The HYPERSTATUS Codex configuration maximizes the available built-in items by ordering them "
        "to approximate the left-variable / right-fixed layout pattern. Since the items are built-in, "
        "they handle their own formatting and width internally. The configuration is specified in "
        "TOML format in ~/.codex/config.toml under the [tui] section. Community issues (#17827, #16921) "
        "are actively requesting Claude Code-style shell script support, which would enable the full "
        "HYPERSTATUS feature set in future Codex versions.",
        styles['BodyText2']
    ))
    
    codex_mockup = """
    Codex CLI built-in status bar (single line, limited customization):
    
    [o4-mini+reasoning] | [/home/chetaz/project] | [main] | [██░░ 23%] | [77%] | [200K] | [49.3K] | [2.1K] | [5h:23%] | [7d:8%]
      model+effort        directory              branch    ctx-used   remain   size    tokens   output    5h-limit   7d-limit
    
    Note: Codex does not support shell scripts, Nerd Font icons, or custom colors.
    Items are displayed in the order specified in config.toml [tui].status_line array.
    """
    story.append(Paragraph(codex_mockup.replace("\n", "<br/>").replace(" ", "&nbsp;"), styles['CodeBlock']))
    
    story.append(Paragraph(
        "<b>Configuration path:</b> ~/.codex/config.toml ([tui] section)<br/>"
        "<b>Data source:</b> Internal TUI state (no external data access)<br/>"
        "<b>Limitations:</b> No custom scripts, no Nerd Fonts, no colors, single line only<br/>"
        "<b>Future:</b> Issues #17827 and #16921 request shell script support",
        styles['BodyText2']
    ))
    
    # 4.3 Hermes Agent
    story.append(Paragraph("4.3 Hermes Agent Status Bar", styles['H2']))
    story.append(Paragraph(
        "Hermes Agent's status bar is configured via YAML gateway settings with opt-in flags. "
        "It supports adaptive width modes (full at >=76 cols, compact at 52-75 cols, minimal below 52), "
        "color-coded context thresholds, and special indicators for compression count and background "
        "tasks. The HYPERSTATUS Hermes configuration extends the built-in status bar with custom "
        "Nerd Font icon mappings, compression proxy integration settings, and per-model pricing "
        "for accurate cost calculation. Hermes uniquely supports a YOLO mode badge that displays "
        "a warning indicator when HERMES_YOLO_MODE is enabled, providing immediate visual feedback "
        "about the current permission level.",
        styles['BodyText2']
    ))
    
    hermes_mockup = """
    Full layout (>= 76 columns):
    ⚕ claude-sonnet-4-20250514 |  [████░░░░] 6% | 12.4K/200K |  $0.06 |  15m |  ▼12.4K | ⚠ YOLO
      model                       context bar      tokens       cost     dur    compress   permission
    
    Compact layout (52-75 columns):
    ⚕ c-sonnet-4 |  [████░░] 6% |  $0.06 |  15m
    
    Minimal layout (< 52 columns):
    ⚕ c-sonnet-4 |  15m |  ⚠ Y
    """
    story.append(Paragraph(hermes_mockup.replace("\n", "<br/>").replace(" ", "&nbsp;"), styles['CodeBlock']))
    
    story.append(Paragraph(
        "<b>Configuration path:</b> ~/.hermes/config.yaml<br/>"
        "<b>Data source:</b> Internal gateway state dict<br/>"
        "<b>Unique features:</b> Adaptive width modes, YOLO badge, compression count indicator<br/>"
        "<b>Pricing:</b> Per-model pricing configured in YAML for accurate cost tracking",
        styles['BodyText2']
    ))
    
    # 4.4 Pi Agent
    story.append(Paragraph("4.4 Pi Agent Status Bar", styles['H2']))
    story.append(Paragraph(
        "Pi Agent takes the most extensible approach: the core has a minimal built-in status bar, "
        "but the dominant pattern is extension-based customization. The pi-powerline-footer extension "
        "(14.3K monthly downloads) is the community favorite, providing Powerlevel10k-inspired segments "
        "with full theme access. The HYPERSTATUS Pi extension is a TypeScript module that builds "
        "StatusBarSegment arrays with full control over icons, colors, background colors, minimum "
        "widths, and side placement (left vs right). This provides the most flexible rendering "
        "pipeline of any agent, as the extension can dynamically construct segments based on any "
        "available data, including metrics from external sources like headroom or RTK proxies.",
        styles['BodyText2']
    ))
    
    pi_mockup = """
    Pi Agent HYPERSTATUS extension (full TypeScript control):
    
    Left segments:                    Right segments:
    [󰜖 c-sonnet-4] [ my-project] [󰐘 main] ... [ [████░░] 23.6%] [ 49.3K/200K] [ 97%] [ $0.06] [ 45t/s] [ 5h23%] [ 15m] [ ▲] [✦]
    
    Segment rendering with Powerline arrows:
    Each segment has: icon, text, bg color, fg color, side (left/right), minWidth
    Segments are joined with Powerline U+E0B0 arrows and color transitions
    
    Extension location: ~/.pi/extensions/hyperstatus/
    """
    story.append(Paragraph(pi_mockup.replace("\n", "<br/>").replace(" ", "&nbsp;"), styles['CodeBlock']))
    
    story.append(Paragraph(
        "<b>Extension path:</b> ~/.pi/extensions/hyperstatus/<br/>"
        "<b>Data source:</b> Pi context object + custom fetch() for external metrics<br/>"
        "<b>Unique features:</b> Full TypeScript control, theme integration, live fetch for proxy data<br/>"
        "<b>Activation:</b> /reload command after installation",
        styles['BodyText2']
    ))
    
    # ===========================================================================
    #  SECTION 5: COMPRESSION PROXY INTEGRATION
    # ===========================================================================
    story.append(Paragraph("5. Compression Proxy Integration Methods", styles['H1']))
    story.append(Paragraph(
        "Beyond the metrics natively available from coding agents, HYPERSTATUS can integrate data "
        "from external compression proxies and tools. These systems sit between the agent and the "
        "LLM provider (or between the agent and the terminal), intercepting and compressing data "
        "before it enters the context window. The metrics they expose provide powerful insights "
        "into token efficiency that are not available from the agent itself.",
        styles['BodyText2']
    ))
    
    # 5.1 Headroom
    story.append(Paragraph("5.1 Headroom Prompt Compression", styles['H2']))
    story.append(Paragraph(
        "Headroom is an open-source context optimization layer that compresses everything an AI agent "
        "reads before it reaches the LLM. It uses six compression algorithms auto-routed by content "
        "type: SmartCrusher for JSON arrays (70-90% savings), AST-aware code compression (40-70%), "
        "build/test log compression (80-95%), search result compression (60-80%), plain text via "
        "ModernBERT (30-50%), and git diff compression (40-60%). Headroom also provides reversible "
        "compression (CCR) that stores originals and injects a retrieval tool for the LLM to fetch "
        "full data on demand, plus cache optimization that stabilizes prefixes for 90% cache-read "
        "discounts.",
        styles['BodyText2']
    ))
    
    headroom_data = [
        ["Metric", "Source", "Status Bar Display", "Example"],
        ["Tokens Saved", "compress() result", "IC_COMPRESS + value", "▼12.4K"],
        ["Compression Ratio", "compress() result", "Percentage or ratio", "87%"],
        ["Cache Optimization", "Prefix tracking", "Separate cache metric", "Cache+: 90%"],
        ["Retrieval Rate", "TOIN tracking", "How often LLM retrieves", "Retr: 3/12"],
        ["Cost Saved", "Derived from tokens", "Dollar savings", "↓$2.40"],
    ]
    
    ht = Table(headroom_data, colWidths=[1.1*inch, 1.2*inch, 1.4*inch, 1.1*inch])
    ht.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), C_SURFACE1),
        ('TEXTCOLOR', (0, 0), (-1, 0), white),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 8),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('GRID', (0, 0), (-1, -1), 0.5, DOC_BORDER),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [white, HexColor("#f8f9fa")]),
        ('TOPPADDING', (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
        ('LEFTPADDING', (0, 0), (-1, -1), 5),
    ]))
    story.append(ht)
    
    story.append(Spacer(1, 8))
    story.append(Paragraph(
        "<b>Integration method:</b> Run Headroom as a transparent proxy by setting "
        "ANTHROPIC_BASE_URL=http://localhost:8787/v1. The status bar script polls the proxy's "
        "/metrics endpoint every 5 seconds, or reads environment variables set by the compression-env.sh "
        "helper script. The TypeScript Pi extension uses fetch() to query the proxy directly.",
        styles['BodyText2']
    ))
    
    # 5.2 RTK
    story.append(Paragraph("5.2 RTK Terminal Compression (Rust Token Killer)", styles['H2']))
    story.append(Paragraph(
        "RTK is an open-source CLI proxy (single Rust binary, zero dependencies) that sits between "
        "AI coding agents and the terminal, compressing command outputs before they enter the context "
        "window. It uses command-specific compressors for common tools: cargo test (91.8% savings), "
        "git status (80.8%), find (78.3%), grep (49.5%), pytest, go test, git diff, git log, ls, "
        "pnpm list, tsc, eslint, prisma, docker, and kubectl. RTK works by installing a PreToolUse "
        "hook in Claude Code that rewrites Bash commands to RTK equivalents at the proxy layer. "
        "The rtk gain command provides real-time analytics showing per-command and aggregate token "
        "savings, with historical reporting across sessions.",
        styles['BodyText2']
    ))
    
    rtk_data = [
        ["Metric", "Source", "Status Bar Display", "Example"],
        ["Total Tokens Saved", "rtk gain --json", "IC_COMPRESS + value", "▼8.9M"],
        ["Compression Rate", "rtk gain", "Efficiency percentage", "89%"],
        ["Commands Compressed", "rtk gain", "Count", "3,231 cmd"],
        ["Per-Command Savings", "rtk gain --per-cmd", "Breakdown by tool", "pytest: 92%"],
        ["Historical Savings", "rtk gain --all-time", "Lifetime total", "138M tok"],
    ]
    
    rt = Table(rtk_data, colWidths=[1.3*inch, 1.1*inch, 1.4*inch, 1.0*inch])
    rt.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), C_SURFACE1),
        ('TEXTCOLOR', (0, 0), (-1, 0), white),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 8),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('GRID', (0, 0), (-1, -1), 0.5, DOC_BORDER),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [white, HexColor("#f8f9fa")]),
        ('TOPPADDING', (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
        ('LEFTPADDING', (0, 0), (-1, -1), 5),
    ]))
    story.append(rt)
    
    story.append(Spacer(1, 8))
    story.append(Paragraph(
        "<b>Integration method:</b> Install RTK globally with 'rtk init --global', which sets up "
        "the PreToolUse hook. The status bar reads /tmp/rtk-metrics.json (written by a background "
        "polling process in compression-env.sh) or the RTK_TOKENS_SAVED environment variable. "
        "The Claude Code shell script sources this file on each refresh.",
        styles['BodyText2']
    ))
    
    # 5.3 Inline Proxy Architecture
    story.append(Paragraph("5.3 Inline LLM Proxy Architecture", styles['H2']))
    story.append(Paragraph(
        "An inline LLM proxy (such as LiteLLM, Portkey, or Kong AI Gateway) acts as centralized "
        "middleware between the coding agent and model providers. By routing all API traffic through "
        "a local proxy endpoint (set via ANTHROPIC_BASE_URL or OPENAI_BASE_URL), the proxy can "
        "intercept every request and response, providing observability data that is not available "
        "from the agent itself. This includes per-request latency breakdowns, cache hit rates from "
        "the provider side, cost attribution by user/team/key, and model routing decisions. The "
        "proxy exposes metrics via a local HTTP endpoint (e.g., http://localhost:4000/metrics) "
        "that the status bar script can poll on its refresh interval.",
        styles['BodyText2']
    ))
    
    proxy_data = [
        ["Proxy", "Metrics Available", "Endpoint", "Integration"],
        ["LiteLLM", "Per-request tokens, cost, latency,\nmodel, status, spend by key", "localhost:4000/metrics\n(Prometheus format)", "ANTHROPIC_BASE_URL\n=http://localhost:4000"],
        ["Headroom", "Tokens saved, compression ratio,\ncache optimization, retrieval rate", "localhost:8787/metrics\n(JSON)", "ANTHROPIC_BASE_URL\n=http://localhost:8787/v1"],
        ["Kong AI GW", "Request count, latency, tokens\nper route/consumer, cost", "Prometheus metrics\n(AI-specific)", "Route via Kong\nproxy port"],
        ["RTK", "CLI output compression, per-command\nsavings, aggregate efficiency", "Local JSON file\n(/tmp/rtk-metrics.json)", "PreToolUse hook\n(rtk init --global)"],
    ]
    
    pt = Table(proxy_data, colWidths=[0.9*inch, 1.8*inch, 1.4*inch, 1.3*inch])
    pt.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), C_SURFACE1),
        ('TEXTCOLOR', (0, 0), (-1, 0), white),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 7.5),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('GRID', (0, 0), (-1, -1), 0.5, DOC_BORDER),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [white, HexColor("#f8f9fa")]),
        ('TOPPADDING', (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
        ('LEFTPADDING', (0, 0), (-1, -1), 5),
    ]))
    story.append(pt)
    
    # 5.4 Recommended Architecture
    story.append(Paragraph("5.4 Recommended Integration Architecture", styles['H2']))
    story.append(Paragraph(
        "The optimal architecture chains multiple compression and proxy layers, with each layer "
        "contributing metrics to the status bar. RTK handles CLI output compression at the terminal "
        "layer via PreToolUse hooks, Headroom handles context-level compression at the API layer "
        "via transparent proxying, and LiteLLM provides unified observability across all providers. "
        "The status bar script aggregates data from all three sources, displaying the combined "
        "savings in a single compression segment. This architecture is compatible with all four "
        "target agents, though the specific data pipeline varies (shell script for Claude Code, "
        "TypeScript extension for Pi, YAML configuration for Hermes, and limited to built-in "
        "items for Codex).",
        styles['BodyText2']
    ))
    
    arch_diagram = """
    CODING AGENT (Claude Code / Codex / Hermes / Pi)
        |
        +-- PreToolUse Hook --> RTK (CLI output compression)
        |                        +-- Reports: tokens_saved, compression_rate per command
        |
        +-- API Proxy --> Headroom Proxy (context compression) --> LLM Provider
        |                  +-- Reports: tokens_saved, compression_ratio, cache_optimization
        |
        +-- API Response --> Token Tracker (parses usage fields)
        |                    +-- Reports: input_tokens, output_tokens, cache_creation, cache_read
        |
        +-- All Metrics --> STATUS BAR RENDERER
                             +-- Context: 47K/200K (23.6%)
                             +-- Compressed: -12.4K tokens (87%)
                             +-- Cache: 97.5% hit rate
                             +-- Session cost: $0.42
                             +-- Model: sonnet-4
    """
    story.append(Paragraph(arch_diagram.replace("\n", "<br/>").replace(" ", "&nbsp;"), styles['CodeBlock']))
    
    # ===========================================================================
    #  SECTION 6: INSTALLATION AND SETUP
    # ===========================================================================
    story.append(Paragraph("6. Installation and Setup", styles['H1']))
    story.append(Paragraph(
        "HYPERSTATUS includes an automated setup script that handles agent detection, configuration "
        "backup, installation, and verification. The script supports installing for specific agents "
        "or all detected agents, with automatic backup of existing configurations before any changes "
        "are made. It also provides a compression proxy setup command that configures RTK and "
        "Headroom integration, and a status command that shows the current installation state.",
        styles['BodyText2']
    ))
    
    # Default paths
    story.append(Paragraph("6.1 Default Paths and Configuration", styles['H2']))
    
    paths_data = [
        ["Agent", "Config File", "Status Bar File", "Data Source"],
        ["Claude Code", "~/.claude/settings.json", "~/.claude/statusline.sh", "JSON on stdin"],
        ["Codex CLI", "~/.codex/config.toml", "(built-in items)", "Internal TUI state"],
        ["Hermes", "~/.hermes/config.yaml", "(built-in + config)", "Internal gateway state"],
        ["Pi Agent", "~/.pi/extensions/hyperstatus/", "index.ts + powerline-config.ts", "Context object"],
        ["Setup Script", "~/statusbar/scripts/setup.sh", "", ""],
        ["Backups", "~/statusbar/backups/YYYYMMDD_HHMMSS/", "", ""],
        ["Compression Env", "~/statusbar/compression-env.sh", "", ""],
    ]
    
    pat = Table(paths_data, colWidths=[1.0*inch, 1.7*inch, 1.8*inch, 1.2*inch])
    pat.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), C_SURFACE1),
        ('TEXTCOLOR', (0, 0), (-1, 0), white),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 7.5),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('GRID', (0, 0), (-1, -1), 0.5, DOC_BORDER),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [white, HexColor("#f8f9fa")]),
        ('TOPPADDING', (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
        ('LEFTPADDING', (0, 0), (-1, -1), 5),
    ]))
    story.append(pat)
    
    # 6.2 Setup Script Usage
    story.append(Paragraph("6.2 Setup Script Usage", styles['H2']))
    
    usage_text = """
    # Install for all detected agents (with automatic backup)
    ./setup.sh install all
    
    # Install for a specific agent
    ./setup.sh install claude
    ./setup.sh install codex
    ./setup.sh install hermes
    ./setup.sh install pi
    
    # Backup current configurations
    ./setup.sh backup all
    
    # Restore from a specific backup
    ./setup.sh restore all /path/to/backup
    
    # Set up compression proxy integration
    ./setup.sh compress
    
    # Check installation status
    ./setup.sh status
    
    # Detect installed agents
    ./setup.sh detect
    """
    story.append(Paragraph(usage_text.replace("\n", "<br/>"), styles['CodeBlock']))
    
    # 6.3 Compression Environment
    story.append(Paragraph("6.3 Compression Environment Setup", styles['H2']))
    story.append(Paragraph(
        "The compression-env.sh helper script configures environment variables and starts background "
        "processes for compression proxy integration. Source this file before launching your coding "
        "agent to enable metrics collection from Headroom and RTK. The script accepts a mode argument "
        "to select which compression systems to activate: 'headroom' sets the API base URL to route "
        "through the Headroom proxy, 'rtk' starts a background process that polls RTK gain metrics, "
        "and 'both' enables both systems simultaneously. The status bar scripts read these environment "
        "variables and metrics files on each refresh cycle to display compression savings alongside "
        "the native agent metrics.",
        styles['BodyText2']
    ))
    
    compress_usage = """
    # Enable Headroom proxy integration
    source ./compression-env.sh headroom
    
    # Enable RTK metrics polling
    source ./compression-env.sh rtk
    
    # Enable both
    source ./compression-env.sh both
    
    # Then start your agent CLI normally
    claude  # or: codex, hermes, pi
    """
    story.append(Paragraph(compress_usage.replace("\n", "<br/>"), styles['CodeBlock']))
    
    # ===========================================================================
    #  SECTION 7: CURRENT STYLISTIC TRENDS (JUNE 2026)
    # ===========================================================================
    story.append(Paragraph("7. Current Stylistic Trends (June 2026)", styles['H1']))
    story.append(Paragraph(
        "The coding agent CLI space is rapidly converging on a set of design patterns that define "
        "what the community considers the 'sickest' status bar configurations. These trends are "
        "grounded in the most popular community tools and configurations as of June 2026.",
        styles['BodyText2']
    ))
    
    trend_items = [
        ("<b>Powerline Segments:</b> The dominant visual pattern. Colored background segments with "
         "arrow/chevron separators (U+E0B0-U+E0B3). Both ccstatusline (Claude Code, 10.1K+ GitHub "
         "stars) and pi-powerline-footer (Pi, 14.3K/mo downloads) use this approach. Powerline "
         "provides the most visually distinctive and information-dense layout possible in a single "
         "terminal line, with color transitions between segments creating natural visual grouping."),
        
        ("<b>Context Threshold Coloring:</b> Universally adopted as the most important visual signal. "
         "The four-tier green/yellow/orange/red system is now standard across all major tools. "
         "The community considers any status bar without color-coded context thresholds to be "
         "incomplete. Some advanced implementations add a 60% 'quality degradation' threshold "
         "that shifts the bar to a distinct intermediate color as a performance warning."),
        
        ("<b>Multi-line Layouts:</b> Claude Code's support for arbitrary multi-line status bars has "
         "sparked a trend toward two-line configurations: a primary line with the most critical "
         "metrics, and a secondary context detail line that appears when context exceeds 50%. "
         "This approach avoids overwhelming users with data during low-activity sessions while "
         "providing full detail when it matters most."),
        
        ("<b>Nerd Font Icons:</b> Increasingly standard for visual anchoring. The most popular "
         "configs use icons for model identification, context visualization, git status, and cost "
         "tracking. The community has largely settled on a common icon vocabulary (model = U+E716, "
         "branch = U+F418, cost = U+F155, etc.) that provides instant recognition without reading."),
        
        ("<b>Command-Backed Customization:</b> Claude Code's shell script approach is the gold "
         "standard. The community强烈 demands this for Codex (issues #17827, #16921) and Hermes. "
         "The ability to pipe arbitrary data into the status bar via shell scripts is considered "
         "essential for power users, enabling integration with any external tool or data source."),
        
        ("<b>Cost Awareness:</b> As API pricing awareness grows, cost tracking has become a "
         "must-have feature. Tools like ccusage provide historical tracking across sessions, and "
         "status bars that display running cost totals are now expected rather than optional. "
         "Per-model pricing configuration (as in the Hermes YAML) enables accurate cost estimates."),
        
        ("<b>Adaptive Width Modes:</b> Hermes's three-tier adaptive layout (full/compact/minimal) "
         "based on terminal width is gaining traction. Users who work in split terminal panes "
         "or tmux windows need status bars that gracefully degrade rather than truncating. The "
         "community considers hard truncation without adaptation to be a design failure."),
        
        ("<b>Cache Hit Rate Display:</b> With Anthropic's aggressive caching and 90% cache-read "
         "discounts, showing cache hit rates has become valuable for understanding both cost "
         "efficiency and context reuse patterns. High cache rates indicate well-structured "
         "conversations that are cheaper to maintain."),
    ]
    
    for item in trend_items:
        story.append(Paragraph(item, styles['BodyText2']))
    
    # ===========================================================================
    #  SECTION 8: FILE MANIFEST
    # ===========================================================================
    story.append(Paragraph("8. Deliverable File Manifest", styles['H1']))
    story.append(Paragraph(
        "The HYPERSTATUS v2.0 deliverable includes all scripts, configurations, and documentation "
        "needed to install and use the status bar across all four target agents. Files are organized "
        "by agent with a shared scripts directory for the setup tooling.",
        styles['BodyText2']
    ))
    
    file_data = [
        ["File", "Purpose", "Target Agent"],
        ["claude-code/statusline.sh", "Powerline status bar shell script", "Claude Code"],
        ["claude-code/settings.json", "Status line configuration fragment", "Claude Code"],
        ["codex/config.toml", "TOML configuration with status_line items", "Codex CLI"],
        ["hermes/config.yaml", "YAML gateway config with status bar + pricing", "Hermes Agent"],
        ["pi/hyperstatus-extension.ts", "TypeScript status bar extension module", "Pi Agent"],
        ["pi/powerline-config.ts", "Powerline separator and adaptive layout config", "Pi Agent"],
        ["scripts/setup.sh", "Universal install/backup/restore/detect script", "All agents"],
        ["compression-env.sh", "Environment helper for Headroom/RTK integration", "All agents"],
        ["HYPERSTATUS_v2_Design_Document.pdf", "This design document", "Reference"],
    ]
    
    ft = Table(file_data, colWidths=[2.2*inch, 2.4*inch, 1.2*inch])
    ft.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), C_SURFACE1),
        ('TEXTCOLOR', (0, 0), (-1, 0), white),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 8),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('GRID', (0, 0), (-1, -1), 0.5, DOC_BORDER),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [white, HexColor("#f8f9fa")]),
        ('TOPPADDING', (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
        ('LEFTPADDING', (0, 0), (-1, -1), 5),
        ('FONTNAME', (0, 1), (0, -1), 'Courier'),
    ]))
    story.append(ft)
    
    # Build the document
    doc.build(story, onFirstPage=page_template, onLaterPages=page_template)
    print(f"PDF generated: {output_path}")
    return output_path


if __name__ == "__main__":
    build_document()
