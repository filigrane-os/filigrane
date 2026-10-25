# Resources

Goal: the base system idles as low as possible so the browser, agents, containers and apps keep the memory and CPU.

## Measure

- `budget` (apps/budget, Rust, ~0,15 s, 2 Mo): OS memory vs user work (browser, agents, containers, anything run from a terminal shell), biggest system residents (PSS), CPU over 2 s, kernel/unattributed split. Limits in `~/.config/budget/limits` (distribution: `dotfiles/config/budget/limits`, overridden by the user layer).
- Before a durable install: `budget save avant`; after: `budget diff avant`, and report the system delta and new residents. `budget check` exits 1 over limits (cron-watch runs `budget check --notify` twice a day).
- Services: `sudo sv status /var/service/*`. Disk (small): `df -h /`, check before big installs.

## Light choices

| Need | Prefer |
|---|---|
| Containers | `podman` (daemonless), started only when needed |
| Editor | neovim (installed), `helix` |
| File manager | `yazi`, `nnn`, `lf` |
| Image viewer / PDF / media | `imv` or `swayimg` / `zathura` / `mpv` |
| Notifications | `mako` or `fnott` |
| Network | `dhcpcd` + `wpa_supplicant` (current), `iwd` |
| Search | `ripgrep`, `fd`, `fzf` instead of tracker/baloo |
| Database | SQLite, or start the service only when needed |
| Runtimes (Node/Python/JVM) | on demand, never as a boot service |
| Visuals | static wallpaper (`swaybg`), plain waybar, no animated widgets; blur only behind the menu (`menu-backdrop`, computed while it is open) |

Waybar: few modules, `interval` of 5 s or more, no custom scripts that spawn often. Prefer a maintained Void package over source builds or curl-pipe installers (for those, say what they install and where).

## Home-made tools (`apps/`)

Prefer a light, fast native binary even if it has to be compiled, over a script that loads a heavy runtime on every launch (Python + GTK, Node, Electron). Example: `menu-backdrop` in Rust starts in ~6 ms with 2.4 MB RSS, the Python/GTK version took ~185 ms and 69 MB.

- Sources in `apps/<name>/` (Cargo project, `Cargo.lock` committed, `--locked`). Keep dependencies minimal: raw `wayland-client` + `wayland-protocols*` rather than a toolkit for a small Wayland client.
- Release profile: `opt-level = "s"`, `lto`, `codegen-units = 1`, `panic = "abort"`, `strip`.
- Packaged for the distribution as `fili-apps` by `distro/build-repo.sh` (then `setup_apps` skips compiling).
- `bootstrap.sh` (`setup_apps`, dotfiles step) builds into `~/.local/opt/<name>-<source hash>`, links `~/.local/bin/<name>`, rebuilds only when sources change; `target/` stays in `~/.cache/void-setup-apps` (and `apps/*/target/` is git-ignored).
- Measure startup time and RSS against what it replaces, and report both.
- Shell scripts stay fine for glue (they spawn existing binaries); the rule targets programs that would load an interpreter or toolkit.
