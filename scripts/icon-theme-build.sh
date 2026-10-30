#!/bin/sh
# Régénère icons/Filigrane-Icons (dans le dépôt, GPL v3) à partir de Nordic-Slot-Dark-Icons: seulement les
# dossiers (places/scalable), les glyphes (places/16, places/symbolic, mimetypes/symbolic), file.svg (icône des fichiers) et les dossiers à la couleur
# d'accentuation (folder-accent-<accent>.svg, folder-dark-default.svg, folder-light-default.svg, choisis par fili-file).
# Le reste (types de fichiers, applications) vient d'Adwaita puis hicolor. Papirus n'est plus utilisé.
# Seulement pour mettre à jour le thème: l'installation (scripts/icon-theme.sh) copie icons/Filigrane-Icons tel quel.
# COPYING, README.md et mimetypes/scalable/file.svg (icône des fichiers, dessin propre à Filigrane) du dossier sont conservés.
# Usage: icon-theme.sh [dossier ou archive .tar.xz de Nordic-Slot-Dark-Icons]
# Sans argument: ~/.local/share/icons/Nordic-Slot-Dark-Icons, sinon ~/Downloads/Nordic-Slot-Dark-Icons.tar.xz.
# Idempotent.
set -eu
dest="$(cd "$(dirname "$0")/.." && pwd)/icons/Filigrane-Icons"
src="${1:-}"
[ -n "$src" ] || for c in "$HOME/.local/share/icons/Nordic-Slot-Dark-Icons" "$HOME/Downloads/Nordic-Slot-Dark-Icons.tar.xz"; do
    [ -e "$c" ] && { src=$c; break; }
done
[ -n "$src" ] || { echo "icon-theme-build: source Nordic-Slot-Dark-Icons introuvable" >&2; exit 1; }
tmp=
trap '[ -z "$tmp" ] || rm -rf "$tmp"' EXIT
if [ -f "$src" ]; then
    tmp=$(mktemp -d)
    tar -C "$tmp" -xJf "$src" 2>/dev/null
    src="$tmp/Nordic-Slot-Dark-Icons"
fi
[ -f "$src/places/scalable/folder-blue.svg" ] || { echo "icon-theme-build: $src n'est pas Nordic-Slot-Dark-Icons" >&2; exit 1; }

mkdir -p "$dest"
keep=
[ -f "$dest/mimetypes/scalable/file.svg" ] && { keep=$(mktemp); cp "$dest/mimetypes/scalable/file.svg" "$keep"; }
find "$dest" -mindepth 1 -maxdepth 1 ! -name COPYING ! -name README.md -exec rm -rf {} +
mkdir -p "$dest/places" "$dest/mimetypes/scalable" "$dest/devices/symbolic"
cp -a "$src/places/scalable" "$src/places/16" "$src/places/symbolic" "$dest/places/"
cp -a "$src/mimetypes/symbolic" "$dest/mimetypes/"
# Icône par défaut d'un fichier (file.svg, celle du dépôt si elle existe, sinon application-x-generic de Nordic) et glyphes des appareils
if [ -n "$keep" ]; then mv "$keep" "$dest/mimetypes/scalable/file.svg"; else cp "$src/mimetypes/scalable/application-x-generic.svg" "$dest/mimetypes/scalable/file.svg"; fi
for n in computer drive-harddisk drive-removable-media; do cp "$src/devices/symbolic/$n-symbolic.svg" "$dest/devices/symbolic/"; done
d="$dest/places/scalable"
# Variantes de Nordic les plus proches de chaque teinte (voir FiliTheme.qml, accentTones)
for pair in voile:blue ardoise:grey sauge:green sable:yellow cendre:red; do
    cp "$d/folder-${pair#*:}.svg" "$d/folder-accent-${pair%%:*}.svg"
done
# brume (presque blanc): pas de variante en scalable, recoloration de folder-blue (devant, derrière)
sed -e 's/#5e81ac/#dbe7f4/g' -e 's/#456487/#a9b8c8/g' "$d/folder-blue.svg" > "$d/folder-accent-brume.svg"
# Accent par défaut: brume en sombre, noir en clair
cp "$d/folder-accent-brume.svg" "$d/folder-dark-default.svg"
cp "$d/folder-black.svg" "$d/folder-light-default.svg"

cat > "$dest/index.theme" <<'EOF'
[Icon Theme]
Name=Filigrane-Icons
Comment=Dossiers et glyphes de Filigrane (d'après Nordic-Slot-Dark-Icons), le reste d'Adwaita
Inherits=Adwaita,hicolor
Directories=places/scalable,places/16,places/symbolic,mimetypes/scalable,mimetypes/symbolic,devices/symbolic

[places/scalable]
Size=48
MinSize=16
MaxSize=512
Type=Scalable
Context=Places

[places/16]
Size=16
Type=Fixed
Context=Places

[places/symbolic]
Size=16
MinSize=16
MaxSize=512
Type=Scalable
Context=Places

[mimetypes/scalable]
Size=48
MinSize=16
MaxSize=512
Type=Scalable
Context=MimeTypes

[devices/symbolic]
Size=16
MinSize=16
MaxSize=512
Type=Scalable
Context=Devices

[mimetypes/symbolic]
Size=16
MinSize=16
MaxSize=512
Type=Scalable
Context=MimeTypes
EOF
echo "icon-theme-build: $dest ($(du -sh "$dest" | cut -f1))"
