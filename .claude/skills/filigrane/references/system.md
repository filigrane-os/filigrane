# System (this machine)

Only what differs from a stock Void install.

- **Services**: declare in `services/`, then `./bootstrap.sh`. Logs go through socklog: `/var/log/socklog/<facility>/current` (daemon, kernel...). No cron daemon: periodic jobs go in `~/.local/bin/cron-watch` (user mini-cron started by niri, catches up after reboot).
- **Session**: `dbus-run-session niri` (no `niri-session`). The session bus is private: from ssh, read `DBUS_SESSION_BUS_ADDRESS` in `/proc/$(pidof waybar)/environ`.
- **Network**: `iwd` connects the Wi-Fi AND configures its IP and DNS (`/etc/iwd/main.conf` from `system/iwd/`). `dhcpcd` is for wired only (`denyinterfaces wl*`): never run it on `wlp229s0`. IPv4 dead, IPv6 alive: `iwctl station wlp229s0 disconnect` then `connect <ssid>`. TUI: `impala`.
- **Audio**: pipewire + wireplumber start from niri `spawn-at-startup` (and are stopped by `session-reap` at logout). Mac T2 audio: `hardware/mac-t2/audio/`.
- **Boot**: Limine on an ESP shared with another OS, root on LUKS + btrfs (`subvol=@void`), plymouth (thème `filigrane`, `system/plymouth/`, installé par `sudo system/plymouth/install.sh`). Kernel copies and the Void block of `limine.conf` are managed by `hardware/mac-t2/limine-void` (`sync`, `status`, `purge` instead of `vkpurge`). Never edit `limine.conf` by hand outside that block. Initramfs: `xbps-reconfigure -f linux<ver>`.
- **Memory**: zram (`system/zramen.conf`) and earlyoom (`system/earlyoom.conf`).
