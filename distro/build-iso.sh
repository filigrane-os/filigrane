#!/bin/bash
# Live ISO of the distribution (console, x86_64 UEFI and BIOS) with void-mklive, the official Void tool:
# Void base + embedded repository (distro/out/repo) + generic copy of the repository (without users/) + <distro>-install installer.
# The installation downloads the rest from the Void mirrors (no offline copy of the 650 packages).
# distro/build-repo.sh, then distro/build-iso.sh as root
# Host tools (mklive.sh does not check them): kmod lzo liblz4 dosfstools e2fsprogs squashfs-tools xorriso
# SERIAL=1: console and login on the serial port as well (boot test in QEMU, CI).
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
# Files tracked by git (local changes included), without the personal layers
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
# Live packages: what the installer uses (disk tools, git, curl) and the native tools
(cd "$MK" && ./mklive.sh -a "$ARCH" -r "$REPO" -r "$VOID_REPO" \
    -p "git curl parted dosfstools e2fsprogs wpa_supplicant $DISTRO-apps" \
    -I "$INC" -S "$services" -C "$cmdline" -T "$DISTRO_TITLE" -o "$iso")
echo "ISO: $iso ($(du -h "$iso" | cut -f1))"
