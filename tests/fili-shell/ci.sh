#!/bin/sh
# Tests du fili-shell sans bureau (CI): sway sans écran (backend headless, rendu pixman) sert d'hôte Wayland à un niri
# imbriqué (config minimale), puis tests/fili-shell/run.sh tourne dans ce niri. Tout vit dans un dossier d'exécution
# temporaire: rien ne touche une session en cours.
# Usage: tests/fili-shell/ci.sh [-v]   (mêmes options et code de sortie que run.sh)
# Paquets: niri sway quickshell mesa-dri dbus jq libnotify libxkbcommon-tools python3, plus les programmes appelés par la fili-bar (voir TestShell.qml).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
R="$(mktemp -d "${TMPDIR:-/tmp}/fili-shell-ci.XXXXXX")"
chmod 700 "$R"
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$R"' EXIT INT TERM
export XDG_RUNTIME_DIR="$R"
unset WAYLAND_DISPLAY NIRI_SOCKET DISPLAY

# wait_for FICHIER: attend jusqu'à 30 s qu'un socket apparaisse
wait_for() {
    i=0
    while [ ! -S "$1" ]; do
        i=$((i + 1)); [ "$i" -le 300 ] || return 1
        sleep 0.1
    done
}

printf 'output * resolution 1920x1200\n' > "$R/sway.conf"
# Copie sans la capacité de fichier du paquet (cap_sys_nice), qu'un conteneur refuse (exec: Operation not permitted)
cp "$(command -v sway)" "$R/sway"
WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 \
    "$R/sway" -c "$R/sway.conf" > "$R/sway.log" 2>&1 &
wait_for "$R/wayland-1" || { echo "not ok - sway headless n'a pas démarré"; cat "$R/sway.log"; exit 1; }

# niri imbriqué (backend winit dans sway): sa propre fenêtre, son socket Wayland et son socket IPC
printf 'hotkey-overlay { skip-at-startup; }\n' > "$R/niri.kdl"
WAYLAND_DISPLAY=wayland-1 niri -c "$R/niri.kdl" > "$R/niri.log" 2>&1 &
i=0
until NIRI_SOCKET="$(ls "$R"/niri.*.sock 2>/dev/null | head -1)" && [ -n "$NIRI_SOCKET" ] && [ -S "$R/wayland-2" ]; do
    i=$((i + 1)); [ "$i" -le 300 ] || { echo "not ok - niri n'a pas démarré"; cat "$R/niri.log"; exit 1; }
    sleep 0.1
done
export NIRI_SOCKET WAYLAND_DISPLAY=wayland-2
niri msg outputs >/dev/null || { echo "not ok - niri ne répond pas"; cat "$R/niri.log"; exit 1; }

"$ROOT/tests/fili-shell/run.sh" "$@"
