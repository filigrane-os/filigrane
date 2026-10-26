# niri desktop

- Config: `dotfiles/config/niri/config.kdl` (linked to `~/.config/niri/`). `niri validate` before saving; niri reloads on save.
- `environment {}` sets `CHROME_FLAGS` (Void's chromium wrapper reads only that, no flags file) and `ELECTRON_OZONE_PLATFORM_HINT`. Autostart: `spawn-at-startup` lines.
- Keys (bépo right hand, arrows also work): `Mod+T/S/R/N` = left/down/up/right, `Ctrl` moves, `Shift` changes screen. `Mod+Return` foot, `Mod+Space` menu, `Mod+D` app launcher, `Mod+Y` AI agent (`fili-ai`), `Super+Alt+L` lock. `Mod+Shift+/` lists them.
- Personal additions: `users/<login>/dotfiles/config/niri/local.kdl` (included at the end of `config.kdl`).
- Shell: **fili-shell**, one Quickshell process (replaces waybar, mako, fuzzel), config `dotfiles/config/quickshell/`. Use these names with the user:

  | Name | What | File |
  | --- | --- | --- |
  | fili-shell | the Quickshell process, and its client `~/.local/bin/fili-shell` | `shell.qml`, `FiliShell.qml` (commands) |
  | fili-bar | top bar, one per screen | `FiliBar.qml` (+ `BarScript`, `BarItem`, `BarHover`, `BarPower`) |
  | fili-tooltip | hover card of a bar module (details + click hints, Omarchy panels as model) | `FiliTooltip.qml`, data `~/.local/bin/fili-info network\|power\|display` |
  | fili-calendar | month grid under the clock | `FiliCalendar.qml` |
  | fili-notification | notification bubbles (top right) | `FiliNotification.qml` |
  | fili-notification-center | notification history panel (bell icon) | `FiliNotification.qml` |
  | fili-menu | fuzzy picker used by `menu`, the timer, `fili-ai`; blurred backdrop (layer `fili-menu`) | `FiliMenu.qml` |
  | fili-theme | colours and fonts (brand.md) | `FiliTheme.qml` |

  Software rendering (`QT_QUICK_BACKEND=software` pragma in `shell.qml`, no GL context: about half the memory). Client commands (named pipe `$XDG_RUNTIME_DIR/fili-shell`, no Qt client): `fili-shell bar refresh N` (was `pkill -RTMIN+N waybar`), `fili-shell notification dnd on|off|toggle|dismiss-all|dismiss TEXT|center|history`, `fili-shell menu [fuzzel --dmenu options]`, `fili-shell menu close`, `fili-shell reload`. Logs: `/run/user/$UID/quickshell/`.
- Menu: `~/.local/bin/menu` (fili-menu via `fili-shell menu`, one fuzzy list: `~/.config/menu/entries`, .desktop apps, "Category: Action" entries; `menu <section>` jumps to clip, emoji, calc...). `Shift+BackSpace` up one level, `Escape` quits.
- fili-bar modules: script modules (`BarScript.qml`) use the waybar custom JSON protocol (`bar-status`, `bar-tray`, `bar-alert`...); CPU/RAM/temperature/disk/network from `apps/bar-stats` (resident, no forks); rarely-changing indicators (SSH, airplane, VPN, night light, backup, calendar, low battery) are not polled: `bar-stats watch` reads /proc and /sys and sends `bar refresh N` on change. Audio, MPRIS, Bluetooth, tray, keyboard layout, workspaces are native. New indicator: prefer `bar refresh N` over an `interval`; a fili-tooltip that needs fresh data uses `tipCmd` (run on hover only).
- Wallpaper: static `swaybg` via `~/.local/bin/wallpaper [image]`, images in `~/.local/share/wallpapers/`. Never animated.
- Visual changes follow `references/brand.md`.
