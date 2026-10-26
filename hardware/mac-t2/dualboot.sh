#!/bin/bash
# Double démarrage sur un volume LUKS + btrfs partagé (ex. Omarchy à côté), démarré par Limine.
# À lancer dans le système Void (ou son chroot), en root. Idempotent.
#
#   ./dualboot.sh [--dry-run]
#
# Écrit, avec les UUID détectés à l'exécution (rien d'identifiant dans le dépôt):
#   /etc/fstab                       racine, home, ancien home, swapfile, ESP
#   /etc/dracut.conf.d/10-dualboot.conf  initramfs hostonly avec crypt, btrfs
# Hibernation désactivée (nohibernate): image fragile sur Mac T2, et dangereuse si l'autre système
# démarre sur le même btrfs pendant qu'un système est hiberné. Le swapfile sert de swap seulement.
#   /etc/kernel/cmdline              paramètres de démarrage (lus par limine-void)
# Installe limine-void, t2-rollback, void-update (/usr/local/sbin), les hooks noyau
# /etc/kernel.d/post-{install,remove}/60-limine-void et la config snapper "root" (@void),
# puis synchronise les noyaux et l'entrée "Void Linux" sur l'ESP (limine-void sync).
# Les paramètres de cmdline non gérés ici (ex. ceux de setup.sh) sont conservés.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
HOME_SUBVOL="${HOME_SUBVOL:-@home-void}"
OTHER_HOME_SUBVOL="${OTHER_HOME_SUBVOL:-@home}"     # home de l'autre système, vide = pas monté
OTHER_HOME_MNT="${OTHER_HOME_MNT:-/mnt/omarchy-home}"
SWAP_SUBVOL="${SWAP_SUBVOL:-@swap}"
SWAP_SIZE="${SWAP_SIZE:-16g}"
ESP_MNT="${ESP_MNT:-/boot/efi}"
# Disposition du clavier au prompt LUKS: doit être celle avec laquelle la phrase de passe a été définie
LUKS_KEYMAP="${LUKS_KEYMAP:-us}"
# Démarrage silencieux avec écran Plymouth (system/plymouth) pour le prompt LUKS. BOOT_QUIET="" pour tout voir.
BOOT_QUIET="${BOOT_QUIET-quiet splash loglevel=3 rd.udev.log_level=3}"
OPTS="noatime,compress=zstd:3,ssd,space_cache=v2"

DRY=0
[ "${1:-}" = --dry-run ] && DRY=1
[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"

die() { echo "[dualboot] $*" >&2; exit 1; }
put() { # put FICHIER : écrit stdin dans FICHIER (ou l'affiche en --dry-run)
    if [ "$DRY" -eq 1 ]; then echo "--- $1"; cat; return; fi
    mkdir -p "$(dirname "$1")"
    [ -f "$1" ] && [ ! -f "$1.orig" ] && cp -a "$1" "$1.orig"
    cat > "$1.tmp" && mv "$1.tmp" "$1"
}

[ "$(findmnt -no FSTYPE /)" = btrfs ] || die "la racine n'est pas en btrfs"
ROOT_SRC="$(findmnt -no SOURCE / | sed 's/\[.*//')"
ROOT_SUBVOL="$(findmnt -no FSROOT /)"
FS_UUID="$(blkid -s UUID -o value "$ROOT_SRC")"
MAPPER="${ROOT_SRC#/dev/mapper/}"
[ "$MAPPER" != "$ROOT_SRC" ] || die "la racine n'est pas sur un volume chiffré (/dev/mapper)"
LUKS_DEV="$(cryptsetup status "$MAPPER" | awk '$1 == "device:" {print $2}')"
LUKS_UUID="$(cryptsetup luksUUID "$LUKS_DEV")"
ESP_UUID="$(findmnt -no UUID "$ESP_MNT")" || die "ESP non montée sur $ESP_MNT"
[ -n "$FS_UUID" ] && [ -n "$LUKS_UUID" ] && [ -n "$ESP_UUID" ] || die "UUID introuvable"
echo "[dualboot] racine $ROOT_SUBVOL sur $LUKS_DEV, ESP sur $ESP_MNT"

{
    echo "# Généré par filigrane/hardware/mac-t2/dualboot.sh"
    echo "UUID=$FS_UUID  /                btrfs  subvol=$ROOT_SUBVOL,$OPTS  0 0"
    echo "UUID=$FS_UUID  /home            btrfs  subvol=/$HOME_SUBVOL,$OPTS  0 0"
    [ -n "$OTHER_HOME_SUBVOL" ] && \
    echo "UUID=$FS_UUID  $OTHER_HOME_MNT  btrfs  subvol=/$OTHER_HOME_SUBVOL,$OPTS  0 0"
    echo "UUID=$FS_UUID  /swap            btrfs  subvol=/$SWAP_SUBVOL,noatime,ssd,space_cache=v2  0 0"
    echo "/swap/swapfile none             swap   defaults  0 0"
    echo "UUID=$ESP_UUID  $ESP_MNT  vfat  umask=0077  0 2"
    echo "tmpfs          /tmp             tmpfs  defaults,nosuid,nodev  0 0"
} | put /etc/fstab

if [ "$DRY" -eq 0 ]; then
    mkdir -p /swap "$OTHER_HOME_MNT"
    mountpoint -q /swap || mount /swap
    if [ ! -f /swap/swapfile ]; then
        chattr +C /swap
        btrfs filesystem mkswapfile --size "$SWAP_SIZE" /swap/swapfile
    fi
fi

put /etc/dracut.conf.d/10-dualboot.conf <<'EOF'
# Généré par filigrane/hardware/mac-t2/dualboot.sh
hostonly="yes"
hostonly_cmdline="no"
add_dracutmodules+=" crypt btrfs plymouth "
omit_dracutmodules+=" resume "
compress="zstd"
EOF
# Clavier du prompt LUKS: dracut copie sinon le KEYMAP de rc.conf (ex. fr-bepo) dans l'initramfs.
# Sans le module i18n, la console garde la disposition us intégrée au noyau.
if [ "$LUKS_KEYMAP" = us ]; then
    echo 'omit_dracutmodules+=" i18n "' | put /etc/dracut.conf.d/11-luks-keymap.conf
else
    echo 'i18n_vars="/etc/vconsole.conf:KEYMAP"' | put /etc/dracut.conf.d/11-luks-keymap.conf
    echo "KEYMAP=$LUKS_KEYMAP" | put /etc/vconsole.conf
fi

# Paramètres gérés ici (remplacés à chaque passage); les autres sont conservés
MANAGED='^(rd\.luks\.uuid|root|rootflags|rootfstype|resume|resume_offset|rd\.vconsole\.keymap|rw|ro|quiet|splash|loglevel|rd\.udev\.log_level|nohibernate)(=|$)'
keep=""
if [ -f /etc/kernel/cmdline ]; then
    for p in $(cat /etc/kernel/cmdline); do
        [[ "$p" =~ $MANAGED || " $keep " == *" $p "* ]] || keep="$keep $p"   # sans doublons
    done
fi
echo "rd.luks.uuid=$LUKS_UUID root=/dev/mapper/luks-$LUKS_UUID rootflags=subvol=$ROOT_SUBVOL rootfstype=btrfs rw nohibernate rd.vconsole.keymap=$LUKS_KEYMAP${BOOT_QUIET:+ $BOOT_QUIET}$keep" \
    | put /etc/kernel/cmdline

echo "[dualboot] fstab, dracut et /etc/kernel/cmdline à jour (hibernation désactivée)"

[ "$DRY" -eq 1 ] && exit 0

echo "[dualboot] outils, hooks noyau, snapper"
xbps-install -y $(sed -e 's/#.*//' "$ROOT/packages/dualboot.txt" | xargs) >/dev/null || true
for t in limine-void t2-rollback void-update; do
    install -m 0755 "$HERE/$t" "/usr/local/sbin/$t"
done
for d in post-install post-remove; do
    mkdir -p "/etc/kernel.d/$d"
    cat > "/etc/kernel.d/$d/60-limine-void" <<'EOF'
#!/bin/sh
# filigrane: noyaux et entrée Limine sur l'ESP ($1 = paquet, $2 = version). Non bloquant.
/usr/local/sbin/limine-void sync || echo "AVERTISSEMENT: limine-void sync a échoué, l'ESP n'est pas à jour" >&2
exit 0
EOF
    chmod 0755 "/etc/kernel.d/$d/60-limine-void"
done

if [ ! -f /etc/snapper/configs/root ]; then
    snapper --no-dbus -c root create-config /
fi
# Pas d'instantanés horaires (pas de cron): seulement avant/après void-update, 10 gardés
snapper --no-dbus -c root set-config TIMELINE_CREATE=no NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=5

# Écran de démarrage Plymouth: invite de passphrase LUKS avec points, puis session en autologin
if [[ " $BOOT_QUIET " == *" splash "* ]]; then
    echo "[dualboot] Plymouth (thème filigrane) et initramfs du noyau courant"
    SKIP_LIMINE_SYNC=1 "$ROOT/system/plymouth/install.sh"
fi

if [ -f "$ESP_MNT/limine.conf" ]; then
    ESP="$ESP_MNT" /usr/local/sbin/limine-void sync
else
    echo "[dualboot] $ESP_MNT/limine.conf absent: entrée Limine non créée"
fi
