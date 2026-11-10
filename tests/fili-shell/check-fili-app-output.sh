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
# Applications on a monitor or a named workspace, numbered workspaces and their bindings
mkdir -p "$XDG_CONFIG_HOME/niri"; B="$XDG_CONFIG_HOME/niri/workspace-binds.kdl"
printf 'binds {\n    Mod+1 hotkey-overlay-title="One" { focus-workspace 1; }\n    // Mod+2 { focus-workspace 2; }\n    Mod+Ctrl+3 { move-column-to-workspace 3; } // end\n    Mod+9 { focus-workspace 9; }\n}\n' > "$XDG_CONFIG_HOME/niri/config.kdl"
"$FA" set foot "A 1 2"; "$FA" set-workspace foot 2
check "set-workspace replaces the monitor of the application" '! grep -q "^foot" "$S/app-outputs" && grep -q "open-on-workspace \"2\"" "$O"'
"$FA" numbered 2 "A 1 2" 1 "B 3 4"
check "numbered names 1..N in the given order, keeps the other pinned workspaces" '[ "$(cut -f1 "$S/workspace-outputs" | tr "\n" " ")" = "ws-a bad\\name ws-b 1 2 3 " ] && grep -q "^3${tab}B 3 4$" "$S/workspace-outputs"'
check "bindings by index up to N repeated by name, comments and higher numbers skipped" '[ "$(grep -c "workspace \"[0-9]" "$B")" = 2 ] && grep -q "Mod+1 hotkey-overlay-title=\"One\" { focus-workspace \"1\"; }" "$B" && grep -q "Mod+Ctrl+3 { move-column-to-workspace \"3\"; }$" "$B"'
check "json lists applications and workspaces" '[ "$("$FA" json | jq -r "[(.apps[] | select(.app == \"foot\") | .workspace), ([.workspaces[] | select(.output == \"B 3 4\")] | length)] | join(\",\")")" = "2,1" ]'
"$FA" numbered
check "numbering off: no numbered workspace, no binding" '! grep -q "^[0-9]" "$S/workspace-outputs" && ! grep -q binds "$B"'
"$FA" forget foot > /dev/null
check "forget also removes the workspace of the application" '[ ! -s "$S/app-workspaces" ]'
# Placement of the windows: one rule per application, valid for niri, kept apart from the monitor, cleared by none/forget
"$FA" set zed "A 1 2"; "$FA" layout zed left; "$FA" layout mpv float; "$FA" layout foot full
check "layout left: floating half against the left edge" 'grep -q "relative-to=\"left\"" "$O" && grep -q "proportion 0.5" "$O"'
check "layout full and float" 'grep -q "open-maximized-to-edges true" "$O" && grep -q "^    open-floating true$" "$O"'
check "layout rejects an unknown mode (top and bottom are not offered)" '! "$FA" layout zed sideways 2>/dev/null && ! "$FA" layout zed top 2>/dev/null'
check "json: layout next to the monitor, an application with only a layout listed" '[ "$("$FA" json | jq -r "[(.apps[] | select(.app == \"zed\") | .output + \"/\" + .layout), (.apps[] | select(.app == \"mpv\") | .layout)] | join(\",\")")" = "A 1 2/left,float" ]'
if command -v niri > /dev/null; then
    printf 'include "app-outputs.kdl"\n' > "$T/cfg/niri/check.kdl"
    check "generated rules are valid for niri" 'niri validate -c "$T/cfg/niri/check.kdl" > /dev/null 2>&1'
fi
"$FA" layout zed none
check "layout none removes the placement only" '! grep -q "^zed" "$S/app-layouts" && grep -q "^zed" "$S/app-outputs"'
"$FA" forget mpv > /dev/null
check "forget also removes the placement" '! grep -q "^mpv" "$S/app-layouts"'
exit "$fail"
