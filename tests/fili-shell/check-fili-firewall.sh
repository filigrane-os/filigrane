#!/bin/sh
# fili-firewall CLI and fili-firewall-apply (rules generation) in an isolated config directory, without root:
# the helper is replaced by a wrapper that records what would be loaded
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FF="$ROOT/dotfiles/home/.local/bin/fili-firewall"
REAL="$ROOT/system/firewall/fili-firewall-apply"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export XDG_CONFIG_HOME="$T/cfg" HOME="$T/home"
mkdir -p "$XDG_CONFIG_HOME/filigrane" "$HOME"
CONF="$XDG_CONFIG_HOME/filigrane/firewall.toml"
cat > "$T/helper" << EOS
#!/bin/sh
case "\$1" in
    apply) cat > "$T/applied"; exit \${STUB_FAIL:-0} ;;
    status) echo "v4 DROP"; echo "v6 DROP" ;;
    *) exec "$REAL" "\$@" ;;
esac
EOS
chmod +x "$T/helper"
export FILI_FIREWALL_APPLY="$T/helper" FILI_FIREWALL_SUDO=env
fail=0
check() { if eval "$2"; then echo "ok - fili-firewall: $1"; else echo "not ok - fili-firewall: $1"; fail=1; fi; }
rules4() { "$REAL" print4 < "${1:-/dev/null}"; }
rules6() { "$REAL" print6 < "${1:-/dev/null}"; }

# Rules generation
check "default: incoming dropped, outgoing free, forwarding dropped" 'rules4 | grep -q "^:INPUT DROP" && rules4 | grep -q "^:OUTPUT ACCEPT" && rules4 | grep -q "^:FORWARD DROP"'
check "default: established traffic, loopback, DHCP replies, LocalSend and mDNS" 'rules4 | grep -q "ESTABLISHED" && rules4 | grep -q "^-A INPUT -i lo" && rules4 | grep -q "sport 67" && rules4 | grep -q "dport 53317 -s 192.168" && rules4 | grep -q "224.0.0.251"'
check "default IPv6: neighbour discovery kept" 'rules6 | grep -q "neighbour-solicitation" && rules6 | grep -q "ff02::fb"'
printf 'ping = false\nmdns = false\nlocalsend = false\n' > "$T/off.toml"
check "presets off: no ping, mDNS or LocalSend rule" '! rules4 "$T/off.toml" | grep -Eq "echo-request|224.0.0.251|53317" && ! rules6 "$T/off.toml" | grep -Eq "echo-request|ff02::fb"'
printf 'ports = ["tcp:8080:lan", "udp:5000:any"]\n' > "$T/ports.toml"
check "a lan port is limited to the private ranges" 'rules4 "$T/ports.toml" | grep -q "tcp --dport 8080 -s 10.0.0.0/8" && ! rules4 "$T/ports.toml" | grep -q "tcp --dport 8080 -j"'
check "an any port has no source" 'rules4 "$T/ports.toml" | grep -q "^-A INPUT -p udp --dport 5000 -j ACCEPT" && rules6 "$T/ports.toml" | grep -q "^-A INPUT -p udp --dport 5000 -j ACCEPT"'
check "IPv6 lan port: link-local and unique local" 'rules6 "$T/ports.toml" | grep -q "tcp --dport 8080 -s fe80::/10" && rules6 "$T/ports.toml" | grep -q "tcp --dport 8080 -s fc00::/7"'
printf 'enabled = false\n' > "$T/disabled.toml"
check "disabled: policy ACCEPT" 'rules4 "$T/disabled.toml" | grep -q "^:INPUT ACCEPT" && ! rules4 "$T/disabled.toml" | grep -q DROP'
for bad in 'ping = maybe' 'ports = ["tcp:0:lan"]' 'ports = ["tcp:70000:lan"]' 'ports = ["sctp:80:lan"]' 'ports = ["tcp:80:lan; reboot"]' 'ports = "tcp:80:lan"' 'enabled = 1'; do
    printf '%s\n' "$bad" > "$T/bad.toml"
    check "refused: $bad" '! "$REAL" normalize < "$T/bad.toml" > /dev/null 2>&1'
done

# Command
check "list without a file shows the defaults" '[ "$("$FF" list | tr "\n" ,)" = "enabled on,ping on,mdns on,localsend on," ]'
"$FF" block ping > /dev/null
check "block writes the file and loads it" 'grep -q "^ping = false" "$CONF" && grep -q "^ping = false" "$T/applied"'
"$FF" allow ping > /dev/null
check "allow turns it back on" '"$FF" list | grep -q "^ping on"'
check "an unknown preset is refused" '! "$FF" allow telnet 2> /dev/null'
"$FF" open tcp 8080 > /dev/null
check "open defaults to the local network" '"$FF" list | grep -qx "port tcp:8080:lan"'
"$FF" open udp 5000 any > /dev/null
"$FF" open tcp 22 lan > /dev/null
check "ports are kept sorted by number" '[ "$("$FF" list | grep ^port | tr "\n" ,)" = "port tcp:22:lan,port udp:5000:any,port tcp:8080:lan," ]'
"$FF" open tcp 8080 any > /dev/null
check "open again changes the scope, no duplicate" '[ "$("$FF" list | grep -c "^port tcp:8080")" = 1 ] && "$FF" list | grep -qx "port tcp:8080:any"'
check "open refuses a bad port and a bad protocol" '! "$FF" open tcp 0 2> /dev/null && ! "$FF" open tcp 80a 2> /dev/null && ! "$FF" open icmp 80 2> /dev/null && ! "$FF" open tcp 80 nowhere 2> /dev/null'
"$FF" close tcp 8080 > /dev/null
"$FF" open tcp 3000 lan "Dev server / API & docs" > /dev/null
check "a name says why, with spaces and symbols" '"$FF" list | grep -qx "port tcp:3000:lan:Dev server / API & docs"'
check "the name becomes a comment in the rules" '"$REAL" print4 < "$CONF" | grep -qx "# Dev server / API & docs"'
check "the name is kept when the file is read again" '"$FF" apply > /dev/null && "$FF" list | grep -qx "port tcp:3000:lan:Dev server / API & docs"'
check "a comma, a quote or a hash in a name is refused" '! "$FF" open tcp 3001 lan "a,b" 2> /dev/null && ! "$FF" open tcp 3001 lan "a#b" 2> /dev/null && ! "$FF" open tcp 3001 lan "a\"b" 2> /dev/null && ! "$FF" list | grep -q 3001'
"$FF" open tcp 3000 any > /dev/null
check "open again replaces the name too" '"$FF" list | grep -qx "port tcp:3000:any"'
"$FF" close tcp 3000 > /dev/null
check "close removes the port" '! "$FF" list | grep -q "tcp:8080"'
check "close of a port that is not open is refused" '! "$FF" close tcp 9999 2> /dev/null'
"$FF" close tcp 22 > /dev/null; "$FF" close udp 5000 > /dev/null
check "no port left: an empty list" 'grep -qx "ports = \[\]" "$CONF"'
"$FF" off > /dev/null
check "off writes enabled = false" 'grep -qx "enabled = false" "$CONF" && "$FF" list | grep -qx "enabled off"'
"$FF" on > /dev/null
before="$(cat "$CONF")"
STUB_FAIL=1 "$FF" block mdns > /dev/null 2>&1
check "when loading fails the file is left as it was" '[ "$(cat "$CONF")" = "$before" ]'
check "status shows what the kernel enforces" '[ "$("$FF" status | head -n1)" = "v4 DROP" ]'
# A file that is a link (user layer): the target is edited, the link stays
mkdir -p "$T/layer"; mv "$CONF" "$T/layer/firewall.toml"; ln -s "$T/layer/firewall.toml" "$CONF"
"$FF" block localsend > /dev/null
check "a linked file is edited through the link" '[ -L "$CONF" ] && grep -q "^localsend = false" "$T/layer/firewall.toml"'
exit $fail
