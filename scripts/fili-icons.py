#!/usr/bin/env python3
# Generates the "Fili Icons" font (dotfiles/home/.local/share/fonts/FiliIcons.ttf): thin-stroke Lucide icons
# (https://lucide.dev, ISC licence) placed on the Font Awesome / Nerd Font codes already used by the fili-bar,
# the scripts (bar-status, bar-tray...), the fili-launcher and the menu. A fontconfig rule (dotfiles/config/fontconfig)
# puts it before Font Awesome behind Jost: no script to change, an uncovered code falls back to Font Awesome.
# Icons reduced and centred on the cap height of Jost (Lucide fills the whole em).
# Usage: scripts/fili-icons.py [lucide.ttf info.json]   (without arguments: downloads lucide-static VERSION)
# After regeneration (or after bootstrap.sh relinks the fonts): restart Quickshell (`pkill quickshell`, the niri loop restarts
# it), otherwise its font cache loses Fili Icons and the bar falls back to full Font Awesome (thick icons).
# Adding an icon: a line in MAP (code used -> Lucide name, see https://lucide.dev/icons), run again.
# Development dependency: fonttools (packages/dev.txt).
import json
import os
import sys
import tempfile
import urllib.request

from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.subset import Options, Subsetter
from fontTools.ttLib import TTFont

VERSION = "0.460.0"
OUT = os.path.join(os.path.dirname(__file__), "..", "dotfiles/home/.local/share/fonts/FiliIcons.ttf")

# Scale and position: 85 % of the em, centred on the mid-height of the Jost capitals (700 / 2)
SCALE = 0.85
CENTER_Y = 350
ADVANCE = 950

# Topic icons of the fili-chat sessions: the AI picks one by its name (apps/fili-chat, TOPICS, same order), the code
# is 0xF2000 + position. 0xF2F00 and following: drawer buttons (session list, settings).
TOPICS = [
    "message-circle", "terminal", "code", "bug", "git-branch", "package", "wrench", "settings", "wifi", "volume-2",
    "monitor", "keyboard", "hard-drive", "cpu", "database", "shield", "key", "globe", "mail", "calendar",
    "file-text", "folder", "image", "music", "video", "book-open", "palette", "printer", "download", "search",
    "lightbulb", "rocket", "map", "shopping-cart", "graduation-cap", "calculator", "clock", "sparkles", "archive",
    "battery-full", "bluetooth", "languages",
    # everyday-life topics (add at the end: the icons already chosen keep their code)
    "car", "plane", "house", "heart-pulse", "wallet", "shirt", "utensils", "trees", "sun", "dumbbell", "gamepad-2", "smartphone", "briefcase", "bike", "train-front", "paw-print", "flask-conical", "landmark", "scale", "hammer", "plug", "tv", "film", "baby",
]

MAP = {
    # fili-bar and bar scripts
    0xF002: "search", 0xF021: "refresh-cw", 0xF023: "lock", 0xF026: "volume", 0xF027: "volume-1",
    0xF028: "volume-2", 0xF6A9: "volume-x", 0xF04B: "play", 0xF04C: "pause", 0xF053: "chevron-left",
    0xF054: "chevron-right", 0xF071: "triangle-alert", 0xF072: "plane", 0xF073: "calendar", 0xF0A0: "hard-drive",
    0xF0E0: "mail", 0xF0E7: "zap", 0xF0EE: "cloud-upload", 0xF0F3: "bell", 0xF1F6: "bell-off", 0xF0F4: "coffee",
    0xF108: "monitor", 0xF111: "circle-dot", 0xF11C: "keyboard", 0xF130: "mic", 0xF131: "mic-off", 0xF186: "moon", 0xF185: "contrast",
    0xF1EA: "newspaper", 0xF1EB: "wifi", 0xF233: "server", 0xF240: "battery-full", 0xF241: "battery-full",
    0xF242: "battery-medium", 0xF243: "battery-low", 0xF244: "battery", 0xF293: "bluetooth", 0xF2C9: "thermometer",
    0xF2DB: "cpu", 0xF2F2: "timer", 0xF538: "memory-stick", 0xF796: "ethernet-port", 0xF05A3: "message-circle",
    0xF040: "pencil",
    # Wi-Fi signal strength (Nerd Font codes md-wifi_strength_1..4): fili-bar (bar-stats net) and network fili-panel
    0xF091F: "wifi-zero", 0xF0922: "wifi-low", 0xF0925: "wifi-high", 0xF0928: "wifi",
    # menu (I_* of ~/.local/bin/menu)
    0xF009: "layout-grid", 0xF0EA: "clipboard", 0xF118: "smile", 0xF1EC: "calculator", 0xF011: "power",
    0xF1FC: "paintbrush", 0xF1B2: "package", 0xF005: "star", 0xF08B: "log-out", 0xF01E: "rotate-cw",
    0xF025: "headphones", 0xF0AC: "globe", 0xF03E: "image", 0xF1F8: "trash-2", 0xF019: "download",
    0xF12D: "eraser", 0xF120: "terminal", 0xF121: "code", 0xF080: "chart-column", 0xF0DB: "columns-2",
    0xF030: "camera", 0xF2D0: "app-window", 0xF0EB: "lightbulb", 0xF05A: "info", 0xF06A9: "bot",
}


MAP.update({0xF2000 + i: n for i, n in enumerate(TOPICS)})
MAP.update({0xF2F00: "list", 0xF2F01: "settings"})


def fetch(dest):
    base = f"https://unpkg.com/lucide-static@{VERSION}/font/"
    for name in ("lucide.ttf", "info.json"):
        urllib.request.urlretrieve(base + name, os.path.join(dest, name))
    return os.path.join(dest, "lucide.ttf"), os.path.join(dest, "info.json")


def main():
    if len(sys.argv) == 3:
        ttf, info_path = sys.argv[1:3]
    else:
        ttf, info_path = fetch(tempfile.mkdtemp(prefix="lucide-"))
    info = json.load(open(info_path))
    src = TTFont(ttf)
    lucide_cp = {}
    for target, name in MAP.items():
        if name not in info:
            sys.exit(f"icône Lucide inconnue: {name}")
        lucide_cp[target] = int(info[name]["encodedCode"].lstrip("\\"), 16)
    cmap = src.getBestCmap()
    names = {t: cmap[c] for t, c in lucide_cp.items()}

    # Subset: only the glyphs used
    opts = Options()
    opts.notdef_outline = True
    opts.name_IDs = ["*"]
    sub = Subsetter(opts)
    sub.populate(unicodes=sorted(set(lucide_cp.values())))
    sub.subset(src)

    # Scaling and centring of each glyph
    glyf, hmtx = src["glyf"], src["hmtx"]
    gs = src.getGlyphSet()
    dy = CENTER_Y - SCALE * 500
    dx = (ADVANCE - SCALE * 1000) / 2
    for g in set(names.values()):
        pen = TTGlyphPen(gs)
        gs[g].draw(TransformPen(pen, (SCALE, 0, 0, SCALE, dx, dy)))
        glyf[g] = pen.glyph()
        glyf[g].recalcBounds(glyf)
        hmtx[g] = (ADVANCE, glyf[g].xMin)

    # Character table: Font Awesome / Nerd Font codes -> Lucide glyphs
    # format 4 for the base plane, format 12 in addition for the Nerd Font codes beyond (U+F05A3...)
    from fontTools.ttLib.tables._c_m_a_p import CmapSubtable
    cmap_t = src["cmap"]
    cmap_t.tables = [t for t in cmap_t.tables if t.isUnicode() and t.format in (4, 12)]
    if not any(t.format == 12 for t in cmap_t.tables):
        t12 = CmapSubtable.newSubtable(12)
        t12.platformID, t12.platEncID, t12.language = 3, 10, 0
        cmap_t.tables.append(t12)
    for table in cmap_t.tables:
        table.cmap = {t: g for t, g in names.items() if t <= 0xFFFF or table.format == 12}
    # Vertical metrics of Jost (ascent 1070, descent -375): same line height
    src["hhea"].ascent, src["hhea"].descent = 1070, -375
    os2 = src["OS/2"]
    os2.sTypoAscender, os2.sTypoDescender, os2.usWinAscent, os2.usWinDescent = 1070, -375, 1070, 375

    # Nom de famille
    for rec in src["name"].names:
        if rec.nameID in (1, 16):
            rec.string = "Fili Icons"
        elif rec.nameID == 4:
            rec.string = "Fili Icons Regular"
        elif rec.nameID == 6:
            rec.string = "FiliIcons-Regular"
        elif rec.nameID == 5:
            rec.string = f"Version 1.0 (Lucide {VERSION})"
    src.save(OUT)
    print(f"{os.path.normpath(OUT)}: {len(MAP)} codes, {len(set(names.values()))} icônes, {os.path.getsize(OUT)} octets")


if __name__ == "__main__":
    main()
