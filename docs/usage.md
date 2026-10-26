# Using the desktop

`Mod` is the Super key (Command on a Mac). `Mod+Shift+/` shows every shortcut, `Mod+Shift+Space` searches them.

## Session

- niri starts from `tty1` through `~/.zprofile` (`dbus-run-session niri`). To get a plain console instead: `touch ~/.no-niri`, or log in on `tty2` to `tty6`.
- Auto-login on `tty1` is controlled by `AUTOLOGIN` (on in VMs, off on physical machines by default, see [configuration.md](configuration.md)).
- `Mod+L` locks the screen (swaylock).

## Main shortcuts

| Keys | Action |
|---|---|
| `Mod+Space` | Menu: applications, clipboard, emoji, calculator, windows, files, web, system... (press again to close) |
| `Mod+D` | Application launcher, most used first |
| `Mod+Return` | Terminal (foot) |
| `Mod+Y` | AI agent (`fili-ai`), see [ai-agent.md](ai-agent.md) |
| `Mod+Tab` | Go to a window |
| `Mod+O` | Overview of all workspaces |
| `Mod+Q` | Close the window |
| `Mod+Arrows` | Move the focus; with `Ctrl`, move the window; with `Shift`, change monitor |
| `Mod+B`, `Mod+Shift+B` | Do-not-disturb on/off, dismiss all notifications |
| `Mod+Ctrl+A`, `W`, `B`, `D` | Audio (wiremix), Wi-Fi (impala), Bluetooth (bluetui), displays (wdisplays) |
| `Mod+Ctrl+P` | Save the current display layout as a profile |
| `Super+Alt+S` | Screen reader (orca) on/off |

Media, volume and brightness keys work, also when the screen is locked.

## Menu

`Mod+Space` opens categories when empty and fuzzy-searches everything (applications, system actions, your own entries) as soon as you type. `Shift+Backspace` goes up one level, `Esc` closes the whole menu. The menu only exists while it is open: no daemon, nothing in memory at rest.

Sections can be opened directly: `menu apps|clip|emoji|calc|windows|files|web|keys|toggles|history|system|audio|network|style|packages|capture|custom`.

Your own entries live in `~/.config/menu/entries`, one per line:

```
Label | mode | command
```

`mode` is `term` (terminal that closes when the command ends), `hold` (terminal left open) or `run` (in the background, for graphical apps). Lines starting with `#` are ignored. You can also add entries from the menu: *Custom entries › Add an entry*.

The *Shut down*, *Reboot* and *Suspend* actions use `sudo` without a password, through a rule limited to `zzz`, `reboot` and `poweroff` (`/etc/sudoers.d/zz-power`), since there is no polkit.

## Screenshots

Built into niri, no extra software. Saved in `~/Screenshots` and copied to the clipboard.

| Keys | Capture |
|---|---|
| `Mod+Shift+4` | Area |
| `Mod+Shift+3` | Screen |
| `Mod+Shift+Ctrl+4` | Window |
| `Mod+Shift+5` | Capture interface |
| `Print`, `Ctrl+Print`, `Alt+Print` | Area, screen, window |

## Shell and tools

- zsh without a framework, zellij on demand (`zj`), neovim with LazyVim.
- CLI tools: `eza`, `fzf`, `zoxide`, `ripgrep`, `bat`, `lazygit`, `gh`.
- Chromium runs natively on Wayland. Containers: `podman` (alias `d`).
- Wallpaper: `wallpaper [image]` (swaybg), images in `~/.local/share/wallpapers/`.
- `budget` shows how much RAM and CPU the system uses compared with your own work.

## Background tasks

There is no cron daemon. `cron-watch`, started by niri, is a sleeping shell (~3 MB) that runs periodic jobs from `~/.config/cron-watch/jobs.d/` and catches up after a reboot. `watch-void` notifies when xbps updates are available (every 6 hours).

## Packages

| Task | Command |
|---|---|
| Search | `xbps-query -Rs <word>` |
| Details, files, reverse dependencies | `xbps-query -R <pkg>`, `xbps-query -f <pkg>`, `xbps-query -X <pkg>` |
| Install | `sudo xbps-install <pkg>` |
| Remove | `sudo xbps-remove <pkg>` |
| Remove orphans, clean the cache | `sudo xbps-remove -o`, `sudo xbps-remove -O` |

A package installed by hand disappears on a reinstall. To keep it, add it to a list that `bootstrap.sh` replays: `users/<login>/packages/<name>.txt` for yourself, `packages/*.txt` for the distribution. The menu has a *Packages* section too.

## Services

Services are managed by runit.

- State: `sudo sv status /var/service/*`
- Start, stop, restart: `sudo sv up|down|restart <service>`
- Enable durably: add the name to `services/*.txt` or `users/<login>/services/*.txt`, then `./bootstrap.sh --system-only`.
- Logs: `/var/log/socklog/<facility>/current` (`daemon`, `kernel`, `messages`...). There is no journalctl.

## Updating

- **System packages**: `sudo xbps-install -Su`. On a T2 Mac, use `void-update` instead (it takes btrfs snapshots), see [hardware/mac-t2/README.md](../hardware/mac-t2/README.md). Reboot after a kernel update.
- **Filigrane itself**: `git -C ~/filigrane pull --ff-only`, then `./bootstrap.sh`. Commit your own changes first, or keep them in your personal layer: files in `users/<login>/` are never touched by an update.
- **AI agent**: `fili-ai update` (Claude Code also updates itself).
