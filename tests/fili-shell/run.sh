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
for f in "${FILI_APPS:-$HOME/.local/bin}"/bar-stats "${FILI_APPS:-$HOME/.local/bin}"/fili-ai-session "${FILI_APPS:-$HOME/.local/bin}"/fili-appmenu; do [ -e "$f" ] && ln -sf "$f" "$T/bin/"; done

FILI_TEST=1 FILI_APPMENU_DIR="$ROOT/dotfiles/config/filigrane/appmenu" FILI_NIRI_DIR="$ROOT/dotfiles/config/niri" LANG=C.UTF-8 LC_ALL= LC_MESSAGES= XDG_STATE_HOME="$T/state" FILI_BIN="$T/bin" FILI_EMOJI="$ROOT/dotfiles/home/.local/share/menu/emoji.txt" XDG_RUNTIME_DIR="$T/run" WAYLAND_DISPLAY="$wl" \
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
# Le menu de fili-file dans la fili-bar suit les commandes et raccourcis de l'application
python3 -I "$ROOT/tests/fili-shell/check-fili-file-menu.py" || exit 1
# Casier (fili-file) lives in its own repository: the pinned version (apps/fili-file/upstream, or FILI_SRC_FILI_FILE for a
# local checkout) is built, must follow the shell (same theme defaults and kinetic scroll: opt-in tests of its unit
# suite) and must pass its own headless scenarios (tests/run.sh of that repository).
FILI_FILE_SRC="$("$ROOT/scripts/upstream-dir" fili-file)" || { echo "not ok - source of fili-file not available"; exit 1; }
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$HOME/.cache/filigrane-apps}"
(cd "$FILI_FILE_SRC" && QMAKE="${QMAKE:-/usr/lib/qt6/bin/qmake6}" make >/dev/null 2>&1) || { echo "not ok - fili-file does not build ($FILI_FILE_SRC: make)"; exit 1; }
(cd "$FILI_FILE_SRC" && QMAKE="${QMAKE:-/usr/lib/qt6/bin/qmake6}" FILI_SHELL_DIR="$ROOT/dotfiles/config/quickshell" cargo test --release -q shell_parity) >/dev/null 2>&1 \
    && echo "ok - Casier follows the shell (theme defaults, kinetic scroll)" || { echo "not ok - Casier no longer matches the shell: cd $FILI_FILE_SRC && FILI_SHELL_DIR=$ROOT/dotfiles/config/quickshell make test"; exit 1; }
"$FILI_FILE_SRC/tests/run.sh" || exit 1
python3 -I "$ROOT/tests/fili-shell/check-fili-chat-menu.py" || exit 1
python3 -I "$ROOT/tests/fili-shell/check-fili-chat-topics.py" "$ROOT" || exit 1
# Config live: chaque fichier QML du dépôt doit être lié dans ~/.config/quickshell (bootstrap.sh), sinon la session
# ne charge plus le shell (type introuvable) alors que ces tests, sur une copie du dépôt, passent
missing="$(for f in "$ROOT"/dotfiles/config/quickshell/*.qml; do [ -e "$HOME/.config/quickshell/${f##*/}" ] || printf '%s ' "${f##*/}"; done)"
if [ -n "$missing" ]; then
    echo "not ok - non liés dans ~/.config/quickshell (lancer ./bootstrap.sh --dotfiles-only): $missing"
    exit 1
fi
grep -q '^# fin: 0 échec' "$T/clean" 2>/dev/null || grep -q '# fin: 0 échec' "$T/clean" || { [ "$rc" -eq 124 ] && echo "not ok - délai dépassé (90 s)"; exit 1; }
exit 0
