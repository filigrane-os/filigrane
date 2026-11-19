#!/bin/sh
# webapp-edit: changes name, URL and icon of a line of the web app list, keeps the other fields, refuses a duplicate
# name or an unknown app, and calls webapp-sync.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp" XDG_CONFIG_HOME="$tmp/.config"
mkdir -p "$XDG_CONFIG_HOME/webapps/icons" "$tmp/bin"
printf 'A | https://a.org | \nB | https://b.org | web-browser\n' > "$XDG_CONFIG_HOME/webapps/list"
printf '#!/bin/sh\necho sync >> "%s/log"\n' "$tmp" > "$tmp/bin/webapp-sync"; chmod +x "$tmp/bin/webapp-sync"
PATH="$tmp/bin:$PATH"
E="$ROOT/dotfiles/home/.local/bin/webapp-edit"
fail() { echo "not ok - webapp-edit: $1"; exit 1; }
list="$XDG_CONFIG_HOME/webapps/list"

"$E" A --name AA --url https://aa.org --icon mail > /dev/null || fail "edit failed"
grep -qx 'AA | https://aa.org | mail' "$list" || fail "line not rewritten"
grep -qx 'B | https://b.org | web-browser' "$list" || fail "another line changed"
"$E" AA --url https://x.org > /dev/null || fail "partial edit failed"
grep -qx 'AA | https://x.org | mail' "$list" || fail "kept fields lost"
"$E" B --name AA > /dev/null 2>&1 && fail "duplicate name accepted"
"$E" nope --url x > /dev/null 2>&1 && fail "unknown app accepted"
"$E" B --icon - > /dev/null || fail "icon reset failed"
grep -qx 'B | https://b.org | ' "$list" || fail "icon not reset"
[ "$(wc -l < "$tmp/log")" = 3 ] || fail "webapp-sync not called once per edit"
echo "ok - webapp-edit"
