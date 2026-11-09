#!/bin/sh
# fili-bar CLI (list, enable, disable, move, new, check, install) in an isolated config and data directory
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FB="$ROOT/dotfiles/home/.local/bin/fili-bar"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export XDG_CONFIG_HOME="$T/cfg" XDG_DATA_HOME="$T/data"
mkdir -p "$XDG_CONFIG_HOME/quickshell/bar" "$XDG_CONFIG_HOME/filigrane"
cp -r "$ROOT/dotfiles/config/quickshell/bar/modules" "$XDG_CONFIG_HOME/quickshell/bar/modules"
fail=0
check() { if eval "$2"; then echo "ok - fili-bar: $1"; else echo "not ok - fili-bar: $1"; fail=1; fi; }

check "list shows the manifests by side and order" '"$FB" list | awk "\$2 == \"right\" { print \$1 }" | head -n 2 | tr "\n" " " | grep -q "^status tray "'
"$FB" disable clock > /dev/null
check "disable writes enabled = false" 'grep -q "^enabled = false" "$XDG_CONFIG_HOME/filigrane/fili-bar.toml" && "$FB" list | grep "^clock" | grep -q " off "'
"$FB" enable clock > /dev/null
check "enable removes it" '! grep -q "enabled" "$XDG_CONFIG_HOME/filigrane/fili-bar.toml"'
"$FB" move power left 5 > /dev/null
check "move sets side and order" '"$FB" list | grep "^power" | grep -q "left *5 "'
check "move refuses a bad side" '! "$FB" move power up 2> /dev/null'
"$FB" new hello > /dev/null
check "new makes a script plugin that passes check" '"$FB" check hello > /dev/null && [ -L "$XDG_CONFIG_HOME/quickshell/bar/modules/hello" ]'
"$FB" new qq --qml > /dev/null
check "new --qml makes a QML plugin that passes check" '"$FB" check qq > /dev/null'
printf 'side = "middle"\ncmd = "./nope.sh"\n' > "$T/data/filigrane/bar/plugins/hello/module.toml"
check "check fails on a bad manifest" '! "$FB" check hello > /dev/null'
R="$T/src/ext"; mkdir -p "$R"
(cd "$R" && git init -q && printf 'title = "Ext"\napi = 1\ncmd = "./e.sh"\n' > module.toml && printf '#!/bin/sh\necho "{}"\n' > e.sh && chmod +x e.sh && git add . && git -c user.name=t -c user.email=t@t commit -qm i)
check "install shows the manifest and installs nothing without --yes" '[ "$("$FB" install "$R" > /dev/null; echo $?)" = 2 ] && [ ! -e "$T/data/filigrane/bar/plugins/ext" ]'
"$FB" install "$R" --yes > /dev/null
check "install --yes clones, links and pins the commit" '[ -L "$XDG_CONFIG_HOME/quickshell/bar/modules/ext" ] && grep -q "^ext = " "$XDG_CONFIG_HOME/filigrane/bar-plugins.toml"'
rm -rf "$T/data/filigrane/bar/plugins/ext" "$XDG_CONFIG_HOME/quickshell/bar/modules/ext"
"$FB" sync > /dev/null
check "sync clones the pinned plugins again" '[ -f "$T/data/filigrane/bar/plugins/ext/module.toml" ]'
printf '[bar]\nedge = "left"   # sidebar\n' > "$XDG_CONFIG_HOME/filigrane/fili-bar.toml"
check "edge ignores an inline comment" '[ "$("$FB" edge)" = left ]'
"$FB" edge bottom > /dev/null
check "edge writes [bar] edge" '[ "$("$FB" edge)" = bottom ]'
check "edge refuses a bad value" '! "$FB" edge middle 2> /dev/null'
"$FB" screens DP-6 HDMI-A-1 > /dev/null
check "screens writes a list" '[ "$("$FB" screens)" = "[\"DP-6\", \"HDMI-A-1\"]" ]'
check "screens refuses a bad name" '! "$FB" screens "a b" 2> /dev/null'
R2="$T/src/fili-bar-pfx"; mkdir -p "$R2"
(cd "$R2" && git init -q && printf 'title = "Pfx"\napi = 1\ncmd = "./e.sh"\n' > module.toml && printf '#!/bin/sh\necho "{}"\n' > e.sh && chmod +x e.sh && git add . && git -c user.name=t -c user.email=t@t commit -qm i)
"$FB" install "$R2" --yes > /dev/null
check "install strips the fili-bar- prefix of the repository name" '[ -L "$XDG_CONFIG_HOME/quickshell/bar/modules/pfx" ]'
R3="$T/src/fili-bar-hook"; mkdir -p "$R3"
(cd "$R3" && git init -q && printf 'title = "Hook"\napi = 1\ncmd = "./e.sh"\n' > module.toml && printf '#!/bin/sh\necho "{}"\n' > e.sh && chmod +x e.sh && printf '#!/bin/sh\necho x >> "$FILI_BAR_OPTIONS.ran"\n' > install.sh && git add . && git -c user.name=t -c user.email=t@t commit -qm i)
export FILI_BAR_OPTIONS="$T/hook.toml"
check "install without --yes shows install.sh and runs nothing" '"$FB" install "$R3" 2> /dev/null | grep -q "echo x" && [ ! -e "$T/hook.toml.ran" ]'
"$FB" install "$R3" --yes > /dev/null
check "install --yes runs install.sh once" '[ "$(wc -l < "$T/hook.toml.ran")" = 1 ]'
"$FB" setup hook > /dev/null
check "setup runs install.sh again" '[ "$(wc -l < "$T/hook.toml.ran")" = 2 ]'
check "setup refuses an unknown plugin" '! "$FB" setup nope 2> /dev/null'
rm -rf "$T/data/filigrane/bar/plugins/hook"; "$FB" sync > /dev/null
check "sync runs install.sh of a plugin it clones" '[ "$(wc -l < "$T/hook.toml.ran")" = 3 ]'
unset FILI_BAR_OPTIONS
rm -f "$XDG_CONFIG_HOME/filigrane/fili-bar.toml"
exit "$fail"
