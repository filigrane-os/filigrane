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
  "actions": [ { "name": "go", "label": "Go There", "keys": "Ctrl+G" }, { "name": "quiet" } ] }
J
check "list shows a catalog" 'fili-api list | grep -q "^demo .*Demo .*2 "'
check "show finds it by name, any case" 'fili-api show DEMO | grep -q "state   \[read\]"'
check "show lists the actions with label and shortcut" 'fili-api show demo | grep -q "go  Go There  (Ctrl+G)" && fili-api show demo | grep -q "^  quiet$"'
check "check refuses malformed actions" 'echo "{\"v\":1,\"app_id\":\"x\",\"name\":\"X\",\"ctl\":\"x\",\"commands\":[],\"actions\":[\"a\"]}" > "$T/act.json"; ! fili-api check "$T/act.json" > /dev/null'
check "show refuses an unknown application" '! fili-api show nothing 2> /dev/null'
check "check accepts a valid catalog" 'fili-api check "$T/shell/ctl/demo.json" > /dev/null'
echo '{"v":1,"app_id":"x","name":"X","ctl":"x ctl --pid","commands":[{"verb":"a"}]}' > "$T/bad.json"
check "check rejects a --pid without %pid and a command without summary" 'out="$(fili-api check "$T/bad.json")"; [ $? -ne 0 ] && echo "$out" | grep -q "needs %pid" && echo "$out" | grep -q "verb and a summary"'
echo '{"v":2,"app_id":"x","name":"X","ctl":"x","commands":[]}' > "$T/new.json"
check "check refuses a newer version" 'fili-api check "$T/new.json" | grep -q "newer"'
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
