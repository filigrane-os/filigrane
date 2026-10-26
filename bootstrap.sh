#!/bin/bash
# Rejoue la configuration Void sur un système fraîchement installé. Idempotent.
#
#   ./bootstrap.sh [--profile auto|vm|baremetal] [--machine auto|generic|mac-t2]
#                  [--cpu auto|intel|amd|other] [--gpu auto|none|intel,amd,nvidia]
#                  [--arch auto|x86_64|aarch64|riscv64] [--user-layer auto|none|<nom>]
#                  [--system-only | --dotfiles-only | --plan]
#
# Trois couches, appliquées dans l'ordre (une couche suivante remplace un fichier de même chemin):
#   1. la distribution (racine du dépôt: packages/, services/, system/, dotfiles/, apps/), générique;
#   2. le matériel (hardware/<machine>/);
#   3. la couche personnelle (users/<nom>/: config.env, packages/*.txt, services/*.txt, dotfiles/, layer.sh).
# --user-layer: auto = users/<utilisateur cible> s'il existe, none = distribution seule (comme une installation neuve).
#
# --plan: affiche les listes retenues pour la configuration et quitte, sans rien modifier (CI).
# --profile: environnement (VM ou machine physique). --machine: matériel, pour tout ce qui est
# spécifique à un modèle (hardware/<machine>/). --cpu/--gpu: firmware et pilotes (packages/cpu-*.txt,
# gpu-*.txt, machine physique seulement). --arch: architecture (binaires x86_64 seulement ignorés ailleurs).
# auto détecte; forcer permet de tester ailleurs (variables PROFILE, MACHINE, CPU_VENDOR,
# GPU_VENDORS, TARGET_ARCH équivalentes).
#
# Lancé en utilisateur normal (sudo requis) ou en root avec TARGET_USER=<nom>
# (cas du chroot de install-void.sh).
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
        --user-layer) USER_LAYER="${2:?couche manquante}"; shift 2 ;;
        -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
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

# Couche personnelle: users/<nom>/. Le choix est mémorisé dans .user-layer (hors git, écrit par --user-layer ou par
# l'installateur). auto sans .user-layer: users/<utilisateur cible> s'il existe, avec un avertissement.
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
# Réglages: la couche personnelle d'abord (ses valeurs passent avant les défauts de la distribution)
if [ -n "$LAYER_DIR" ] && [ -f "$LAYER_DIR/config.env" ]; then
    # shellcheck source=users/thomas/config.env
    source "$LAYER_DIR/config.env"
fi
# Agent IA choisi à l'installation ou avec `fili-ai use`, si ni l'environnement ni la couche ne le fixent
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

# Mac Intel à puce T2 (Apple 106b:1801/1802), via sysfs: lspci n'est pas forcément installé
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

# Fabricant du CPU (intel|amd|other: ARM et RISC-V n'ont pas de vendor_id)
detect_cpu() {
    case "$(grep -m1 '^vendor_id' /proc/cpuinfo 2>/dev/null)" in
        *GenuineIntel*) echo intel ;;
        *AuthenticAMD*) echo amd ;;
        *) echo other ;;
    esac
}
# GPU présents (intel amd nvidia), via sysfs; vide si aucun reconnu (virtio, vmware, SoC...)
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

# Listes retenues pour la configuration (profil, CPU, GPU, machine), dans l'ordre d'installation
package_lists() {
    echo "$ROOT/packages/base.txt" "$ROOT/packages/desktop.txt" "$ROOT/packages/dev.txt" "$ROOT/packages/$PROFILE.txt"
}
hardware_package_lists() { # dépôt nonfree requis (microcode), machine physique seulement
    local g
    echo "$ROOT/packages/cpu-$CPU_VENDOR.txt"
    for g in $GPU_VENDORS; do echo "$ROOT/packages/gpu-$g.txt"; done
}
service_lists() {
    echo "$ROOT/services/common.txt" "$ROOT/services/$PROFILE.txt"
    [ -z "$LAYER_DIR" ] || find "$LAYER_DIR/services" -name '*.txt' 2>/dev/null | sort
}
# Paquets de la couche personnelle (restricted.txt à part: construit avec xbps-src)
layer_package_lists() {
    [ -z "$LAYER_DIR" ] || find "$LAYER_DIR/packages" -name '*.txt' ! -name restricted.txt 2>/dev/null | sort
}
restricted_lists() {
    local f
    for f in "$ROOT/packages/restricted.txt" "${LAYER_DIR:+$LAYER_DIR/packages/restricted.txt}"; do
        if [ -n "$f" ] && [ -f "$f" ]; then echo "$f"; fi
    done
}

# --plan: affiche la configuration résolue et vérifie que les listes existent, sans rien modifier
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
    [ -f "$file" ] || return 0  # ex. cpu-other.txt: rien à installer
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

set_rc() { # set_rc CLE VALEUR dans /etc/rc.conf
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

    # Dépôt de la distribution embarqué (ISO: distro/out/repo, construit par distro/build-repo.sh): outils natifs
    # déjà compilés, sans passer par cargo
    if [ -f "$ROOT/distro/out/repo/$TARGET_ARCH-repodata" ] && ! xbps-query "$DISTRO-apps" >/dev/null 2>&1; then
        log 'Native tools (%s-apps, embedded repository)' "$DISTRO"
        $SUDO xbps-install -Sy --repository="$ROOT/distro/out/repo" "$DISTRO-apps" || warn '%s-apps not installed: apps/ will be built' "$DISTRO"
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

    # Services retirés des listes: désactivés s'ils l'étaient (acpid: elogind gère le capot,
    # et handler.sh mettait en veille capot fermé même avec des écrans externes; agetty-tty3 à 6:
    # deux consoles texte suffisent, tty1 pour la session et tty2 en secours)
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

    log 'Auto-login on tty1'
    local conf=/etc/sv/agetty-tty1/conf autologin="$AUTOLOGIN"
    [ "$autologin" = auto ] && { [ "$PROFILE" = vm ] && autologin=1 || autologin=0; }
    if [ "$autologin" = 1 ]; then
        $SUDO sed -i -E "s|GETTY_ARGS=\"(--autologin [^ ]+ )?--noclear\"|GETTY_ARGS=\"--autologin $TARGET_USER --noclear\"|" "$conf"
        # l'autologin doit attendre elogind (sinon /run/user est masqué, cf. le script)
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

    if [ -d /etc/sv/iwd ]; then
        log 'Wi-Fi: IP configured by iwd, dhcpcd kept for wired'
        # dhcpcd ratait la coupure quand iwd se reconnecte vite (sortie de veille) et gardait
        # l'ancien bail IPv4 (IPv6 ok, IPv4 mort). iwd lie l'adresse à chaque connexion.
        $SUDO install -d /etc/iwd
        $SUDO install -m 644 "$ROOT/system/iwd/main.conf" /etc/iwd/
        if [ -f /etc/dhcpcd.conf ] && ! grep -qE '^denyinterfaces.*wl\*' /etc/dhcpcd.conf; then
            printf '\n# filigrane: le Wi-Fi est configuré par iwd\ndenyinterfaces wl*\n' | $SUDO tee -a /etc/dhcpcd.conf >/dev/null
        fi
    fi

    log 'DNS (resolv.conf managed by resolvconf: dhcpcd, iwd)'
    # Un resolv.conf copié d'ailleurs (ex. install depuis un autre système) bloque resolvconf
    # ("signature mismatch"). On ne le remplace que si dhcpcd ou iwd a déjà fourni des serveurs DNS.
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
    if [ "$LOCALE" != "C.UTF-8" ] && [ -f /etc/default/libc-locales ]; then
        $SUDO sed -i "s/^#\(${LOCALE//./\\.} \)/\1/" /etc/default/libc-locales
        $SUDO xbps-reconfigure -f glibc-locales
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
    # Les fichiers NOPASSWD portent le préfixe zz- : sudoers applique la dernière règle qui correspond,
    # et wheel (mot de passe) doit donc être lu avant eux. Anciens noms nettoyés au passage.
    $SUDO rm -f /etc/sudoers.d/power /etc/sudoers.d/claude /etc/sudoers.d/zz-claude
    # Menu Système: éteindre, redémarrer, veille sans mot de passe (pas de polkit sur cette machine)
    echo '%wheel ALL=(root) NOPASSWD: /usr/bin/zzz, /usr/bin/reboot, /usr/bin/poweroff' | $SUDO tee /etc/sudoers.d/zz-power >/dev/null
    $SUDO chmod 440 /etc/sudoers.d/zz-power
    $SUDO visudo -cf /etc/sudoers.d/zz-power >/dev/null
    # Agent IA (fili-ai): sv et xbps sans mot de passe pour les agents dont Filigrane règle les garde-fous, la
    # confirmation venant de l'agent (Claude Code: permissions et hook; Codex: bac à sable, sudo et réseau
    # seulement après accord). opencode n'a pas de bac à sable: sudo garde son mot de passe.
    case "$FILI_AI" in
        claude|codex|ollama)
            echo "$TARGET_USER ALL=(root) NOPASSWD: /usr/bin/sv, /usr/bin/xbps-install, /usr/bin/xbps-remove, /usr/bin/xbps-query, /usr/bin/xbps-reconfigure" | $SUDO tee /etc/sudoers.d/zz-agent >/dev/null
            $SUDO chmod 440 /etc/sudoers.d/zz-agent
            $SUDO visudo -cf /etc/sudoers.d/zz-agent >/dev/null
            ;;
        *) $SUDO rm -f /etc/sudoers.d/zz-agent ;;
    esac
    # Bac à sable de Codex (bubblewrap) et archive d'Ollama (zstd)
    case "$FILI_AI" in
        codex) install_pkgs bubblewrap ;;
        ollama) install_pkgs bubblewrap zstd ;;
    esac

    # Matériel spécifique: hardware/<machine>/ (generic n'a rien)
    if [ "$MACHINE" = mac-t2 ]; then
        # Double démarrage LUKS + btrfs + Limine (fichier créé par hardware/mac-t2/dualboot.sh)
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

# Outils maison (apps/<nom>, Rust): binaires natifs plutôt que scripts Python/GTK, pour que l'OS reste léger.
# Compilés en release dans ~/.local/opt/<nom>-<empreinte des sources>, liés dans ~/.local/bin; recompilés
# seulement quand les sources changent. Le dossier de compilation (target/) reste hors du dépôt, dans ~/.cache.
# Avec le paquet <distro>-apps (dépôt xbps de la distribution, voir distro/), les binaires sont déjà dans /usr/bin.
setup_apps() {
    local manifest app name sum dir
    if xbps-query "$DISTRO-apps" >/dev/null 2>&1; then say 'SKIP: apps/ provided by the %s-apps package' "$DISTRO"; return 0; fi
    for manifest in "$ROOT"/apps/*/Cargo.toml; do
        [ -e "$manifest" ] || return 0
        command -v cargo >/dev/null || { warn 'cargo missing (packages/dev.txt): apps/ not built'; return 0; }
        app="$(dirname "$manifest")"; name="$(basename "$app")"
        sum="$(cd "$app" && find Cargo.toml Cargo.lock src -type f | sort | xargs cat | sha256sum | cut -c1-12)"
        dir="$TARGET_HOME/.local/opt/$name-$sum"
        if [ ! -x "$dir/$name" ]; then
            log 'Building %s (%s)' "$name" "$sum"
            if run_as_user env CARGO_TARGET_DIR="$TARGET_HOME/.cache/filigrane-apps" \
                    cargo build -q --release --locked --manifest-path "$manifest" \
                && run_as_user mkdir -p "$dir" \
                && run_as_user cp "$TARGET_HOME/.cache/filigrane-apps/release/$name" "$dir/$name"; then
                # anciennes versions
                find "$TARGET_HOME/.local/opt" -maxdepth 1 -name "$name-*" ! -name "$name-$sum" -exec rm -rf {} +
            else
                warn 'Build of %s failed' "$name"; run_as_user rm -rf "$dir"; continue
            fi
        fi
        run_as_user mkdir -p "$TARGET_HOME/.local/bin"
        run_as_user ln -sfn "$dir/$name" "$TARGET_HOME/.local/bin/$name"
    done
}

# Paquets restricted (packages/restricted.txt de la distribution ou de la couche personnelle): construits avec
# xbps-src dans un clone de void-packages.
# Mise à jour: git pull dans le clone, ./xbps-src pkg <paquet>, puis xbps-install -u -R <dépôt local> <paquet>
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
    # dépôts locaux produits par xbps-src (hostdir/binpkgs/<branche>/nonfree...)
    mapfile -t repos < <(find "$VOID_PACKAGES/hostdir/binpkgs" -name '*-repodata' -printf '%h\n' | sort -u)
    [ ${#repos[@]} -gt 0 ] || return 0
    $SUDO xbps-install -y "${repos[@]/#/--repository=}" "${todo[@]}" || warn 'Installing %s failed' "${todo[*]}"
}

# Agent IA choisi (FILI_AI): installé par fili-ai (dotfiles/home/.local/bin), qui sait aussi le mettre à jour
setup_ai() {
    [ "$FILI_AI" != none ] || return 0
    log 'AI agent: %s' "$FILI_AI"
    run_as_user "$ROOT/dotfiles/home/.local/bin/fili-ai" install "$FILI_AI" \
        || warn 'Installing the %s agent failed (network?), run bootstrap.sh again or fili-ai install %s' "$FILI_AI" "$FILI_AI"
}

# Réglages de fili-ai (~/.config/filigrane/ai.env), skills des agents (agents/skills: ~/.claude/skills pour
# Claude Code, ~/.agents/skills pour Codex et opencode) et consignes du dossier de travail (agents/work)
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
    # Pas sur un AGENTS.md ou CLAUDE.md existant (dossier de travail placé dans un projet, ou dans ce dépôt)
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
        # en root, les dossiers créés (~/.config, ~/.local/share...) doivent appartenir à l'utilisateur
        local d="$dst"
        while [ "$d" != "$TARGET_HOME" ] && [ "$d" != / ]; do
            chown -h "$TARGET_USER:" "$d"
            d="$(dirname "$d")"
        done
    fi
}

# Liens vers ce dépôt devenus orphelins (fichier déplacé, supprimé ou passé dans une autre couche): retirés
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

setup_dotfiles() {
    log 'Dotfiles (symlinks to %s/dotfiles)' "$ROOT"
    link_tree "$ROOT/dotfiles"
    # Dotfiles propres au matériel (hardware/<machine>/dotfiles/{home,config})
    if [ -d "$ROOT/hardware/$MACHINE/dotfiles" ]; then
        log 'Dotfiles for machine %s' "$MACHINE"
        link_tree "$ROOT/hardware/$MACHINE/dotfiles"
    fi
    # Couche personnelle en dernier: un fichier de même chemin remplace celui de la distribution
    if [ -n "$LAYER_DIR" ] && [ -d "$LAYER_DIR/dotfiles" ]; then
        log 'Dotfiles for layer users/%s' "$USER_LAYER"
        link_tree "$LAYER_DIR/dotfiles"
    fi
    prune_links
    setup_ai_dotfiles
    # Disposition clavier de niri (incluse par config.kdl), depuis config.env
    run_as_user mkdir -p "$TARGET_HOME/.config/niri"
    run_as_user sh -c 'printf "%s\n" "$1" "input {" "    keyboard {" "        xkb {" \
        "            layout \"$2\"" "            variant \"$3\"" "            options \"$4\"" "        }" "    }" "}" > "$5"' _ \
        "// Généré par bootstrap.sh depuis config.env (XKB_LAYOUT, XKB_VARIANT, XKB_OPTIONS), ne pas modifier ici" \
        "$XKB_LAYOUT" "$XKB_VARIANT" "$XKB_OPTIONS" "$TARGET_HOME/.config/niri/keyboard.kdl"
    # Identité Filigrane: fichiers maîtres du logo (brand/) dans ~/.local/share/filigrane (logo de la fili-bar),
    # polices Jost et JetBrains Mono (dotfiles/home/.local/share/fonts, OFL, absentes des dépôts Void)
    link_one "$ROOT/brand" "$TARGET_HOME/.local/share/filigrane"
    run_as_user fc-cache -f "$TARGET_HOME/.local/share/fonts" >/dev/null || warn 'fc-cache failed'
    # .desktop des applications web (liste ~/.config/webapps/list)
    HOME="$TARGET_HOME" sh "$ROOT/dotfiles/home/.local/bin/webapp-sync"
    # Thème sombre par défaut (portail xdg: Chromium, GTK4, libadwaita); sans effet hors session D-Bus
    if gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null; then
        gsettings set org.gnome.desktop.interface font-name 'Jost 10'
        gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrains Mono 10'
    else
        warn 'gsettings: theme and fonts not applied (no D-Bus session)'
    fi
    # Thunar: Espace lance l'aperçu rapide (action "quicklook" de uca.xml). Thunar réécrit accels.scm
    # en quittant (un lien serait remplacé, l'ajout perdu): on le ferme puis on ajoute la ligne.
    local acc="$TARGET_HOME/.config/Thunar/accels.scm"
    local ql='(gtk_accel_path "<Actions>/ThunarActions/uca-action-quicklook" "space")'
    if ! grep -qxF "$ql" "$acc" 2>/dev/null; then
        log 'Thunar: Space = quick look (quicklook)'
        run_as_user thunar -q 2>/dev/null || true
        while pgrep -u "$TARGET_USER" -x Thunar >/dev/null; do sleep 0.2; done
        run_as_user mkdir -p "${acc%/*}"
        run_as_user sh -c 'printf "%s\n" "$1" >> "$2"' _ "$ql" "$acc"
    fi
    # Mac T2 (MacBookPro16,2): la route ALSA "Speaker" est cachée par le DSP (hide-parent), donc plus
    # réglable, et un volume bas sur elle atténue tout le DSP. WirePlumber n'a pas de règle de volume
    # par route: on la fixe à 1.0 dans son état, le volume se règle sur le DSP.
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

# Fonctions optionnelles de la couche personnelle: layer_system (droits root, après la distribution)
# et layer_dotfiles (après les liens). Elles disposent de log, warn, read_list, install_list, run_as_user, $SUDO...
if [ -n "$LAYER_DIR" ] && [ -f "$LAYER_DIR/layer.sh" ]; then
    # shellcheck source=users/thomas/layer.sh
    source "$LAYER_DIR/layer.sh"
fi

if [ "$PLAN" -eq 1 ]; then print_plan; exit; fi
[ "$DO_SYSTEM" -eq 1 ] && setup_system
[ "$DO_DOTFILES" -eq 1 ] && setup_dotfiles
[ "$DO_DOTFILES" -eq 1 ] && setup_apps
[ "$DO_SYSTEM" -eq 1 ] && setup_ai
[ "$DO_SYSTEM" -eq 1 ] && setup_restricted
if [ "$DO_SYSTEM" -eq 1 ] && declare -F layer_system >/dev/null; then layer_system; fi
log 'Done'
