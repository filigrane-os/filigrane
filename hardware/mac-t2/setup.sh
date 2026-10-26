#!/bin/bash
# Support des Mac Intel à puce T2 (MacBook Pro/Air 2018-2020, Mac mini 2018, iMac 2020, iMac Pro, Mac Pro 2019).
# Approche inspirée d'Omarchy (install/hardware/apple/fix-t2.sh), adaptée à Void:
# xbps + DKMS (pas de noyau linux-t2), dracut, GRUB ou Limine (/etc/kernel/cmdline), runit.
#
#   ./setup.sh [--check] [--only dkms|touchbar|smc|trackpad|keys|boot|audio|fan|sleeplog|net|tools]
#
# --check: affiche si une puce T2 est détectée (code 0 = oui) puis quitte.
# Appelé automatiquement par bootstrap.sh quand la machine est mac-t2 (détectée, ou forcée avec --machine).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

# Pilotes t2bce (clavier, trackpad, audio): successeur d'apple-bce, épinglé pour la reproductibilité
T2BCE_REPO="https://github.com/AdityaGarg8/t2bce"
T2BCE_REF="d493b0696b133ef2a3e2192790758180d62886b0"
T2BCE_VER="0.0+git${T2BCE_REF:0:7}"
# Pilotes Touch Bar hors arbre (hid-appletb-kbd/bl, appletbdrm), voir appletb/: incrémenter si SHA256SUMS change
APPLETB_VER="2"
# applesmc avec le SMC T2 (ventilateurs), voir applesmc/: celui du noyau Void bloque le démarrage
APPLESMC_VER="1"
# Trackpad multitouch (hid-apple + hid-magicmouse T2), voir trackpad/: sans lui, trackpad = simple souris
TRACKPAD_VER="1"
# Fn et Ctrl gauche inversés (clavier interne)
HID_APPLE_OPTS="swap_fn_leftctrl=1"
# Démon de ventilateurs (GPL-3.0), compilé avec cargo
FAN_REPO="https://github.com/GnomedDev/T2FanRD"
FAN_REF="48baf962697ec3d4d969c74cf601ee8e15b7aeaa"
# DSP haut-parleurs d'Asahi (asahi-audio, GPL-2.0/MIT): FIR du MacBook Pro 13" M1 (j293), même châssis que MacBookPro16,2
ASAHI_AUDIO_REPO="https://github.com/AsahiLinux/asahi-audio"
ASAHI_AUDIO_REF="ab1b46928d056bb02bb4ad72d522dab57dc9efe1"
# Script officiel t2linux (licence MIT) pour récupérer le firmware Wi-Fi/Bluetooth
FIRMWARE_URL="https://wiki.t2linux.org/tools/firmware.sh"

# Paramètres noyau (Omarchy): IOMMU, veille profonde stable avec t2bce
KERNEL_PARAMS=(intel_iommu=on iommu=pt pm_async=off mem_sleep_default=deep rd.luks.allow-discards)
# wpa_supplicant >= 2.11 casse le Wi-Fi Broadcom (t2linux): contournement côté pilote
WIFI_PARAM="brcmfmac.feature_disable=0x82000"

log() { printf '\n[t2] %s\n' "$*"; }
warn() { printf '[t2] AVERTISSEMENT: %s\n' "$*" >&2; }

# Via sysfs (lspci n'est pas forcément installé avant setup_packages)
is_t2() {
    local d
    for d in /sys/bus/pci/devices/*; do
        [ "$(cat "$d/vendor" 2>/dev/null)" = 0x106b ] || continue
        case "$(cat "$d/device" 2>/dev/null)" in 0x1801|0x1802) return 0 ;; esac
    done
    return 1
}

ONLY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --check)
            if is_t2; then echo "Puce T2 détectée"; exit 0; else echo "Pas de puce T2"; exit 1; fi ;;
        --only) ONLY="${2:?}"; shift 2 ;;
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
        *) echo "Option inconnue: $1" >&2; exit 1 ;;
    esac
done

[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"
want() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }

read_list() { sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$1" | grep -v '^$' || true; }

# Récupère une révision précise sans l'historique complet
fetch_ref() { # fetch_ref DEPOT REF DESTINATION
    local repo="$1" ref="$2" dest="$3" tmp
    tmp="$(mktemp -d)"
    git -C "$tmp" init -q
    git -C "$tmp" remote add origin "$repo"
    git -C "$tmp" fetch -q --depth 1 origin "$ref"
    git -C "$tmp" checkout -q FETCH_HEAD
    rm -rf "$tmp/.git"
    mkdir -p "$(dirname "$dest")"
    rm -rf "$dest"
    mv "$tmp" "$dest"
}

setup_packages() {
    log "Paquets (dkms, en-têtes noyau, alsa-ucm-conf, outils firmware)"
    xbps-install -y $(read_list "$ROOT/packages/mac-t2.txt")
}

installed_kernels() { # versions dont les en-têtes sont présents
    local d
    for d in /lib/modules/*/build; do
        [ -e "$d" ] && basename "$(dirname "$d")"
    done
}

setup_dkms() {
    log "Pilotes t2bce via DKMS ($T2BCE_VER)"
    local src="/usr/src/t2bce-$T2BCE_VER" k
    [ -d "$src" ] || fetch_ref "$T2BCE_REPO" "$T2BCE_REF" "$src"

    # Le dépôt amont n'a pas de dkms.conf: on construit les 4 modules dans l'ordre des dépendances
    cat > "$src/dkms.conf" <<EOF
PACKAGE_NAME="t2bce"
PACKAGE_VERSION="$T2BCE_VER"
AUTOINSTALL="yes"
MAKE[0]="make -C t2bce_dma KVERSION=\${kernelver} && make -C t2bce_core KVERSION=\${kernelver} T2BCE_DMA_SRC=../t2bce_dma && make -C t2bce_vhci KVERSION=\${kernelver} T2BCE_CORE_SRC=../t2bce_core && make -C t2bce_audio KVERSION=\${kernelver} T2BCE_CORE_SRC=../t2bce_core"
CLEAN="make -C t2bce_audio clean; make -C t2bce_vhci clean; make -C t2bce_core clean; make -C t2bce_dma clean"
BUILT_MODULE_NAME[0]="t2bce_dma"
BUILT_MODULE_LOCATION[0]="t2bce_dma/"
DEST_MODULE_LOCATION[0]="/extra/t2bce"
BUILT_MODULE_NAME[1]="t2bce_core"
BUILT_MODULE_LOCATION[1]="t2bce_core/"
DEST_MODULE_LOCATION[1]="/extra/t2bce"
BUILT_MODULE_NAME[2]="t2bce_vhci"
BUILT_MODULE_LOCATION[2]="t2bce_vhci/"
DEST_MODULE_LOCATION[2]="/extra/t2bce"
BUILT_MODULE_NAME[3]="t2bce_audio"
BUILT_MODULE_LOCATION[3]="t2bce_audio/"
DEST_MODULE_LOCATION[3]="/extra/t2bce"
EOF

    dkms status -m t2bce -v "$T2BCE_VER" 2>/dev/null | grep -E 'added|built|installed' >/dev/null \
        || dkms add -m t2bce -v "$T2BCE_VER"
    local found=0
    for k in $(installed_kernels); do
        found=1
        if dkms status -m t2bce -v "$T2BCE_VER" -k "$k" 2>/dev/null | grep -E 'installed' >/dev/null; then
            echo "t2bce déjà installé pour $k"
        else
            dkms install -m t2bce -v "$T2BCE_VER" -k "$k"
        fi
    done
    [ "$found" -eq 1 ] || warn "aucun noyau avec en-têtes trouvé (paquet linux-headers ?)"
}

cmdline_add() { # cmdline_add PARAM : ajoute à GRUB_CMDLINE_LINUX_DEFAULT s'il manque
    local p="$1" key="${1%%=*}"
    grep -E "^GRUB_CMDLINE_LINUX_DEFAULT=.*[\" ]${key}([= \"])" /etc/default/grub >/dev/null && return 0
    sed -i -E "s|^(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*)\"|\1 ${p}\"|" /etc/default/grub
}

kcmdline_add() { # kcmdline_add PARAM : ajoute à /etc/kernel/cmdline (Limine, dualboot.sh) s'il manque
    local p="$1" key="${1%%=*}"
    grep -E "(^| )${key}(=| |$)" /etc/kernel/cmdline >/dev/null && return 0
    sed -i -E "1s|\$| ${p}|" /etc/kernel/cmdline
}

setup_boot() {
    log "Chargement des modules, initramfs et paramètres noyau"
    mkdir -p /etc/modules-load.d /etc/dracut.conf.d
    cat > /etc/modules-load.d/t2.conf <<'EOF'
# Clavier/trackpad internes (USB virtuel via t2bce) et audio.
# applesmc, hid_appletb_bl/kbd (Touch Bar) et le Bluetooth sont chargés par udev (ACPI/USB):
# les forcer ici, avant udev, bloque le démarrage sous runit.
t2bce_vhci
t2bce_audio
EOF
    # Clavier disponible dès l'initramfs (add_drivers: ignoré proprement si un module manque)
    cat > /etc/dracut.conf.d/t2.conf <<'EOF'
add_drivers+=" t2bce_dma t2bce_core t2bce_vhci usbhid hid_apple hid_generic xhci_pci xhci_hcd "
EOF
    # Options du clavier interne (copiées dans l'initramfs par dracut, hid_apple y est chargé)
    echo "options hid_apple $HID_APPLE_OPTS" > /etc/modprobe.d/hid_apple.conf

    if [ -f /etc/kernel/cmdline ]; then
        local p
        for p in "${KERNEL_PARAMS[@]}"; do kcmdline_add "$p"; done
        if [ -d /etc/sv/wpa_supplicant ] && [ -e /etc/runit/runsvdir/default/wpa_supplicant ]; then
            kcmdline_add "$WIFI_PARAM"
        fi
        cat /etc/kernel/cmdline | sed -E 's/[0-9a-fA-F]{8}-[0-9a-fA-F-]{27}/<UUID>/g'
    elif [ -f /etc/default/grub ]; then
        local p
        for p in "${KERNEL_PARAMS[@]}"; do cmdline_add "$p"; done
        if xbps-query wpa_supplicant >/dev/null 2>&1; then cmdline_add "$WIFI_PARAM"; fi
        grep GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub
        if [ -d /boot/grub ] && command -v grub-mkconfig >/dev/null; then
            grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | tail -1
        fi
    else
        warn "ni /etc/kernel/cmdline ni /etc/default/grub: ajouter à la main ${KERNEL_PARAMS[*]}"
    fi

    command -v dracut >/dev/null && dracut --force --regenerate-all 2>&1 | tail -2 || true
    # Double démarrage Limine: recopier les initramfs régénérés sur l'ESP
    if [ -x /usr/local/sbin/limine-void ]; then /usr/local/sbin/limine-void sync || warn "limine-void sync a échoué"; fi
}

setup_touchbar() {
    log "Pilotes Touch Bar via DKMS (appletb $APPLETB_VER)"
    local src="/usr/src/appletb-$APPLETB_VER" k
    # anciennes versions retirées (une seule version installée par noyau)
    dkms status -m appletb 2>/dev/null | sed -nE 's|^appletb/([^,]+),.*|\1|p' | sort -u | while read -r v; do
        [ "$v" = "$APPLETB_VER" ] || dkms remove -m appletb -v "$v" --all || true
    done
    rm -rf "$src"
    cp -a "$HERE/appletb" "$src"
    dkms status -m appletb -v "$APPLETB_VER" 2>/dev/null | grep -E 'added|built|installed' >/dev/null \
        || dkms add -m appletb -v "$APPLETB_VER"
    for k in $(installed_kernels); do
        if dkms status -m appletb -v "$APPLETB_VER" -k "$k" 2>/dev/null | grep -E 'installed' >/dev/null; then
            echo "appletb déjà installé pour $k"
        else
            # non bloquant: sans Touch Bar, le clavier (t2bce) reste utilisable
            dkms install -m appletb -v "$APPLETB_VER" -k "$k" || warn "appletb non compilé pour $k (voir appletb/build.sh)"
        fi
    done
}

setup_smc() {
    log "applesmc pour le SMC T2 via DKMS (applesmc-t2 $APPLESMC_VER)"
    # Jamais chargé par udev: l'applesmc du noyau Void bloque "waiting for devices to settle".
    # Le service t2fanrd charge la version DKMS (/updates) après le démarrage, si elle existe.
    cat > /etc/modprobe.d/t2-applesmc.conf <<'EOF'
# filigrane: applesmc chargé par le service t2fanrd (version DKMS applesmc-t2), pas par udev
blacklist applesmc
EOF
    local src="/usr/src/applesmc-t2-$APPLESMC_VER" k
    rm -rf "$src"
    cp -a "$HERE/applesmc" "$src"
    dkms status -m applesmc-t2 -v "$APPLESMC_VER" 2>/dev/null | grep -E 'added|built|installed' >/dev/null \
        || dkms add -m applesmc-t2 -v "$APPLESMC_VER"
    for k in $(installed_kernels); do
        if dkms status -m applesmc-t2 -v "$APPLESMC_VER" -k "$k" 2>/dev/null | grep -E 'installed' >/dev/null; then
            echo "applesmc-t2 déjà installé pour $k"
        else
            dkms install -m applesmc-t2 -v "$APPLESMC_VER" -k "$k" || warn "applesmc-t2 non compilé pour $k: ventilateurs gérés par la T2 seule"
        fi
    done
}

setup_trackpad() {
    log "Trackpad multitouch via DKMS (t2-trackpad $TRACKPAD_VER)"
    local src="/usr/src/t2-trackpad-$TRACKPAD_VER" k
    rm -rf "$src"
    cp -a "$HERE/trackpad" "$src"
    dkms status -m t2-trackpad -v "$TRACKPAD_VER" 2>/dev/null | grep -E 'added|built|installed' >/dev/null \
        || dkms add -m t2-trackpad -v "$TRACKPAD_VER"
    # T2_TRACKPAD_KERNELS: limiter à certains noyaux (ex. garder le précédent intact pour un premier essai)
    for k in ${T2_TRACKPAD_KERNELS:-$(installed_kernels)}; do
        if dkms status -m t2-trackpad -v "$TRACKPAD_VER" -k "$k" 2>/dev/null | grep -E 'installed' >/dev/null; then
            echo "t2-trackpad déjà installé pour $k"
        else
            dkms install -m t2-trackpad -v "$TRACKPAD_VER" -k "$k" || warn "t2-trackpad non compilé pour $k: trackpad en mode souris"
        fi
    done
}

setup_keys() {
    log "Touche Command façon macOS (keyd)"
    # Le pilote Touch Bar (appletb >= 2) écoute le clavier virtuel de keyd: Fn et réveil restent actifs
    command -v keyd >/dev/null || xbps-install -y keyd
    mkdir -p /etc/keyd
    install -m 0644 "$HERE/keyd.conf" /etc/keyd/default.conf
    install -m 0644 "$HERE/keyd-external-azerty.conf" /etc/keyd/external-azerty.conf
    keyd check /etc/keyd/default.conf /etc/keyd/external-azerty.conf
    # Clavier virtuel de keyd déclaré interne: sinon dwt du trackpad ne réagit pas à la frappe (relu au prochain démarrage de niri)
    install -d /etc/libinput
    install -m 0644 "$HERE/libinput-keyd.quirks" /etc/libinput/local-overrides.quirks
    ln -sfn /etc/sv/keyd /etc/runit/runsvdir/default/keyd
    if [ -e /var/service/keyd ]; then sv restart /var/service/keyd 2>/dev/null || true; fi

    # Le noyau remet le rétroéclairage clavier à 0 au boot: règle udev (le LED apparaît tard, après
    # l'énumération USB de la T2, donc rc.local serait trop tôt). 3000 sur 14660 max, environ 20%.
    mkdir -p /etc/udev/rules.d
    cat > /etc/udev/rules.d/71-t2-kbd-backlight.rules <<'EOF'
# filigrane: rétroéclairage clavier allumé dès que le LED apparaît
SUBSYSTEM=="leds", ACTION=="add", KERNEL==":white:kbd_backlight", ATTR{brightness}="3000"
EOF
}

setup_audio() {
    log "Profils ALSA UCM (haut-parleurs / casque)"
    local src="/usr/src/t2bce-$T2BCE_VER"
    [ -d "$src" ] || fetch_ref "$T2BCE_REPO" "$T2BCE_REF" "$src"
    mkdir -p /usr/share/alsa/ucm2
    cp -a "$src/t2bce_audio-alsa-ucm-conf/ucm2/." /usr/share/alsa/ucm2/

    case "$(cat /sys/class/dmi/id/product_name 2>/dev/null)" in
        MacBookPro16,2) ;;
        *) return 0 ;;
    esac
    log "DSP haut-parleurs façon macOS (asahi-audio j293, bankstown, lsp-plugins)"
    local tmp
    tmp="$(mktemp -d)"
    fetch_ref "$ASAHI_AUDIO_REPO" "$ASAHI_AUDIO_REF" "$tmp/asahi-audio"
    mkdir -p /usr/share/t2-audio/j293 /usr/share/wireplumber/wireplumber.conf.d
    install -m 0644 "$tmp"/asahi-audio/firs/j293/{front,rear}-*.wav /usr/share/t2-audio/j293/
    install -m 0644 "$HERE/audio/speakers-j293.json" /usr/share/t2-audio/
    install -m 0644 "$HERE/audio/51-t2-speakers-dsp.conf" /usr/share/wireplumber/wireplumber.conf.d/
    rm -rf "$tmp"
}

setup_fan() {
    log "Ventilateurs (t2fanrd)"
    if ! command -v t2fanrd >/dev/null; then
        command -v cargo >/dev/null || { warn "cargo absent, ventilateurs non configurés"; return 0; }
        local tmp
        tmp="$(mktemp -d)"
        fetch_ref "$FAN_REPO" "$FAN_REF" "$tmp/src"
        (cd "$tmp/src" && cargo build --release --locked)
        install -m 0755 "$tmp/src/target/release/t2fanrd" /usr/local/bin/t2fanrd
        rm -rf "$tmp"
    fi
    # Une section par ventilateur détecté ; les sections en trop sont ignorées (valeurs Omarchy)
    if [ ! -f /etc/t2fand.conf ]; then
        cat > /etc/t2fand.conf <<'EOF'
[Fan1]
low_temp=55
high_temp=75
speed_curve=linear
always_full_speed=false

[Fan2]
low_temp=55
high_temp=75
speed_curve=linear
always_full_speed=false
EOF
    fi
    mkdir -p /etc/sv/t2fanrd
    cat > /etc/sv/t2fanrd/run <<'EOF'
#!/bin/sh
# applesmc est sur liste noire pour udev: charger ici la version T2 (DKMS, /updates) seulement
exec 2>&1
if ! modinfo -F filename applesmc 2>/dev/null | grep -q '/updates/'; then
    echo "applesmc-t2 absent pour $(uname -r): t2fanrd arrêté, ventilateurs gérés par la T2"
    sv down /var/service/t2fanrd
    exit 0
fi
timeout 30 modprobe applesmc || { echo "chargement d'applesmc échoué"; sleep 300; exit 1; }
exec /usr/local/bin/t2fanrd
EOF
    chmod 755 /etc/sv/t2fanrd/run
    # Journal (sinon "Found fan: FanController {...}" s'affiche sur la console au démarrage)
    mkdir -p /etc/sv/t2fanrd/log /var/log/t2fanrd
    cat > /etc/sv/t2fanrd/log/run <<'EOF'
#!/bin/sh
exec svlogd -tt /var/log/t2fanrd
EOF
    chmod 755 /etc/sv/t2fanrd/log/run
    # Au réveil, le SMC repasse les ventilateurs en automatique (fan*_manual=0): relancer t2fanrd
    mkdir -p /etc/zzz.d/resume
    cat > /etc/zzz.d/resume/50-t2fanrd <<'EOF'
#!/bin/sh
[ -e /var/service/t2fanrd ] && sv restart /var/service/t2fanrd
exit 0
EOF
    chmod 755 /etc/zzz.d/resume/50-t2fanrd
    ln -sfn /etc/sv/t2fanrd /etc/runit/runsvdir/default/t2fanrd
}

setup_sleeplog() {
    log "Journal de veille (batterie avant/après, dans le journal socklog)"
    local ev
    for ev in suspend resume; do
        mkdir -p "/etc/zzz.d/$ev"
        cat > "/etc/zzz.d/$ev/10-sleeplog" <<EOF
#!/bin/sh
# Niveau de batterie à l'entrée et à la sortie de veille: distingue batterie vidée et plantage au réveil
b=/sys/class/power_supply/BAT0
logger -t sleeplog "$ev batterie=\$(cat \$b/capacity)% etat=\$(cat \$b/status) charge=\$(cat \$b/charge_now)/\$(cat \$b/charge_full)"
exit 0
EOF
        chmod 755 "/etc/zzz.d/$ev/10-sleeplog"
    done

    log "Hooks zzz.d aussi pour la veille d'elogind (capot, menu)"
    # elogind met en veille sans passer par zzz: ses hooks system-sleep relaient vers /etc/zzz.d
    mkdir -p /usr/libexec/elogind/system-sleep
    cat > /usr/libexec/elogind/system-sleep/50-zzz.d <<'EOF'
#!/bin/sh
# filigrane: elogind appelle ce hook avec pre|post; on lance les hooks zzz.d correspondants
case "$1" in
    pre) d=/etc/zzz.d/suspend ;;
    post) d=/etc/zzz.d/resume ;;
    *) exit 0 ;;
esac
for h in "$d"/*; do [ -x "$h" ] && "$h"; done
exit 0
EOF
    chmod 755 /usr/libexec/elogind/system-sleep/50-zzz.d

    log "Cœurs secondaires arrêtés pendant la veille"
    # Au réveil S3, le noyau rallume les cœurs 1-7 en 10 à 35 s (firmware Apple): écran noir,
    # le capot semble ne pas réveiller. Arrêtés avant la veille, rallumés après: quelques ms.
    cat > /etc/zzz.d/suspend/90-cpu-offline <<'EOF'
#!/bin/sh
for c in /sys/devices/system/cpu/cpu[1-9]*/online; do echo 0 > "$c"; done
exit 0
EOF
    cat > /etc/zzz.d/resume/05-cpu-online <<'EOF'
#!/bin/sh
for c in /sys/devices/system/cpu/cpu[1-9]*/online; do echo 1 > "$c"; done
logger -t sleeplog "resume cpus=$(cat /sys/devices/system/cpu/online)"
exit 0
EOF
    chmod 755 /etc/zzz.d/suspend/90-cpu-offline /etc/zzz.d/resume/05-cpu-online
}

setup_net() {
    log "Interface USB interne de la T2 (cdc_ncm) ignorée par dhcpcd"
    # Même adresse MAC sur tous les Mac T2: nom fixe, puis exclusion de dhcpcd
    # (sinon adresse 169.254.x.x et route par défaut parasite avant le Wi-Fi)
    mkdir -p /etc/udev/rules.d
    cat > /etc/udev/rules.d/70-t2-ncm.rules <<'EOF'
# filigrane: interface Ethernet USB interne de la puce T2 (pas un vrai réseau)
SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="ac:de:48:00:11:22", NAME="t2ncm0"
EOF
    if [ -f /etc/dhcpcd.conf ] && ! grep -qE '^denyinterfaces.*t2ncm0' /etc/dhcpcd.conf; then
        printf '\n# filigrane: interface interne de la T2\ndenyinterfaces t2ncm0\n' >> /etc/dhcpcd.conf
    fi

    log "Wi-Fi Broadcom: pas de réveil de la veille"
    # Capot fermé, la machine se réveillait seule ~35 s après la mise en veille (ARPT dans
    # /proc/acpi/wakeup). Le capot (LID0) et le clavier (T2) réveillent toujours la machine.
    cat > /etc/udev/rules.d/72-t2-wifi-nowake.rules <<'EOF'
# filigrane: la carte Wi-Fi Broadcom (ARPT) ne réveille pas la machine en veille
SUBSYSTEM=="pci", ACTION=="add", ATTR{vendor}=="0x14e4", ATTR{class}=="0x028000", ATTR{power/wakeup}="disabled"
EOF
}

setup_tools() {
    log "Outil firmware Wi-Fi/Bluetooth (t2-wifi-firmware)"
    cat > /usr/local/bin/t2-wifi-firmware <<EOF
#!/bin/sh
# Télécharge et lance le script officiel t2linux (MIT) qui récupère le firmware Broadcom.
# Méthode 5 = sans macOS (télécharge l'image de récupération Apple). Dépendances: curl, dmg2img, python3.
set -e
tmp=\$(mktemp)
trap 'rm -f "\$tmp"' EXIT
curl -fsSL "$FIRMWARE_URL" -o "\$tmp"
echo "Script récupéré: $FIRMWARE_URL"
exec bash "\$tmp"
EOF
    chmod 755 /usr/local/bin/t2-wifi-firmware
}

if ! is_t2 && [ -z "${T2_FORCE:-}" ]; then
    echo "Pas de puce T2 détectée (T2_FORCE=1 pour forcer)."
    exit 0
fi

[ -z "$ONLY" ] && setup_packages  # avec --only: dkms et linux-headers doivent déjà être installés
want dkms && setup_dkms
want touchbar && setup_touchbar
want smc && setup_smc
want trackpad && setup_trackpad
want keys && setup_keys
want audio && setup_audio
want boot && setup_boot
want fan && setup_fan
want sleeplog && setup_sleeplog
want net && setup_net
want tools && setup_tools
log "Terminé. Redémarrer, puis lancer t2-wifi-firmware pour le Wi-Fi/Bluetooth."
