#!/bin/sh
# fili-internal-panel: the internal panel starts off only when enough external displays are connected at login
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FP="$ROOT/dotfiles/home/.local/bin/fili-internal-panel"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export XDG_CONFIG_HOME="$T/cfg" FILI_DRM_DIR="$T/drm"
O="$XDG_CONFIG_HOME/niri/internal-panel.kdl"
fail=0
check() { if eval "$2"; then echo "ok - fili-internal-panel: $1"; else echo "not ok - fili-internal-panel: $1"; fail=1; fi; }
conn() { mkdir -p "$FILI_DRM_DIR/card0-$1"; echo "$2" > "$FILI_DRM_DIR/card0-$1/status"; }

conn eDP-1 connected
conn DP-1 disconnected
"$FP"
check "no external display: the panel stays on" '! grep -q "^output" "$O"'
conn DP-6 connected; conn DP-8 connected
"$FP"
check "two external displays: the panel stays on" '! grep -q "^output" "$O"'
conn DP-9 connected
"$FP"
check "three external displays: the panel starts off" 'grep -q "^output \"eDP-1\" { off; }" "$O"'
FILI_INTERNAL_OFF_AT=0 "$FP"
check "threshold 0: never off" '! grep -q "^output" "$O"'
FILI_INTERNAL_OFF_AT=2 "$FP"
check "threshold 2 is honored" 'grep -q "^output \"eDP-1\"" "$O"'
rm -rf "$FILI_DRM_DIR/card0-eDP-1"
"$FP"
check "no internal panel: nothing to turn off" '! grep -q "^output" "$O"'
check "no temporary file left" '[ ! -e "$O.new" ]'
exit "$fail"
