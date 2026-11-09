# Starts niri automatically on tty1 (no login manager, 0 MB more).
# No `exec`: if niri exits or crashes, we fall back to a shell instead of looping.
# Disable: touch ~/.no-niri (or log in on tty2 to tty6 to troubleshoot).
if [[ -z "$WAYLAND_DISPLAY" && -z "$SSH_CONNECTION" && "$(tty)" == /dev/tty1 && ! -e ~/.no-niri ]]; then
    mkdir -p ~/.local/state
    # Internal panel off from the start when a dock brings three displays (frees its graphics pipe), see fili-internal-panel
    ~/.local/bin/fili-internal-panel
    dbus-run-session niri >~/.local/state/niri.log 2>&1
    # What niri started (pipewire, wa-daemon...) outlives it without systemd: it is stopped here, before any new session
    # (at login, stopping an old pipewire would delete the socket of the new one)
    ~/.local/bin/session-reap
fi
