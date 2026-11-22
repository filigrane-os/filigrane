#!/bin/sh
# The fili command (list, search, info, install, remove, sync) with a test index and stubs for xbps, sudo and the web apps
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FILI="$ROOT/dotfiles/home/.local/bin/fili"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export XDG_CONFIG_HOME="$T/cfg" XDG_DATA_HOME="$T/data" LOG="$T/log"
mkdir -p "$XDG_CONFIG_HOME/filigrane/index.d" "$XDG_CONFIG_HOME/webapps" "$T/stub" "$XDG_DATA_HOME/filigrane/bar/plugins"
: > "$LOG"
fail=0
check() { if eval "$2"; then echo "ok - fili: $1"; else echo "not ok - fili: $1"; fail=1; fi; }
stub() { printf '#!/bin/sh\n%s\n' "$2" > "$T/stub/$1"; chmod +x "$T/stub/$1"; }
stub xbps-query 'case "$*" in *installed_size*) echo 5280KB ;; *) [ -e "$T_HAVE/$1" ] ;; esac'
sed -i "s#\$T_HAVE#$T/have#" "$T/stub/xbps-query"; mkdir -p "$T/have"
stub sudo 'echo "sudo $*" >> "$LOG"; case "$*" in "xbps-install -y "*) for p in ${*#xbps-install -y }; do touch "$T_HAVE/$p"; done ;; "xbps-remove -y "*) rm -f "$T_HAVE/${*#xbps-remove -y }" ;; esac'
sed -i "s#\$T_HAVE#$T/have#g" "$T/stub/sudo"
stub webapp-add 'echo "webapp-add $*" >> "$LOG"; printf "%s | %s | %s\n" "$1" "$2" "$3" >> "$XDG_CONFIG_HOME/webapps/list"'
stub webapp-remove 'echo "webapp-remove $*" >> "$LOG"; grep -v "^$1 " "$XDG_CONFIG_HOME/webapps/list" > "$LOG.w"; cat "$LOG.w" > "$XDG_CONFIG_HOME/webapps/list"'
cat > "$XDG_CONFIG_HOME/filigrane/index.d/00-test.toml" <<'TOML'
# test index
[tapp]
kind = "app"
title = "Test App"
description = "A test application"
package = "tapp-pkg"

[heavy-app]
kind = "app"
title = "Big"
description = "Heavy thing"
package = "big-pkg"
weight = "heavy"

[tplug]
kind = "plugin"
title = "Test Plugin"
description = "A bar plugin"
url = "https://example.invalid/fili-bar-tplug"

[tweb]
kind = "webapp"
title = "Test Web"
description = "A web page"
url = "https://example.org"
icon = "web-browser"
TOML
cat > "$XDG_CONFIG_HOME/filigrane/index.d/10-other.toml" <<'TOML'
[tapp]
kind = "app"
title = "Overridden?"
package = "other-pkg"
TOML
P="$T/stub:$PATH"
check "list shows every entry with its kind" 'out="$(PATH="$P" "$FILI" list)"; echo "$out" | grep -q "^tapp .*app .*Test App" && echo "$out" | grep -q "^tplug .*plugin" && echo "$out" | grep -q "^tweb .*webapp"'
check "the first definition of an entry wins" '[ "$(PATH="$P" "$FILI" list | grep -c "^tapp ")" = 1 ] && PATH="$P" "$FILI" info tapp | grep -q "package: tapp-pkg"'
check "list filters by kind" '[ "$(PATH="$P" "$FILI" list plugin | wc -l)" = 1 ]'
check "search matches the description" 'PATH="$P" "$FILI" search "bar plugin" | grep -q "^tplug "'
check "info shows the fields and the state" 'PATH="$P" "$FILI" info tweb | grep -q "url: https://example.org" && PATH="$P" "$FILI" info tweb | grep -q "not installed"'
check "an unknown entry is refused" '! PATH="$P" "$FILI" install nope 2> /dev/null'
# app
check "install of an app shows the plan and installs nothing without --yes" 'PATH="$P" "$FILI" install tapp > "$T/out"; [ $? = 2 ] && grep -q "xbps package tapp-pkg (5280KB)" "$T/out" && ! grep -q "xbps-install" "$LOG"'
check "a heavy app says so" 'PATH="$P" "$FILI" install heavy-app | grep -q "Heavy"'
PATH="$P" "$FILI" install tapp --yes > /dev/null
check "install --yes runs xbps-install and records the app" 'grep -qx "sudo xbps-install -y tapp-pkg" "$LOG" && grep -q "^tapp = \"tapp-pkg\"" "$XDG_CONFIG_HOME/filigrane/apps.toml"'
check "list shows it installed" 'PATH="$P" "$FILI" list --installed | grep -q "^tapp "'
check "installing twice does nothing" 'PATH="$P" "$FILI" install tapp --yes | grep -q "already installed"'
check "remove needs --yes" 'PATH="$P" "$FILI" remove tapp > /dev/null; [ $? = 2 ] && PATH="$P" "$FILI" list --installed | grep -q "^tapp "'
PATH="$P" "$FILI" remove tapp --yes > /dev/null
check "remove --yes runs xbps-remove and forgets the app" 'grep -qx "sudo xbps-remove -y tapp-pkg" "$LOG" && ! grep -q "^tapp" "$XDG_CONFIG_HOME/filigrane/apps.toml"'
# sync of the recorded apps
printf '[apps]\nback = "back-pkg"\n' > "$XDG_CONFIG_HOME/filigrane/apps.toml"; : > "$LOG"
stub fili-bar 'echo "fili-bar $*" >> "$LOG"'; cp "$T/stub/fili-bar" "$T/fili-bar"
mkdir -p "$T/bin"; cp "$FILI" "$T/bin/fili"; cp "$T/stub/fili-bar" "$T/bin/fili-bar"
check "sync installs the recorded apps then the plugins" 'PATH="$P" "$T/bin/fili" sync > /dev/null; grep -qx "sudo xbps-install -y  back-pkg" "$LOG" || grep -qx "sudo xbps-install -y back-pkg" "$LOG"; grep -q "fili-bar sync" "$LOG"'
# web app
check "install of a web app shows the plan and adds nothing without --yes" 'PATH="$P" "$FILI" install tweb > /dev/null; [ $? = 2 ] && ! grep -q webapp-add "$LOG"'
: > "$LOG"; PATH="$P" "$FILI" install tweb --yes > /dev/null
check "install --yes calls webapp-add with title, url and icon" 'grep -qx "webapp-add Test Web https://example.org web-browser" "$LOG"'
check "list shows the web app installed" 'PATH="$P" "$FILI" list webapp --installed | grep -q "^tweb "'
PATH="$P" "$FILI" remove tweb --yes > /dev/null
check "remove --yes calls webapp-remove" 'grep -qx "webapp-remove Test Web" "$LOG"'
# plugin: handed to fili-bar (the real one is tested by check-fili-bar-cli.sh)
: > "$LOG"
check "install of a plugin goes through fili-bar" 'PATH="$P" "$T/bin/fili" install tplug --yes > /dev/null; grep -qx "fili-bar install https://example.invalid/fili-bar-tplug --yes" "$LOG"'
# published index: cloned by update, below the user layers and above 00-core
IX="$T/ix"; mkdir -p "$IX"
(cd "$IX" && git init -q && printf '[remote-only]\nkind = "webapp"\ntitle = "From Remote"\nurl = "https://remote.example"\n\n[tapp]\nkind = "app"\ntitle = "Remote tapp"\npackage = "remote-pkg"\n' > index.toml && git add . && git -c user.name=t -c user.email=t@t commit -qm i)
check "update clones the published index" 'FILI_INDEX_URL="$IX" PATH="$P" "$FILI" update | grep -q "2 entries" && PATH="$P" "$FILI" list | grep -q "^remote-only "'
check "a user layer file wins over the published index" 'PATH="$P" "$FILI" info tapp | grep -q "package: tapp-pkg"'
(cd "$IX" && printf '\n[second]\nkind = "webapp"\ntitle = "Second"\nurl = "https://second.example"\n' >> index.toml && git -c user.name=t -c user.email=t@t commit -qam i2)
check "update pulls the new entries" 'FILI_INDEX_URL="$IX" PATH="$P" "$FILI" update > /dev/null && PATH="$P" "$FILI" list | grep -q "^second "'
check "the published index wins over 00-core" '
    mkdir -p "$T/pc/filigrane/index.d"; printf "[remote-only]\nkind = \"app\"\ntitle = \"Core\"\npackage = \"core-pkg\"\n" > "$T/pc/filigrane/index.d/00-core.toml"
    XDG_CONFIG_HOME="$T/pc" PATH="$P" "$FILI" info remote-only | grep -q "url: https://remote.example"'
check "the index of the distribution parses and every app has a package, every plugin and web app a url" '
    XDG_CONFIG_HOME="$T/real" ; mkdir -p "$T/real/filigrane/index.d"; cp "$ROOT"/dotfiles/config/filigrane/index.d/*.toml "$T/real/filigrane/index.d/"
    ok=1; for n in $(XDG_CONFIG_HOME="$T/real" PATH="$P" "$FILI" list | awk "{print \$1}"); do
        k="$(XDG_CONFIG_HOME="$T/real" PATH="$P" "$FILI" info "$n" | sed -n "1s/.*(\(.*\)).*/\1/p")"
        i="$(XDG_CONFIG_HOME="$T/real" PATH="$P" "$FILI" info "$n")"
        case "$k" in app) echo "$i" | grep -q "^package: " || ok=0 ;; plugin | webapp) echo "$i" | grep -q "^url: https://" || ok=0 ;; *) ok=0 ;; esac
    done; [ "$ok" = 1 ]'
exit "$fail"
