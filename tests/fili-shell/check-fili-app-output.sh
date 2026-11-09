#!/bin/sh
# fili-app-output: generated niri rules, exact (non-regex) matching of saved entries, atomic include file
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FA="$ROOT/dotfiles/home/.local/bin/fili-app-output"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export XDG_STATE_HOME="$T/state" XDG_CONFIG_HOME="$T/cfg"
unset WAYLAND_DISPLAY
mkdir -p "$XDG_STATE_HOME/filigrane"
S="$XDG_STATE_HOME/filigrane"; O="$XDG_CONFIG_HOME/niri/app-outputs.kdl"
tab="$(printf '\t')"
fail=0
check() { if eval "$2"; then echo "ok - fili-app-output: $1"; else echo "not ok - fili-app-output: $1"; fail=1; fi; }

printf 'org.gnome.Nautilus\tA 1 2\norgxgnomexNautilus\tB 3 4\n' > "$S/app-outputs"
printf 'ws-a\tA 1 2\nbad\\name\tA 1 2\nws-b\t\n' > "$S/workspace-outputs"
"$FA" apply
check "apply writes one rule per application" '[ "$(grep -c "^window-rule" "$O")" = 2 ]'
check "apply writes the pinned workspace" 'grep -q "^workspace \"ws-a\"" "$O"'
check "apply skips a backslash name and an empty monitor" '! grep -q "bad\\\\name\|ws-b" "$O"'
check "apply leaves no temporary file" '[ ! -e "$O.new" ]'
"$FA" forget org.gnome.Nautilus > /dev/null
check "forget removes the exact app-id only (dots are not wildcards)" '[ "$(cat "$S/app-outputs")" = "orgxgnomexNautilus${tab}B 3 4" ]'
exit "$fail"
