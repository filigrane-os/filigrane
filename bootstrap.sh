#!/bin/bash
# Replays the Void configuration on a freshly installed system. Idempotent.
#
# ./bootstrap.sh [--profile auto|vm|baremetal] [--machine auto|generic|mac-t2]
# [--cpu auto|intel|amd|other] [--gpu auto|none|intel,amd,nvidia]
# [--arch auto|x86_64|aarch64|riscv64] [--user-layer auto|none|<name>]
# [--system-only | --dotfiles-only | --fili-shell | --apps | --plan]
#
# Three layers, applied in order (a later layer replaces a file of the same path):
# 1. the distribution (root of the repository: packages/, services/, system/, dotfiles/, apps/), generic;
# 2. the hardware (hardware/<machine>/);
# 3. the personal layer (users/<name>/: config.env, packages/*.txt, services/*.txt, dotfiles/, layer.sh).
# --user-layer: auto = users/<target user> if it exists, none = distribution only (like a fresh install).
#
# --fili-shell: only links the fili-shell (config/quickshell, bar-* and fili-* scripts, of each layer) and reloads it;
# without sudo, for a new QML file or script.
# --apps: only builds and installs the tools of apps/ (own Rust and third-party, patches included) and links
# their binaries into ~/.local/bin; without sudo.
# --plan: prints the lists retained for the configuration and exits, without changing anything (CI).
# --profile: environment (VM or physical machine). --machine: hardware, for everything that is
# specific to a model (hardware/<machine>/). --cpu/--gpu: firmware and drivers (packages/cpu-*.txt,
# gpu-*.txt, physical machine only). --arch: architecture (x86_64-only binaries are skipped elsewhere).
# auto detects; forcing allows testing elsewhere (equivalent variables PROFILE, MACHINE, CPU_VENDOR,
# GPU_VENDORS, TARGET_ARCH).
#
# Run as a normal user (sudo required) or as root with TARGET_USER=<name>
# (the chroot case of install-void.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=distro/distro.env
source "$ROOT/distro/distro.env"  # DISTRO: prefix of the distribution's xbps packages

# Messages are written in English; lib/i18n/<lang>.sh translates them (see lib/i18n.sh)
FILI_LIB="$ROOT/lib"
# shellcheck source=lib/i18n.sh
. "$FILI_LIB/i18n.sh"
say() { t "$@"; printf '\n'; }
note() { say "$@" >&2; }
log() { printf '\n==> '; say "$@"; }
warn() { { printf '%s: ' "$(t 'WARNING')"; say "$@"; } >&2; }
die() { note "$@"; exit 1; }

USER_LAYER="${USER_LAYER:-auto}"
PROFILE="${PROFILE:-auto}"
MACHINE="${MACHINE:-auto}"
CPU_VENDOR="${CPU_VENDOR:-auto}"
GPU_VENDORS="${GPU_VENDORS:-auto}"
TARGET_ARCH="${TARGET_ARCH:-auto}"
[ -z "${T2_FORCE:-}" ] || MACHINE=mac-t2  # ancien nom
DO_SYSTEM=1
DO_DOTFILES=1
PLAN=0
SHELL_ONLY=0
APPS_ONLY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --profile) PROFILE="${2:?profil manquant}"; shift 2 ;;
        --machine) MACHINE="${2:?machine manquante}"; shift 2 ;;
        --cpu) CPU_VENDOR="${2:?cpu manquant}"; shift 2 ;;
        --gpu) GPU_VENDORS="${2:?gpu manquant}"; shift 2 ;;
        --arch) TARGET_ARCH="${2:?architecture manquante}"; shift 2 ;;
        --plan) PLAN=1; shift ;;
        --system-only) DO_DOTFILES=0; shift ;;
        --dotfiles-only) DO_SYSTEM=0; shift ;;
        --fili-shell) DO_SYSTEM=0; DO_DOTFILES=0; SHELL_ONLY=1; shift ;;
        --apps) DO_SYSTEM=0; DO_DOTFILES=0; APPS_ONLY=1; shift ;;
        --user-layer) USER_LAYER="${2:?couche manquante}"; shift 2 ;;
        -h|--help) sed -n '2,27p' "$0"; exit 0 ;;
        *) die 'Unknown option: %s' "$1" ;;
    esac
done

if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
    TARGET_USER="${TARGET_USER:?en root, définir TARGET_USER=<nom>}"
else
    SUDO="sudo"
    TARGET_USER="${TARGET_USER:-$USER}"
fi
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[ -n "$TARGET_HOME" ] || die 'User not found: %s' "$TARGET_USER"

# Personal layer: users/<name>/. The choice is remembered in .user-layer (outside git, written by --user-layer or by
# the installer). auto without .user-layer: users/<target user> if it exists, with a warning.
if [ "$USER_LAYER" = auto ]; then
    if [ -f "$ROOT/.user-layer" ]; then USER_LAYER="$(cat "$ROOT/.user-layer")"
    elif [ -d "$ROOT/users/$TARGET_USER" ]; then
        USER_LAYER="$TARGET_USER"
        note 'Layer users/%s chosen from the name (pin it: --user-layer %s, or none)' "$TARGET_USER" "$TARGET_USER"
    else USER_LAYER=none; fi
elif [ "$PLAN" -eq 0 ]; then
    { echo "$USER_LAYER" > "$ROOT/.user-layer"; } 2>/dev/null || warn '.user-layer not saved (read-only repository)'
fi
LAYER_DIR=""
if [ "$USER_LAYER" != none ]; then
    LAYER_DIR="$ROOT/users/$USER_LAYER"
    [ -d "$LAYER_DIR" ] || die 'Layer not found: users/%s' "$USER_LAYER"
fi
# Settings: the personal layer first (its values take precedence over the defaults of the distribution)
if [ -n "$LAYER_DIR" ] && [ -f "$LAYER_DIR/config.env" ]; then
    # shellcheck source=users/<name>/config.env
    source "$LAYER_DIR/config.env"
fi
# AI agent chosen at installation or with `fili-ai use`, if neither the environment nor the layer sets it
AI_ENV="$TARGET_HOME/.config/filigrane/ai.env"
if [ -z "${FILI_AI:-}" ] && [ -f "$AI_ENV" ]; then
    FILI_AI="$(sed -n 's/^FILI_AI=//p' "$AI_ENV" | tail -n1)"
fi
# shellcheck source=config.env
source "$ROOT/config.env"


detect_profile() {
    if grep -q hypervisor /proc/cpuinfo; then echo vm; else echo baremetal; fi
}
[ "$PROFILE" = auto ] && PROFILE="$(detect_profile)"
case "$PROFILE" in vm|baremetal) ;; *) die 'Invalid profile: %s' "$PROFILE" ;; esac

# Intel Mac with a T2 chip (Apple 106b:1801/1802), through sysfs: lspci is not necessarily installed
detect_machine() {
    local d
    for d in /sys/bus/pci/devices/*; do
        [ "$(cat "$d/vendor" 2>/dev/null)" = 0x106b ] || continue
        case "$(cat "$d/device" 2>/dev/null)" in 0x1801|0x1802) echo mac-t2; return ;; esac
    done
    echo generic
}
[ "$MACHINE" = auto ] && MACHINE="$(detect_machine)"
case "$MACHINE" in generic|mac-t2) ;; *) die 'Invalid machine: %s (generic|mac-t2)' "$MACHINE" ;; esac
export MACHINE

# CPU vendor (intel|amd|other: ARM and RISC-V have no vendor_id)
detect_cpu() {
    case "$(grep -m1 '^vendor_id' /proc/cpuinfo 2>/dev/null)" in
        *GenuineIntel*) echo intel ;;
        *AuthenticAMD*) echo amd ;;
        *) echo other ;;
    esac
}
# GPUs present (intel amd nvidia), through sysfs; empty if none recognised (virtio, vmware, SoC...)
detect_gpus() {
    local d v out=""
    for d in /sys/class/drm/card[0-9]*/device/vendor; do
        [ -e "$d" ] || continue
        case "$(cat "$d")" in
            0x8086) v=intel ;; 0x1002) v=amd ;; 0x10de) v=nvidia ;; *) continue ;;
        esac
        case " $out " in *" $v "*) ;; *) out="${out:+$out }$v" ;; esac
    done
    echo "$out"
}
[ "$CPU_VENDOR" = auto ] && CPU_VENDOR="$(detect_cpu)"
[ "$TARGET_ARCH" = auto ] && TARGET_ARCH="$(uname -m)"
if [ "$GPU_VENDORS" = auto ]; then GPU_VENDORS="$(detect_gpus)"; fi
[ "$GPU_VENDORS" = none ] && GPU_VENDORS=""
GPU_VENDORS="${GPU_VENDORS//,/ }"
case "$CPU_VENDOR" in intel|amd|other) ;; *) die 'Invalid CPU: %s (intel|amd|other)' "$CPU_VENDOR" ;; esac
case "$TARGET_ARCH" in x86_64|aarch64|riscv64) ;; *) warn 'Unexpected architecture: %s' "$TARGET_ARCH" ;; esac
for g in $GPU_VENDORS; do
    [ -f "$ROOT/packages/gpu-$g.txt" ] || die 'Invalid GPU: %s (intel|amd|nvidia|none)' "$g"
done
log 'Profile: %s, machine: %s, arch: %s, cpu: %s, gpu: %s, user: %s, layer: %s' "$PROFILE" "$MACHINE" "$TARGET_ARCH" "$CPU_VENDOR" "${GPU_VENDORS:-$(t 'none')}" "$TARGET_USER" "$USER_LAYER"

# Liste sans commentaires ni lignes vides
read_list() { sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$1" | grep -v '^$' || true; }

# Lists retained for the configuration (profile, CPU, GPU, machine), in installation order
package_lists() {
    echo "$ROOT/packages/base.txt" "$ROOT/packages/desktop.txt" "$ROOT/packages/dev.txt" "$ROOT/packages/$PROFILE.txt"
}
hardware_package_lists() { # nonfree repository required (microcode), physical machine only
    local g
    echo "$ROOT/packages/cpu-$CPU_VENDOR.txt"
    for g in $GPU_VENDORS; do echo "$ROOT/packages/gpu-$g.txt"; done
}
service_lists() {
    echo "$ROOT/services/common.txt" "$ROOT/services/$PROFILE.txt"
    [ -z "$LAYER_DIR" ] || find "$LAYER_DIR/services" -name '*.txt' 2>/dev/null | sort
}
# Packages of the personal layer (restricted.txt apart: built with xbps-src)
layer_package_lists() {
    [ -z "$LAYER_DIR" ] || find "$LAYER_DIR/packages" -name '*.txt' ! -name restricted.txt 2>/dev/null | sort
}
restricted_lists() {
    local f
    for f in "$ROOT/packages/restricted.txt" "${LAYER_DIR:+$LAYER_DIR/packages/restricted.txt}"; do
        if [ -n "$f" ] && [ -f "$f" ]; then echo "$f"; fi
    done
}

# --plan: prints the resolved configuration and checks that the lists exist, without changing anything
print_plan() {
    local f rc=0 pkgs=""
    pkgs="$(package_lists)"
    [ "$PROFILE" = baremetal ] && pkgs="$pkgs $(hardware_package_lists)"
    [ "$MACHINE" = mac-t2 ] && pkgs="$pkgs $ROOT/packages/mac-t2.txt"
    pkgs="$pkgs $(layer_package_lists) $(restricted_lists)"
    for f in $pkgs $(service_lists); do
        if [ -f "$f" ]; then echo "${f#"$ROOT/"}"; elif [[ "$f" == */cpu-other.txt ]]; then echo "${f#"$ROOT/"} ($(t 'no list'))"; else
            note 'MISSING: %s' "${f#"$ROOT/"}"; rc=1
        fi
    done
    [ -d "$ROOT/hardware/$MACHINE" ] && echo "hardware/$MACHINE"
    [ -z "$LAYER_DIR" ] || echo "users/$USER_LAYER"
    return $rc
}

install_list() {
    local file="$1" pkg
    local -a ok=()
    [ -f "$file" ] || return 0  # e.g. cpu-other.txt: nothing to install
    for pkg in $(read_list "$file"); do
        if xbps-query "$pkg" >/dev/null 2>&1; then say 'SKIP: %s already installed' "$pkg"
        elif xbps-query -R "$pkg" >/dev/null 2>&1; then ok+=("$pkg")
        else warn 'Package not found: %s' "$pkg"; fi
    done
    [ ${#ok[@]} -gt 0 ] && $SUDO xbps-install -y "${ok[@]}"
    return 0
}

install_pkgs() { # install_pkgs PAQUET... : installe ceux qui manquent
    local pkg
    local -a todo=()
    for pkg in "$@"; do xbps-query "$pkg" >/dev/null 2>&1 || todo+=("$pkg"); done
    [ ${#todo[@]} -eq 0 ] || $SUDO xbps-install -y "${todo[@]}"
}

set_rc() { # set_rc KEY VALUE in /etc/rc.conf
    local key="$1" val="$2"
    if $SUDO grep -qE "^#?${key}=" /etc/rc.conf; then
        $SUDO sed -i -E "s|^#?${key}=.*|${key}=\"${val}\"|" /etc/rc.conf
    else
        echo "${key}=\"${val}\"" | $SUDO tee -a /etc/rc.conf >/dev/null
    fi
}

setup_system() {
    log 'Repositories and update'
    $SUDO xbps-install -Syu xbps
    $SUDO xbps-install -Syu

    log 'Packages'
    local list
    for list in $(package_lists); do install_list "$list"; done
    if [ "$PROFILE" = baremetal ]; then
        if xbps-query void-repo-nonfree >/dev/null 2>&1; then say 'SKIP: %s already installed' void-repo-nonfree
        else $SUDO xbps-install -y void-repo-nonfree; fi
        $SUDO xbps-install -S
        for list in $(hardware_package_lists); do install_list "$list"; done
    fi
    for list in $(layer_package_lists); do install_list "$list"; done

    # Browser: Chromium only if no default browser exists (e.g. Chrome of the personal layer)
    if [ -n "$(run_as_user xdg-settings get default-web-browser 2>/dev/null)" ]; then
        say 'SKIP: default browser already set (%s)' "$(run_as_user xdg-settings get default-web-browser 2>/dev/null)"
    else install_pkgs chromium; fi

    # Native tools already compiled, without going through cargo. First the embedded repository (ISO: distro/out/repo, built by
    # distro/build-repo.sh), else the published repository (DISTRO_REPO_URL): its address and its signing key are set, then
    # <distro>-repo (which then owns them and keeps them up to date) and <distro>-apps. As a last resort, setup_apps compiles.
    if ! xbps-query "$DISTRO-apps" >/dev/null 2>&1; then
        if [ -f "$ROOT/distro/out/repo/$TARGET_ARCH-repodata" ]; then
            log 'Native tools (%s-apps, embedded repository)' "$DISTRO"
            $SUDO xbps-install -Sy --repository="$ROOT/distro/out/repo" "$DISTRO-apps" || warn '%s-apps not installed: apps/ will be built' "$DISTRO"
        elif [ -n "${DISTRO_REPO_URL:-}" ]; then
            log 'Native tools (%s-apps, published repository)' "$DISTRO"
            if ! xbps-query "$DISTRO-repo" >/dev/null 2>&1 && [ ! -f "/etc/xbps.d/10-$DISTRO.conf" ]; then
                printf '# Dépôt de la distribution %s (remplacé par le paquet %s-repo)\nrepository=%s\n' "$DISTRO" "$DISTRO" "$DISTRO_REPO_URL" \
                    | $SUDO install -Dm644 /dev/stdin "/etc/xbps.d/10-$DISTRO.conf"
                $SUDO install -Dm644 -t /var/db/xbps/keys "$ROOT"/distro/repo/keys/*.plist
            fi
            $SUDO xbps-install -Sy "$DISTRO-repo" "$DISTRO-apps" || warn '%s-apps not installed: apps/ will be built' "$DISTRO"
        fi
    fi

    # niri with the Filigrane patch (distro/niri/), until niri fixes niri-wm/niri#2691: once the distribution's
    # repository is set, it replaces Void's niri (packages/desktop.txt, the fallback everywhere else: other
    # architectures, repository unreachable). Its "replaces" removes niri, its "provides" keeps <distro>-desktop happy.
    if ! xbps-query "$DISTRO-niri" >/dev/null 2>&1 && xbps-query -R "$DISTRO-niri" >/dev/null 2>&1; then
        log 'niri with the Filigrane patch (%s-niri)' "$DISTRO"
        $SUDO xbps-install -y "$DISTRO-niri" || warn '%s-niri not installed: Void niri kept' "$DISTRO"
    fi

    log 'Cleaning the xbps cache (small disk)'
    $SUDO xbps-remove -yO >/dev/null || true

    log 'runit services'
    local svc
    for list in $(service_lists); do
        [ -f "$list" ] || continue
        for svc in $(read_list "$list"); do
            if [ -d "/etc/sv/$svc" ]; then
                $SUDO ln -sfn "/etc/sv/$svc" "/etc/runit/runsvdir/default/$svc"
            else
                warn 'Service not found: %s' "$svc"
            fi
        done
    done

    # Services removed from the lists: disabled if they were enabled (acpid: elogind handles the lid,
    # and handler.sh suspended with the lid closed even with external displays; agetty-tty3 to 6:
    # two text consoles are enough, tty1 for the session and tty2 as a fallback)
    for svc in acpid agetty-tty3 agetty-tty4 agetty-tty5 agetty-tty6; do
        if [ -L "/etc/runit/runsvdir/default/$svc" ]; then
            $SUDO sv down "/var/service/$svc" 2>/dev/null || true
            $SUDO rm -f "/etc/runit/runsvdir/default/$svc"
        fi
    done

    log 'Firewall (iptables/ip6tables: incoming denied by default)'
    $SUDO install -d /etc/iptables
    $SUDO install -m 644 "$ROOT/system/iptables/iptables.rules" "$ROOT/system/iptables/ip6tables.rules" /etc/iptables/
    for svc in iptables ip6tables; do
        $SUDO ln -sfn "/etc/sv/$svc" "/etc/runit/runsvdir/default/$svc"
    done
    # Rules active right away (the service only re-reads them at start); restore is atomic: an invalid
    # file leaves the rules in place
    $SUDO iptables-restore /etc/iptables/iptables.rules || warn 'iptables-restore failed'
    $SUDO ip6tables-restore /etc/iptables/ip6tables.rules || warn 'ip6tables-restore failed'

    if [ "$PROFILE" != vm ]; then
        log 'CPU profile on battery/mains (udev rule)'
        $SUDO install -m 644 "$ROOT/system/udev/90-power-profile.rules" /etc/udev/rules.d/
        $SUDO udevadm control --reload
        $SUDO udevadm trigger --subsystem-match=power_supply --action=change
    fi

    log 'Kernel settings (sysctl), earlyoom and zram'
    $SUDO install -d /etc/sysctl.d
    $SUDO install -m 644 "$ROOT/system/sysctl/90-hardening.conf" /etc/sysctl.d/
    $SUDO sysctl -q --system || warn 'sysctl --system failed'
    [ -d /etc/sv/earlyoom ] && $SUDO install -m 644 "$ROOT/system/earlyoom.conf" /etc/sv/earlyoom/conf
    [ -d /etc/sv/zramen ] && $SUDO install -m 644 "$ROOT/system/zramen.conf" /etc/sv/zramen/conf

    log 'Lid handled by niri (~/.local/bin/lid), not by elogind'
    $SUDO install -d /etc/elogind/logind.conf.d
    $SUDO install -m 644 "$ROOT/system/elogind/10-lid.conf" /etc/elogind/logind.conf.d/

    log 'Sleep hooks (/etc/zzz.d, also run when elogind suspends)'
    $SUDO install -Dm755 "$ROOT/system/elogind/system-sleep/50-zzz.d" /usr/libexec/elogind/system-sleep/50-zzz.d
    local ev
    for ev in suspend resume; do
        $SUDO install -Dm755 "$ROOT/system/zzz.d/$ev/60-bluetooth" "/etc/zzz.d/$ev/60-bluetooth"
    done
    # Run as root by the resume hook: a copy outside the home directory
    $SUDO install -Dm755 "$ROOT/dotfiles/home/.local/bin/fili-bt-autoconnect" /usr/local/libexec/filigrane/fili-bt-autoconnect

    log 'Auto-login on tty1'
    local conf=/etc/sv/agetty-tty1/conf autologin="$AUTOLOGIN"
    [ "$autologin" = auto ] && { [ "$PROFILE" = vm ] && autologin=1 || autologin=0; }
    if [ "$autologin" = 1 ]; then
        $SUDO sed -i -E "s|GETTY_ARGS=\"(--autologin [^ ]+ )?--noclear\"|GETTY_ARGS=\"--autologin $TARGET_USER --noclear\"|" "$conf"
        # the autologin must wait for elogind (otherwise /run/user is masked, see the script)
        $SUDO "$ROOT/scripts/tty1-wait-elogind.sh" on >/dev/null
    else
        $SUDO sed -i -E 's|GETTY_ARGS="--autologin [^ ]+ --noclear"|GETTY_ARGS="--noclear"|' "$conf"
        $SUDO "$ROOT/scripts/tty1-wait-elogind.sh" off >/dev/null
    fi
    grep -n GETTY_ARGS "$conf"

    log 'PipeWire: wireplumber and pipewire-pulse started by pipewire (the Void way)'
    $SUDO mkdir -p /etc/pipewire/pipewire.conf.d
    $SUDO ln -sfn /usr/share/examples/wireplumber/10-wireplumber.conf /etc/pipewire/pipewire.conf.d/10-wireplumber.conf
    $SUDO ln -sfn /usr/share/examples/pipewire/20-pipewire-pulse.conf /etc/pipewire/pipewire.conf.d/20-pipewire-pulse.conf

    log 'ALSA: default device routed to PipeWire (cpal/ALSA apps)'
    $SUDO mkdir -p /etc/alsa/conf.d
    for f in 50-pipewire.conf 99-pipewire-default.conf; do
        # A dangling link would make every ALSA client print errors: only link what the package installed
        [ -e "/usr/share/alsa/alsa.conf.d/$f" ] || continue
        $SUDO ln -sfn "/usr/share/alsa/alsa.conf.d/$f" "/etc/alsa/conf.d/$f"
    done

    if [ -d /etc/sv/iwd ]; then
        log 'Wi-Fi: IP configured by iwd, dhcpcd kept for wired'
        # dhcpcd missed the disconnection when iwd reconnects quickly (wake from sleep) and kept
        # the old IPv4 lease (IPv6 ok, IPv4 dead). iwd binds the address at each connection.
        $SUDO install -d /etc/iwd
        $SUDO install -m 644 "$ROOT/system/iwd/main.conf" /etc/iwd/
        if [ -f /etc/dhcpcd.conf ] && ! grep -qE '^denyinterfaces.*wl\*' /etc/dhcpcd.conf; then
            printf '\n# filigrane: le Wi-Fi est configuré par iwd\ndenyinterfaces wl*\n' | $SUDO tee -a /etc/dhcpcd.conf >/dev/null
        fi
    fi

    log 'DNS (resolv.conf managed by resolvconf: dhcpcd, iwd)'
    # A resolv.conf copied from elsewhere (e.g. install from another system) blocks resolvconf
    # ("signature mismatch"). It is only replaced if dhcpcd or iwd has already provided DNS servers.
    if ! grep -q 'Generated by resolvconf' /etc/resolv.conf 2>/dev/null \
        && $SUDO resolvconf -l 2>/dev/null | grep -q '^nameserver'; then
        $SUDO mv /etc/resolv.conf /etc/resolv.conf.bak
        $SUDO resolvconf -u
    fi
    grep '^nameserver' /etc/resolv.conf || warn 'No DNS server in /etc/resolv.conf'

    log 'System settings (keyboard, time zone, locale)'
    set_rc KEYMAP "$KEYMAP"
    set_rc TIMEZONE "$TIMEZONE"
    $SUDO ln -sfn "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
    echo "LANG=$LOCALE" | $SUDO tee /etc/locale.conf >/dev/null
    # LOCALE and LOCALES (languages offered by fili-lang) uncommented, regenerated only if one was missing
    if [ -f /etc/default/libc-locales ]; then
        local loc gen=0
        for loc in $LOCALE $LOCALES; do
            [ "$loc" = C.UTF-8 ] && continue
            if grep -q "^#${loc//./\\.} " /etc/default/libc-locales; then
                $SUDO sed -i "s/^#\(${loc//./\\.} \)/\1/" /etc/default/libc-locales
                gen=1
            fi
        done
        [ "$gen" = 0 ] || $SUDO xbps-reconfigure -f glibc-locales
    fi

    log 'User %s' "$TARGET_USER"
    local g
    for g in $USER_GROUPS; do
        if getent group "$g" >/dev/null; then $SUDO usermod -aG "$g" "$TARGET_USER"; fi
    done
    if [ -x /bin/zsh ] && [ "$(getent passwd "$TARGET_USER" | cut -d: -f7)" != "/bin/zsh" ]; then
        $SUDO chsh -s /bin/zsh "$TARGET_USER"
    fi
    echo '%wheel ALL=(ALL:ALL) ALL' | $SUDO tee /etc/sudoers.d/wheel >/dev/null
    $SUDO chmod 440 /etc/sudoers.d/wheel
    $SUDO visudo -cf /etc/sudoers.d/wheel >/dev/null
    # The NOPASSWD files carry the prefix zz-: sudoers applies the last matching rule,
    # and wheel (password) must therefore be read before them. Old names cleaned up on the way.
    $SUDO rm -f /etc/sudoers.d/power /etc/sudoers.d/claude /etc/sudoers.d/zz-claude
    # System menu: shut down, restart, sleep without a password (no polkit on this machine)
    echo '%wheel ALL=(root) NOPASSWD: /usr/bin/zzz, /usr/bin/reboot, /usr/bin/poweroff' | $SUDO tee /etc/sudoers.d/zz-power >/dev/null
    $SUDO chmod 440 /etc/sudoers.d/zz-power
    $SUDO visudo -cf /etc/sudoers.d/zz-power >/dev/null
    # AI agent (fili-ai): sv and xbps without a password for the agents whose guard-rails Filigrane sets, the
    # confirmation coming from the agent (Claude Code: permissions and hook; Codex: sandbox, sudo and network
    # only after agreement). opencode has no sandbox: sudo keeps its password.
    case "$FILI_AI" in
        claude|codex|ollama)
            echo "$TARGET_USER ALL=(root) NOPASSWD: /usr/bin/sv, /usr/bin/xbps-install, /usr/bin/xbps-remove, /usr/bin/xbps-query, /usr/bin/xbps-reconfigure" | $SUDO tee /etc/sudoers.d/zz-agent >/dev/null
            $SUDO chmod 440 /etc/sudoers.d/zz-agent
            $SUDO visudo -cf /etc/sudoers.d/zz-agent >/dev/null
            ;;
        *) $SUDO rm -f /etc/sudoers.d/zz-agent ;;
    esac
    # Codex sandbox (bubblewrap) and Ollama archive (zstd)
    case "$FILI_AI" in
        codex) install_pkgs bubblewrap ;;
        ollama) install_pkgs bubblewrap zstd ;;
    esac

    # Hardware-specific: hardware/<machine>/ (generic has nothing)
    if [ "$MACHINE" = mac-t2 ]; then
        # LUKS + btrfs + Limine dual boot (file created by hardware/mac-t2/dualboot.sh)
        if [ -f /etc/kernel/cmdline ]; then
            log 'Dual boot (dualboot.sh)'
            $SUDO "$ROOT/hardware/mac-t2/dualboot.sh"
        fi
        log 'Mac with a T2 chip'
        $SUDO env T2_FORCE=1 "$ROOT/hardware/mac-t2/setup.sh"
    fi
}

run_as_user() {
    if [ "$(id -u)" -eq 0 ]; then
        runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" "$@"
    else
        "$@"
    fi
}

# Own tools (apps/<name>, Rust): native binaries rather than Python/GTK scripts, so that the OS stays light.
# Compiled in release in ~/.local/opt/<name>-<source hash>, linked into ~/.local/bin; recompiled
# only when the sources change. The build folder (target/) stays outside the repository, in ~/.cache.
# With the <distro>-apps package (xbps repository of the distribution, see distro/), the binaries are already in /usr/bin.
setup_apps() {
    local app name src sum dir alias bin bins
    if xbps-query "$DISTRO-apps" >/dev/null 2>&1; then say 'SKIP: apps/ provided by the %s-apps package' "$DISTRO"; return 0; fi
    for app in "$ROOT"/apps/*/; do
        app="${app%/}"; name="$(basename "$app")"
        if [ -f "$app/upstream" ]; then
            # Tool that lives in its own repository: the pinned version (apps/<name>/upstream, scripts/upstream-dir)
            command -v git >/dev/null || { warn 'git missing: %s not built' "$name"; continue; }
            src="$(run_as_user "$ROOT/scripts/upstream-dir" "$name")" || { warn 'Source of %s not available (network?)' "$name"; continue; }
        elif [ -f "$app/Cargo.toml" ]; then
            src="$app"
        else
            continue
        fi
        command -v cargo >/dev/null || { warn 'cargo missing (packages/dev.txt): apps/ not built'; return 0; }
        # build.rs, qml/, fonts/, i18n/ and theme.toml (fili-file: embedded in the binary); daemon/: second crate of fili-term
        sum="$(cd "$src" && { find Cargo.toml Cargo.lock src build.rs qml fonts i18n theme.toml daemon -type f 2>/dev/null || true; } | sort | xargs cat | sha256sum | cut -c1-12)"
        dir="$TARGET_HOME/.local/opt/$name-$sum"
        # Programs of the tool (BINS in package.env, e.g. fili-term and its session daemon), default: the one named like it
        bins="$(BINS="" && . "$src/package.env" 2>/dev/null && echo "$BINS")"; bins="${bins:-$name}"
        if ! (for bin in $bins; do [ -x "$dir/$bin" ] || exit 1; done); then
            log 'Building %s (%s)' "$name" "$sum"
            # QMAKE: cxx-qt (fili-file) finds Qt through it; Void keeps qmake6 outside PATH
            if (cd "$src" && run_as_user env QMAKE="${QMAKE:-/usr/lib/qt6/bin/qmake6}" CARGO_TARGET_DIR="$TARGET_HOME/.cache/filigrane-apps" \
                    cargo build -q --release --locked --workspace --manifest-path "$src/Cargo.toml") \
                && run_as_user mkdir -p "$dir" \
                && (for bin in $bins; do run_as_user cp "$TARGET_HOME/.cache/filigrane-apps/release/$bin" "$dir/$bin" || exit 1; done); then
                # old versions
                find "$TARGET_HOME/.local/opt" -maxdepth 1 -name "$name-*" ! -name "$name-$sum" -exec rm -rf {} +
            else
                warn 'Build of %s failed' "$name"; run_as_user rm -rf "$dir"; continue
            fi
        fi
        run_as_user mkdir -p "$TARGET_HOME/.local/bin"
        for bin in $bins; do run_as_user ln -sfn "$dir/$bin" "$TARGET_HOME/.local/bin/$bin"; done
        # Other command names of the same program (ALIASES in package.env, e.g. casier -> fili-file)
        for alias in $(ALIASES="" && . "$src/package.env" 2>/dev/null && echo "$ALIASES"); do
            run_as_user ln -sfn "$dir/$name" "$TARGET_HOME/.local/bin/$alias"
        done
    done
    setup_apps_git
}

# Third-party tools in Rust (apps/<name>/source: url, commit, bins): cloned at a precise commit, compiled in ~/.cache, installed
# in ~/.local/opt/<name>-<commit>, linked into ~/.local/bin; recompiled only when the commit changes.
setup_apps_git() {
    local src name url commit bins dir b p src_dir patches sum
    for src in "$ROOT"/apps/*/source; do
        [ -e "$src" ] || return 0
        command -v cargo >/dev/null && command -v git >/dev/null || { warn 'cargo or git missing: %s not built' "$src"; return 0; }
        name="$(basename "$(dirname "$src")")"
        url="$(sed -n 's/^url=//p' "$src")"; commit="$(sed -n 's/^commit=//p' "$src")"; bins="$(sed -n 's/^bins=//p' "$src" | tr -d '"')"
        # Local patches (apps/<name>/patches/*.patch): applied after the checkout; their hash is part of the folder name,
        # so a modified patch recompiles
        patches="$(ls "$ROOT/apps/$name/patches/"*.patch 2>/dev/null)"
        sum=""; [ -z "$patches" ] || sum="-p$(cat $patches | sha256sum | cut -c1-8)"
        dir="$TARGET_HOME/.local/opt/$name-${commit:0:12}$sum"
        if [ ! -x "$dir/${bins%% *}" ]; then
            log 'Building %s (%s)' "$name" "${commit:0:12}"
            src_dir="$TARGET_HOME/.cache/filigrane-src/$name"
            if run_as_user sh -c 'rm -rf "$1" && mkdir -p "$1" && cd "$1" && git init -q && git fetch -q --depth 1 "$2" "$3" && git checkout -q FETCH_HEAD' sh "$src_dir" "$url" "$commit" \
                && for p in $patches; do run_as_user git -C "$src_dir" apply "$p" || false; done \
                && run_as_user env CARGO_TARGET_DIR="$TARGET_HOME/.cache/filigrane-apps/$name" cargo build -q --release --locked --manifest-path "$src_dir/Cargo.toml" \
                && run_as_user mkdir -p "$dir" \
                && for b in $bins; do run_as_user cp "$TARGET_HOME/.cache/filigrane-apps/$name/release/$b" "$dir/$b" || false; done; then
                find "$TARGET_HOME/.local/opt" -maxdepth 1 -name "$name-*" ! -name "$name-${commit:0:12}$sum" -exec rm -rf {} +
            else
                warn 'Build of %s failed' "$name"; run_as_user rm -rf "$dir"; continue
            fi
        fi
        run_as_user mkdir -p "$TARGET_HOME/.local/bin"
        for b in $bins; do run_as_user ln -sfn "$dir/$b" "$TARGET_HOME/.local/bin/$b"; done
    done
}

# Restricted packages (packages/restricted.txt of the distribution or of the personal layer): built with
# xbps-src in a clone of void-packages.
# Update: git pull in the clone, ./xbps-src pkg <package>, then xbps-install -u -R <local repository> <package>
VOID_PACKAGES="${VOID_PACKAGES:-$TARGET_HOME/Projects/void-packages}"

setup_restricted() {
    local pkg list
    local -a todo=() repos=()
    for pkg in $(for list in $(restricted_lists); do read_list "$list"; done); do
        if xbps-query "$pkg" >/dev/null 2>&1; then say 'SKIP: %s already installed' "$pkg"; else todo+=("$pkg"); fi
    done
    [ ${#todo[@]} -gt 0 ] || return 0
    log 'Restricted packages (xbps-src): %s' "${todo[*]}"
    if [ ! -x "$VOID_PACKAGES/xbps-src" ]; then
        run_as_user git clone -q --depth 1 https://github.com/void-linux/void-packages "$VOID_PACKAGES" \
            || { warn 'Cloning void-packages failed'; return 0; }
    fi
    grep -qx 'XBPS_ALLOW_RESTRICTED=yes' "$VOID_PACKAGES/etc/conf" 2>/dev/null \
        || echo 'XBPS_ALLOW_RESTRICTED=yes' | run_as_user tee -a "$VOID_PACKAGES/etc/conf" >/dev/null
    if ! compgen -G "$VOID_PACKAGES/masterdir*" >/dev/null; then
        (cd "$VOID_PACKAGES" && run_as_user ./xbps-src binary-bootstrap) || { warn 'xbps-src binary-bootstrap failed'; return 0; }
    fi
    for pkg in "${todo[@]}"; do
        (cd "$VOID_PACKAGES" && run_as_user ./xbps-src pkg "$pkg") || warn 'Build of %s failed' "$pkg"
    done
    # local repositories produced by xbps-src (hostdir/binpkgs/<branch>/nonfree...)
    mapfile -t repos < <(find "$VOID_PACKAGES/hostdir/binpkgs" -name '*-repodata' -printf '%h\n' | sort -u)
    [ ${#repos[@]} -gt 0 ] || return 0
    $SUDO xbps-install -y "${repos[@]/#/--repository=}" "${todo[@]}" || warn 'Installing %s failed' "${todo[*]}"
}

# AI agent chosen (FILI_AI): installed by fili-ai (dotfiles/home/.local/bin), which also knows how to update it
setup_ai() {
    [ "$FILI_AI" != none ] || return 0
    log 'AI agent: %s' "$FILI_AI"
    run_as_user "$ROOT/dotfiles/home/.local/bin/fili-ai" install "$FILI_AI" \
        || warn 'Installing the %s agent failed (network?), run bootstrap.sh again or fili-ai install %s' "$FILI_AI" "$FILI_AI"
}

# Settings of fili-ai (~/.config/filigrane/ai.env), agent skills (agents/skills: ~/.claude/skills for
# Claude Code, ~/.agents/skills for Codex and opencode) and instructions of the working folder (agents/work)
setup_ai_dotfiles() {
    local workdir="$FILI_AI_WORKDIR" skill f
    case "$workdir" in /*) ;; *) workdir="$TARGET_HOME/$workdir" ;; esac
    log 'AI agent: settings, skills, working directory %s' "${workdir/#"$TARGET_HOME"/\~}"
    run_as_user mkdir -p "${AI_ENV%/*}" "$workdir"
    { echo "# Generated by bootstrap.sh from config.env; fili-ai use <agent> changes FILI_AI"
      printf '%s=%q\n' FILI_AI "$FILI_AI" FILI_AI_MODEL "$FILI_AI_MODEL" FILI_AI_WORKDIR "$workdir" FILI_AI_ARGS "$FILI_AI_ARGS" FILIGRANE_DIR "$ROOT"
    } | run_as_user tee "$AI_ENV" >/dev/null
    for skill in "$ROOT"/agents/skills/*/; do
        skill="${skill%/}"
        link_one "$skill" "$TARGET_HOME/.claude/skills/${skill##*/}"
        link_one "$skill" "$TARGET_HOME/.agents/skills/${skill##*/}"
    done
    # Not on an existing AGENTS.md or CLAUDE.md (working folder placed in a project, or in this repository)
    for f in AGENTS.md CLAUDE.md; do
        if [ -L "$workdir/$f" ] || [ ! -e "$workdir/$f" ]; then link_one "$ROOT/agents/work/$f" "$workdir/$f"; fi
    done
}

link_one() { # link_one SOURCE DESTINATION
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        mv "$dst" "$dst.bak.$(date +%Y%m%d%H%M%S)"
    fi
    ln -sfn "$src" "$dst"
    if [ "$(id -u)" -eq 0 ]; then
        # as root, the folders created (~/.config, ~/.local/share...) must belong to the user
        local d="$dst"
        while [ "$d" != "$TARGET_HOME" ] && [ "$d" != / ]; do
            chown -h "$TARGET_USER:" "$d"
            d="$(dirname "$d")"
        done
    fi
}

# Links to this repository that became orphans (file moved, deleted or moved to another layer): removed
prune_links() {
    local l
    while IFS= read -r -d '' l; do
        case "$(readlink "$l")" in "$ROOT"/*) rm -f "$l"; say 'Orphan link removed: ~/%s' "${l#"$TARGET_HOME/"}" ;; esac
    done < <(find "$TARGET_HOME" -maxdepth 1 -xtype l -print0
             find "$TARGET_HOME/.config" "$TARGET_HOME/.local" "$TARGET_HOME/.claude" "$TARGET_HOME/.agents" \
                 "$TARGET_HOME/.codex" -xtype l -print0 2>/dev/null)
}

link_tree() { # link_tree DOSSIER : DOSSIER/home -> ~, DOSSIER/config -> ~/.config
    local f
    if [ -d "$1/home" ]; then
        while IFS= read -r -d '' f; do
            link_one "$f" "$TARGET_HOME/${f#"$1/home/"}"
        done < <(find "$1/home" -type f -print0)
    fi
    if [ -d "$1/config" ]; then
        while IFS= read -r -d '' f; do
            link_one "$f" "$TARGET_HOME/.config/${f#"$1/config/"}"
        done < <(find "$1/config" -type f -print0)
    fi
}

# Only the fili-shell: QML files and bar-*/fili-* scripts of each layer (the last one replaces), then reload
setup_fili_shell() {
    local dir f
    log 'fili-shell (symlinks to %s)' "$ROOT"
    for dir in "$ROOT" "$ROOT/hardware/$MACHINE" "$LAYER_DIR"; do
        [ -d "$dir/dotfiles" ] || continue
        while IFS= read -r -d '' f; do
            link_one "$f" "$TARGET_HOME/.config/${f#"$dir/dotfiles/config/"}"
        done < <(find "$dir/dotfiles/config/quickshell" -type f -print0 2>/dev/null)
        while IFS= read -r -d '' f; do
            link_one "$f" "$TARGET_HOME/.local/bin/${f##*/}"
        done < <(find "$dir/dotfiles/home/.local/bin" -type f \( -name 'bar-*' -o -name 'fili-*' \) -print0 2>/dev/null)
    done
    prune_links
    [ "$(id -u)" -eq 0 ] || "$TARGET_HOME/.local/bin/fili-shell" reload || true
}

setup_dotfiles() {
    log 'Dotfiles (symlinks to %s/dotfiles)' "$ROOT"
    link_tree "$ROOT/dotfiles"
    # Hardware-specific dotfiles (hardware/<machine>/dotfiles/{home,config})
    if [ -d "$ROOT/hardware/$MACHINE/dotfiles" ]; then
        log 'Dotfiles for machine %s' "$MACHINE"
        link_tree "$ROOT/hardware/$MACHINE/dotfiles"
    fi
    # Personal layer last: a file of the same path replaces the one of the distribution
    if [ -n "$LAYER_DIR" ] && [ -d "$LAYER_DIR/dotfiles" ]; then
        log 'Dotfiles for layer users/%s' "$USER_LAYER"
        link_tree "$LAYER_DIR/dotfiles"
    fi
    prune_links
    setup_ai_dotfiles
    # niri keyboard layout (included by config.kdl), from config.env
    run_as_user mkdir -p "$TARGET_HOME/.config/niri"
    run_as_user sh -c 'printf "%s\n" "$1" "input {" "    keyboard {" "        xkb {" \
        "            layout \"$2\"" "            variant \"$3\"" "            options \"$4\"" "        }" "    }" "}" > "$5"' _ \
        "// Généré par bootstrap.sh depuis config.env (XKB_LAYOUT, XKB_VARIANT, XKB_OPTIONS), ne pas modifier ici" \
        "$XKB_LAYOUT" "$XKB_VARIANT" "$XKB_OPTIONS" "$TARGET_HOME/.config/niri/keyboard.kdl"
    # Filigrane identity: master files of the logo (brand/) in ~/.local/share/filigrane (logo of the fili-bar),
    # Jost and JetBrains Mono fonts (dotfiles/home/.local/share/fonts, OFL, absent from the Void repositories)
    link_one "$ROOT/brand" "$TARGET_HOME/.local/share/filigrane"
    run_as_user fc-cache -f "$TARGET_HOME/.local/share/fonts" >/dev/null || warn 'fc-cache failed'
    # .desktop des applications web (liste ~/.config/webapps/list)
    HOME="$TARGET_HOME" sh "$ROOT/dotfiles/home/.local/bin/webapp-sync"
    # OS icons: Filigrane-Icons theme (folders and glyphs of Nordic, the rest from Adwaita), before fili-theme which names it
    run_as_user sh "$ROOT/scripts/icon-theme.sh" || warn 'icon-theme failed'
    # Dark mode by default, or light if it was chosen (displays fili-panel): files included by foot, niri and GTK3,
    # gsettings (xdg portal: Chromium, GTK, libadwaita; no effect outside a D-Bus session)
    run_as_user sh "$ROOT/dotfiles/home/.local/bin/fili-theme" apply || warn 'fili-theme apply failed'
    run_as_user sh "$ROOT/dotfiles/home/.local/bin/fili-lang" apply || warn 'fili-lang apply failed'
    run_as_user sh "$ROOT/dotfiles/home/.local/bin/fili-app-output" apply || warn 'fili-app-output apply failed'
    if gsettings set org.gnome.desktop.interface font-name 'Jost 10' 2>/dev/null; then
        gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrains Mono 10'
    else
        warn 'gsettings: fonts not applied (no D-Bus session)'
    fi
    # Mac T2 (MacBookPro16,2): the ALSA "Speaker" route is hidden by the DSP (hide-parent), so it is no longer
    # adjustable, and a low volume on it attenuates the whole DSP. WirePlumber has no per-route volume
    # rule: it is set to 1.0 in its state, the volume is adjusted on the DSP.
    if [ "$MACHINE" = mac-t2 ] && [ "$(cat /sys/class/dmi/id/product_name 2>/dev/null)" = MacBookPro16,2 ]; then
        local st="$TARGET_HOME/.local/state/wireplumber/default-routes"
        local line='alsa_card.pci-0000_e6_00.3:output:\oOut\c\sSpeaker={"latencyOffsetNsec":0, "mute":false, "channelVolumes":[1.000000, 1.000000, 1.000000, 1.000000], "channelMap":["FL", "FR", "RL", "RR"]}'
        run_as_user mkdir -p "${st%/*}"
        [ -f "$st" ] || run_as_user sh -c 'printf "[default-routes]\n" > "$1"' _ "$st"
        if ! grep -qxF "$line" "$st"; then
            log 'Mac T2: Speaker route volume set to 1.0 (restart wireplumber to apply)'
            sed -i '/:output:\\oOut\\c\\sSpeaker=/d' "$st"
            printf '%s\n' "$line" >> "$st"
        fi
    fi
    if declare -F layer_dotfiles >/dev/null; then layer_dotfiles; fi
}

# Optional functions of the personal layer: layer_system (root rights, after the distribution)
# and layer_dotfiles (after the links). They have log, warn, read_list, install_list, run_as_user, $SUDO...
if [ -n "$LAYER_DIR" ] && [ -f "$LAYER_DIR/layer.sh" ]; then
    # shellcheck source=users/<name>/layer.sh
    source "$LAYER_DIR/layer.sh"
fi

if [ "$PLAN" -eq 1 ]; then print_plan; exit; fi
[ "$DO_SYSTEM" -eq 1 ] && setup_system
[ "$SHELL_ONLY" -eq 1 ] && setup_fili_shell
[ "$APPS_ONLY" -eq 1 ] && setup_apps
[ "$DO_DOTFILES" -eq 1 ] && setup_dotfiles
[ "$DO_DOTFILES" -eq 1 ] && setup_apps
[ "$DO_SYSTEM" -eq 1 ] && setup_ai
[ "$DO_SYSTEM" -eq 1 ] && setup_restricted
if [ "$DO_SYSTEM" -eq 1 ] && declare -F layer_system >/dev/null; then layer_system; fi
log 'Done'
