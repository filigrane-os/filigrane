#!/bin/sh
# fili-login CLI (list, add, remove, enable, disable, run, start) in an isolated config directory
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FL="$ROOT/dotfiles/home/.local/bin/fili-login"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export XDG_CONFIG_HOME="$T/cfg" XDG_RUNTIME_DIR="$T/run" HOME="$T/home" NIRI_SOCKET="$T/niri.sock"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_RUNTIME_DIR" "$HOME"
CONF="$XDG_CONFIG_HOME/filigrane/login.toml"
export T_OUT="$T/out"
fail=0
check() { if eval "$2"; then echo "ok - fili-login: $1"; else echo "not ok - fili-login: $1"; fail=1; fi; }

check "list is empty without a file" '[ "$("$FL" list | wc -l)" = 1 ]'
id="$("$FL" add "Proton Bridge" "echo bridge >> \$T_OUT")"
check "add derives the id from the name and writes a section" '[ "$id" = proton-bridge ] && grep -q "^\[items.proton-bridge\]" "$CONF" && grep -q "^name = \"Proton Bridge\"" "$CONF"'
check "list shows the item as on" '"$FL" list | grep "^proton-bridge" | grep -q " on "'
id2="$("$FL" add "Proton Bridge" "echo two >> \$T_OUT")"
check "add keeps ids unique" '[ "$id2" = proton-bridge-2 ]'
check "add refuses a double quote" '! "$FL" add x "echo \"hi\"" 2> /dev/null'
check "add refuses a backslash" '! "$FL" add x "echo a\\nb" 2> /dev/null'
check "add refuses an empty command" '! "$FL" add x "" 2> /dev/null'
"$FL" disable proton-bridge-2 > /dev/null
check "disable writes enabled = false" '"$FL" list | grep "^proton-bridge-2" | grep -q " off "'
"$FL" enable proton-bridge-2 > /dev/null
"$FL" disable proton-bridge-2 > /dev/null
"$FL" start > /dev/null
sleep 1
check "start runs the enabled items only" '[ "$(cat "$T_OUT")" = bridge ]'
"$FL" start > /dev/null
sleep 1
check "start runs once per session" '[ "$(wc -l < "$T_OUT")" = 1 ]'
"$FL" start --force > /dev/null
sleep 1
check "start --force runs them again" '[ "$(wc -l < "$T_OUT")" = 2 ]'
"$FL" run proton-bridge-2 > /dev/null
sleep 1
check "run starts one item now, even a disabled one" '[ "$(wc -l < "$T_OUT")" = 3 ]'
"$FL" remove proton-bridge-2 > /dev/null
check "remove drops the section and keeps the others" '! "$FL" list | grep -q "^proton-bridge-2" && "$FL" list | grep -q "^proton-bridge "'
check "remove leaves no doubled blank line" '[ "$(cat -s "$CONF" | wc -l)" = "$(wc -l < "$CONF")" ]'
check "an unknown id is refused" '! "$FL" remove nope 2> /dev/null && ! "$FL" enable "../x" 2> /dev/null'
mkdir -p "$T/layer"; mv "$CONF" "$T/layer/login.toml"; ln -s "$T/layer/login.toml" "$CONF"
"$FL" disable proton-bridge > /dev/null
check "a linked file stays a link and the target is edited" '[ -L "$CONF" ] && grep -q "enabled = false" "$T/layer/login.toml"'
exit $fail
