#!/bin/sh
# Tests of the fili-shell (Quickshell): an isolated instance loads the real config (dotfiles/config/quickshell) with
# tests/fili-shell/TestShell.qml as shell.qml, without touching the session: private D-Bus bus (dbus-run-session, hence its
# own notification server), temporary runtime folder and fili-shell pipe, windows hidden and
# click commands recorded instead of run (FILI_TEST=1). Scripts of the repository first (FILI_BIN). Texts in
# English (LANG=C.UTF-8, fili-lang state in $T/state), whatever the language of the session.
# Usage: tests/fili-shell/run.sh [-v] [--changed]   (-v: full Quickshell log; --changed: only the checks that the
# uncommitted changes (git status) can affect, e.g. a fili-bt-pair change runs its own unit check only).
# Exit code 0 if everything passes.
# A running Wayland session (niri) is needed: run from the desktop, not over ssh.
set -u
VERBOSE=0; CHANGED=0
for a in "$@"; do case "$a" in -v) VERBOSE=1 ;; --changed) CHANGED=1 ;; esac; done
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# want GROUP: always true without --changed; else true if a changed path concerns the group
CHG=""
[ "$CHANGED" = 1 ] && CHG="$(git -C "$ROOT" status --porcelain --untracked-files=all | sed 's/^...//; s/.* -> //')"
want() {
    [ "$CHANGED" = 1 ] || return 0
    printf '%s\n' "$CHG" | grep -Eq "$1"
}
if [ "$CHANGED" = 1 ] && [ -z "$CHG" ]; then echo "ok - nothing changed, nothing to test"; exit 0; fi
T="$(mktemp -d "${TMPDIR:-/tmp}/fili-shell-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT INT TERM
[ -n "${WAYLAND_DISPLAY:-}" ] || { echo "pas de session Wayland (WAYLAND_DISPLAY)" >&2; exit 2; }
case "$WAYLAND_DISPLAY" in /*) wl="$WAYLAND_DISPLAY" ;; *) wl="${XDG_RUNTIME_DIR:?}/$WAYLAND_DISPLAY" ;; esac

mkdir -m 700 "$T/run" "$T/bin" "$T/state"
cp -r "$ROOT/dotfiles/config/quickshell" "$T/config"
cp "$ROOT/tests/fili-shell/TestShell.qml" "$T/config/shell.qml"
# Repo scripts, and compiled apps/ binaries (bar-stats): $FILI_APPS (build in progress), else ~/.local/bin, then /usr/bin
for f in "$ROOT"/dotfiles/home/.local/bin/*; do ln -s "$f" "$T/bin/"; done
# Packaged tools (fili-apps) are in /usr/bin; a local build or ~/.local/bin wins when present
for n in bar-stats fili-ai-session fili-appmenu; do
    for d in "${FILI_APPS:-$HOME/.local/bin}" /usr/bin; do [ -e "$d/$n" ] && { ln -sf "$d/$n" "$T/bin/"; break; }; done
done

if want '^dotfiles/config/quickshell/|^tests/fili-shell/TestShell.qml|^dotfiles/home/.local/bin/(bar-|fili-)|^dotfiles/config/filigrane/'; then
FILI_TEST=1 FILI_APPMENU_DIR="$ROOT/dotfiles/config/filigrane/appmenu" FILI_NIRI_DIR="$ROOT/dotfiles/config/niri" LANG=C.UTF-8 LC_ALL= LC_MESSAGES= XDG_STATE_HOME="$T/state" FILI_BIN="$T/bin" FILI_EMOJI="$ROOT/dotfiles/home/.local/share/menu/emoji.txt" XDG_RUNTIME_DIR="$T/run" WAYLAND_DISPLAY="$wl" \
    dbus-run-session -- timeout 90 quickshell -p "$T/config" > "$T/log" 2>&1
rc=$?
RAN_QML=1
else RAN_QML=0; rc=0; : > "$T/log"; fi

sed 's/\x1b\[[0-9;]*m//g' "$T/log" > "$T/clean"
[ "$VERBOSE" = 1 ] && cat "$T/clean"
# TAP results, and QML errors (loading, exceptions) that count as failures
grep -oE '(not ok|ok) [0-9]+ - .*|# end: .*' "$T/clean"
errors="$(grep -E 'caused by|TypeError|ReferenceError|SyntaxError|is not a function|Cannot assign' "$T/clean" | grep -v 'TestShell' | sort -u)"
if [ -n "$errors" ]; then
    echo "not ok - erreurs QML:"; printf '%s\n' "$errors" | sed 's/^/#   /'
    exit 1
fi
if want '^apps/fili-file/|appmenu/fili-file.json|^tests/fili-shell/check-fili-file-menu.py'; then
# The fili-file menu in the fili-bar follows the commands and shortcuts of the application
python3 -I "$ROOT/tests/fili-shell/check-fili-file-menu.py" || exit 1
fi
if want '^apps/fili-file/|^dotfiles/config/quickshell/|^dotfiles/config/filigrane/fili-file'; then
# Casier (fili-file) lives in its own repository: the pinned version (apps/fili-file/upstream, or FILI_SRC_FILI_FILE for a
# local checkout) is built, must follow the shell (same theme defaults and kinetic scroll: opt-in tests of its unit
# suite) and must pass its own headless scenarios (tests/run.sh of that repository).
FILI_FILE_SRC="$("$ROOT/scripts/upstream-dir" fili-file)" || { echo "not ok - source of fili-file not available"; exit 1; }
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$HOME/.cache/filigrane-apps}"
(cd "$FILI_FILE_SRC" && QMAKE="${QMAKE:-/usr/lib/qt6/bin/qmake6}" make >/dev/null 2>&1) || { echo "not ok - fili-file does not build ($FILI_FILE_SRC: make)"; exit 1; }
(cd "$FILI_FILE_SRC" && QMAKE="${QMAKE:-/usr/lib/qt6/bin/qmake6}" FILI_SHELL_DIR="$ROOT/dotfiles/config/quickshell" cargo test --release -q shell_parity) >/dev/null 2>&1 \
    && echo "ok - Casier follows the shell (theme defaults, kinetic scroll)" || { echo "not ok - Casier no longer matches the shell: cd $FILI_FILE_SRC && FILI_SHELL_DIR=$ROOT/dotfiles/config/quickshell make test"; exit 1; }
"$FILI_FILE_SRC/tests/run.sh" || exit 1
fi
if want 'fili-chat|chat'; then
python3 -I "$ROOT/tests/fili-shell/check-fili-chat-menu.py" || exit 1
python3 -I "$ROOT/tests/fili-shell/check-fili-chat-topics.py" "$ROOT" || exit 1
fi
if want 'fili-bar|bar/modules/'; then
# The fili-bar command (modules, plugins)
"$ROOT/tests/fili-shell/check-fili-bar-cli.sh" || exit 1
fi
if want 'bin/fili-theme|check-fili-theme-font|fontconfig/|config/gtk-'; then
# The interface font reaches GTK and fontconfig (fili-theme font)
"$ROOT/tests/fili-shell/check-fili-theme-font.sh" || exit 1
fi
if want 'fili-login|SettingsLogin'; then
# The fili-login command (programs started at login)
"$ROOT/tests/fili-shell/check-fili-login.sh" || exit 1
fi
if want 'bin/fili$|index\.d/|check-fili\.sh'; then
# The fili command (index of apps, plugins and web apps)
"$ROOT/tests/fili-shell/check-fili.sh" || exit 1
fi
if want '^distro/niri/|workflows/niri\.yml|build-repo\.sh|distro\.env|check-fili-niri'; then
"$ROOT/tests/fili-shell/check-fili-niri.sh" || exit 1
fi
if want 'fili-internal-panel|internal-panel\.toml|\.zprofile|config/niri/config\.kdl'; then
"$ROOT/tests/fili-shell/check-fili-internal-panel.sh" || exit 1
fi
if want 'fili-app-output'; then
"$ROOT/tests/fili-shell/check-fili-app-output.sh" || exit 1
fi
if want 'bar/modules/|controls/|check-panel-text-fit'; then
python3 -I "$ROOT/tests/fili-shell/check-panel-text-fit.py" "$ROOT" || exit 1
fi
if want 'FiliNotification|check-notification-buttons'; then
python3 -I "$ROOT/tests/fili-shell/check-notification-buttons.py" "$ROOT" || exit 1
fi
if want 'fili-bt-pair|fili-bt-autoconnect|bluetooth|zzz.d'; then
"$ROOT/tests/fili-shell/check-fili-bt-pair.sh" || exit 1
"$ROOT/tests/fili-shell/check-fili-bt-autoconnect.sh" || exit 1
"$ROOT/tests/fili-shell/check-bt-sleep-hooks.sh" || exit 1
fi
# Live config: every QML file of the repository must be linked in ~/.config/quickshell (bootstrap.sh), otherwise the session
# no longer loads the shell (type not found) while these tests, on a copy of the repository, pass
QS_DIR="$ROOT/dotfiles/config/quickshell"
missing="$(cd "$QS_DIR" && find . -name '*.qml' | while read -r f; do [ -e "$HOME/.config/quickshell/$f" ] || printf '%s ' "${f#./}"; done)"
if [ -n "$missing" ]; then
    echo "not ok - not linked in ~/.config/quickshell (run ./bootstrap.sh --dotfiles-only): $missing"
    exit 1
fi
[ "$RAN_QML" = 1 ] || exit 0
grep -q '^# end: 0 failure' "$T/clean" 2>/dev/null || grep -q '# end: 0 failure' "$T/clean" || { [ "$rc" -eq 124 ] && echo "not ok - timed out (90 s)"; exit 1; }
exit 0
