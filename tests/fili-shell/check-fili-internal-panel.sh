#!/bin/sh
# fili-internal-panel: the internal panel starts off only when enough external displays of its card are connected,
# threshold from the environment or internal-panel.toml (0 = never), file rewritten only on change, wired in niri
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FP="$ROOT/dotfiles/home/.local/bin/fili-internal-panel"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export XDG_CONFIG_HOME="$T/cfg" FILI_DRM_DIR="$T/drm"
unset FILI_INTERNAL_OFF_AT
O="$XDG_CONFIG_HOME/niri/internal-panel.kdl"
C="$XDG_CONFIG_HOME/filigrane/internal-panel.toml"
fail=0
check() { if eval "$2"; then echo "ok - fili-internal-panel: $1"; else echo "not ok - fili-internal-panel: $1"; fail=1; fi; }
conn() { mkdir -p "$FILI_DRM_DIR/$1"; echo "$2" > "$FILI_DRM_DIR/$1/status"; }
off() { grep -q "^output \"eDP-1\" { off; }" "$O"; }

conn card0-eDP-1 connected
conn card0-DP-1 disconnected
conn card0-DP-6 connected; conn card0-DP-8 connected; conn card0-DP-9 connected
"$FP"
check "no threshold set: never off, even with three external displays" '! off'
mkdir -p "$(dirname "$C")"; printf '# comment\noff-at = 3\n' > "$C"
"$FP"
check "threshold 3 from internal-panel.toml: off with three external displays" 'off'
rm -rf "$FILI_DRM_DIR/card0-DP-9"
"$FP"
check "two external displays: the panel comes back on" '! off'
conn card1-DVI-I-1 connected
"$FP"
check "a display of another card (DisplayLink) does not count" '! off'
conn card0-DP-9 connected
FILI_INTERNAL_OFF_AT=0 "$FP"
check "FILI_INTERNAL_OFF_AT=0 overrides the file: never off" '! off'
FILI_INTERNAL_OFF_AT=2 "$FP"
check "FILI_INTERNAL_OFF_AT=2 is honored" 'off'
FILI_INTERNAL_OFF_AT=yes "$FP" 2> "$T/err"
check "invalid threshold: warning, treated as 0" '! off && grep -q "invalid threshold" "$T/err"'
"$FP"; touch -d "2000-01-01" "$O"; "$FP"
check "unchanged content: the file is not rewritten (niri reloads on every write)" '[ "$(date -r "$O" +%Y)" = 2000 ]'
rm -rf "$FILI_DRM_DIR/card0-eDP-1"
"$FP"
check "no internal panel: nothing to turn off" '! grep -q "^output" "$O"'
check "no temporary file left" '[ ! -e "$O.new" ]'
"$FP" bogus 2> /dev/null; rc=$?
check "unknown argument: usage error" '[ "$rc" -ne 0 ]'
check "niri includes the generated file" 'grep -q "^include optional=true \"internal-panel.kdl\"" "$ROOT/dotfiles/config/niri/config.kdl"'
check "niri starts the watcher" 'grep -q "^spawn-at-startup .*fili-internal-panel watch" "$ROOT/dotfiles/config/niri/config.kdl"'
check ".zprofile applies it before niri starts" 'grep -q "fili-internal-panel$" "$ROOT/dotfiles/home/.zprofile"'
check "the mac-t2 hardware layer sets the threshold" 'grep -q "^off-at = 3" "$ROOT/hardware/mac-t2/dotfiles/config/filigrane/internal-panel.toml"'
exit "$fail"
