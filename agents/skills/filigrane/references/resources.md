# Resources

The base system idles as low as possible: the browser, agents and containers keep the RAM and CPU.

- **Measure** with `budget` (apps/budget, Rust, ~0.15 s): OS memory vs user work (browser, agents, containers, terminal shells), biggest system residents (PSS), CPU over 2 s. Before a durable install `budget save avant`, after `budget diff avant`, report the system delta and new residents. `budget check` exits 1 over the limits in `~/.config/budget/limits` (cron-watch runs `budget check --notify` twice a day). Also `sudo sv status /var/service/*`, `df -h /` before big installs.
- **Chosen tools** (keep them, propose these first): podman (daemonless), neovim, yazi + Thunar on demand, imv, mpv, iwd, ripgrep/fd/fzf, swaybg, Quickshell as the only shell (bar + notifications + menu, software rendering, no animations; modules refreshed by signal, no frequently spawned scripts). Runtimes (Node, Python, JVM) on demand, never as a boot service. Prefer a Void package over source builds or curl-pipe installers.

## Home-made tools (`apps/`)

Native Rust binary rather than a script loading a heavy runtime (Python/GTK, Node). Example: `bar-stats` (all bar stats, the pipe reader and kernel events in one process, under 1 MB PSS, no forks) vs a shell script spawned every few seconds. Shell stays fine for glue.

- `apps/<name>/`, `Cargo.lock` committed, built `--locked`; minimal deps (raw `wayland-client` + `wayland-protocols*`, no toolkit).
- Release profile: `opt-level = "s"`, `lto`, `codegen-units = 1`, `panic = "abort"`, `strip`.
- Packaged for the distribution as `fili-apps` by `distro/build-repo.sh` (then `setup_apps` skips compiling).
- `bootstrap.sh` (`setup_apps`) builds into `~/.local/opt/<name>-<hash>`, links `~/.local/bin/<name>`, rebuilds only on source change; `target/` in `~/.cache/filigrane-apps`.
- Report startup time and RSS against what it replaces.
