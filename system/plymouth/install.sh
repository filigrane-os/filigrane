#!/bin/sh
# Installe le thème Plymouth Filigrane et régénère l'initramfs du noyau courant (root).
# Usage: sudo system/plymouth/install.sh   (appelé aussi par hardware/mac-t2/dualboot.sh)
set -eu
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
DIR="$(cd "$(dirname "$0")" && pwd)"
xbps-query plymouth >/dev/null 2>&1 || xbps-install -y plymouth >/dev/null
install -d /usr/share/plymouth/themes/filigrane /etc/plymouth
install -m 0644 "$DIR"/filigrane/* /usr/share/plymouth/themes/filigrane/
install -m 0644 "$DIR/plymouthd.conf" /etc/plymouth/plymouthd.conf
rm -rf /usr/share/plymouth/themes/void  # ancien thème (remplacé par filigrane)
dracut --force --kver "$(uname -r)"
# Mac T2 (Limine): copie du nouvel initramfs sur l'ESP
# (dualboot.sh fait la synchro lui-même: SKIP_LIMINE_SYNC=1)
if [ -z "${SKIP_LIMINE_SYNC:-}" ] && [ -x /usr/local/sbin/limine-void ]; then /usr/local/sbin/limine-void sync; fi
echo "Thème Plymouth: $(plymouth-set-default-theme 2>/dev/null || grep Theme= /etc/plymouth/plymouthd.conf)"
