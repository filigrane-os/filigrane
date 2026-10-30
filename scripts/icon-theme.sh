#!/bin/sh
# Construit le thème d'icônes « Filigrane-Icons » (~/.local/share/icons) à partir de Nordic-Slot-Dark-Icons: seulement les
# dossiers (places/scalable), les glyphes (places/16, places/symbolic, mimetypes/symbolic), file.svg (icône des fichiers) et les dossiers à la couleur
# d'accentuation (folder-accent-<accent>.svg, folder-dark-default.svg, folder-light-default.svg, choisis par fili-file).
# Le reste (types de fichiers, applications) vient d'Adwaita puis hicolor. Papirus n'est plus utilisé.
# Usage: icon-theme.sh [dossier ou archive .tar.xz de Nordic-Slot-Dark-Icons]
# Sans argument: ~/.local/share/icons/Nordic-Slot-Dark-Icons, sinon ~/Downloads/Nordic-Slot-Dark-Icons.tar.xz.
# Sans source (installation neuve), ne fait rien: le thème n'est pas dans le dépôt (licence à confirmer) et fili-file
# retombe sur Adwaita. Idempotent.
set -eu
dest="$HOME/.local/share/icons/Filigrane-Icons"
src="${1:-}"
[ -n "$src" ] || for c in "$HOME/.local/share/icons/Nordic-Slot-Dark-Icons" "$HOME/Downloads/Nordic-Slot-Dark-Icons.tar.xz"; do
    [ -e "$c" ] && { src=$c; break; }
done
[ -n "$src" ] || { echo "icon-theme: source Nordic-Slot-Dark-Icons introuvable, thème Filigrane-Icons non construit" >&2; exit 0; }
tmp=
trap '[ -z "$tmp" ] || rm -rf "$tmp"' EXIT
if [ -f "$src" ]; then
    tmp=$(mktemp -d)
    tar -C "$tmp" -xJf "$src" 2>/dev/null
    src="$tmp/Nordic-Slot-Dark-Icons"
fi
[ -f "$src/places/scalable/folder-blue.svg" ] || { echo "icon-theme: $src n'est pas Nordic-Slot-Dark-Icons" >&2; exit 1; }

rm -rf "$dest"
mkdir -p "$dest/places" "$dest/mimetypes/scalable" "$dest/devices/symbolic"
cp -a "$src/places/scalable" "$src/places/16" "$src/places/symbolic" "$dest/places/"
cp -a "$src/mimetypes/symbolic" "$dest/mimetypes/"
# Icône par défaut d'un fichier (file.svg) et glyphes des appareils
cp "$src/mimetypes/scalable/application-x-generic.svg" "$dest/mimetypes/scalable/file.svg"
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
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -f -t "$dest" || true
rm -rf "$HOME/.cache/fili-file/tint"
echo "icon-theme: $dest ($(du -sh "$dest" | cut -f1))"
