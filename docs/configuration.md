# Configuration and layers

Everything durable lives in the repository, and `./bootstrap.sh` applies it. A change made only on the live system is lost on the next reinstall. Edit the repo, then run `./bootstrap.sh` (idempotent).

Dotfiles in `~` and `~/.config` are symlinks into the repo: editing `~/.config/niri/config.kdl` edits the repo file. Never replace a link with a copy.

## Layers

Three layers are applied in order. A file at the same path in a later layer replaces the earlier one.

| Layer | Path | Contents |
|---|---|---|
| 1. Distribution | repo root | Generic: what any user would get. `packages/`, `services/`, `system/`, `dotfiles/`, `apps/`, `config.env` |
| 2. Hardware | `hardware/<machine>/` | What a hardware model needs: `setup.sh`, `dotfiles/`, extra packages |
| 3. Personal | `users/<login>/` | Your accounts, third-party services and tastes. Never shipped in the ISO |

When unsure, a change is personal. Nothing personal (account, service URL, `/home/<login>` path) belongs in the distribution layer.

### Personal layer

```
users/<login>/
├── config.env            overrides config.env, same VAR="${VAR:-value}" form
├── packages/*.txt        extra xbps packages, one per line
├── services/*.txt        extra runit services
├── dotfiles/home/        linked into ~, replaces distribution files at the same path
├── dotfiles/config/      linked into ~/.config
└── layer.sh              optional shell hooks: layer_system (as root), layer_dotfiles (after the links)
```

Create the directory, then run once:

```
./bootstrap.sh --user-layer <login>
```

The choice is remembered in `.user-layer` (not tracked by git). `--user-layer none` applies the distribution only, like a fresh install from the ISO. Without `.user-layer`, `bootstrap.sh` uses `users/<current user>` if it exists and prints a warning.

Extra niri settings go in `users/<login>/dotfiles/config/niri/local.kdl`: the main config includes it last, so it can add or override anything.

`layer.sh` sees `ROOT`, `LAYER_DIR`, `TARGET_USER`, `TARGET_HOME`, `TARGET_ARCH`, `PROFILE`, `MACHINE`, `SUDO` and the helpers `log`, `warn`, `read_list`, `install_list`, `run_as_user`. Use it for what lists cannot express, such as a pinned download checked against a hash.

## Settings (`config.env`)

`config.env` holds the distribution defaults, `users/<login>/config.env` overrides them, and an environment variable beats both. Run `./bootstrap.sh` after a change.

| Variable | Default | Role |
|---|---|---|
| `KEYMAP` | `us` | Console keymap |
| `XKB_LAYOUT`, `XKB_VARIANT`, `XKB_OPTIONS` | `us`, empty, `compose:caps` | niri keyboard, written to `~/.config/niri/keyboard.kdl` |
| `TIMEZONE` | `UTC` | Time zone |
| `LOCALE` | `C.UTF-8` | System language; `fr_FR.UTF-8` gives French messages and menus |
| `USER_GROUPS` | `wheel audio video input bluetooth socklog lpadmin` | Groups added to the user (missing ones are skipped) |
| `AUTOLOGIN` | `auto` | Auto-login on `tty1`: `1`, `0`, or `auto` (VMs only) |
| `FILI_AI` | `claude` | AI agent: `claude`, `codex`, `ollama`, `opencode`, `none`. See [ai-agent.md](ai-agent.md) |
| `FILI_AI_MODEL` | empty | Agent model (empty = the agent's default) |
| `FILI_AI_WORKDIR` | `work` | Agent working directory, relative to your home |
| `FILI_AI_ARGS` | empty | Agent options replacing the defaults (permissions, sandbox) |

Example `users/<login>/config.env`:

```
KEYMAP="${KEYMAP:-fr}"
XKB_LAYOUT="${XKB_LAYOUT:-fr}"
TIMEZONE="${TIMEZONE:-Europe/Paris}"
LOCALE="${LOCALE:-fr_FR.UTF-8}"
```

## `bootstrap.sh` options

```
./bootstrap.sh [--profile auto|vm|baremetal] [--machine auto|generic|mac-t2]
               [--cpu auto|intel|amd|other] [--gpu auto|none|intel,amd,nvidia]
               [--arch auto|x86_64|aarch64|riscv64] [--user-layer auto|none|<login>]
               [--system-only | --dotfiles-only | --fili-shell | --plan]
```

| Option | Effect |
|---|---|
| `--system-only` | Packages, services, system settings, AI agent install; no dotfiles |
| `--dotfiles-only` | Symlinks and Rust tools; no packages or services |
| `--fili-shell` | Only the fili-shell (QML, `bar-*`, `fili-*` scripts) is linked and reloaded; no sudo |
| `--plan` | Print the package lists, services and layers that would be applied, then exit without changing anything |

Run as a normal user (it calls `sudo`), or as root with `TARGET_USER=<login>` (what `install-void.sh` does in its chroot).

### Hardware detection

Each axis is detected, and can be forced to test another configuration (`--plan` is handy for that):

| Axis | Values | Detected from | Effect |
|---|---|---|---|
| Profile | `vm`, `baremetal` | `hypervisor` flag in `/proc/cpuinfo` | `packages/vm.txt` or `baremetal.txt`, auto-login |
| Machine | `generic`, `mac-t2` | Apple T2 chip in `/sys/bus/pci` | `hardware/<machine>/` (nothing for `generic`) |
| CPU | `intel`, `amd`, `other` | `vendor_id` in `/proc/cpuinfo` | `packages/cpu-<x>.txt`: firmware, microcode (physical machines only) |
| GPU | `intel,amd,nvidia` list or `none` | vendors in `/sys/class/drm` | `packages/gpu-<x>.txt`: Vulkan, video acceleration (physical machines only). NVIDIA uses the free nouveau driver |
| Architecture | `x86_64`, `aarch64`, `riscv64` | `uname -m` | Skips x86_64-only binaries; packages missing for the architecture are skipped with a warning |

The same values can be set through the variables `PROFILE`, `MACHINE`, `CPU_VENDOR`, `GPU_VENDORS` and `TARGET_ARCH`.

### Adding a machine

Create `hardware/<name>/` with a `setup.sh` (and optionally `dotfiles/`), add `<name>` to the machine `case` in `bootstrap.sh` and its detection, then add a line to the `plan` matrix in `.github/workflows/ci.yml`. [hardware/mac-t2/](../hardware/mac-t2/README.md) is the reference example.
