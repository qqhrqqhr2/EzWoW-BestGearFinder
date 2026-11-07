#!/usr/bin/env python3
"""Draws the README mock-ups of EzWoW - Best Gear Finder (docs/images/ui_*.png, settings_*.png).

The gear window, an item tooltip and the settings window are rebuilt from the sizes,
coordinates, colours and strings in the addon code (UI/MainWindow.lua, UI/OptionsWindow.lua,
Core/Locales.lua, Core/Init.lua defaults), in game pixels x scale. Icons are simplified
drawings; items and scores are examples.

usage: python scripts/make_readme_images.py .
Renders with a local headless Chrome (set CHROME=<path> if it is not found).
"""
import base64
import html
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PAGE_W = 1600

# ---------------------------------------------------------------------------
# Small readers for the Lua code
# ---------------------------------------------------------------------------


def read(root, rel):
    return (root / rel).read_text(encoding="utf-8")


def find_file(root, *names):
    """First existing file of names (case-insensitive on every system)."""
    for name in names:
        p = root / name
        if p.exists():
            return p
        parent = p.parent
        if parent.exists():
            for q in parent.iterdir():
                if q.name.lower() == p.name.lower():
                    return q
    raise FileNotFoundError(names)


def rgb_list(body):
    return [float(v) for v in body.split(",") if v.strip()]


def lua_table(src, start_pattern):
    """Text of the Lua table that starts at start_pattern (balanced braces)."""
    m = re.search(start_pattern, src)
    if not m:
        raise ValueError(start_pattern)
    i = src.index("{", m.start())
    depth = 0
    for j in range(i, len(src)):
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                return src[i + 1:j]
    raise ValueError("unbalanced " + start_pattern)


def lua_strings(block):
    """key = "value" pairs of a Lua table body (plain keys and ["keys"])."""
    out = {}
    for k1, k2, v in re.findall(r'(?:^|[\s,{])(?:(\w+)|\["((?:[^"\\]|\\.)*)"\])\s*=\s*"((?:[^"\\]|\\.)*)"', block, re.M):
        out[k1 or k2] = unlua(v)
    return out


def unlua(v):
    return v.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")


def toc_version(root):
    for p in root.glob("*.toc"):
        m = re.search(r"^## Version:\s*(\S+)", p.read_text(encoding="utf-8"), re.M)
        if m:
            return m.group(1)
    return ""


def css(c, alpha=None, mul=1.0):
    r, g, b = (round(min(1, v * mul) * 255) for v in c[:3])
    a = alpha if alpha is not None else (c[3] if len(c) > 3 else 1)
    return f"rgba({r},{g},{b},{a:.2f})"


def hexc(c):
    return "#%02x%02x%02x" % tuple(round(v * 255) for v in c[:3])


def esc(s):
    return html.escape(str(s), quote=False)


def wow(s):
    """Game text -> HTML: |cffRRGGBB..|r colours, |n / \\n line breaks, icons dropped."""
    s = esc(s)
    s = re.sub(r"\|T[^|]*\|t", "", s)
    s = re.sub(r"\|A[^|]*\|a", "", s)
    out, depth = [], 0
    pos = 0
    for m in re.finditer(r"\|c[0-9a-fA-F]{2}([0-9a-fA-F]{6})|\|r", s):
        out.append(s[pos:m.start()])
        if m.group(0) == "|r":
            if depth:
                out.append("</span>")
                depth -= 1
        else:
            out.append(f'<span style="color:#{m.group(1)}">')
            depth += 1
        pos = m.end()
    out.append(s[pos:])
    out.append("</span>" * depth)
    return "".join(out).replace("|n", "<br>").replace("\n", "<br>")


# ---------------------------------------------------------------------------
# Page parts (game px x S -> page px)
# ---------------------------------------------------------------------------
S = 1.3


def px(v):
    return f"{v * S:.2f}px"


OUTLINE = "text-shadow:-1px 0 #000,1px 0 #000,0 -1px #000,0 1px #000,0 0 2px #000;"
SHADOW = "text-shadow:1px 1px 0 #000,0 0 2px rgba(0,0,0,.8);"

# client colours used by several mock-ups
QUALITY = {0: "#9d9d9d", 1: "#ffffff", 2: "#1eff00", 3: "#0070dd", 4: "#a335ee", 5: "#ff8000"}
CLASS_HEX = {"WARRIOR": "#c69b6d", "PALADIN": "#f48cba", "HUNTER": "#aad372", "ROGUE": "#fff468", "PRIEST": "#ffffff",
             "SHAMAN": "#0070dd", "MAGE": "#3fc7eb", "WARLOCK": "#8788ee", "DRUID": "#ff7c0a"}
GOLD = "#ffd100"

THEME = {
    "bg": (0.071, 0.094, 0.122, 0.97), "bgSub": (0.114, 0.157, 0.192, 0.96), "border": (0.204, 0.298, 0.357, 1),
    "text": (0.929, 0.957, 0.969, 1), "muted": (0.655, 0.725, 0.773, 1), "accent": (0.5, 0.8, 0.9, 1),
}


def page_css(call):
    return f"""
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
html, body {{ width: {PAGE_W}px; overflow: hidden; }}
body {{ background: #0e141a; font-family: 'Noto Sans KR','Malgun Gothic',sans-serif; color: #edf4f7; position: relative; }}
.sky {{ position: absolute; left: 0; top: 0; width: {PAGE_W}px; height: 100%;
  background: radial-gradient(ellipse at 25% 0%, #1d2b38 0%, #151f28 45%, #10171d 75%, #0c1115 100%); }}
.hills {{ position: absolute; left: 0; bottom: 0; width: {PAGE_W}px; height: 260px; }}
.page {{ position: relative; padding: 34px 50px 0; }}
h1 {{ color: {call}; font-size: 40px; font-weight: 700; letter-spacing: .3px; display: flex; align-items: center; gap: 14px; }}
h1 .badge {{ font-size: 15px; background: {call}; color: #10161c; padding: 2px 9px; border-radius: 5px; }}
.lead {{ color: #d5dde2; font-size: 19px; margin-top: 6px; }}
.abs {{ position: absolute; }}
.t {{ position: absolute; white-space: nowrap; line-height: 1.15; }}
.call {{ position: absolute; width: 30px; height: 30px; border-radius: 50%; background: {call}; color: #10161c; font-weight: 700;
  font-size: 16px; display: flex; align-items: center; justify-content: center; border: 2px solid #10161c; box-shadow: 0 0 0 2px {call}55; z-index: 60; }}
.notes {{ position: absolute; }}
.note {{ display: flex; gap: 12px; margin-bottom: 11px; font-size: 16px; line-height: 1.5; color: #dfe6ea; }}
.note .n {{ flex: none; width: 28px; height: 28px; border-radius: 50%; background: {call}; color: #10161c; font-weight: 700;
  font-size: 15px; display: flex; align-items: center; justify-content: center; }}
.note b {{ color: #fff; }}
.foot {{ position: absolute; color: #7d8d98; font-size: 13.5px; line-height: 1.5; }}
.fit {{ display: inline-block; white-space: nowrap; }}
.tip {{ position: absolute; z-index: 30; }}
.tip .row {{ display: flex; justify-content: space-between; gap: 18px; white-space: nowrap; }}
"""


HILLS = ('<svg class="hills" viewBox="0 0 1600 260" preserveAspectRatio="none">'
         '<path d="M0 150 C 220 70 420 90 640 140 C 860 190 1060 60 1300 80 C 1440 92 1540 120 1600 130 V260 H0 Z" fill="#141c23" opacity=".9"/>'
         '<path d="M0 210 C 260 160 520 170 800 205 C 1080 240 1340 170 1600 190 V260 H0 Z" fill="#0b1014"/></svg>')

FIT_JS = """
<script>
document.querySelectorAll('[data-fit]').forEach(function (e) {
  var max = parseFloat(e.dataset.fit), min = parseFloat(e.dataset.min || 8);
  var fs = parseFloat(getComputedStyle(e).fontSize);
  while (e.scrollWidth > max && fs > min) { fs -= 0.25; e.style.fontSize = fs + 'px'; }
  if (e.scrollWidth > max) { e.style.maxWidth = max + 'px'; e.style.overflow = 'hidden'; e.style.textOverflow = 'ellipsis'; }
});
// place the footnote under the lowest element, then record the page height
var bottom = 0;
document.querySelectorAll('.page *, body > .abs, body > .notes, body > .call, body > .tip').forEach(function (e) {
  var r = e.getBoundingClientRect(); if (r.height > 0 && r.bottom > bottom) bottom = r.bottom;
});
var foot = document.querySelector('.foot');
if (foot) { foot.style.top = (bottom + 26) + 'px'; bottom = foot.getBoundingClientRect().bottom; }
document.body.setAttribute('data-h', Math.ceil(bottom + 34));
document.body.style.height = Math.ceil(bottom + 34) + 'px';
</script>
"""


def box(x, y, w, h, style="", inner=""):
    return f'<div class="abs" style="left:{px(x)};top:{px(y)};width:{px(w)};height:{px(h)};{style}">{inner}</div>'


def text(x, y, s, size, color="#fff", anchor="left", style="", fit=None, shadow=SHADOW):
    """Font string; y is the vertical centre (game px)."""
    tr = {"left": "translate(0,-50%)", "right": "translate(-100%,-50%)", "center": "translate(-50%,-50%)"}[anchor]
    inner = s if fit is None else f'<span class="fit" data-fit="{fit * S:.1f}" data-min="{size * 0.7 * S:.1f}">{s}</span>'
    return (f'<div class="t" style="left:{px(x)};top:{px(y)};font-size:{px(size)};color:{color};'
            f'transform:{tr};{shadow}{style}">{inner}</div>')


def text_top(x, y, s, size, color="#fff", width=None, style="", shadow=SHADOW):
    """Font string anchored at its top-left (TOPLEFT points)."""
    w = f"width:{px(width)};white-space:normal;" if width else ""
    return (f'<div class="t" style="left:{px(x)};top:{px(y)};font-size:{px(size)};color:{color};line-height:1.3;'
            f'{w}{shadow}{style}">{s}</div>')


class Window:
    """A flat EzWoW style window: header strip, accent line, icon, title, sub title, close box."""

    def __init__(self, th, w, h, title, sub="", icon=None, header=56, close=22, close_off=10, title_color=None):
        self.th, self.w, self.h = th, w, h
        self.p = []
        acc = css(th["accent"], 1)
        if header:
            self.p.append(box(1, 1, w - 2, header, f"background:{css(th['bgSub'], .98)}"))
            self.p.append(box(1, header - 1, w - 2, 2, f"background:{acc}"))
            if icon:
                self.p.append(f'<img class="abs" src="{icon}" style="left:{px(14)};top:{px(14)};width:{px(28)};height:{px(28)}">')
            self.p.append(text_top(48, 10, esc(title), 16, title_color or acc))
            if sub:
                self.p.append(text_top(48, 32, sub, 10, css(th["muted"]), width=w - 120))
            if close:
                self.button(w - 1 - close_off - close, close_off + 1, close, close, "X", size=12)

    def add(self, s):
        self.p.append(s)

    def section(self, x, y, label, width=None, line_dy=18):
        acc = css(self.th["accent"], 1)
        self.p.append(text_top(x, y, label, 13, acc))
        w = width if width else self.w - x - 20
        self.p.append(box(x, y + line_dy, w, 1, f"background:{css(self.th['border'], .85)}"))

    def check(self, x, y, label, on, size=24, label_w=180, font=12, disabled=False, color=None):
        mark = (f'<div class="t" style="left:{px(size * 0.1)};top:{px(-size * 0.12)};font-size:{px(size * 0.9)};color:#ffd200;'
                f'text-shadow:0 0 1px #000,1px 1px 0 #6b4a00">&#10004;</div>') if on else ""
        b = size * 0.72
        o = (size - b) / 2
        alpha = ";opacity:.55" if disabled else ""
        self.p.append(box(x + o, y + o, b, b, f"border:1px solid #6d6a5d;background:#191919;border-radius:2px;overflow:visible{alpha}", mark))
        col = color or css(self.th["muted"] if disabled else self.th["text"])
        self.p.append(text(x + size + 4, y + size / 2, label, font, col, fit=label_w))

    def radio(self, x, y, label, on, size=22, label_w=150, font=12):
        dot = box(size * .32, size * .32, size * .36, size * .36, "border-radius:50%;background:#ffd200;box-shadow:0 0 3px #ffb000") if on else ""
        self.p.append(box(x + 2, y + 2, size - 4, size - 4, "border:1px solid #7a7a7a;border-radius:50%;background:#151515", dot))
        self.p.append(text(x + size + 4, y + size / 2, label, font, css(self.th["text"]), fit=label_w))

    def button(self, x, y, w, h, label, accent=False, size=12, color=None, bg=None, border=None):
        th = self.th
        bgc = bg or css(th["bgSub"])
        bd = border or (css(th["accent"]) if accent else css(th["border"]))
        col = color or (css(th["accent"]) if accent else css(th["text"]))
        self.p.append(box(x, y, w, h, f"background:{bgc};border:1px solid {bd};display:flex;align-items:center;justify-content:center",
                          f'<span class="fit" data-fit="{(w - 10) * S:.1f}" data-min="{size * .7 * S:.1f}" '
                          f'style="font-size:{px(size)};color:{col};{SHADOW}">{label}</span>'))

    def stepper(self, x, y, label, value, minus_dx, plus_dx, bw=25, bh=25, label_dy=6, label_w=84, value_color=None, font=12):
        self.p.append(text_top(x, y + label_dy, f'<span class="fit" data-fit="{label_w * S:.1f}" data-min="{9 * S:.1f}">{label}</span>',
                               font, css(self.th["text"])))
        self.button(x + minus_dx, y, bw, bh, "-", size=14)
        self.button(x + plus_dx, y, bw, bh, "+", size=14)
        cx = x + minus_dx + bw / 2 + (plus_dx - minus_dx) / 2
        self.p.append(text(cx, y + bh / 2, value, font, value_color or css(self.th["text"]), anchor="center"))

    def html(self, ox, oy, extra_style=""):
        th = self.th
        return (f'<div class="abs" style="left:{ox}px;top:{oy}px;width:{px(self.w)};height:{px(self.h)};background:{css(th["bg"])};'
                f'border:1px solid {css(th["border"])};box-shadow:0 10px 40px rgba(0,0,0,.45);{extra_style}">' + "".join(self.p) + "</div>")


def tooltip(x, y, lines, border="#344c5b", width=None, pad=10, bg="rgba(18,24,31,.95)", gloss=True, bar=None, font=12,
            title_size=14, left_pad=0, z=30, extra=""):
    """A tooltip card at page px (x, y). lines: list of str | (left, right) | ("gap",); first line is the title.
    Strings are already HTML. bar: (fraction, colour, label) drawn along the bottom."""
    rows = []
    for i, ln in enumerate(lines):
        fs = title_size if i == 0 else font
        if ln == ("gap",):
            rows.append(f'<div style="height:{px(font * .7)}"></div>')
        elif isinstance(ln, tuple):
            rows.append(f'<div class="row" style="font-size:{px(fs)};line-height:1.42"><span>{ln[0]}</span><span>{ln[1]}</span></div>')
        else:
            rows.append(f'<div style="font-size:{px(fs)};line-height:1.42;white-space:nowrap">{ln}</div>')
    w = f"width:{px(width)};" if width else ""
    glo = (f'<div class="abs" style="left:0;right:0;top:0;height:{px(26)};background:linear-gradient(to bottom,rgba(255,255,255,.07),'
           f'rgba(255,255,255,0))"></div>') if gloss else ""
    bar_h = ""
    bottom_pad = pad
    if bar:
        frac, col, label = bar
        bottom_pad = pad + 10
        bar_h = (f'<div class="abs" style="left:{px(1)};right:{px(1)};bottom:{px(1)};height:{px(8)};background:rgba(0,0,0,.6)">'
                 f'<div class="abs" style="left:0;top:0;bottom:0;width:{frac * 100:.1f}%;background:{col}"></div>'
                 f'<div class="abs" style="inset:0;display:flex;align-items:center;justify-content:center;font-size:{px(7.5)};color:#fff;{OUTLINE}">{label}</div></div>')
    return (f'<div class="tip" style="left:{x:.0f}px;top:{y:.0f}px;{w}background:{bg};border:1px solid {border};'
            f'padding:{px(pad)} {px(pad)} {px(bottom_pad)} {px(pad + left_pad)};{SHADOW}z-index:{z};{extra}">'
            f'{glo}{"".join(rows)}{bar_h}</div>')


def callouts(points):
    return "".join(f'<div class="call" style="left:{x - 15:.0f}px;top:{y - 15:.0f}px">{i}</div>' for i, (x, y) in enumerate(points, 1))


def notes_html(notes, start=1):
    return "".join(f'<div class="note"><span class="n">{start + i}</span><div><b>{esc(a)}</b> — {b}</div></div>'
                   for i, (a, b) in enumerate(notes))


def notes_block(x, y, w, notes, start=1):
    return f'<div class="notes" style="left:{x:.0f}px;top:{y:.0f}px;width:{w:.0f}px">{notes_html(notes, start)}</div>'


def heading(title, lead, badge=None):
    b = f' <span class="badge">{esc(badge)}</span>' if badge else ""
    return f'<div class="page"><h1>{esc(title)}{b}</h1><div class="lead">{lead}</div></div>'


def icon_data(path):
    return "data:image/png;base64," + base64.b64encode(Path(path).read_bytes()).decode()


# simple square icon art (stands in for game icons)
ICON_ART = {
    "potion": ("#3a1418", '<path d="M40 14 H60 V34 C76 40 82 54 82 64 A32 26 0 0 1 18 64 C18 54 24 40 40 34 Z" fill="#d8323c"/><rect x="38" y="10" width="24" height="8" fill="#b08860"/>'),
    "mana": ("#121e3e", '<path d="M40 14 H60 V34 C76 40 82 54 82 64 A32 26 0 0 1 18 64 C18 54 24 40 40 34 Z" fill="#3d7cf0"/><rect x="38" y="10" width="24" height="8" fill="#b08860"/>'),
    "elixir": ("#14301e", '<path d="M44 12 H56 V40 L74 80 H26 L44 40 Z" fill="#5fd05a"/><rect x="40" y="8" width="20" height="8" fill="#b08860"/>'),
    "stone": ("#1c2a1c", '<path d="M50 12 L80 40 L62 86 H38 L20 40 Z" fill="#62e07a"/><path d="M50 12 L62 40 L50 86 L38 40 Z" fill="#a8f5b4"/>'),
    "helm": ("#2a2a30", '<path d="M18 64 C18 30 34 16 50 16 C66 16 82 30 82 64 L72 80 H28 Z" fill="#a8adb8"/><rect x="30" y="50" width="40" height="10" fill="#2a2a30"/>'),
    "glove": ("#2a2420", '<path d="M30 86 V44 L26 22 H36 L40 40 V16 H48 V40 V12 H56 V40 V16 H64 V44 L74 34 L80 40 L66 62 V86 Z" fill="#b58a5a"/>'),
    "ring": ("#2a2418", '<circle cx="50" cy="56" r="24" fill="none" stroke="#e8c050" stroke-width="10"/><path d="M42 26 L50 14 L58 26 L50 34 Z" fill="#6ad0ff"/>'),
    "sword": ("#202830", '<path d="M70 14 L84 16 L86 30 L44 72 L30 58 Z" fill="#cfd8e0"/><path d="M26 54 L46 74 L40 80 L20 60 Z" fill="#b08040"/><path d="M28 72 L18 82" stroke="#806030" stroke-width="8"/>'),
    "food": ("#3a2412", '<ellipse cx="50" cy="58" rx="30" ry="20" fill="#c87838"/><circle cx="64" cy="40" r="12" fill="#f0e0c0"/>'),
    "drink": ("#14283a", '<path d="M30 20 H70 L64 84 H36 Z" fill="#8fd0f0" opacity=".85"/><rect x="30" y="20" width="40" height="10" fill="#e0f4ff"/>'),
    "bandage": ("#2c2c2c", '<rect x="18" y="38" width="64" height="26" rx="12" fill="#e8e0d0" transform="rotate(-35 50 50)"/>'),
    "hearth": ("#1a2a3a", '<circle cx="50" cy="50" r="26" fill="#7fd0ff"/><circle cx="50" cy="50" r="12" fill="#e0f6ff"/>'),
    "pet": ("#2a2018", '<ellipse cx="50" cy="62" rx="26" ry="18" fill="#d8a060"/><circle cx="66" cy="38" r="14" fill="#d8a060"/><path d="M60 26 L62 14 L70 24 Z M72 28 L80 18 L80 32 Z" fill="#a06a30"/><circle cx="70" cy="38" r="3" fill="#201008"/>'),
    "pick": ("#2a2a2a", '<path d="M20 30 C40 14 64 14 82 30 L76 36 C62 26 42 26 26 36 Z" fill="#bcc4cc"/><rect x="46" y="28" width="8" height="58" fill="#8a6030"/>'),
    "herb": ("#1c3018", '<path d="M50 86 V40" stroke="#5a9040" stroke-width="6"/><ellipse cx="36" cy="44" rx="14" ry="8" fill="#70c050" transform="rotate(-30 36 44)"/><ellipse cx="64" cy="40" rx="14" ry="8" fill="#70c050" transform="rotate(30 64 40)"/><circle cx="50" cy="28" r="10" fill="#e070d0"/>'),
    "fire": ("#3a1a0a", '<path d="M50 12 C62 34 80 44 70 70 A22 22 0 0 1 30 70 C22 50 40 40 42 26 C48 36 50 30 50 12 Z" fill="#ff8a2a"/><path d="M50 46 C58 58 62 64 56 76 A10 10 0 0 1 42 74 C40 64 48 58 50 46 Z" fill="#ffe070"/>'),
    "holy": ("#3a3010", '<circle cx="50" cy="50" r="20" fill="#ffe680"/><path d="M50 10 V30 M50 70 V90 M10 50 H30 M70 50 H90 M22 22 L36 36 M64 64 L78 78 M22 78 L36 64 M64 36 L78 22" stroke="#ffe680" stroke-width="6"/>'),
    "shield": ("#1e2836", '<path d="M50 10 L84 22 C84 56 72 78 50 90 C28 78 16 56 16 22 Z" fill="#7aa4d8"/><path d="M50 22 L72 30 C72 54 64 70 50 78 Z" fill="#b8d4f4"/>'),
    "shadow": ("#1e1430", '<circle cx="50" cy="50" r="28" fill="#8a5ad8"/><circle cx="50" cy="50" r="14" fill="#2a1840"/>'),
    "frost": ("#14283a", '<path d="M50 12 V88 M17 31 L83 69 M17 69 L83 31" stroke="#bfe6ff" stroke-width="9" stroke-linecap="round"/>'),
    "nature": ("#203a1c", '<path d="M50 84 C20 70 18 36 50 14 C82 36 80 70 50 84 Z" fill="#7cd060"/><path d="M50 84 V30" stroke="#2a5a1c" stroke-width="5"/>'),
    "arcane": ("#2a1840", '<path d="M50 14 L58 42 L86 50 L58 58 L50 86 L42 58 L14 50 L42 42 Z" fill="#d79cff"/>'),
    "claw": ("#3a1414", '<path d="M25 80 L45 20 M45 82 L62 22 M65 84 L80 28" stroke="#ff6a5a" stroke-width="9" stroke-linecap="round"/>'),
    "bear": ("#2e2014", '<circle cx="50" cy="56" r="26" fill="#8a5a30"/><circle cx="30" cy="30" r="10" fill="#8a5a30"/><circle cx="70" cy="30" r="10" fill="#8a5a30"/><circle cx="42" cy="52" r="4" fill="#1a0a00"/><circle cx="58" cy="52" r="4" fill="#1a0a00"/>'),
    "cat": ("#3a2a1a", '<path d="M24 82 L24 34 L36 18 L44 34 L56 34 L64 18 L76 34 L76 82 Z" fill="#c9965a"/><circle cx="40" cy="50" r="5" fill="#2a1a0a"/><circle cx="60" cy="50" r="5" fill="#2a1a0a"/>'),
    "heal": ("#14301e", '<rect x="40" y="18" width="20" height="64" fill="#8cf08c"/><rect x="18" y="40" width="64" height="20" fill="#8cf08c"/>'),
    "book": ("#2a1e14", '<rect x="20" y="16" width="60" height="70" rx="4" fill="#8a4a2a"/><rect x="28" y="16" width="6" height="70" fill="#5a2a14"/><rect x="40" y="30" width="30" height="6" fill="#e8c890"/>'),
    "scroll": ("#2e2616", '<rect x="24" y="22" width="52" height="56" fill="#e8d8a8"/><rect x="18" y="16" width="64" height="10" rx="5" fill="#b89860"/><rect x="18" y="74" width="64" height="10" rx="5" fill="#b89860"/><path d="M34 40 H66 M34 52 H66 M34 64 H56" stroke="#8a6a3a" stroke-width="4"/>'),
    "flask": ("#2a1a3a", '<circle cx="50" cy="60" r="24" fill="#b070f0"/><rect x="42" y="14" width="16" height="26" fill="#b070f0"/><rect x="38" y="10" width="24" height="8" fill="#b08860"/>'),
    "thread": ("#1a2840", '<rect x="34" y="16" width="32" height="68" rx="6" fill="#d8b070"/><rect x="30" y="30" width="40" height="40" fill="#3a78d8"/>'),
    "hammer": ("#2a2a2a", '<rect x="22" y="18" width="56" height="22" rx="3" fill="#a0a8b0"/><rect x="45" y="40" width="10" height="46" fill="#8a6030"/>'),
    "fish": ("#10304a", '<path d="M14 50 C30 26 62 26 74 50 C62 74 30 74 14 50 Z" fill="#7fb8e0"/><path d="M74 50 L90 34 V66 Z" fill="#7fb8e0"/><circle cx="30" cy="46" r="4" fill="#0a1a2a"/>'),
    "gear": ("#26303a", '<circle cx="50" cy="50" r="22" fill="none" stroke="#c0c8d0" stroke-width="12" stroke-dasharray="9 6"/><circle cx="50" cy="50" r="10" fill="#c0c8d0"/>'),
    "bolt": ("#24204a", '<path d="M56 10 L26 56 H48 L40 90 L76 40 H54 Z" fill="#ffe14a"/>'),
    "chest": ("#2a1e10", '<rect x="18" y="38" width="64" height="42" fill="#9a6a30"/><path d="M18 38 C18 18 82 18 82 38 Z" fill="#b8843c"/><rect x="44" y="44" width="12" height="14" fill="#e8c050"/>'),
    "arrow": ("#2a2418", '<path d="M18 82 L72 28" stroke="#c8a870" stroke-width="7"/><path d="M64 20 L84 16 L80 36 Z" fill="#c0c8d0"/><path d="M18 82 L26 66 M18 82 L34 74" stroke="#e8e0d0" stroke-width="5"/>'),
    "kick": ("#2e1c14", '<path d="M30 20 L48 20 L54 56 L80 64 L78 80 L34 80 Z" fill="#c9965a"/>'),
    "stealth": ("#1a1a24", '<circle cx="50" cy="50" r="30" fill="#4a4a6a"/><path d="M26 50 C38 34 62 34 74 50 C62 66 38 66 26 50 Z" fill="#1a1a24"/><circle cx="50" cy="50" r="8" fill="#9aa0d0"/>'),
}


def icon_svg(kind):
    bg, shape = ICON_ART[kind]
    return (f'<svg width="100%" height="100%" viewBox="0 0 100 100" preserveAspectRatio="none" style="display:block">'
            f'<defs><linearGradient id="sh_{kind}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".18"/>'
            f'<stop offset=".55" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".35"/></linearGradient></defs>'
            f'<rect width="100" height="100" fill="{bg}"/>{shape}<rect width="100" height="100" fill="url(#sh_{kind})"/></svg>')


def icon_box(x, y, size, kind, border="#000", style=""):
    return box(x, y, size, size, f"border:1px solid {border};overflow:hidden;{style}", icon_svg(kind))


# ---------------------------------------------------------------------------
# Rendering (local headless Chrome)
# ---------------------------------------------------------------------------
def find_chrome():
    cands = [os.environ.get("CHROME"), r"C:\Program Files\Google\Chrome\Application\chrome.exe",
             r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
             shutil.which("chrome"), shutil.which("google-chrome"), shutil.which("chromium")]
    for c in cands:
        if c and Path(c).exists():
            return c
    sys.exit("Chrome not found (set CHROME=<path to chrome>)")


def chrome_args(chrome, tmp):
    return [chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
            f"--user-data-dir={Path(tmp) / 'chrome_profile'}", "--virtual-time-budget=3000"]


def render(chrome, body, call, out_png, tmp):
    doc = (f'<!doctype html><html><head><meta charset="utf-8"><style>{page_css(call)}</style></head>'
           f'<body><div class="sky"></div>{HILLS}{body}{FIT_JS}</body></html>')
    page = Path(tmp) / (out_png.stem + ".html")
    page.write_text(doc, encoding="utf-8")
    # pass 1: let the page measure itself, pass 2: screenshot at that height
    dom = subprocess.run(chrome_args(chrome, tmp) + ["--window-size=1600,4000", "--dump-dom", page.as_uri()],
                         check=True, capture_output=True, timeout=120).stdout.decode("utf-8", "replace")
    m = re.search(r'data-h="(\d+)"', dom)
    height = int(m.group(1)) if m else 1200
    subprocess.run(chrome_args(chrome, tmp) + [f"--window-size={PAGE_W},{height}", f"--screenshot={out_png}", page.as_uri()],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
    return height


def run_pages(root, pages, call):
    """pages: list of (file stem, function returning page body html)."""
    out = root / "docs" / "images"
    out.mkdir(parents=True, exist_ok=True)
    chrome = find_chrome()
    tmp = tempfile.mkdtemp(prefix="ezwow_readme_")
    try:
        for stem, fn in pages:
            png = out / f"{stem}.png"
            h = render(chrome, fn(), call, png, tmp)
            print("wrote", png, h)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------------------
# EzWoW - Best Gear Finder
# ---------------------------------------------------------------------------
TITLE = "EzWoW - Best Gear Finder"


def load(root):
    ow = read(root, "UI/OptionsWindow.lua")
    mw = read(root, "UI/MainWindow.lua")
    loc = read(root, "Core/Locales.lua")
    init = read(root, "Core/Init.lua")
    th = {k: rgb_list(v) for k, v in re.findall(r"(\w+)\s*=\s*\{\s*([\d.,\s]+)\}", lua_table(ow, r"local Theme = \{"))}
    en = lua_strings(lua_table(loc, r"local enVal = \{"))
    for k, v in re.findall(r'^enVal\["((?:[^"\\]|\\.)*)"\] = "((?:[^"\\]|\\.)*)"', loc, re.M):
        en[unlua(k)] = unlua(v)
    dflt = {}
    for k, v in re.findall(r"(\w+) = (true|false|\d+(?:\.\d+)?)", lua_table(init, r"local DEFAULTS = \{")):
        dflt.setdefault(k, v)
    qual = [int(q) for q in re.findall(r"\[(\d)\] = true", re.search(r"qual = \{([^}]*)\}", lua_table(init, r"local DEFAULTS = \{")).group(1))]
    size = re.search(r"windowFrame:SetSize\((\d+), (\d+)\)", ow)
    body = ow[ow.index("function SettingsDialog.buildConfigWindow"):]
    checks = [{"x": int(x), "y": -int(y), "w": int(w), "label": unlua(lab), "key": key}
              for x, y, w, lab, key in re.findall(r'createStyledCheckbox\((\d+), (-?\d+), (\d+), L\["((?:[^"\\]|\\.)*)"\], "(\w+)"', body)]
    sections = [(-int(y), unlua(lab)) for y, lab in re.findall(r'createSectionDivider\((-?\d+), L\["((?:[^"\\]|\\.)*)"\]\)', body)]
    buttons = [(int(x), -int(y), int(w), int(h), lab, acc == "true") for x, y, w, h, lab, acc in
               re.findall(r"createStyledButton\((\d+), (-?\d+), (\d+), (\d+), (.+?), (true|false), ", body)]
    managed = re.findall(r"^\s{4}(\w+) = \{\s*\n\s*addon = \"(EzWoW-\w+)\", title = \"([^\"]+)\"", lua_table(ow, r"local MANAGED_BY = \{"), re.M)
    quals = [(int(q), unlua(lab), col) for q, lab, col in re.findall(r'\{ (\d), L\["([^"]+)"\], "\|cff(\w{6})" \}', body)]
    qpos = re.search(r'SetPoint\("TOPLEFT", (\d+) \+ columnIndex \* (\d+), (-?\d+) - rowWidget \* (\d+)\)', body)
    consts = {k: int(v) for k, v in re.findall(r"^local (\w+) = (\d+)\b", mw, re.M)}
    rh = re.search(r"local ROW_H, HEADER_H = (\d+), (\d+)", mw)
    consts["ROW_H"], consts["HEADER_H"] = int(rh.group(1)), int(rh.group(2))
    return {"th": th, "en": en, "dflt": dflt, "qual": qual, "W": int(size.group(1)), "H": int(size.group(2)),
            "checks": checks, "sections": sections, "buttons": buttons, "managed": {k: (a, t) for k, a, t in managed},
            "quals": quals, "qpos": (int(qpos.group(1)), int(qpos.group(2)), -int(qpos.group(3)), int(qpos.group(4))), "mw": consts,
            "icon": icon_data(find_file(root, "Media/Icon.png"))}


def tr(ctx, lang, ko):
    return ko if lang == "ko" else ctx["en"].get(ko, ko)


T = {
    "ko": {
        "lead": "내 직업 · 레벨에서 지금 입을 수 있는 최고 장비를 딜/힐/탱 역할별로 나란히 비교하고, 어디서 나오는지 알려 줍니다",
        "cls": "성기사", "specs": ["징벌 (딜)", "신성 (힐)", "보호 (탱)"],
        "slots": [("머리", False), ("손", False), ("한손 무기", True), ("반지", True)],
        "items": {
            "머리": [[("서약의 사슬 투구", 3, "+18.2%", "41.6", "BiS*", "요구 24 · 제작:대장기술", True),
                      ("모래폭풍 투구", 2, "+2.1%", "35.1", "", "요구 27 · 월드 드랍", False)],
                     [("수행자의 은도금 사슬 투구", 3, "+12.0%", "38.9", "", "요구 26 · 제작:대장기술", True),
                      ("새벽빛 두건", 2, "+9.4%", "35.2", "", "요구 25 · 통곡의 동굴", True)],
                     [("수호자의 은도금 사슬 투구", 3, "+21.5%", "52.3", "BiS", "요구 26 · 제작:대장기술", True),
                      ("역전용사의 은도금 투구", 2, "+9.8%", "46.4", "", "요구 26 · 제작:대장기술", True)]],
            "손": [[("성전사의 장갑", 3, "+24.7%", "22.8", "BiS", "요구 21 · 제작:대장기술", True),
                    ("광택나는 미늘 장갑", 2, "+0.8%", "18.6", "", "요구 25 · 죽음의 폐광", False)],
                   [("바람결 장갑", 2, "+15.4%", "20.4", "", "요구 22 · 퀘스트:잃어버린 순찰대", True),
                    ("가시덤불 손보호구", 2, "+6.2%", "19.1", "", "요구 24 · 상인:가르텐", True)],
                   [("수호자의 장갑", 3, "+15.3%", "27.0", "BiS*", "요구 21 · 제작:대장기술", True),
                    ("빗바랜 사슬 장갑", 2, "+3.1%", "21.4", "", "요구 18 · 통곡의 동굴", True)]],
        },
        "status": "요구 레벨 18~28(자동) · 확인된 아이템 1,284개 · 점수는 추정치",
        "tipItem": "서약의 사슬 투구", "tipBind": "착용 시 귀속", "tipSlot": ("머리", "사슬"), "tipArmor": "방어도 208",
        "tipStats": ["+9 힘", "+7 체력"], "tipReq": "최소 요구 레벨: 24", "tipDelta": "▲ +18.2% (힘 +5, 체력 +3)",
        "bagItem": "수호자의 은도금 사슬 투구",
        "bagSrc": ["[BiS] 보호 (탱)", "제작: 대장기술 [도안 필요] (숙련 175)", "  재료: 강철 주괴 x10, 은 막대 x2", "  배우는 곳: 대장기술 상인 (아이언포지)"],
        "notes": [
            ("정렬", "추천순(역할별 스탯 가중치 점수) 또는 30레벨 BiS 우선. 방어도 · 초당 공격력 · 힘 · 민첩성 · 체력 · 지능 · 정신력을 여러 개 고르면 합계 순."),
            ("요구 레벨 범위", "직접 입력 후 검색, 또는 “자동(현재-10)”으로 내 레벨-10~현재 레벨."),
            ("역할 열 · 단추", "직업의 딜/힐/탱 특성을 나란히 비교. 오른쪽 위 아이템 검색 · 내 캐릭터 ▼(다른 직업 미리 보기) · 설정."),
            ("슬롯 헤더", "클릭해 모든 열에서 그 부위를 접고 펼칩니다(저장됨)."),
            ("추천 행", "녹색 배경과 ▲는 업그레이드, BiS/BiS*는 30레벨 BiS 목록, 셋째 줄은 요구 레벨과 획득처(던전 · 제작 · 퀘스트 · 상인 · 월드 드랍)."),
            ("행 툴팁", "착용 장비 대비 변화와 추정 점수. 우클릭: EzWoW - Map Finder로 획득처 찾기, Shift+클릭: 채팅 링크, Ctrl+클릭: 착용 미리보기."),
            ("아이템 툴팁 획득처", "가방 · 보상 · 채팅 링크 장비에 BiS 여부와 획득처(제작품은 재료 · 배우는 곳) 블록. 이 블록이 나오면 EzWoW - Tooltip은 겹치는 획득처 줄을 생략합니다."),
            ("상태 줄", "현재 범위와 확인된 아이템 수. 오른쪽 아래 모서리로 창 높이 조절."),
        ],
        "foot": "애드온 코드의 창 크기 · 좌표 · 색상 · 문구로 재현한 예시 화면입니다(성기사 28레벨 예시). 아이템 이름 · 점수 · 획득처는 지어낸 예시이고 아이콘은 단순화했습니다.",
        "sLead": "/ezbg config · 추천 조건, 출처, 아이템 등급, 표시 방식",
        "sTitle": "설정창",
        "sNotes": [
            ("조건", "언어(목록에서 선택), 업그레이드만, 출처 확인된 것만, 다른 직업 전용 숨김, 몹 레벨 제한(범위+8), 아이템 툴팁 획득처, 착용 장비 비교 자동 표시, 화면 아이콘, 획득처 자동 기록."),
            ("슬롯당 표시 개수", "부위마다 보여 줄 후보 수(2~10)."),
            ("출처", "제작템, 퀘스트 보상, 저확률 월드 드랍, 출처 불명 신규 아이템 포함 여부."),
            ("등급", "표시할 아이템 품질(하급~전설)."),
            ("창 열기 · 투명도 · 월드 드랍 기준", "추천 장비 창 · 아이템 검색 창 단추, 메인 창 불투명도 30~100%, 이 확률(0~20%) 미만 드랍은 “월드 드랍”."),
            ("창 위치 초기화 · 후원", "메인 창과 런처 아이콘을 제자리로."),
        ],
        "sFoot": "애드온 코드의 창 크기 · 좌표 · 색상 · 문구로 재현한 예시 화면입니다. 체크 상태는 기본값이며, 회색 줄(착용 장비 비교)은 EzWoW - Tooltip이 함께 설치되어 그쪽에서 설정하는 경우의 모습입니다.",
    },
    "en": {
        "lead": "Compares the best gear you can wear right now for your class and level, DPS / heal / tank side by side, and shows where it comes from",
        "cls": "Paladin", "specs": ["징벌 (딜)", "신성 (힐)", "보호 (탱)"],
        "slots": [("Head", False), ("Hands", False), ("One-Hand", True), ("Finger", True)],
        "items": {
            "Head": [[("Oathbound Chain Helm", 3, "+18.2%", "41.6", "BiS*", "Req. 24 · Craft: Blacksmithing", True),
                      ("Sandstorm Helm", 2, "+2.1%", "35.1", "", "Req. 27 · World drop", False)],
                     [("Adept's Silvered Chain Helm", 3, "+12.0%", "38.9", "", "Req. 26 · Craft: Blacksmithing", True),
                      ("Dawnlight Hood", 2, "+9.4%", "35.2", "", "Req. 25 · Wailing Caverns", True)],
                     [("Warden's Silvered Chain Helm", 3, "+21.5%", "52.3", "BiS", "Req. 26 · Craft: Blacksmithing", True),
                      ("Veteran's Silvered Helm", 2, "+9.8%", "46.4", "", "Req. 26 · Craft: Blacksmithing", True)]],
            "Hands": [[("Crusader's Gauntlets", 3, "+24.7%", "22.8", "BiS", "Req. 21 · Craft: Blacksmithing", True),
                       ("Polished Scale Gloves", 2, "+0.8%", "18.6", "", "Req. 25 · The Deadmines", False)],
                      [("Windborne Gloves", 2, "+15.4%", "20.4", "", "Req. 22 · Quest: The Lost Patrol", True),
                       ("Thornbrush Handguards", 2, "+6.2%", "19.1", "", "Req. 24 · Vendor: Garten", True)],
                      [("Warden's Gauntlets", 3, "+15.3%", "27.0", "BiS*", "Req. 21 · Craft: Blacksmithing", True),
                       ("Weathered Chain Gloves", 2, "+3.1%", "21.4", "", "Req. 18 · Wailing Caverns", True)]],
        },
        "status": "Required level 18-28 (auto) · 1,284 items found · scores are estimates",
        "tipItem": "Oathbound Chain Helm", "tipBind": "Binds when equipped", "tipSlot": ("Head", "Mail"), "tipArmor": "208 Armor",
        "tipStats": ["+9 Strength", "+7 Stamina"], "tipReq": "Requires Level 24", "tipDelta": "▲ +18.2% (Strength +5, Stamina +3)",
        "bagItem": "Warden's Silvered Chain Helm",
        "bagSrc": ["[BiS] Protection (Tank)", "Craft: Blacksmithing [recipe needed] (Skill 175)", "  Reagents: Steel Bar x10, Silver Rod x2",
                   "  Learned from: Blacksmithing supplier (Ironforge)"],
        "notes": [
            ("Sort", "Recommended (role stat-weight score) or Level 30 BiS first. Tick armor, DPS, Strength, Agility, Stamina, Intellect, Spirit… to sort by their sum."),
            ("Required-level range", "Type a range and press Search, or “Auto (Lv-10)” for your level - 10 up to your level."),
            ("Role columns · buttons", "DPS, heal and tank specs side by side. Top right: Item search · My character ▼ (preview other classes) · Settings."),
            ("Slot header", "Click to collapse or expand that slot in every column (saved)."),
            ("Item row", "Green background and ▲ mark upgrades, BiS/BiS* the level-30 BiS list; the third line is the required level and source (dungeon, craft, quest, vendor, world drop)."),
            ("Row tooltip", "Change versus equipped and estimated score. Right-click: find the source with EzWoW - Map Finder; Shift+click: chat link; Ctrl+click: dress-up."),
            ("Sources in item tooltips", "Bag, reward and chat-link gear gets a block with BiS info and sources (reagents and trainer for crafts). When it shows, EzWoW - Tooltip leaves out its overlapping source lines."),
            ("Status line", "Current range and items found. Drag the bottom-right corner to change the height."),
        ],
        "foot": "Mock-ups rebuilt from the window sizes, coordinates, colours and strings in the addon code (level 28 Paladin example). Item names, scores and sources are made-up examples; icons are simplified.",
        "sLead": "/ezbg config · conditions, sources, item quality, display",
        "sTitle": "Settings",
        "sNotes": [
            ("Conditions", "Language (pick from the list), upgrades only, known sources only, hide other-class items, mob level limit (range+8), sources in item tooltips, auto-compare equipped gear, on-screen icon, record sources."),
            ("Items per slot", "Candidates per slot (2–10)."),
            ("Sources", "Include crafted items, quest rewards, low-chance world drops and new items with unknown sources."),
            ("Quality", "Item qualities to show (Poor to Legendary)."),
            ("Windows · opacity · world-drop threshold", "Open the gear window or item search, main window opacity 30–100%, drops below this chance (0–20%) count as “World drop”."),
            ("Reset window position · support", "Put the main window and launcher icon back."),
        ],
        "sFoot": "Mock-up rebuilt from the window size, coordinates, colours and strings in the addon code. Check boxes show the defaults; the grey row (auto-compare equipped gear) shows how it looks when EzWoW - Tooltip is installed and owns that setting.",
    },
}

ROLE_COL = {"딜": (0.945, 0.741, 0.341), "힐": (0.376, 0.808, 0.639), "탱": (0.45, 0.74, 1)}
SLOT_ICON = {0: "helm", 1: "glove"}


def ui_page(lang, ctx):
    global S
    S = 1.2
    t, mwc, th = T[lang], ctx["mw"], ctx["th"]
    L = lambda ko: tr(ctx, lang, ko)  # noqa: E731
    acc = css(th["accent"])
    n = len(t["specs"])
    frame_w = max(mwc["MIN_FRAME_W"], mwc["SIDE_PAD"] + n * mwc["COL_MIN_W"])
    col_w = (frame_w - mwc["SIDE_PAD"]) / n
    H = mwc["FRAME_H"]
    win = Window(th, frame_w, H, "", header=0)
    win.add(box(1, 1, frame_w - 2, 2, f"background:{css(th['accent'], .9)}"))
    win.button(frame_w - 10 - 22, 8, 22, 22, "X")
    win.add(text_top(18, 12, f'EzWoW - Best Gear Finder  <span style="color:{CLASS_HEX["PALADIN"]}">{esc(t["cls"])}</span>  Lv.28', 12, css(th["text"])))
    win.button(16, 34, 168, 22, esc(L("정렬: ") + L("추천순")) + " ▼", size=10)
    cfg_x = frame_w - 18 - 76
    win.button(cfg_x, 36, 76, 20, "설정" if lang == "ko" else "Settings", size=10)
    win.button(cfg_x - 6 - 110, 36, 110, 20, esc(L("내 캐릭터")) + " ▼", size=10)
    win.button(cfg_x - 6 - 110 - 6 - 96, 36, 96, 20, esc(L("아이템 검색")), size=10)
    win.add(text_top(20, 66, esc(L("요구 레벨")), 10, GOLD))
    lx = 20 + (58 if lang == "ko" else 92)
    for i, v in enumerate(("18", "28")):
        x = lx + i * 50
        win.add(box(x, 62, 36, 20, f"background:rgba(12,17,22,.96);border:1px solid {css(th['border'])}",
                    f'<div class="t" style="left:50%;top:50%;transform:translate(-50%,-50%);font-size:{px(12)};color:#fff">{v}</div>'))
    win.add(text(lx + 36 + 7, 72, "~", 12, GOLD, anchor="center"))
    sx = lx + 50 + 36 + 8
    win.button(sx, 61, 64, 22, esc(L("검색")), accent=True, size=10, bg="rgba(59,48,28,.96)")
    win.button(sx + 68, 61, 86, 22, esc(L("자동(현재-10)")), size=10)
    for i, spec in enumerate(t["specs"]):
        role = next(k for k in ROLE_COL if k in spec)
        col = css(ROLE_COL[role])
        win.add(text_top(18 + i * col_w + 4, 92, esc(L(spec)), 12, col))
        win.add(box(22 + i * col_w, 109, col_w - 10, 2, f"background:{col}"))
    win.add(box(18, 110, col_w * n, 1, f"background:{css(th['border'], .85)}"))
    # scroll child at (18, 114)
    y = 114
    row_h, hdr_h = mwc["ROW_H"], mwc["HEADER_H"]
    rows_xy = []
    for si, (slot, collapsed) in enumerate(t["slots"]):
        win.add(box(20, y, col_w * n - 4, hdr_h, f"background:{css(th['bgSub'])}"))
        win.add(box(26, y + hdr_h / 2 - 9, 18, 18, "border:1px solid #c8c8c8;border-radius:3px;background:#2a2a2a;display:flex;align-items:center;justify-content:center",
                    f'<span style="color:#fff;font-size:{px(13)};line-height:1">{"+" if collapsed else "−"}</span>'))
        win.add(text(50, y + hdr_h / 2, esc(slot), 12, acc))
        win.add(text(20 + col_w * n - 4 - 10, y + hdr_h / 2, esc(L("펼치기") if collapsed else L("접기")), 10, css(th["text"]), anchor="right"))
        y += hdr_h
        if collapsed:
            y += 4
            continue
        lists = t["items"][slot]
        for c, lst in enumerate(lists):
            for k, (name, q, delta, score, bis, src, up) in enumerate(lst):
                rx, ry = 18 + c * col_w + 2, y + k * row_h
                bg = "rgba(24,47,45,.95)" if up else "rgba(29,40,49,.95)"
                win.add(box(rx, ry, col_w - 6, row_h - 4, f"background:{bg}"))
                win.add(box(rx, ry, 2, row_h - 4, f"background:{QUALITY[q]}"))
                win.add(icon_box(rx + 8, ry + 8, 34, SLOT_ICON[si]))
                win.add(text_top(rx + 50, ry + 7, f'<span style="color:{QUALITY[q]}">[{esc(name)}]</span>', 10, "#fff",
                                 width=col_w - 64, style="white-space:nowrap;overflow:hidden"))
                comp = (f'<span style="color:#68d9a4">▲ {delta}</span>' if up else f'<span style="color:#9baabd">{delta}</span>')
                badge = {"BiS": ' <span style="color:#ffcf68">BiS</span>', "BiS*": ' <span style="color:#9baabd">BiS*</span>'}.get(bis, "")
                win.add(text_top(rx + 50, ry + 24, f'{comp} · {esc(L("점수 %.1f").replace("%.1f", score))}{badge}', 10, "#fff"))
                win.add(text_top(rx + 50, ry + 40, esc(src), 10, "#8a8a8a"))
                rows_xy.append((c, k, rx, ry))
        y += max(len(lst) for lst in lists) * row_h + 6
    for i in range(1, n):
        win.add(box(18 + i * col_w, 114, 1, y - 114, "background:rgba(52,76,91,.5)"))
    win.add(text(20, H - 18 - 6, esc(t["status"]), 10, css(th["text"])))
    win.add(f'<div class="abs" style="right:{px(8)};bottom:{px(8)};width:{px(14)};height:{px(14)};'
            f'background:linear-gradient(135deg,transparent 50%,#7c8a96 50%,#7c8a96 58%,transparent 58%,transparent 70%,#7c8a96 70%,#7c8a96 78%,transparent 78%)"></div>')

    ox, oy = 50, 168
    parts = [heading(TITLE, esc(t["lead"])), win.html(ox, oy)]
    # hovered row tooltip (row 1 of the first column) with the comparison lines
    c0 = rows_xy[0]
    tx = ox + (c0[2] + col_w - 6) * S + 6
    ty = oy + c0[3] * S
    W = "#fff"
    lines = [f'<span style="color:{QUALITY[3]}">{esc(t["tipItem"])}</span>', esc(t["tipBind"]),
             (esc(t["tipSlot"][0]), esc(t["tipSlot"][1])), esc(t["tipArmor"])] + [esc(s) for s in t["tipStats"]] + [
        esc(t["tipReq"]), ("gap",),
        f'<span style="color:#b3b3b3">{esc(L("현재 착용 장비 아이템 레벨: "))}22</span>',
        f'<span style="color:#99ccff">{esc(L("현재 장비 대비: %s").replace("%s", t["tipDelta"]))}</span>',
        f'<span style="color:#99e699">{esc(L("추정 점수: 이 아이템 %.1f / 착용 중 %.1f").replace("%.1f", "41.6", 1).replace("%.1f", "35.2", 1))}</span>',
        f'<span style="color:#a6b8cc">{esc(L("표시된 %는 추정 점수 변화입니다."))}</span>',
        f'<span style="color:#4bc8e8">{esc(L("우클릭: 지도에서 획득처 찾기"))}</span>']
    parts.append(tooltip(tx, ty, lines, border=QUALITY[3], gloss=False, bg="rgba(8,12,18,.96)", z=40))
    # bag item tooltip with the source block (right of the window)
    bx = ox + frame_w * S + 30
    by = oy + 40
    blines = [f'<span style="color:{QUALITY[3]}">{esc(t["bagItem"])}</span>', esc(L("착용 시 귀속") if lang == "ko" else "Binds when equipped"),
              (esc(t["tipSlot"][0]), esc(t["tipSlot"][1])), ("gap",),
              f'<span style="color:{acc}">EzWoW - Best Gear Finder</span>',
              f'<span style="color:#ffd100">{esc(t["bagSrc"][0])}</span>',
              f'<span style="color:#66ccff">{esc(t["bagSrc"][1])}</span>',
              f'<span style="color:#b3d9ff">{esc(t["bagSrc"][2])}</span>',
              f'<span style="color:#b3d9ff">{esc(t["bagSrc"][3])}</span>']
    parts.append(tooltip(bx, by, blines, border=QUALITY[3], gloss=False, bg="rgba(8,12,18,.96)", width=(PAGE_W - 40 - bx) / S))
    calls = [(ox - 20, oy + 45 * S), (ox - 20, oy + 72 * S), (ox + (cfg_x - 236) * S - 6, oy + 46 * S), (ox - 20, oy + (114 + hdr_h / 2) * S),
             (ox - 20, oy + (114 + hdr_h + 30) * S), (tx + 4, ty + 4), (bx, by), (ox - 20, oy + (H - 22) * S)]
    parts.append(callouts(calls))
    parts.append(notes_block(50, oy + H * S + 30, 730, [(a, esc(b_)) for a, b_ in t["notes"][:4]]))
    parts.append(notes_block(820, oy + H * S + 30, 730, [(a, esc(b_)) for a, b_ in t["notes"][4:]], start=5))
    parts.append(f'<div class="foot" style="left:50px;width:1500px">{esc(t["foot"])}</div>')
    return "".join(parts)


def settings_page(lang, ctx):
    global S
    S = 1.3
    t, th, d = T[lang], ctx["th"], ctx["dflt"]
    L = lambda ko: tr(ctx, lang, ko)  # noqa: E731
    W, H = ctx["W"], ctx["H"]
    win = Window(th, W, H, TITLE, esc(L("점수는 직업·역할별 스탯 가중치로 계산한 추정치입니다.")), ctx["icon"], close=0)
    win.button(428, 14, 22, 22, "X")
    for y, lab in ctx["sections"]:
        win.section(20, y, esc(L(lab)))
    win.button(250, 66, 190, 20, esc(L("언어")) + ": " + ("자동" if lang == "ko" else "Auto") + " ▼", size=10)
    for c in ctx["checks"]:
        on = d.get(c["key"]) == "true"
        label = esc(L(c["label"]))
        disabled = False
        if c["key"] in ctx["managed"]:
            note = L("%s에서 설정합니다").replace("%s", ctx["managed"][c["key"]][1])
            label += f' <span style="color:#8398a6">({esc(note)})</span>'
            disabled = True
        win.check(c["x"], c["y"], label, on, label_w=c["w"], font=10, disabled=disabled)
    mut = css(th["muted"])
    # steppers (label, minus/plus x, value)
    win.add(text_top(20, 202, esc(L("슬롯당 표시 개수")), 10, mut))
    win.button(140, 198, 22, 20, "-", size=12)
    win.add(text(140 + 22 + 2 + 19, 208, f'{d["perSlot"]}', 10, css(th["text"]), anchor="center"))
    win.button(204, 198, 22, 20, "+", size=12)
    qx, qdx, qy, qdy = ctx["qpos"]
    for i, (q, lab, col) in enumerate(ctx["quals"]):
        win.check(qx + (i % 3) * qdx, qy + (i // 3) * qdy, f'<span style="color:#{col}">{esc(L(lab))}</span>', q in ctx["qual"], font=10, label_w=108)
    for x, y, w, h, lab, accent in ctx["buttons"]:
        if lab.startswith('"X"') or (w == 22):
            continue
        text_l = {'"EzWoW - Best Gear Finder (/ezbg)"': "EzWoW - Best Gear Finder (/ezbg)",
                  'L["아이템 검색"] .. " (/ezbg find)"': L("아이템 검색") + " (/ezbg find)",
                  'L["창 위치 초기화"] .. " / " .. L["아이콘 복원"]': L("창 위치 초기화") + " / " + L("아이콘 복원"),
                  'L["후원"]': L("후원")}.get(lab)
        if text_l is None:
            continue
        win.button(x, y, w, h, esc(text_l), accent=accent, size=10, bg="rgba(59,48,28,.96)" if accent else None)
    win.add(text_top(20, 436, esc(L("배경 불투명도")), 10, mut))
    win.button(120, 432, 24, 20, "-", size=12)
    win.add(text(120 + 24 + 2 + 23, 442, f'{round(0.92 * 100)}%', 10, css(th["text"]), anchor="center"))
    win.button(194, 432, 24, 20, "+", size=12)
    win.add(text_top(236, 436, esc(L("월드 드랍 (저확률)")), 10, mut, width=112))
    win.button(354, 432, 22, 20, "-", size=12)
    win.add(text(354 + 22 + 2 + 19, 442, f'{d["minChance"]}%', 10, css(th["text"]), anchor="center"))
    win.button(418, 432, 22, 20, "+", size=12)
    win.add(f'<div class="t" style="right:{px(20)};bottom:{px(10)};font-size:{px(10)};color:{mut};{SHADOW}">EzWoW - Best Gear Finder · /ezbg</div>')
    ox, oy = 60, 150
    secs = [y for y, _ in ctx["sections"]]
    spans = [(66, 194), (196, 222), (secs[1], secs[2] - 4), (secs[2], 386), (394, 424), (430, 456), (470, 502)]
    spans = [spans[0], spans[1], spans[2], spans[3], spans[4], spans[5]]
    calls = [(ox + W * S + 22, oy + (a + b_) / 2 * S) for a, b_ in spans]
    calls[4] = (ox + W * S + 22, oy + (394 + 456) / 2 * S)
    calls[5] = (ox + W * S + 22, oy + 487 * S)
    nx = ox + W * S + 70
    return (heading(TITLE, esc(t["sLead"]), t["sTitle"]) + win.html(ox, oy) + callouts(calls)
            + notes_block(nx, oy + 6, PAGE_W - nx - 40, [(a, esc(b_)) for a, b_ in t["sNotes"]])
            + f'<div class="foot" style="left:50px;width:1500px">{esc(t["sFoot"])}</div>')


def main(root: Path):
    ctx = load(root)
    call = hexc(ctx["th"]["accent"])
    run_pages(root, [(f"{n}_{lang}", (lambda n=n, lang=lang: (ui_page if n == "ui" else settings_page)(lang, ctx)))
                     for lang in ("ko", "en") for n in ("ui", "settings")], call)


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve())
