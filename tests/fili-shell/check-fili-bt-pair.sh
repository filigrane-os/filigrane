#!/bin/sh
# fili-bt-pair against a fake bluetoothctl: command sequence, agent, failure and bad input.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cat > "$T/btctl" <<'F'
#!/bin/sh
echo "$*" >> "$FAKE_LOG"
case "$*" in
  *"pair "*) [ "$FAKE_PAIR" = ok ] && echo "Pairing successful" || echo "Failed to pair: org.bluez.Error.AuthenticationFailed" ;;
esac
F
chmod +x "$T/btctl"
export FILI_BTCTL="$T/btctl" FAKE_LOG="$T/log"
A=AA:BB:CC:DD:EE:FF
fail=0
check() { if [ "$2" = ok ]; then echo "ok - $1"; else echo "not ok - $1"; fail=1; fi; }

FAKE_PAIR=ok "$ROOT/dotfiles/home/.local/bin/fili-bt-pair" $A; rc=$?
[ $rc = 0 ] && grep -q -- "--agent NoInputNoOutput pair $A" "$T/log" && check "fili-bt-pair: pairs with an agent" ok || check "fili-bt-pair: pairs with an agent" no
grep -q "^trust $A" "$T/log" && grep -q "^connect $A" "$T/log" && grep -q "^pairable on" "$T/log" && check "fili-bt-pair: pairable, trust, connect" ok || check "fili-bt-pair: pairable, trust, connect" no
: > "$T/log"
FAKE_PAIR=ko "$ROOT/dotfiles/home/.local/bin/fili-bt-pair" $A 2>/dev/null; rc=$?
[ $rc = 1 ] && ! grep -q "^connect" "$T/log" && check "fili-bt-pair: failure stops, exit 1" ok || check "fili-bt-pair: failure stops, exit 1" no
"$ROOT/dotfiles/home/.local/bin/fili-bt-pair" 'x;rm' 2>/dev/null; [ $? = 2 ] && check "fili-bt-pair: bad address refused" ok || check "fili-bt-pair: bad address refused" no
exit $fail
