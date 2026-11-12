#!/bin/sh
# fili-theme header|footer: the headless and status-bar options of the fili-* windows are written to [window] of theme.toml,
# read back, removed with "default", and do not disturb the rest of the file (other sections, comments, the font).
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
export XDG_CONFIG_HOME="$tmp/config" XDG_STATE_HOME="$tmp/state"
unset WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS
mkdir -p "$XDG_CONFIG_HOME/filigrane"
T="$XDG_CONFIG_HOME/filigrane/theme.toml"
S="$ROOT/dotfiles/home/.local/bin/fili-theme"
fail() { echo "not ok - fili-theme header/footer: $1"; exit 1; }
get() { sh "$S" "$1"; }

[ "$(get header)" = on ] && [ "$(get footer)" = on ] || fail "default is not on without a file"

printf '# my colours\n[theme]\nfont = "Inter"  # sans\n\n[theme.dark]\nbackground = "#101010"\n' > "$T"
sh "$S" header off || fail "header off failed"
[ "$(get header)" = off ] && [ "$(get footer)" = on ] || fail "header off changed the footer or was not stored"
sh "$S" footer off || fail "footer off failed"
[ "$(get footer)" = off ] || fail "footer off not stored"
grep -q '^# my colours$' "$T" && grep -q '^font = "Inter"' "$T" && grep -q '^background = "#101010"$' "$T" || fail "other lines of theme.toml were lost"
[ "$(grep -c '^\[window\]$' "$T")" = 1 ] || fail "[window] section duplicated"

sh "$S" header on && sh "$S" footer default || fail "on/default failed"
[ "$(get header)" = on ] && [ "$(get footer)" = on ] || fail "on / default not read back"
grep -q '^footer' "$T" && fail "default did not remove the key"

sh "$S" header maybe 2>/dev/null && fail "invalid value accepted"
echo "ok - fili-theme header and footer ([window] of theme.toml)"
