#!/bin/sh
# fili-app-output: generated niri rules, exact (non-regex) matching of saved entries, atomic include file
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FA="$ROOT/dotfiles/home/.local/bin/fili-app-output"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export XDG_STATE_HOME="$T/state" XDG_CONFIG_HOME="$T/cfg"
unset WAYLAND_DISPLAY NIRI_SOCKET
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
check "moves go through move-to, numbered-max is written" 'grep -q "Mod+Ctrl+3 { spawn \"fili-app-output\" \"move-to\" \"column\" \"3\"; }" "$B" && [ "$(cat "$S/numbered-max")" = 3 ]'
check "bindings by index up to 9 repeated by name (temporary numbers), comments skipped" '[ "$(grep -c "workspace \"[0-9]" "$B")" = 2 ] && grep -q "Mod+1 hotkey-overlay-title=\"One\" { focus-workspace \"1\"; }" "$B"'
check "json lists applications and workspaces" '[ "$("$FA" json | jq -r "[(.apps[] | select(.app == \"foot\") | .workspace), ([.workspaces[] | select(.output == \"B 3 4\")] | length)] | join(\",\")")" = "2,1" ]'
# Workspaces already open are moved to their monitor and put in order (fake niri: requests by id logged)
F="$T/fake"; mkdir -p "$F"
printf '{"A-1":{"name":"A-1","make":"A","model":"1","serial":"2"},"B-1":{"name":"B-1","make":"B","model":"3","serial":"4"}}' > "$T/outs.json"
printf '[{"id":11,"idx":1,"name":"1","output":"A-1","is_active":true,"is_focused":false},{"id":12,"idx":1,"name":"2","output":"B-1","is_active":true,"is_focused":true},{"id":13,"idx":2,"name":"3","output":"A-1","is_active":false,"is_focused":false}]' > "$T/ws.json"
printf '#!/bin/sh\ncase "$*" in "msg --json outputs") cat "%s/outs.json" ;; "msg --json workspaces") cat "%s/ws.json" ;; esac\n' "$T" "$T" > "$F/niri"
printf '#!/bin/sh\ncat >> "%s/ipc.log"\n' "$T" > "$F/ipc"
chmod +x "$F/niri" "$F/ipc"
PATH="$F:$PATH" NIRI_SOCKET=fake FILI_NIRI_IPC="$F/ipc" "$FA" numbered 2 "A 1 2" 1 "B 3 4"
check "numbered moves the open workspaces to their monitor by id, puts them in order, gives the focus back" '[ "$(tr -d " " < "$T/ipc.log" | tr "\n" "|")" = "{\"Action\":{\"MoveWorkspaceToMonitor\":{\"output\":\"A-1\",\"reference\":{\"Id\":12}}}}|{\"Action\":{\"MoveWorkspaceToMonitor\":{\"output\":\"B-1\",\"reference\":{\"Id\":13}}}}|{\"Action\":{\"MoveWorkspaceToIndex\":{\"index\":2,\"reference\":{\"Id\":12}}}}|{\"Action\":{\"MoveWorkspaceToIndex\":{\"index\":1,\"reference\":{\"Id\":13}}}}|{\"Action\":{\"FocusWorkspace\":{\"reference\":{\"Id\":11}}}}|{\"Action\":{\"FocusWorkspace\":{\"reference\":{\"Id\":12}}}}|" ]'
# move-to: creates the workspace (names the empty one of the focused display) and moves, in one request
printf '[{"id":11,"idx":1,"name":"1","output":"A-1","is_active":true,"is_focused":true},{"id":14,"idx":2,"output":"A-1","is_active":false,"is_focused":false}]' > "$T/ws.json"
: > "$T/ipc.log"; PATH="$F:$PATH" NIRI_SOCKET=fake FILI_NIRI_IPC="$F/ipc" "$FA" move-to column 6
check "move-to a missing number names the empty workspace, then moves the column" '[ "$(tr -d " " < "$T/ipc.log" | tr "\n" "|")" = "{\"Action\":{\"SetWorkspaceName\":{\"name\":\"6\",\"workspace\":{\"Id\":14}}}}|{\"Action\":{\"MoveColumnToWorkspace\":{\"reference\":{\"Name\":\"6\"},\"focus\":true}}}|" ]'
: > "$T/ipc.log"; PATH="$F:$PATH" NIRI_SOCKET=fake FILI_NIRI_IPC="$F/ipc" "$FA" move-to window 1
check "move-to an existing number only moves" '[ "$(wc -l < "$T/ipc.log")" = 1 ] && grep -q MoveWindowToWorkspace "$T/ipc.log"'
"$FA" numbered
check "numbering off: no numbered workspace, no binding" '! grep -q "^[0-9]" "$S/workspace-outputs" && ! grep -q binds "$B"'
"$FA" forget foot > /dev/null
check "forget also removes the workspace of the application" '[ ! -s "$S/app-workspaces" ]'
# Placement of the windows: one rule per application, valid for niri, kept apart from the monitor, cleared by none/forget
"$FA" set zed "A 1 2"; "$FA" layout zed left; "$FA" layout mpv float; "$FA" layout foot full
check "layout left: no niri rule (fili-shell moves the column), kept in the state" '[ "$(grep -c "\^zed\\$" "$O")" = 1 ] && ! grep -q "relative-to" "$O" && grep -q "^zed${tab}left$" "$S/app-layouts"'
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
