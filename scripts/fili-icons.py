#!/usr/bin/env python3
# Génère la police « Fili Icons » (dotfiles/home/.local/share/fonts/FiliIcons.ttf): icônes Lucide au trait fin
# (https://lucide.dev, licence ISC) placées sur les codes Font Awesome / Nerd Font déjà utilisés par la fili-bar,
# les scripts (bar-status, bar-tray...), le fili-launcher et le menu. Une règle fontconfig (dotfiles/config/fontconfig)
# la fait passer devant Font Awesome derrière Jost: aucun script à changer, un code non couvert retombe sur Font Awesome.
# Icônes réduites et centrées sur la hauteur des capitales de Jost (Lucide occupe tout l'em).
#
# Usage: scripts/fili-icons.py [lucide.ttf info.json]   (sans argument: télécharge lucide-static VERSION)
# Ajouter une icône: une ligne dans MAP (code utilisé -> nom Lucide, voir https://lucide.dev/icons), relancer.
# Dépendance de développement: fonttools (packages/dev.txt).
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

# Échelle et position: 85 % de l'em, centré sur la mi-hauteur des capitales de Jost (700 / 2)
SCALE = 0.85
CENTER_Y = 350
ADVANCE = 950

MAP = {
    # fili-bar et scripts de la barre
    0xF002: "search", 0xF021: "refresh-cw", 0xF023: "lock", 0xF026: "volume", 0xF027: "volume-1",
    0xF028: "volume-2", 0xF6A9: "volume-x", 0xF04B: "play", 0xF04C: "pause", 0xF053: "chevron-left",
    0xF054: "chevron-right", 0xF071: "triangle-alert", 0xF072: "plane", 0xF073: "calendar", 0xF0A0: "hard-drive",
    0xF0E0: "mail", 0xF0E7: "zap", 0xF0EE: "cloud-upload", 0xF0F3: "bell", 0xF1F6: "bell-off", 0xF0F4: "coffee",
    0xF108: "monitor", 0xF111: "circle-dot", 0xF11C: "keyboard", 0xF130: "mic", 0xF131: "mic-off", 0xF186: "moon", 0xF185: "sun-dim",
    0xF1EA: "newspaper", 0xF1EB: "wifi", 0xF233: "server", 0xF240: "battery-full", 0xF241: "battery-full",
    0xF242: "battery-medium", 0xF243: "battery-low", 0xF244: "battery", 0xF293: "bluetooth", 0xF2C9: "thermometer",
    0xF2DB: "cpu", 0xF2F2: "timer", 0xF538: "memory-stick", 0xF796: "ethernet-port", 0xF05A3: "message-circle",
    0xF040: "pencil",
    # menu (I_* de ~/.local/bin/menu)
    0xF009: "layout-grid", 0xF0EA: "clipboard", 0xF118: "smile", 0xF1EC: "calculator", 0xF011: "power",
    0xF1FC: "paintbrush", 0xF1B2: "package", 0xF005: "star", 0xF08B: "log-out", 0xF01E: "rotate-cw",
    0xF025: "headphones", 0xF0AC: "globe", 0xF03E: "image", 0xF1F8: "trash-2", 0xF019: "download",
    0xF12D: "eraser", 0xF120: "terminal", 0xF121: "code", 0xF080: "chart-column", 0xF0DB: "columns-2",
    0xF030: "camera", 0xF2D0: "app-window", 0xF0EB: "lightbulb",
}


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

    # Sous-ensemble: seulement les glyphes utilisés
    opts = Options()
    opts.notdef_outline = True
    opts.name_IDs = ["*"]
    sub = Subsetter(opts)
    sub.populate(unicodes=sorted(set(lucide_cp.values())))
    sub.subset(src)

    # Mise à l'échelle et centrage de chaque glyphe
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

    # Table des caractères: codes Font Awesome / Nerd Font -> glyphes Lucide
    # format 4 pour le plan de base, format 12 en plus pour les codes Nerd Font au-delà (U+F05A3...)
    from fontTools.ttLib.tables._c_m_a_p import CmapSubtable
    cmap_t = src["cmap"]
    cmap_t.tables = [t for t in cmap_t.tables if t.isUnicode() and t.format in (4, 12)]
    if not any(t.format == 12 for t in cmap_t.tables):
        t12 = CmapSubtable.newSubtable(12)
        t12.platformID, t12.platEncID, t12.language = 3, 10, 0
        cmap_t.tables.append(t12)
    for table in cmap_t.tables:
        table.cmap = {t: g for t, g in names.items() if t <= 0xFFFF or table.format == 12}
    # Métriques verticales de Jost (ascendante 1070, descendante -375): même hauteur de ligne
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
