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
# bar-update counts the pending xbps updates of the machine: the answer depends on the system (a stale container image has
# some), and an active indicator turns the status icon on and adds a panel to the keyboard ring. The bench has none.
rm -f "$T/bin/bar-update"
cat > "$T/bin/bar-update" <<'SH'
#!/bin/sh
[ "${1:-}" = run ] && exit 0
printf '{"text":""}\n'
SH
chmod +x "$T/bin/bar-update"
# Packaged tools (fili-apps) are in /usr/bin; a local build or ~/.local/bin wins when present
for n in bar-stats fili-ai-session fili-appmenu fili-recorder fili-music; do
    for d in "${FILI_APPS:-$HOME/.local/bin}" /usr/bin; do [ -e "$d/$n" ] && { ln -sf "$d/$n" "$T/bin/"; break; }; done
done

# What the pinned applications ship in their shell/ folder (bar modules, fallback menus), found as on a machine where their
# packages are installed: the modules join the bench's bar, the menus the fallback menu folder (the repository's win)
mkdir -p "$T/appmenu"
cp "$ROOT"/dotfiles/config/filigrane/appmenu/*.json "$T/appmenu/"
for pin in "$ROOT"/apps/*/upstream; do
    [ -f "$pin" ] || continue
    src="$("$ROOT/scripts/upstream-dir" "$(basename "$(dirname "$pin")")" 2>/dev/null)" || continue
    for m in "$src"/shell/fili-bar/*/; do
        { [ -f "${m}module.toml" ] && [ ! -e "$T/config/bar/modules/$(basename "$m")" ]; } && ln -s "${m%/}" "$T/config/bar/modules/$(basename "$m")"
    done
    for j in "$src"/shell/appmenu/*.json; do
        { [ -f "$j" ] && [ ! -e "$T/appmenu/$(basename "$j")" ]; } && cp "$j" "$T/appmenu/"
    done
done

if want '^dotfiles/config/quickshell/|^tests/fili-shell/TestShell.qml|^dotfiles/home/.local/bin/(bar-|fili-)|^dotfiles/config/filigrane/'; then
FILI_TEST=1 FILI_APPMENU_DIR="$T/appmenu" FILI_NIRI_DIR="$ROOT/dotfiles/config/niri" LANG=C.UTF-8 LC_ALL= LC_MESSAGES= XDG_STATE_HOME="$T/state" FILI_BIN="$T/bin" FILI_EMOJI="$ROOT/dotfiles/home/.local/share/menu/emoji.txt" XDG_RUNTIME_DIR="$T/run" WAYLAND_DISPLAY="$wl" \
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
if want '^apps/fili-term/|^apps/fili-file/|appmenu/fili-term.json|^dotfiles/config/filigrane/fili-term|^tests/fili-shell/check-app-window.py'; then
# Aéroport (fili-term) lives in its own repository too: the pinned version (apps/fili-term/upstream, or FILI_SRC_FILI_TERM)
# is built, passes its unit tests and keeps the window anatomy of Casier (shared QML files identical, header, footer).
FILI_TERM_SRC="$("$ROOT/scripts/upstream-dir" fili-term)" || { echo "not ok - source of fili-term not available"; exit 1; }
FILI_FILE_SRC="$("$ROOT/scripts/upstream-dir" fili-file)" || { echo "not ok - source of fili-file not available"; exit 1; }
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$HOME/.cache/filigrane-apps}"
(cd "$FILI_TERM_SRC" && QMAKE="${QMAKE:-/usr/lib/qt6/bin/qmake6}" make test >/dev/null 2>&1) \
    && echo "ok - fili-term builds and passes its unit tests" || { echo "not ok - fili-term: cd $FILI_TERM_SRC && make test"; exit 1; }
python3 -I "$ROOT/tests/fili-shell/check-app-window.py" --ref "$FILI_FILE_SRC" "$FILI_TERM_SRC" || exit 1
fi
if want '^apps/fili-recorder/|^dotfiles/config/quickshell/|appmenu/fili-recorder.json|^tests/fili-shell/check-fili-recorder-menu.py|^tests/fili-shell/check-app-window.py'; then
# Cassette (fili-recorder) lives in its own repository: the pinned version (apps/fili-recorder/upstream, or FILI_SRC_FILI_RECORDER
# for a local checkout) passes its unit tests (the shell parity ones compare its theme with the shell's), the fili-bar menu
# stays in agreement with its window, and the window follows the anatomy of Casier
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$HOME/.cache/filigrane-apps}"
FILI_RECORDER_SRC="$("$ROOT/scripts/upstream-dir" fili-recorder)" || { echo "not ok - source of fili-recorder not available"; exit 1; }
(cd "$FILI_RECORDER_SRC" && QMAKE="${QMAKE:-/usr/lib/qt6/bin/qmake6}" FILI_SHELL_DIR="$ROOT/dotfiles/config/quickshell" cargo test --release -q --locked >/dev/null 2>&1) \
    && echo "ok - fili-recorder passes its unit tests" || { echo "not ok - fili-recorder: cd $FILI_RECORDER_SRC && QMAKE=/usr/lib/qt6/bin/qmake6 FILI_SHELL_DIR=$ROOT/dotfiles/config/quickshell cargo test"; exit 1; }
python3 -I "$ROOT/tests/fili-shell/check-fili-recorder-menu.py" || exit 1
FILI_FILE_SRC="$("$ROOT/scripts/upstream-dir" fili-file)" || { echo "not ok - source of fili-file not available"; exit 1; }
python3 -I "$ROOT/tests/fili-shell/check-app-window.py" --ref "$FILI_FILE_SRC" "$FILI_RECORDER_SRC" || exit 1
fi
if want '^apps/fili-incident/'; then
# fili-incident (problems reported by the apps, in this repository): the private details removed from what leaves the machine,
# the signature in the issue, the GitHub search reply, incident ids that cannot leave their folder
(cd "$ROOT/apps/fili-incident" && cargo test --release -q --locked >/dev/null 2>&1) \
    && echo "ok - fili-incident passes its unit tests" || { echo "not ok - fili-incident: cd apps/fili-incident && cargo test"; exit 1; }
fi
if want '^apps/fili-music/|^dotfiles/config/quickshell/|appmenu/fili-music.json|^tests/fili-shell/check-fili-music-menu.py|^tests/fili-shell/check-app-window.py'; then
# Baladeur (fili-music) lives in its own repository: the pinned version (apps/fili-music/upstream, or FILI_SRC_FILI_MUSIC for a
# local checkout) passes its unit tests (the shell parity ones compare its theme with the shell's), the fili-bar menu stays
# in agreement with its window, and the window follows the anatomy of Casier
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$HOME/.cache/filigrane-apps}"
FILI_MUSIC_SRC="$("$ROOT/scripts/upstream-dir" fili-music)" || { echo "not ok - source of fili-music not available"; exit 1; }
(cd "$FILI_MUSIC_SRC" && QMAKE="${QMAKE:-/usr/lib/qt6/bin/qmake6}" FILI_SHELL_DIR="$ROOT/dotfiles/config/quickshell" cargo test --release -q --locked >/dev/null 2>&1) \
    && echo "ok - fili-music passes its unit tests" || { echo "not ok - fili-music: cd $FILI_MUSIC_SRC && QMAKE=/usr/lib/qt6/bin/qmake6 FILI_SHELL_DIR=$ROOT/dotfiles/config/quickshell cargo test"; exit 1; }
python3 -I "$ROOT/tests/fili-shell/check-fili-music-menu.py" || exit 1
FILI_FILE_SRC="$("$ROOT/scripts/upstream-dir" fili-file)" || { echo "not ok - source of fili-file not available"; exit 1; }
python3 -I "$ROOT/tests/fili-shell/check-app-window.py" --ref "$FILI_FILE_SRC" "$FILI_MUSIC_SRC" || exit 1
fi
if want 'fili-chat|chat|appmenu/_default.json|niri/config.kdl'; then
python3 -I "$ROOT/tests/fili-shell/check-fili-chat-menu.py" || exit 1
python3 -I "$ROOT/tests/fili-shell/check-fili-chat-topics.py" "$ROOT" || exit 1
python3 -I "$ROOT/tests/fili-shell/check-fili-chat-here.py" || exit 1
(cd "$ROOT/apps/fili-chat" && cargo test --release --quiet) || exit 1
fi
if want 'fili-bar|bar/modules/'; then
# The fili-bar command (modules, plugins)
"$ROOT/tests/fili-shell/check-fili-bar-cli.sh" || exit 1
fi
if want 'bin/fili-theme|check-fili-theme-font|fontconfig/|config/gtk-'; then
# The interface font reaches GTK and fontconfig (fili-theme font)
"$ROOT/tests/fili-shell/check-fili-theme-font.sh" || exit 1
fi
if want 'bin/fili-theme|check-fili-theme-window'; then
# Headless windows and status bars (fili-theme header|footer)
"$ROOT/tests/fili-shell/check-fili-theme-window.sh" || exit 1
fi
if want 'fili-login|SettingsLogin'; then
# The fili-login command (programs started at login)
"$ROOT/tests/fili-shell/check-fili-login.sh" || exit 1
fi
if want 'fili-firewall|SettingsFirewall|system/firewall|firewall\.toml'; then
# The fili-firewall command and the rules generated by fili-firewall-apply
"$ROOT/tests/fili-shell/check-fili-firewall.sh" || exit 1
fi
if want 'bin/webapp-edit|check-webapp-edit\.sh'; then
# webapp-edit (name, URL and icon of a web app)
"$ROOT/tests/fili-shell/check-webapp-edit.sh" || exit 1
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
