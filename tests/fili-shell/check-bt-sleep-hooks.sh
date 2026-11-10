#!/bin/sh
# Bluetooth sleep hooks (system/zzz.d): the resume hook reconnects the paired devices only if
# the adapter was on before sleep, and never blocks the wake.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
printf '#!/bin/sh\necho "Powered: $FAKE_POWER"\n' > "$T/btctl"
printf '#!/bin/sh\necho ran >> "%s/log"\n' "$T" > "$T/autoconnect"
chmod +x "$T/btctl" "$T/autoconnect"
export FILI_BTCTL="$T/btctl" FILI_BT_STATE="$T/run/bt-powered" FILI_BT_AUTOCONNECT="$T/autoconnect"
S="$ROOT/system/zzz.d/suspend/60-bluetooth" R="$ROOT/system/zzz.d/resume/60-bluetooth"
fail=0
check() { if [ "$2" = ok ]; then echo "ok - $1"; else echo "not ok - $1"; fail=1; fi; }
wait_log() { i=0; while [ ! -s "$T/log" ] && [ "$i" -lt 20 ]; do sleep 0.1; i=$((i + 1)); done; }

FAKE_POWER=yes "$S"; "$R"; wait_log
[ -s "$T/log" ] && [ ! -e "$FILI_BT_STATE" ] && check "bt sleep hooks: adapter on, reconnects on wake" ok || check "bt sleep hooks: adapter on, reconnects on wake" no
rm -f "$T/log"; FAKE_POWER=no "$S"; "$R"; sleep 0.3
[ ! -e "$T/log" ] && check "bt sleep hooks: adapter off, nothing on wake" ok || check "bt sleep hooks: adapter off, nothing on wake" no
printf '#!/bin/sh\nsleep 5\n' > "$T/autoconnect"
FAKE_POWER=yes "$S"; start=$(date +%s); "$R"; end=$(date +%s)
[ $((end - start)) -lt 2 ] && check "bt sleep hooks: resume hook does not wait" ok || check "bt sleep hooks: resume hook does not wait" no
exit $fail
