#!/bin/sh
# Génère les visuels Filigrane de l'OS depuis brand/ (fond d'écran, thème Plymouth). Résultats versionnés:
# à relancer seulement si brand/ ou ce script change. Requiert rsvg-convert, magick et la police Jost
# (dotfiles/home/.local/share/fonts, liée par bootstrap.sh).
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
B="$ROOT/brand"
PLY="$ROOT/system/plymouth/filigrane"
WP="$ROOT/dotfiles/home/.local/share/wallpapers/filigrane.png"
WP_CLAIR="$ROOT/dotfiles/home/.local/share/wallpapers/filigrane-clair.png"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Couleurs (references/brand.md); nuit-2/nuit-4: teintes dérivées entre nuit et voile
NUIT=#1c222b NUIT_PROFOND=#181d25 NUIT_2=#232b36 NUIT_3=#2d3744 NUIT_4=#3c4858 VOILE=#9dbbd6 BRUME=#dbe7f4
# Mode clair (fili-theme): papier, et papier un peu plus sombre en bas (même teinte que la vue d'ensemble de niri)
PAPIER=#f3f1ec PAPIER_3=#dfdbd2

fc-match -f '%{family}\n' 'Jost' | grep -q '^Jost' || { echo "police Jost absente (./bootstrap.sh --dotfiles-only)" >&2; exit 1; }

# Fond d'écran 2560x1600 (16:10, recadré par swaybg en mode fill): nuit, symbole sombre au centre, en retrait
rsvg-convert -w 1100 "$B/filigrane-sombre.svg" -o "$TMP/symbole.png"
magick -size 2560x1600 "gradient:$NUIT-$NUIT_PROFOND" "$TMP/symbole.png" -gravity center -geometry +0-60 \
    -composite -strip "PNG24:$WP"
# Version claire: papier, symbole couleur (arêtes adoucies, grands visuels)
rsvg-convert -w 1100 "$B/filigrane-couleur-doux.svg" -o "$TMP/symbole-clair.png"
magick -size 2560x1600 "gradient:$PAPIER-$PAPIER_3" "$TMP/symbole-clair.png" -gravity center -geometry +0-60 \
    -composite -strip "PNG24:$WP_CLAIR"

# Plymouth: images dessinées pour 2560 px de large (DeviceScale=1), réduites de moitié par le script en dessous de 2000 px
mkdir -p "$PLY"
rsvg-convert -w 640 "$B/filigrane-empile-sombre.svg" -o "$PLY/logo.png"
svg() { printf '<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s">%s</svg>' "$1" "$2" "$3" > "$TMP/x.svg"; rsvg-convert "$TMP/x.svg" -o "$PLY/$4"; }
svg 640 88 "<rect x='1' y='1' width='638' height='86' rx='20' fill='$NUIT_2' stroke='$NUIT_4' stroke-width='2'/>" entry.png
svg 16 16 "<circle cx='8' cy='8' r='7' fill='$BRUME'/>" bullet.png
svg 480 4 "<rect width='480' height='4' rx='2' fill='$NUIT_3'/>" progress_box.png
svg 480 4 "<rect width='480' height='4' rx='2' fill='$VOILE'/>" progress_bar.png
# Étiquette: Jost 500 en capitales espacées (0,16 em)
svg 640 40 "<text x='320' y='29' text-anchor='middle' font-family='Jost' font-weight='500' font-size='24' letter-spacing='3.8' fill='$VOILE'>PHRASE DE PASSE</text>" prompt.png
magick "$PLY/prompt.png" -trim +repage "PNG32:$PLY/prompt.png"
echo "OK: $WP, $WP_CLAIR, $PLY/*.png"
