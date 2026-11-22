#!/bin/bash
# The Filigrane API without an assistant (docs/api.md): fili-api catalogs, fili-event, and the incident handlers of
# fili-incident, in isolated state, runtime and config folders.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$ROOT/dotfiles/home/.local/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export XDG_CONFIG_HOME="$T/cfg" XDG_DATA_HOME="$T/data" XDG_STATE_HOME="$T/state" XDG_RUNTIME_DIR="$T/run" HOME="$T/home" FILI_SHELL_DIRS="$T/shell"
export PATH="$BIN:$PATH"
mkdir -p "$T/shell/ctl" "$T/shell/incident" "$XDG_CONFIG_HOME" "$XDG_RUNTIME_DIR/fili/context" "$XDG_STATE_HOME/filigrane/incidents" "$HOME"
fail=0
check() { if eval "$2"; then echo "ok - api: $1"; else echo "not ok - api: $1"; fail=1; fi; }

cat > "$T/shell/ctl/demo.json" <<'J'
{ "v": 1, "app_id": "demo", "name": "Demo", "program": "demo", "ctl": "demo ctl --pid %pid",
  "commands": [ { "verb": "action", "args": "NAME", "summary": "Run a command", "reads": false }, { "verb": "state", "summary": "State", "reads": true } ],
  "actions": [ { "name": "go", "label": "Go There", "keys": "Ctrl+G", "args": "NAME" }, { "name": "quiet" } ] }
J
check "list shows a catalog" 'fili-api list | grep -q "^demo .*Demo .*2 "'
check "show finds it by name, any case" 'fili-api show DEMO | grep -q "state   \[read\]"'
check "show lists the actions with label and shortcut" 'fili-api show demo | grep -q "go NAME  Go There  (Ctrl+G)" && fili-api show demo | grep -q "^  quiet$"'
check "check refuses malformed actions" 'echo "{\"v\":1,\"app_id\":\"x\",\"name\":\"X\",\"ctl\":\"x\",\"commands\":[],\"actions\":[\"a\"]}" > "$T/act.json"; ! fili-api check "$T/act.json" > /dev/null'
check "show refuses an unknown application" '! fili-api show nothing 2> /dev/null'
check "check accepts a valid catalog" 'fili-api check "$T/shell/ctl/demo.json" > /dev/null'
LINT="$BIN/fili-api-lint"
# One fixture per rule of the format: a catalog that breaks only that rule must fail with its message
bad() { # bad "what" 'jq filter that breaks the demo catalog' "message that must appear"
    mkdir -p "$T/f"; jq "$2" "$T/shell/ctl/demo.json" > "$T/f/demo.json"
    check "the format refuses $1" 'out="$(python3 -I "$LINT" "$T/f/demo.json")"; [ $? -ne 0 ] && echo "$out" | grep -q "$3"'
}
bad "an unknown key" '.extra = 1' "unknown key extra"
bad "a newer version" '.v = 2' "this tool understands 1"
bad "a ctl without %pid" '.ctl = "demo ctl"' 'ctl must be exactly'
bad "a command without summary" 'del(.commands[0].summary)' "missing summary"
bad "a summary with a final full stop" '.commands[0].summary = "Run a command."' "full stop"
bad "a summary without a capital" '.commands[0].summary = "run a command"' "capital letter"
bad "empty args" '.commands[0].args = ""' "args: 1-120"
bad "a verb twice" '.commands += [.commands[0]]' "listed twice"
bad "reads that is not a boolean" '.commands[0].reads = "no"' "reads must be"
bad "an action twice" '.actions += [.actions[0]]' "action go is listed twice"
bad "an action argument that is not capitals" '.actions[0].args = "name"' "placeholders in capitals"
bad "a required argument after an optional one" '.actions[0].args = "[A] B"' "after an optional one"
bad "actions without the verb action" '.commands |= map(select(.verb != "action"))' "needs the verb"
bad "a malformed pattern" '.action_patterns = [{"pattern":"open","summary":"Open"}]' "name:<param>"
check "the format accepts args and patterns" 'jq ".actions[0].args = \"[NAME] [MODE]\" | .action_patterns = [{\"pattern\":\"open:<id>\",\"summary\":\"Open one\"}]" "$T/shell/ctl/demo.json" > "$T/f/demo.json"; python3 -I "$LINT" "$T/f/demo.json" > /dev/null'
check "a file is named after its app id" 'cp "$T/shell/ctl/demo.json" "$T/other.json"; python3 -I "$LINT" "$T/other.json" | grep -q "is named other.json"'
check "fili-api check is the same validator" 'jq ".extra = 1" "$T/shell/ctl/demo.json" > "$T/f/demo.json"; out="$(fili-api check "$T/f/demo.json")"; [ $? -ne 0 ] && echo "$out" | grep -q "unknown key extra"'

# Context and incident files: what the applications really write
ctx() { mkdir -p "$T/c"; printf '%s' "$1" > "$T/c/$2.json"; python3 -I "$LINT" context "$T/c/$2.json"; }
check "a context with its keys is accepted" 'ctx "{\"app\":\"Casier\",\"pid\":42,\"about\":\"What it means\",\"location\":\"/tmp\",\"selection\":[\"a\"],\"selection_count\":1,\"asked_block\":null}" 42 | grep -q "^ok"'
check "a context needs app, pid and about" 'out="$(ctx "{\"app\":\"X\"}" 43)"; echo "$out" | grep -q "missing pid" && echo "$out" | grep -q "missing about"'
check "a context file is named after its pid" 'ctx "{\"app\":\"X\",\"pid\":1,\"about\":\"a\"}" 44 | grep -q "is named 44.json, pid is 1"'
check "a context key is snake_case" 'ctx "{\"app\":\"X\",\"pid\":45,\"about\":\"a\",\"askedBlock\":1}" 45 | grep -q "snake_case"'
check "a selection is a list of strings" 'ctx "{\"app\":\"X\",\"pid\":46,\"about\":\"a\",\"selection\":\"a\"}" 46 | grep -q "selection: a list"'
INC='{"id":"demo-1-ab","app":"demo","repo":"o/r","version":"1.0","kind":"qml","signature":"0123456789abcdef","message":"boom","when":1795000000,"state":"new","system":"Void","log":["l"]}'
inc() { mkdir -p "$T/i"; printf '%s' "$1" > "$T/i/$2.json"; python3 -I "$LINT" incident "$T/i/$2.json"; }
check "an incident with its keys is accepted" 'inc "$INC" demo-1-ab | grep -q "^ok"'
check "an incident time is a number, not a string" 'inc "$(echo "$INC" | jq ".when = \"1795000000\"")" demo-1-ab | grep -q "whole number of seconds"'
check "an incident signature is 16 hex digits" 'inc "$(echo "$INC" | jq ".signature = \"xyz\"")" demo-1-ab | grep -q "16 hexadecimal"'
check "an incident state is one of four" 'inc "$(echo "$INC" | jq ".state = \"open\"")" demo-1-ab | grep -q "new, notified"'
check "an incident has no unknown key" 'inc "$(echo "$INC" | jq ".extra = 1")" demo-1-ab | grep -q "unknown key extra"'
check "a reported incident may carry issue and pr" 'inc "$(echo "$INC" | jq ".state = \"reported\" | .issue = \"u\" | .pr = \"p\"")" demo-1-ab | grep -q "^ok"'
ui() { mkdir -p "$T/u"; printf '%s' "$1" > "$T/u/ui.json"; python3 -I "$LINT" ai-ui "$T/u/ui.json"; }
check "the assistant state is accepted" 'ui "{\"v\":1,\"open\":true,\"focused\":false,\"attention\":\"waiting\",\"busy\":false}" | grep -q "^ok"'
check "the assistant state refuses a bad attention and a missing key" 'out="$(ui "{\"v\":1,\"open\":true,\"focused\":false,\"attention\":\"maybe\"}")"; echo "$out" | grep -q "missing busy" && ui "{\"v\":1,\"open\":true,\"focused\":false,\"attention\":\"maybe\",\"busy\":false}" | grep -q "attention:"'
mkdir -p "$XDG_STATE_HOME/filigrane/incidents"; echo "$INC" > "$XDG_STATE_HOME/filigrane/incidents/demo-1-ab.json"
check "doctor accepts the files of the applications" 'fili-api doctor | grep -q "^ok: .* follow the formats"'
echo "$INC" | jq '.when = "1"' > "$XDG_STATE_HOME/filigrane/incidents/demo-1-ab.json"
check "doctor reports a file that drifts" 'out="$(fili-api doctor)"; [ $? -ne 0 ] && echo "$out" | grep -q "demo-1-ab.json: when"'
rm -f "$XDG_STATE_HOME/filigrane/incidents/demo-1-ab.json"

# The applications: each catalog it ships follows the format and its source, and its copy of the validator is this one
for pin in "$ROOT"/apps/*/upstream; do
    [ -f "$pin" ] || continue
    app="$(basename "$(dirname "$pin")")"
    src="$("$ROOT/scripts/upstream-dir" "$app" 2> /dev/null)" || continue
    [ -d "$src/shell/ctl" ] || continue
    # An application whose sources are in a workspace (fili-ai: crates/fili-ai-window) is checked from that crate
    root="$src"; [ -d "$src/src" ] || root="$(dirname "$(ls -d "$src"/crates/*/shell 2> /dev/null | head -1)")"
    check "$app: its catalog follows the format and its source" 'python3 -I "$src/scripts/fili-api-lint" --app "$root" > /dev/null'
    check "$app: its fili-api-lint is the distribution one" 'cmp -s "$src/scripts/fili-api-lint" "$LINT"'
done
echo '{"app":"Demo","pid":'$$',"location":"/tmp"}' > "$XDG_RUNTIME_DIR/fili/context/$$.json"
echo '{"app":"Dead","pid":999999}' > "$XDG_RUNTIME_DIR/fili/context/999999.json"
check "apps lists the running ones only" 'fili-api apps | grep -q "Demo" && ! fili-api apps | grep -q Dead'

fili-event emit incident.new '{"id":"a"}'; fili-event emit theme.changed
check "events are listed in order" '[ "$(fili-event list | jq -r .name | tr "\n" " ")" = "incident.new theme.changed " ]'
check "list filters by name" '[ "$(fili-event list theme.changed | wc -l)" = 1 ]'
check "an event carries its data" '[ "$(fili-event list incident.new | jq -r .data.id)" = a ]'
check "a bad name or bad data is refused" '! fili-event emit "Bad Name" 2> /dev/null && ! fili-event emit x "{nope" 2> /dev/null'
for i in $(seq 105); do fili-event emit tick; done
check "only the last 100 events are kept" '[ "$(ls "$XDG_RUNTIME_DIR/fili/events" | wc -l)" -le 100 ]'
fili-event watch tick > "$T/watched" & wpid=$!
sleep 1.5; fili-event emit tick '{"n":1}'; sleep 2.5; kill $wpid 2> /dev/null; wait $wpid 2> /dev/null
check "watch prints a new event" 'grep -q "\"n\":1" "$T/watched"'

check "Lia's default brief points to fili-api" 'grep -q "fili-api show" "$("$ROOT/scripts/upstream-dir" fili-ai)/data/prompts/lia/_default.md"'

# fili-incident: no handler = no assistant; a handler adds its button and runs with the prompt as its last argument
INC="$ROOT/apps/fili-incident/target/release/fili-incident"
(cd "$ROOT/apps/fili-incident" && cargo build --release -q --locked 2> /dev/null)
echo '{"id":"i1","app":"demo","repo":"o/r","kind":"manual","signature":"s","message":"boom","state":"new","log":[]}' > "$XDG_STATE_HOME/filigrane/incidents/i1.json"
check "without a handler, ask says no assistant is installed" '"$INC" ask i1 2>&1 | grep -q "no assistant installed" && [ -z "$("$INC" handlers)" ]'
printf '#!/bin/sh\nprintf "%%s" "$1" > "%s"\n' "$T/prompt" > "$T/h.sh"; chmod +x "$T/h.sh"
printf 'label = "Ask Demo"\ncommand = "%s"\n' "$T/h.sh" > "$T/shell/incident/demo.toml"
check "a shipped handler is found" '"$INC" handlers | grep -q "^demo.Ask Demo"'
"$INC" ask i1; sleep 0.5
check "ask runs it with the prompt as the last argument" 'grep -q "fili-incident show i1" "$T/prompt"'
mkdir -p "$XDG_CONFIG_HOME/filigrane/incident"; printf 'label = "Mine"\ncommand = "%s"\n' "$T/h.sh" > "$XDG_CONFIG_HOME/filigrane/incident/demo.toml"
check "a handler of the user wins over the shipped one of the same name" '"$INC" handlers | grep -q "^demo.Mine"'
exit $fail
