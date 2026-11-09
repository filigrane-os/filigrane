#!/bin/sh
# fili-bt-autoconnect against a fake bluetoothctl: connects trusted+paired devices that are
# disconnected, skips connected ones, retries a failure, waits for the adapter.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cat > "$T/btctl" <<'F'
#!/bin/sh
echo "$*" >> "$FAKE_LOG"
case "$*" in
  show) echo "Powered: $FAKE_POWER" ;;
  "devices Trusted") echo "Device AA:00:00:00:00:01 Keyboard"; echo "Device AA:00:00:00:00:02 Mouse"; echo "Device AA:00:00:00:00:03 Unpaired" ;;
  "info AA:00:00:00:00:02") echo "Paired: yes"; echo "Connected: yes" ;;
  "info AA:00:00:00:00:03") echo "Paired: no"; echo "Connected: no" ;;
  info*) echo "Paired: yes"; echo "Connected: no" ;;
  *connect\ AA:00:00:00:00:01) [ "$FAKE_FAIL" = 1 ] && exit 1 ;;
esac
exit 0
F
chmod +x "$T/btctl"
export FILI_BTCTL="$T/btctl" FAKE_LOG="$T/log" FILI_BT_TRIES=3 FILI_BT_DELAY=0 FAKE_POWER=yes
S="$ROOT/dotfiles/home/.local/bin/fili-bt-autoconnect"
fail=0
check() { if [ "$2" = ok ]; then echo "ok - $1"; else echo "not ok - $1"; fail=1; fi; }

"$S"
grep -q "connect AA:00:00:00:00:01" "$T/log" && check "fili-bt-autoconnect: connects a disconnected device" ok || check "fili-bt-autoconnect: connects a disconnected device" no
! grep -q "connect AA:00:00:00:00:02" "$T/log" && ! grep -q "connect AA:00:00:00:00:03" "$T/log" && check "fili-bt-autoconnect: skips connected and unpaired" ok || check "fili-bt-autoconnect: skips connected and unpaired" no
: > "$T/log"; FAKE_FAIL=1 "$S"
[ "$(grep -c "connect AA:00:00:00:00:01" "$T/log")" = 3 ] && check "fili-bt-autoconnect: retries then gives up" ok || check "fili-bt-autoconnect: retries then gives up" no
: > "$T/log"; FAKE_POWER=no "$S"
! grep -q "connect" "$T/log" && grep -q "power on" "$T/log" && check "fili-bt-autoconnect: no adapter, no connect" ok || check "fili-bt-autoconnect: no adapter, no connect" no
exit $fail
