#!/bin/sh
# fili-theme font: the [theme] font of theme.toml reaches GTK (settings.ini) and fontconfig (sans-serif, system-ui);
# an absent or invalid font falls back to Jost; the settings.ini files are generated (a repository link is replaced, never written through).
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
export XDG_CONFIG_HOME="$tmp/config" XDG_STATE_HOME="$tmp/state"
unset WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS
mkdir -p "$XDG_CONFIG_HOME/filigrane" "$XDG_CONFIG_HOME/gtk-3.0" "$tmp/repo"
fail() { echo "not ok - fili-theme font: $1"; exit 1; }

# A link to a "repository" file: the generation must replace it, not write through it
echo "[Settings]" > "$tmp/repo/settings.ini"
ln -s "$tmp/repo/settings.ini" "$XDG_CONFIG_HOME/gtk-3.0/settings.ini"

sh "$ROOT/dotfiles/home/.local/bin/fili-theme" font || fail "command failed"
grep -q '^gtk-font-name=Jost 10$' "$XDG_CONFIG_HOME/gtk-3.0/settings.ini" || fail "default is not Jost"
[ "$(cat "$tmp/repo/settings.ini")" = "[Settings]" ] || fail "wrote through the repository link"
[ ! -L "$XDG_CONFIG_HOME/gtk-3.0/settings.ini" ] || fail "settings.ini is still a link"

printf '[theme]\nfont = "Inter"  # comment\n\n[theme.dark]\nfont = "Other"\n' > "$XDG_CONFIG_HOME/filigrane/theme.toml"
sh "$ROOT/dotfiles/home/.local/bin/fili-theme" font || fail "command failed (Inter)"
for v in 3 4; do
    grep -q '^gtk-font-name=Inter 10$' "$XDG_CONFIG_HOME/gtk-$v.0/settings.ini" || fail "GTK $v does not follow [theme] font"
done
f="$XDG_CONFIG_HOME/fontconfig/conf.d/62-fili-font.conf"
[ "$(grep -c '<string>Inter</string>' "$f")" = 2 ] || fail "fontconfig does not name Inter for sans-serif and system-ui"

printf '[theme]\nfont = "<bad>"\n' > "$XDG_CONFIG_HOME/filigrane/theme.toml"
sh "$ROOT/dotfiles/home/.local/bin/fili-theme" font || fail "command failed (invalid)"
grep -q '^gtk-font-name=Jost 10$' "$XDG_CONFIG_HOME/gtk-3.0/settings.ini" || fail "invalid name does not fall back to Jost"
echo "ok - fili-theme font (GTK and fontconfig follow theme.toml)"
