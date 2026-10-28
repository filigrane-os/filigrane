#!/bin/sh
# Tests du fili-shell (Quickshell): une instance isolée charge la vraie config (dotfiles/config/quickshell) avec
# tests/fili-shell/TestShell.qml comme shell.qml, sans toucher à la session: bus D-Bus privé (dbus-run-session, donc
# serveur de notifications à elle), dossier d'exécution et tuyau fili-shell temporaires, fenêtres masquées et
# commandes des clics enregistrées au lieu d'être lancées (FILI_TEST=1). Scripts du dépôt d'abord (FILI_BIN). Textes en
# anglais (LANG=C.UTF-8, état de fili-lang dans $T/state), quelle que soit la langue de la session.
# Usage: tests/fili-shell/run.sh [-v]   (-v: journal complet de Quickshell). Code 0 si tout passe.
# Il faut une session Wayland (niri) en cours: lancer depuis le bureau, pas en ssh.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/fili-shell-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT INT TERM
[ -n "${WAYLAND_DISPLAY:-}" ] || { echo "pas de session Wayland (WAYLAND_DISPLAY)" >&2; exit 2; }
case "$WAYLAND_DISPLAY" in /*) wl="$WAYLAND_DISPLAY" ;; *) wl="${XDG_RUNTIME_DIR:?}/$WAYLAND_DISPLAY" ;; esac

mkdir -m 700 "$T/run" "$T/bin" "$T/state"
cp -r "$ROOT/dotfiles/config/quickshell" "$T/config"
cp "$ROOT/tests/fili-shell/TestShell.qml" "$T/config/shell.qml"
# Scripts du dépôt, et binaires compilés de apps/ (bar-stats): $FILI_APPS (build en cours) sinon ~/.local/bin
for f in "$ROOT"/dotfiles/home/.local/bin/*; do ln -s "$f" "$T/bin/"; done
for f in "${FILI_APPS:-$HOME/.local/bin}"/bar-stats "${FILI_APPS:-$HOME/.local/bin}"/fili-ai-session; do [ -e "$f" ] && ln -sf "$f" "$T/bin/"; done

FILI_TEST=1 LANG=C.UTF-8 LC_ALL= LC_MESSAGES= XDG_STATE_HOME="$T/state" FILI_BIN="$T/bin" FILI_EMOJI="$ROOT/dotfiles/home/.local/share/menu/emoji.txt" XDG_RUNTIME_DIR="$T/run" WAYLAND_DISPLAY="$wl" \
    dbus-run-session -- timeout 90 quickshell -p "$T/config" > "$T/log" 2>&1
rc=$?

sed 's/\x1b\[[0-9;]*m//g' "$T/log" > "$T/clean"
[ "${1:-}" = -v ] && cat "$T/clean"
# Résultats TAP, et erreurs QML (chargement, exceptions) qui comptent comme des échecs
grep -oE '(not ok|ok) [0-9]+ - .*|# fin: .*' "$T/clean"
errors="$(grep -E 'caused by|TypeError|ReferenceError|SyntaxError|is not a function|Cannot assign' "$T/clean" | grep -v 'TestShell' | sort -u)"
if [ -n "$errors" ]; then
    echo "not ok - erreurs QML:"; printf '%s\n' "$errors" | sed 's/^/#   /'
    exit 1
fi
# Config live: chaque fichier QML du dépôt doit être lié dans ~/.config/quickshell (bootstrap.sh), sinon la session
# ne charge plus le shell (type introuvable) alors que ces tests, sur une copie du dépôt, passent
missing="$(for f in "$ROOT"/dotfiles/config/quickshell/*.qml; do [ -e "$HOME/.config/quickshell/${f##*/}" ] || printf '%s ' "${f##*/}"; done)"
if [ -n "$missing" ]; then
    echo "not ok - non liés dans ~/.config/quickshell (lancer ./bootstrap.sh --dotfiles-only): $missing"
    exit 1
fi
grep -q '^# fin: 0 échec' "$T/clean" 2>/dev/null || grep -q '# fin: 0 échec' "$T/clean" || { [ "$rc" -eq 124 ] && echo "not ok - délai dépassé (90 s)"; exit 1; }
exit 0
