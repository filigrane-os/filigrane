#!/bin/sh
# Makes the tty1 getty wait until the wrapper of the elogind runit service has mounted /run/user
# (needed with autologin).
# Run as root: tty1-wait-elogind.sh [on|off]      (default: on)
# Without it, the automatic login is the first D-Bus client at boot: D-Bus activates elogind
# itself (login1), then the wrapper of the runit service mounts a tmpfs on /run/user and masks
# /run/user/<uid>. Result: no XDG_RUNTIME_DIR, niri fails ("Failed to open session", or
# PermissionDenied panic when creating the Wayland socket).
# We wait for /run/user to be a mount point, not for the service check of elogind: that one succeeds as soon as
# runit starts the run script, which exits at once if D-Bus is not ready (the check of dbus fails).
# Once /run/user is mounted, the wrapper mounts nothing more and can no longer mask the session.
# The wait is bounded to 20 s: if elogind is broken, tty1 starts anyway (tty2 stays free).
set -eu
conf=/etc/sv/agetty-tty1/conf
begin='# >>> void-setup: attendre elogind'
end='# <<< void-setup'
[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"
[ -f "$conf" ] || { echo "Introuvable: $conf" >&2; exit 1; }

# removes an existing block (idempotent)
sed -i "\|^$begin|,\|^$end|d" "$conf"

if [ "${1:-on}" = on ]; then
    {
        printf '%s\n' "$begin"
        printf '%s\n' 'n=0; until mountpoint -q /run/user || [ "$n" -ge 20 ]; do sleep 1; n=$((n+1)); done'
        printf '%s\n' "$end"
    } >> "$conf"
fi
tail -4 "$conf"
