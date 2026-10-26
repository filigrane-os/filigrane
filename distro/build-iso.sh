#!/bin/bash
# ISO live de la distribution (console, x86_64 UEFI et BIOS) avec void-mklive, l'outil officiel de Void:
# base Void + dépôt embarqué (distro/out/repo) + copie générique du dépôt (sans users/) + installateur <distro>-install.
# L'installation télécharge le reste depuis les miroirs Void (pas de copie hors ligne des 650 paquets).
#
#   distro/build-repo.sh && sudo distro/build-iso.sh
#
# Outils de l'hôte (mklive.sh ne les vérifie pas): kmod lzo liblz4 dosfstools e2fsprogs squashfs-tools xorriso
#
# SERIAL=1: console et connexion sur le port série en plus (test de démarrage dans QEMU, CI).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=distro/distro.env
source "$ROOT/distro/distro.env"
[ "$(id -u)" -eq 0 ] || { echo "Lancer en root (void-mklive monte et chroote)" >&2; exit 1; }
ARCH="${ARCH:-x86_64}"
OUT="$ROOT/distro/out"
REPO="$OUT/repo"
[ -f "$REPO/$ARCH-repodata" ] || { echo "Dépôt absent: lancer distro/build-repo.sh d'abord" >&2; exit 1; }

MK="$OUT/void-mklive"
[ -d "$MK/.git" ] || git clone -q "$MKLIVE_GIT" "$MK"
git -C "$MK" fetch -q origin "$MKLIVE_REF"
git -C "$MK" checkout -q FETCH_HEAD
echo "void-mklive $(git -C "$MK" rev-parse --short HEAD)"

INC="$(mktemp -d)"
trap 'rm -rf "$INC"' EXIT
SRC="$INC/usr/share/$DISTRO/filigrane"
mkdir -p "$SRC" "$INC/usr/bin" "$INC/etc"
# Fichiers suivis par git (modifications locales comprises), sans les couches personnelles
(cd "$ROOT" && git ls-files -z --cached --others --exclude-standard | grep -zv '^users/' | tar --null -T - -cf -) | tar -xf - -C "$SRC"
mkdir -p "$SRC/distro/out"
cp -a "$REPO" "$SRC/distro/out/repo"
sed "s|^SRC=.*|SRC=\"\${SRC:-/usr/share/$DISTRO/filigrane}\"|" "$ROOT/distro/live/install" > "$INC/usr/bin/$DISTRO-install"
chmod 755 "$INC/usr/bin/$DISTRO-install"
cat > "$INC/etc/motd" <<EOF

  $DISTRO_TITLE, session live.
  Installer sur un disque: $DISTRO-install (réseau requis; Wi-Fi: voir le message de l'installateur)
  Budget ressources du live: budget

EOF

services="dhcpcd wpa_supplicant"
cmdline="live.autologin"
if [ "${SERIAL:-0}" = 1 ]; then
    services="$services agetty-ttyS0"
    cmdline="$cmdline console=tty0 console=ttyS0,115200"
fi
iso="$OUT/$DISTRO-live-$ARCH-$(date +%Y%m%d).iso"
# Paquets du live: ce qu'utilise install-void.sh (parted, mkfs, git, curl) et les outils natifs
(cd "$MK" && ./mklive.sh -a "$ARCH" -r "$REPO" -r "$VOID_REPO" \
    -p "git curl parted dosfstools e2fsprogs wpa_supplicant $DISTRO-apps" \
    -I "$INC" -S "$services" -C "$cmdline" -T "$DISTRO_TITLE" -o "$iso")
echo "ISO: $iso ($(du -h "$iso" | cut -f1))"
