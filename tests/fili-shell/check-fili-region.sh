#!/bin/sh
# fili-region CLI (list, set, get) and what fili-lang writes for the applications, in an isolated home
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$ROOT/dotfiles/home/.local/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_STATE_HOME="$T/home/.local/state"
unset WAYLAND_DISPLAY LC_ALL LANG
mkdir -p "$HOME"
KDL="$XDG_CONFIG_HOME/niri/locale.kdl"
fail=0
check() { if eval "$2"; then echo "ok - fili-region: $1"; else echo "not ok - fili-region: $1"; fail=1; fi; }
# a region that exists on this machine (the CI image has en_US at least; without any, the test cannot run)
reg="$(locale -a | sed -n 's/^\([a-z][a-z]*_[A-Z][A-Z]*\)\.\(utf8\|UTF-8\)$/\1/p' | head -1)"
if [ -z "$reg" ]; then echo "ok - fili-region: skipped (no language_COUNTRY locale installed)"; exit 0; fi

check "the formats follow the language by default" '[ -z "$("$BIN/fili-region" get)" ]'
check "list offers the installed locales and none is current" '"$BIN/fili-region" list | jq -e --arg r "$reg.UTF-8" "map(select(.locale == \$r)) | length == 1 and all(.current == false)" > /dev/null'
"$BIN/fili-region" set "$reg"
check "set records the region" '[ "$("$BIN/fili-region" get)" = "$reg.UTF-8" ]'
check "the applications get the formats, without the keyboard" 'for v in LC_TIME LC_NUMERIC LC_MONETARY LC_MEASUREMENT LC_PAPER; do grep -q "^    $v \"$reg.UTF-8\"$" "$KDL" || exit 1; done; ! grep -qi -E "xkb|keyboard" "$KDL"'
check "the language is left alone by the region (no LANG line without a language chosen)" '! grep -q "LANG " "$KDL"'
check "list marks the current region" '"$BIN/fili-region" list | jq -e --arg r "$reg.UTF-8" "map(select(.current)) | .[0].locale == \$r" > /dev/null'
"$BIN/fili-lang" set en > /dev/null
check "changing the language keeps the region" 'grep -q "LC_TIME \"$reg.UTF-8\"" "$KDL" && grep -q "LANG " "$KDL"'
"$BIN/fili-region" set language
check "set language gives the formats back to the language" '[ -z "$("$BIN/fili-region" get)" ] && ! grep -q "LC_TIME" "$KDL"'
check "set refuses a region that is not installed" '! "$BIN/fili-region" set xx_XX 2> /dev/null'
check "zone prints a time zone name" '[ -n "$("$BIN/fili-region" zone)" ]'
# time zone
mkdir -p "$T/zi/Europe" "$T/zi/Asia"
: > "$T/zi/Europe/Paris"; : > "$T/zi/Asia/Tokyo"
printf '#c\ncode\tcoord\tTZ\tcomment\nFR,MC\t+4852+00220\tEurope/Paris\tMost of France\nJP\t+353916+1394441\tAsia/Tokyo\tJapan\n' > "$T/zi/zone1970.tab"
export FILI_ZONEINFO="$T/zi" FILI_LOCALTIME="$T/localtime" FILI_REGION_SUDO=env
ln -s "$T/zi/Europe/Paris" "$T/localtime"
check "zone reads the current time zone" '[ "$("$BIN/fili-region" zone)" = Europe/Paris ]'
check "zones lists the zones of the table with their country and place" '"$BIN/fili-region" zones | grep -q "^Asia/Tokyo	JP	Japan$" && "$BIN/fili-region" zones | grep -q "^Europe/Paris	FR	Most of France$" && "$BIN/fili-region" zones | grep -q "^UTC"'
"$BIN/fili-region" zone-set Asia/Tokyo
check "zone-set changes /etc/localtime (through the privileged command)" '[ "$("$BIN/fili-region" zone)" = Asia/Tokyo ]'
check "zone-set refuses a zone that does not exist, and a path that leaves the folder" '! "$BIN/fili-region" zone-set Mars/Base 2> /dev/null && ! "$BIN/fili-region" zone-set ../../etc/passwd 2> /dev/null && ! "$BIN/fili-region" zone-set /etc/passwd 2> /dev/null && [ "$("$BIN/fili-region" zone)" = Asia/Tokyo ]'
exit $fail
