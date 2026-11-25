#!/bin/sh
# fili-assistant CLI (status, set) in an isolated home: ai.env and the personal layer, credentials never opened
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FA="$ROOT/dotfiles/home/.local/bin/fili-assistant"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" FILI_ASSISTANT_ROOT="$T/repo"
unset WAYLAND_DISPLAY
mkdir -p "$HOME/.config/filigrane" "$T/repo/users/me" "$HOME/.claude"
printf '# Generated\nFILI_AI=claude\nFILI_AI_MODEL=\x27\x27\nFILI_AGENT_MODEL=sonnet\nFILI_AI_ARGS=--dangerously-skip-permissions\\ --add-dir\\ ~\nFILIGRANE_DIR=%s\n' "$T/repo" > "$XDG_CONFIG_HOME/filigrane/ai.env"
printf 'me\n' > "$T/repo/.user-layer"
printf 'FILI_AI="claude"\nOTHER=1\n' > "$T/repo/users/me/config.env"
printf '{"secret":"never printed"}' > "$HOME/.claude/.credentials.json"
fail=0
check() { if eval "$2"; then echo "ok - fili-assistant: $1"; else echo "not ok - fili-assistant: $1"; fail=1; fi; }

check "status gives the agent, the quick model and the five agents" '"$FA" status | jq -e ".v == 1 and .agent == \"claude\" and .agent_model == \"sonnet\" and (.agents | map(.id) == [\"claude\",\"codex\",\"ollama\",\"opencode\",\"none\"])" > /dev/null'
check "signed in only means that the login file exists, its content is never output" '"$FA" status | jq -e ".agents[0].signed_in == true" > /dev/null && ! "$FA" status | grep -q "never printed"'
check "an agent without a login file is not signed in" '"$FA" status | jq -e "(.agents | map(select(.id == \"opencode\"))[0].signed_in) == false" > /dev/null'
"$FA" set agent codex
check "set agent writes ai.env and keeps the other lines" '[ "$("$FA" status | jq -r .agent)" = codex ] && grep -q "^FILI_AI_ARGS=--dangerously" "$XDG_CONFIG_HOME/filigrane/ai.env" && [ "$(grep -c "^FILI_AI=" "$XDG_CONFIG_HOME/filigrane/ai.env")" = 1 ]'
check "set agent also changes the personal layer when it sets the variable" 'grep -qx "FILI_AI=\"codex\"" "$T/repo/users/me/config.env" && grep -qx "OTHER=1" "$T/repo/users/me/config.env"'
"$FA" set model gpt-oss:20b
check "set model writes FILI_AI_MODEL, and the layer is untouched when it does not set it" '[ "$("$FA" status | jq -r .model)" = "gpt-oss:20b" ] && ! grep -q FILI_AI_MODEL "$T/repo/users/me/config.env"'
"$FA" set agent-model ""
check "an empty value gives back the default of the agent" '[ -z "$("$FA" status | jq -r .agent_model)" ]'
check "set refuses an unknown agent, a bad key and a value with a shell character" '! "$FA" set agent nope 2> /dev/null && ! "$FA" set colour red 2> /dev/null && ! "$FA" set model "x; rm -rf /" 2> /dev/null && ! "$FA" set model "\$(id)" 2> /dev/null'
check "ai.env still sources cleanly" '(. "$XDG_CONFIG_HOME/filigrane/ai.env" && [ "$FILI_AI" = codex ] && [ "$FILI_AI_MODEL" = "gpt-oss:20b" ])'
exit $fail
