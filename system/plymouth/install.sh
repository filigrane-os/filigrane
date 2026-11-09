#!/bin/sh
# Installs the Filigrane Plymouth theme and regenerates the initramfs of the current kernel (root).
# Usage: system/plymouth/install.sh as root   (also called by hardware/mac-t2/dualboot.sh)
set -eu
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
DIR="$(cd "$(dirname "$0")" && pwd)"
xbps-query plymouth >/dev/null 2>&1 || xbps-install -y plymouth >/dev/null
install -d /usr/share/plymouth/themes/filigrane /etc/plymouth
install -m 0644 "$DIR"/filigrane/* /usr/share/plymouth/themes/filigrane/
install -m 0644 "$DIR/plymouthd.conf" /etc/plymouth/plymouthd.conf
rm -rf /usr/share/plymouth/themes/void  # old theme (replaced by filigrane)
dracut --force --kver "$(uname -r)"
# T2 Mac (Limine): copy of the new initramfs onto the ESP
# (dualboot.sh does the sync itself: SKIP_LIMINE_SYNC=1)
if [ -z "${SKIP_LIMINE_SYNC:-}" ] && [ -x /usr/local/sbin/limine-void ]; then /usr/local/sbin/limine-void sync; fi
echo "Thème Plymouth: $(plymouth-set-default-theme 2>/dev/null || grep Theme= /etc/plymouth/plymouthd.conf)"
