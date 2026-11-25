#!/bin/sh
# Tests of the fili-shell (Quickshell): an isolated instance loads the real config (dotfiles/config/quickshell) with
# tests/fili-shell/TestShell.qml as shell.qml, without touching the session: private D-Bus bus (dbus-run-session, hence its
# own notification server), temporary runtime folder and fili-shell pipe, windows hidden and
# click commands recorded instead of run (FILI_TEST=1). Scripts of the repository first (FILI_BIN). Texts in
# English (LANG=C.UTF-8, fili-lang state in $T/state), whatever the language of the session.
# Usage: tests/fili-shell/run.sh [-v] [--changed]   (-v: full Quickshell log; --changed: only the checks that the
# uncommitted changes (git status) can affect, e.g. a fili-bt-pair change runs its own unit check only).
# Exit code 0 if everything passes.
# The applications' own suites (make test) are not run here unless the pin of an application changed (apps/<app>/upstream) or
# FILI_APP_TESTS=1: the CI of each application runs them. Here only their parity with the shell and their window anatomy.
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
# The applications live in their own repositories and run their unit suites and headless scenarios in their own CI (make test,
# make check). Here only what compares an application with the shell, whenever the shell changes: check-app-shell-parity.py (theme
# defaults, kinetic scroll) and the window anatomy against Casier. The whole suite of an application (its `make test`, `make check`
# for Casier) runs here only when its pin changes (apps/<app>/upstream), or for every application with FILI_APP_TESTS=1.
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$HOME/.cache/filigrane-apps}"
SHELL_RE='^dotfiles/config/quickshell/|^tests/fili-shell/check-app-window.py|^tests/fili-shell/check-app-shell-parity.py|^tests/fili-shell/run.sh'
app_src() { # app_src APP: the pinned sources (or FILI_SRC_<APP>), else the bench stops
    "$ROOT/scripts/upstream-dir" "$1" || { echo "not ok - source of $1 not available" >&2; exit 1; }
}
app_parity() { # app_parity APP NAME: the app follows the shell (theme.toml defaults, KineticScroll.qml, the kit's when it has none)
    src="$(app_src "$1")" || exit 1
    kit="$(app_src fili-ui)" || exit 1
    python3 -I "$ROOT/tests/fili-shell/check-app-shell-parity.py" "$src" "$2" --kit "$kit" || exit 1
}
app_anatomy() { # app_anatomy APP: the window follows the anatomy of app-window.md and takes its shared controls from the fili-ui kit
    src="$(app_src "$1")" || exit 1
    python3 -I "$ROOT/tests/fili-shell/check-app-window.py" "$src" || exit 1
}
app_suite() { # app_suite APP NAME TARGET: its own suite, when its pin changed
    { [ "${FILI_APP_TESTS:-0}" = 1 ] || { [ "$CHANGED" = 1 ] && printf '%s\n' "$CHG" | grep -Eq "^apps/$1/upstream"; }; } || return 0
    src="$(app_src "$1")" || exit 1
    (cd "$src" && QMAKE="${QMAKE:-/usr/lib/qt6/bin/qmake6}" make "$3" >/dev/null 2>&1) \
        && echo "ok - $2 passes its own suite (make $3)" || { echo "not ok - $2: cd $src && make $3"; exit 1; }
}
# The kit itself follows the shell: its default theme and its kinetic scroll
if want "$SHELL_RE|^libs/fili-ui/upstream"; then python3 -I "$ROOT/tests/fili-shell/check-app-shell-parity.py" "$(app_src fili-ui)" "fili-ui (kit)" || exit 1; fi
if want "$SHELL_RE|^apps/fili-file/upstream|^libs/fili-ui/upstream"; then app_parity fili-file Casier; fi
if want "$SHELL_RE|^apps/fili-recorder/upstream|^apps/fili-file/upstream"; then app_parity fili-recorder Cassette; app_anatomy fili-recorder; fi
if want "$SHELL_RE|^apps/fili-music/upstream|^apps/fili-file/upstream"; then app_parity fili-music Baladeur; app_anatomy fili-music; fi
if want "$SHELL_RE|^apps/fili-term/upstream|^apps/fili-file/upstream"; then app_anatomy fili-term; fi
if want "$SHELL_RE|^apps/fili-ai/upstream|^apps/fili-file/upstream"; then app_parity fili-ai Lia; fi
app_suite fili-file Casier check
app_suite fili-ai Lia check
app_suite fili-term Aeroport test
app_suite fili-recorder Cassette test
app_suite fili-music Baladeur test
app_suite fili-im Conversations test
app_suite fili-mail Facteur test
if want '^apps/fili-cal/|check-fili-cal'; then
# fili-cal (calendar and reminders, in this repository): unit tests (dates, iCalendar, recurrence) then the command line
(cd "$ROOT/apps/fili-cal" && cargo test --release -q --locked >/dev/null 2>&1) \
    && echo "ok - fili-cal passes its unit tests" || { echo "not ok - fili-cal: cd apps/fili-cal && cargo test"; exit 1; }
"$ROOT/tests/fili-shell/check-fili-cal.sh" || exit 1
fi
if want '^apps/fili-incident/'; then
# fili-incident (problems reported by the apps, in this repository): the private details removed from what leaves the machine,
# the signature in the issue, the GitHub search reply, incident ids that cannot leave their folder
(cd "$ROOT/apps/fili-incident" && cargo test --release -q --locked >/dev/null 2>&1) \
    && echo "ok - fili-incident passes its unit tests" || { echo "not ok - fili-incident: cd apps/fili-incident && cargo test"; exit 1; }
fi
if want 'fili-ai|chat|appmenu/_default.json|niri/config.kdl|^apps/fili-ai/upstream'; then
# The assistant lives in its own repository (apps/fili-ai/upstream): its menu, catalog and unit tests are checked there
# (make check); here only what ties it to the distribution
python3 -I "$ROOT/tests/fili-shell/check-fili-ai-topics.py" "$(app_src fili-ai)" "$ROOT" || exit 1
python3 -I "$ROOT/tests/fili-shell/check-fili-ai-here.py" "$(app_src fili-ai)" || exit 1
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
if want 'fili-about|SettingsAbout'; then
# The Filigrane version of the About card: tags of the distribution only
"$ROOT/tests/fili-shell/check-fili-about-version.sh" || exit 1
fi
if want 'fili-assistant|SettingsAssistant'; then
# The fili-assistant command (agent, model, sign-in state; the login files are never opened)
"$ROOT/tests/fili-shell/check-fili-assistant.sh" || exit 1
fi
if want 'fili-region|fili-lang|SettingsRegion|FiliI18n'; then
# The fili-region command and what fili-lang writes for the applications (language and region formats)
"$ROOT/tests/fili-shell/check-fili-region.sh" || exit 1
fi
if want 'fili-defaults|SettingsDefaults'; then
# The fili-defaults command (default applications)
"$ROOT/tests/fili-shell/check-fili-defaults.sh" || exit 1
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
if want 'bar/modules/|controls/|check-module-contract'; then
python3 -I "$ROOT/tests/fili-shell/check-module-contract.py" "$ROOT" || exit 1
fi
if want 'bin/fili-(api|event)|apps/fili-incident/|config/filigrane/incident/|docs/api.md|check-api'; then
"$ROOT/tests/fili-shell/check-api.sh" || exit 1
fi
if want 'bar/modules/power/|check-power-level'; then
python3 -I "$ROOT/tests/fili-shell/check-power-level.py" "$ROOT" || exit 1
fi
if want '^dotfiles/config/quickshell/(bar/|FiliNotification|FiliTheme)|check-accent-follow'; then
python3 -I "$ROOT/tests/fili-shell/check-accent-follow.py" "$ROOT" || exit 1
fi
if want 'FiliTheme.qml|bar/modules/(appmenu|agent)/|bar/BarState.qml|check-packaged-tools'; then
python3 -I "$ROOT/tests/fili-shell/check-packaged-tools.py" "$ROOT" || exit 1
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
