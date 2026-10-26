# System

Only what differs from a stock Void install.

- **Services**: declare in `services/` (or `users/<login>/services/`), then `./bootstrap.sh`. Logs go through socklog: `/var/log/socklog/<facility>/current` (daemon, kernel...). No cron daemon: periodic jobs go in `~/.local/bin/cron-watch` (user mini-cron started by niri, catches up after reboot; jobs in `~/.config/cron-watch/jobs.d/`).
- **Session**: autologin on tty1 (`AUTOLOGIN`), then `~/.zprofile` runs `dbus-run-session niri` (no `niri-session`; `touch ~/.no-niri` to stay in the console). The session bus is private: from ssh, read `DBUS_SESSION_BUS_ADDRESS` in `/proc/$(pidof waybar)/environ`.
- **Network**: `iwd` connects the Wi-Fi AND configures its IP and DNS (`/etc/iwd/main.conf` from `system/iwd/`). `dhcpcd` is for wired only (`denyinterfaces wl*`): never run it on the Wi-Fi interface. IPv4 dead, IPv6 alive: `iwctl station <iface> disconnect` then `connect <ssid>` (`iwctl station list` gives `<iface>`). TUI: `impala` (`Mod+Ctrl+W`). Firewall: iptables, inbound denied (`system/iptables/`).
- **Audio**: pipewire + wireplumber start from niri `spawn-at-startup` (and are stopped by `session-reap` at logout). TUI: `wiremix`. Machine specifics: `hardware/<machine>/` (Mac T2: `hardware/mac-t2/audio/`).
- **Boot**: an ISO install (`install-void.sh`) is GRUB + ext4, UEFI; `sudo xbps-reconfigure -f linux<ver>` rebuilds the initramfs. Other layouts are in `hardware/<machine>/README.md` (Mac T2: Limine on a shared ESP, LUKS + btrfs, `limine-void`; never edit `limine.conf` by hand outside its Void block). Plymouth theme `filigrane` (`system/plymouth/`, `sudo system/plymouth/install.sh`).
- **Memory**: zram (`system/zramen.conf`) and earlyoom (`system/earlyoom.conf`).
- **sudo**: `wheel` with password; `zzz`, `reboot`, `poweroff` without (`zz-power`); `sv` and `xbps-*` without for Claude Code and Codex (`zz-agent`, see `usage.md`).
