#!/bin/bash
# Support for Intel Macs with a T2 chip (MacBook Pro/Air 2018-2020, Mac mini 2018, iMac 2020, iMac Pro, Mac Pro 2019).
# Approach inspired by Omarchy (install/hardware/apple/fix-t2.sh), adapted to Void:
# xbps + DKMS (no linux-t2 kernel), dracut, GRUB or Limine (/etc/kernel/cmdline), runit.
# ./setup.sh [--check] [--only dkms|touchbar|smc|trackpad|keys|boot|audio|fan|sleeplog|net|tools|clock]
# --check: prints whether a T2 chip is detected (code 0 = yes) then exits.
# Called automatically by bootstrap.sh when the machine is mac-t2 (detected, or forced with --machine).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

# t2bce drivers (keyboard, trackpad, audio): successor of apple-bce, pinned for reproducibility
T2BCE_REPO="https://github.com/AdityaGarg8/t2bce"
T2BCE_REF="d493b0696b133ef2a3e2192790758180d62886b0"
T2BCE_VER="0.0+git${T2BCE_REF:0:7}"
# Out-of-tree Touch Bar drivers (hid-appletb-kbd/bl, appletbdrm), see appletb/: increment if SHA256SUMS changes
APPLETB_VER="2"
# applesmc with the T2 SMC (fans), see applesmc/: the one of the Void kernel blocks the boot
APPLESMC_VER="1"
# Trackpad multitouch (hid-apple + hid-magicmouse T2), voir trackpad/: sans lui, trackpad = simple souris
TRACKPAD_VER="2"
# Fn and left Ctrl swapped on the internal keyboard only (product 0x027e = 638; patch 9002 of trackpad/):
# an external Apple keyboard keeps its own Fn and Ctrl
HID_APPLE_OPTS="swap_fn_leftctrl=1 swap_fn_leftctrl_product=638"
# Fan daemon (GPL-3.0), built with cargo
FAN_REPO="https://github.com/GnomedDev/T2FanRD"
FAN_REF="48baf962697ec3d4d969c74cf601ee8e15b7aeaa"
# Asahi speaker DSP (asahi-audio, GPL-2.0/MIT): FIR of the MacBook Pro 13" M1 (j293), same chassis as MacBookPro16,2
ASAHI_AUDIO_REPO="https://github.com/AsahiLinux/asahi-audio"
ASAHI_AUDIO_REF="ab1b46928d056bb02bb4ad72d522dab57dc9efe1"
# Official t2linux script (MIT licence) to fetch the Wi-Fi/Bluetooth firmware
FIRMWARE_URL="https://wiki.t2linux.org/tools/firmware.sh"

# Kernel parameters (Omarchy): IOMMU, stable deep sleep with t2bce
KERNEL_PARAMS=(intel_iommu=on iommu=pt pm_async=off mem_sleep_default=deep rd.luks.allow-discards)
# wpa_supplicant >= 2.11 breaks Broadcom Wi-Fi (t2linux): workaround on the driver side
WIFI_PARAM="brcmfmac.feature_disable=0x82000"

log() { printf '\n[t2] %s\n' "$*"; }
warn() { printf '[t2] WARNING: %s\n' "$*" >&2; }

# Through sysfs (lspci is not necessarily installed before setup_packages)
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
            if is_t2; then echo "T2 chip detected"; exit 0; else echo "No T2 chip"; exit 1; fi ;;
        --only) ONLY="${2:?}"; shift 2 ;;
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"
want() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }

read_list() { sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$1" | grep -v '^$' || true; }

# Fetches a precise revision without the full history
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
    log "Packages (dkms, kernel headers, alsa-ucm-conf, firmware tools)"
    # Only the missing ones: the package manager reports each package already there as an "ERROR"
    local pkg todo=()
    for pkg in $(read_list "$ROOT/packages/mac-t2.txt"); do
        if xbps-query "$pkg" >/dev/null 2>&1; then echo "SKIP: $pkg already installed"; else todo+=("$pkg"); fi
    done
    [ ${#todo[@]} -eq 0 ] || xbps-install -y "${todo[@]}"
}

installed_kernels() { # versions whose headers are present
    local d
    for d in /lib/modules/*/build; do
        [ -e "$d" ] && basename "$(dirname "$d")"
    done
}

setup_dkms() {
    log "t2bce drivers via DKMS ($T2BCE_VER)"
    local src="/usr/src/t2bce-$T2BCE_VER" k
    [ -d "$src" ] || fetch_ref "$T2BCE_REPO" "$T2BCE_REF" "$src"

    # The upstream repository has no dkms.conf: we build the 4 modules in dependency order
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
            echo "t2bce already installed for $k"
        else
            dkms install -m t2bce -v "$T2BCE_VER" -k "$k"
        fi
    done
    [ "$found" -eq 1 ] || warn "no kernel with headers found (linux-headers package?)"
}

cmdline_add() { # cmdline_add PARAM : adds to GRUB_CMDLINE_LINUX_DEFAULT if missing
    local p="$1" key="${1%%=*}"
    grep -E "^GRUB_CMDLINE_LINUX_DEFAULT=.*[\" ]${key}([= \"])" /etc/default/grub >/dev/null && return 0
    sed -i -E "s|^(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*)\"|\1 ${p}\"|" /etc/default/grub
}

kcmdline_add() { # kcmdline_add PARAM : adds to /etc/kernel/cmdline (Limine, dualboot.sh) if missing
    local p="$1" key="${1%%=*}"
    grep -E "(^| )${key}(=| |$)" /etc/kernel/cmdline >/dev/null && return 0
    sed -i -E "1s|\$| ${p}|" /etc/kernel/cmdline
}

setup_boot() {
    log "Module loading, initramfs and kernel parameters"
    mkdir -p /etc/modules-load.d /etc/dracut.conf.d
    cat > /etc/modules-load.d/t2.conf <<'EOF'
# Internal keyboard/trackpad (virtual USB through t2bce) and audio.
# applesmc, hid_appletb_bl/kbd (Touch Bar) and Bluetooth are loaded by udev (ACPI/USB):
# forcing them here, before udev, blocks the boot under runit.
t2bce_vhci
t2bce_audio
EOF
    # Keyboard available from the initramfs (add_drivers: cleanly ignored if a module is missing)
    cat > /etc/dracut.conf.d/t2.conf <<'EOF'
add_drivers+=" t2bce_dma t2bce_core t2bce_vhci usbhid hid_apple hid_generic xhci_pci xhci_hcd "
EOF
    # Internal keyboard options (copied into the initramfs by dracut, hid_apple is loaded there)
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
        warn "neither /etc/kernel/cmdline nor /etc/default/grub: add ${KERNEL_PARAMS[*]} by hand"
    fi

    command -v dracut >/dev/null && dracut --force --regenerate-all 2>&1 | tail -2 || true
    # Limine dual boot: copy the regenerated initramfs onto the ESP
    if [ -x /usr/local/sbin/limine-void ]; then /usr/local/sbin/limine-void sync || warn "limine-void sync failed"; fi
}

setup_touchbar() {
    log "Touch Bar drivers via DKMS (appletb $APPLETB_VER)"
    local src="/usr/src/appletb-$APPLETB_VER" k
    # old versions removed (a single version installed per kernel)
    dkms status -m appletb 2>/dev/null | sed -nE 's|^appletb/([^,]+),.*|\1|p' | sort -u | while read -r v; do
        [ "$v" = "$APPLETB_VER" ] || dkms remove -m appletb -v "$v" --all || true
    done
    rm -rf "$src"
    cp -a "$HERE/appletb" "$src"
    dkms status -m appletb -v "$APPLETB_VER" 2>/dev/null | grep -E 'added|built|installed' >/dev/null \
        || dkms add -m appletb -v "$APPLETB_VER"
    for k in $(installed_kernels); do
        if dkms status -m appletb -v "$APPLETB_VER" -k "$k" 2>/dev/null | grep -E 'installed' >/dev/null; then
            echo "appletb already installed for $k"
        else
            # non-blocking: without a Touch Bar, the keyboard (t2bce) stays usable
            dkms install -m appletb -v "$APPLETB_VER" -k "$k" || warn "appletb not built for $k (see appletb/build.sh)"
        fi
    done
}

setup_smc() {
    log "applesmc for the T2 SMC via DKMS (applesmc-t2 $APPLESMC_VER)"
    # Never loaded by udev: the applesmc of the Void kernel blocks "waiting for devices to settle".
    # The t2fanrd service loads the DKMS version (/updates) after the boot, if it exists.
    cat > /etc/modprobe.d/t2-applesmc.conf <<'EOF'
# filigrane: applesmc loaded by the t2fanrd service (DKMS version applesmc-t2), not by udev
blacklist applesmc
EOF
    local src="/usr/src/applesmc-t2-$APPLESMC_VER" k
    rm -rf "$src"
    cp -a "$HERE/applesmc" "$src"
    dkms status -m applesmc-t2 -v "$APPLESMC_VER" 2>/dev/null | grep -E 'added|built|installed' >/dev/null \
        || dkms add -m applesmc-t2 -v "$APPLESMC_VER"
    for k in $(installed_kernels); do
        if dkms status -m applesmc-t2 -v "$APPLESMC_VER" -k "$k" 2>/dev/null | grep -E 'installed' >/dev/null; then
            echo "applesmc-t2 already installed for $k"
        else
            dkms install -m applesmc-t2 -v "$APPLESMC_VER" -k "$k" || warn "applesmc-t2 not built for $k: fans left to the T2 alone"
        fi
    done
}

setup_trackpad() {
    log "Multitouch trackpad via DKMS (t2-trackpad $TRACKPAD_VER)"
    local src="/usr/src/t2-trackpad-$TRACKPAD_VER" k
    rm -rf "$src"
    cp -a "$HERE/trackpad" "$src"
    dkms status -m t2-trackpad -v "$TRACKPAD_VER" 2>/dev/null | grep -E 'added|built|installed' >/dev/null \
        || dkms add -m t2-trackpad -v "$TRACKPAD_VER"
    # T2_TRACKPAD_KERNELS: restrict to some kernels (e.g. keep the previous one untouched for a first try)
    for k in ${T2_TRACKPAD_KERNELS:-$(installed_kernels)}; do
        if dkms status -m t2-trackpad -v "$TRACKPAD_VER" -k "$k" 2>/dev/null | grep -E 'installed' >/dev/null; then
            echo "t2-trackpad already installed for $k"
        else
            dkms install -m t2-trackpad -v "$TRACKPAD_VER" -k "$k" || warn "t2-trackpad not built for $k: trackpad in mouse mode"
        fi
    done
}

setup_keys() {
    log "macOS-style Command key (keyd)"
    # The Touch Bar driver (appletb >= 2) listens to the virtual keyboard of keyd: Fn and wake-up stay active
    command -v keyd >/dev/null || xbps-install -y keyd
    mkdir -p /etc/keyd
    install -m 0644 "$HERE/keyd.conf" /etc/keyd/default.conf
    install -m 0644 "$HERE/keyd-external-azerty.conf" /etc/keyd/external-azerty.conf
    keyd check /etc/keyd/default.conf /etc/keyd/external-azerty.conf
    # Virtual keyboard of keyd declared internal: otherwise the trackpad dwt does not react to typing (re-read at the next niri start)
    install -d /etc/libinput
    install -m 0644 "$HERE/libinput-keyd.quirks" /etc/libinput/local-overrides.quirks
    ln -sfn /etc/sv/keyd /etc/runit/runsvdir/default/keyd
    if [ -e /var/service/keyd ]; then sv restart /var/service/keyd 2>/dev/null || true; fi

    # The kernel resets the keyboard backlight to 0 at boot: udev rule (the LED appears late, after the
    # USB enumeration of the T2, so rc.local would be too early). 3000 out of 14660 max, about 20%.
    mkdir -p /etc/udev/rules.d
    cat > /etc/udev/rules.d/71-t2-kbd-backlight.rules <<'EOF'
# filigrane: keyboard backlight on as soon as the LED appears
SUBSYSTEM=="leds", ACTION=="add", KERNEL==":white:kbd_backlight", ATTR{brightness}="3000"
EOF
}

setup_audio() {
    log "ALSA UCM profiles (speakers / headset)"
    local src="/usr/src/t2bce-$T2BCE_VER"
    [ -d "$src" ] || fetch_ref "$T2BCE_REPO" "$T2BCE_REF" "$src"
    mkdir -p /usr/share/alsa/ucm2
    cp -a "$src/t2bce_audio-alsa-ucm-conf/ucm2/." /usr/share/alsa/ucm2/
    # Headset mic on the jack, missing upstream (fresh copy above, so append once)
    local f
    for f in /usr/share/alsa/ucm2/AppleT2/HiFi-x*.conf; do
        cat "$HERE/audio/ucm-headset-mic.conf" >> "$f"
    done

    case "$(cat /sys/class/dmi/id/product_name 2>/dev/null)" in
        MacBookPro16,2) ;;
        *) return 0 ;;
    esac
    log "macOS-style speaker DSP (asahi-audio j293, bankstown, lsp-plugins)"
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
    log "Fans (t2fanrd)"
    if ! command -v t2fanrd >/dev/null; then
        command -v cargo >/dev/null || { warn "cargo missing, fans not configured"; return 0; }
        local tmp
        tmp="$(mktemp -d)"
        fetch_ref "$FAN_REPO" "$FAN_REF" "$tmp/src"
        (cd "$tmp/src" && cargo build --release --locked)
        install -m 0755 "$tmp/src/target/release/t2fanrd" /usr/local/bin/t2fanrd
        rm -rf "$tmp"
    fi
    # One section per detected fan; extra sections are ignored (Omarchy values)
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
# applesmc is blacklisted for udev: load the T2 version here (DKMS, /updates) only
exec 2>&1
if ! modinfo -F filename applesmc 2>/dev/null | grep -q '/updates/'; then
    echo "applesmc-t2 missing for $(uname -r): t2fanrd stopped, fans left to the T2"
    sv down /var/service/t2fanrd
    exit 0
fi
timeout 30 modprobe applesmc || { echo "loading applesmc failed"; sleep 300; exit 1; }
exec /usr/local/bin/t2fanrd
EOF
    chmod 755 /etc/sv/t2fanrd/run
    # Journal (otherwise "Found fan: FanController {...}" is printed on the console at boot)
    mkdir -p /etc/sv/t2fanrd/log /var/log/t2fanrd
    cat > /etc/sv/t2fanrd/log/run <<'EOF'
#!/bin/sh
exec svlogd -tt /var/log/t2fanrd
EOF
    chmod 755 /etc/sv/t2fanrd/log/run
    # On wake, the SMC puts the fans back to automatic (fan*_manual=0): restart t2fanrd
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
    log "Suspend log (battery before/after, in the socklog log)"
    local ev
    for ev in suspend resume; do
        mkdir -p "/etc/zzz.d/$ev"
        cat > "/etc/zzz.d/$ev/10-sleeplog" <<EOF
#!/bin/sh
# Battery level on entering and leaving sleep: tells a drained battery from a crash on wake
b=/sys/class/power_supply/BAT0
logger -t sleeplog "$ev batterie=\$(cat \$b/capacity)% etat=\$(cat \$b/status) charge=\$(cat \$b/charge_now)/\$(cat \$b/charge_full)"
exit 0
EOF
        chmod 755 "/etc/zzz.d/$ev/10-sleeplog"
    done

    # The elogind relay to /etc/zzz.d is installed by bootstrap.sh (system/elogind/system-sleep)

    log "Secondary cores offline during suspend"
    # On S3 wake, the kernel turns cores 1-7 back on in 10 to 35 s (Apple firmware): black screen,
    # the lid seems not to wake the machine. Stopped before sleep, turned back on after: a few ms.
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
    log "Internal T2 USB interface (cdc_ncm) ignored by dhcpcd"
    # Same MAC address on all the T2 Macs: fixed name, then exclusion from dhcpcd
    # (otherwise a 169.254.x.x address and a stray default route before the Wi-Fi)
    mkdir -p /etc/udev/rules.d
    cat > /etc/udev/rules.d/70-t2-ncm.rules <<'EOF'
# filigrane: internal USB Ethernet interface of the T2 chip (not a real network)
SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="ac:de:48:00:11:22", NAME="t2ncm0"
EOF
    if [ -f /etc/dhcpcd.conf ] && ! grep -qE '^denyinterfaces.*t2ncm0' /etc/dhcpcd.conf; then
        printf '\n# filigrane: internal T2 interface\ndenyinterfaces t2ncm0\n' >> /etc/dhcpcd.conf
    fi

    log "Broadcom Wi-Fi: no wake from suspend"
    # With the lid closed, the machine woke up by itself ~35 s after going to sleep (ARPT in
    # /proc/acpi/wakeup). The lid (LID0) and the keyboard (T2) always wake the machine.
    cat > /etc/udev/rules.d/72-t2-wifi-nowake.rules <<'EOF'
# filigrane: the Broadcom Wi-Fi card (ARPT) does not wake the machine from sleep
SUBSYSTEM=="pci", ACTION=="add", ATTR{vendor}=="0x14e4", ATTR{class}=="0x028000", ATTR{power/wakeup}="disabled"
EOF
}

setup_tools() {
    log "Wi-Fi/Bluetooth firmware tool (t2-wifi-firmware)"
    cat > /usr/local/bin/t2-wifi-firmware <<EOF
#!/bin/sh
# Downloads and runs the official t2linux script (MIT) that fetches the Broadcom firmware.
# Method 5 = without macOS (downloads the Apple recovery image). Dependencies: curl, dmg2img, python3.
set -e
tmp=\$(mktemp)
trap 'rm -f "\$tmp"' EXIT
curl -fsSL "$FIRMWARE_URL" -o "\$tmp"
echo "Script fetched from: $FIRMWARE_URL"
exec bash "\$tmp"
EOF
    chmod 755 /usr/local/bin/t2-wifi-firmware
}

if ! is_t2 && [ -z "${T2_FORCE:-}" ]; then
    echo "No T2 chip detected (T2_FORCE=1 to force)."
    exit 0
fi

[ -z "$ONLY" ] && setup_packages  # with --only: dkms and linux-headers must already be installed
# The hardware clock (RTC) of the T2 sometimes restarts from 1 January 1970 at boot: the system lives in 1970
# until the NTP sync (TLS certificates "not yet valid"). chronyd -s then sets the time back to that of
# its last shutdown (date of the drift file) at boot, before the network.
setup_clock() {
    log "Time at boot: chronyd -s (T2 RTC sometimes reset to 1970)"
    printf '%s\n' '# filigrane (hardware/mac-t2): unreliable T2 RTC, restore the time of the last shutdown' 'OPTS="-s"' > /etc/sv/chronyd/conf
}

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
want clock && setup_clock
log "Done. Reboot, then run t2-wifi-firmware for Wi-Fi/Bluetooth."
