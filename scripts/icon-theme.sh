#!/bin/sh
# Installs the Filigrane-Icons icon theme (icons/Filigrane-Icons, GPL v3) in ~/.local/share/icons, for GTK
# and fili-file. Regenerating the folder from Nordic-Slot-Dark-Icons: scripts/icon-theme-build.sh. Idempotent.
set -eu
src="$(cd "$(dirname "$0")/.." && pwd)/icons/Filigrane-Icons"
dest="$HOME/.local/share/icons/Filigrane-Icons"
[ -f "$src/index.theme" ] || { echo "icon-theme: $src introuvable" >&2; exit 1; }
mkdir -p "$HOME/.local/share/icons"
rm -rf "$dest"
cp -a "$src" "$dest"
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -f -t "$dest" || true
rm -rf "$HOME/.cache/fili-file/tint"
echo "icon-theme: $dest ($(du -sh "$dest" | cut -f1))"
