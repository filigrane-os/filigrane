# Development

How the repository is organised, how to test a change, and what the CI checks.

## Layout

| Path | Role |
|---|---|
| `install-void.sh` | From the Void live ISO: partitions the disk, installs the base system, runs `bootstrap.sh`, installs GRUB |
| `bootstrap.sh` | On an existing Void system: packages, runit services, keyboard and time zone, groups, sudo, dotfiles, Rust tools, AI agent. Idempotent |
| `config.env` | Distribution defaults, see [configuration.md](configuration.md) |
| `packages/*.txt` | xbps lists: `base`, `desktop`, `dev`, `vm`, `baremetal`, `cpu-{intel,amd}`, `gpu-{intel,amd,nvidia}`, `mac-t2`, `dualboot` |
| `services/*.txt` | runit services: `common`, `vm`, `baremetal` |
| `system/` | Files installed under `/etc` and elsewhere: elogind, iwd, iptables, sysctl, udev, plymouth, earlyoom, zramen |
| `dotfiles/home`, `dotfiles/config` | Linked into `~` and `~/.config` |
| `apps/` | Native Rust tools: `bar-stats` (fili-shell's resident helper: bar stats, state watcher, pipe reader, charger events), `budget` (resource budget) |
| `lib/` | `i18n.sh` and `i18n/<lang>.sh`: translations for the scripts, see [Translations](#translations) |
| `agents/` | `skills/filigrane/` (the agent skill) and `work/` (instructions linked into the agent working directory) |
| `brand/` | Master logo files (SVG), colours and typography: see `agents/skills/filigrane/references/brand.md` |
| `hardware/<machine>/` | Everything specific to a hardware model |
| `users/<login>/` | Personal layer, see [configuration.md](configuration.md#personal-layer) |
| `distro/` | xbps repository and live ISO, see [distro/README.md](../distro/README.md) |
| `scripts/` | `check-packages.sh`, `brand-assets.sh` (regenerates wallpaper and Plymouth theme from `brand/`), `pull-from-vm.sh`, `gen-emoji.py` |
| `.github/workflows/` | CI |

## Principles

- **Light first.** A native Void package beats everything else: no daemon that is not needed, no Electron, JVM or resident Node. Home-made tools are small Rust binaries in `apps/`, built by `bootstrap.sh`, rather than scripts that load a heavy runtime. Measure with `budget save before` / `budget diff before`.
- **Declarative.** A durable change goes in the repo, in the right layer, then `./bootstrap.sh`.
- **No personal data in the distribution layer**: no account, service URL or `/home/<login>` path outside `users/`.

## Testing a change

- `./bootstrap.sh --plan [options]` prints the lists selected for any configuration without touching the system. Use it to check hardware-specific logic.
- `niri validate` before reloading the niri configuration.
- `scripts/check-packages.sh [arch]` checks that every listed package exists in the Void repository.
- `shellcheck -x -S error <script>` for shell scripts.
- `tests/fili-shell/run.sh` for the Quickshell shell (bar, notifications, launcher): an isolated instance on a private D-Bus loads the real config and checks every bar click, the `fili-shell` channel, the launcher, notifications and the `FiliInfo` cards. Needs a running Wayland session (not run by the CI).
- A virtual machine is the best test bed: dotfiles there are links into a clone of the repo, so edits are live. `scripts/pull-from-vm.sh [host]` copies the configuration folders back to your working copy; read `git diff`, then commit.
- Never run `install-void.sh` on a disk you care about.

## Continuous integration

`.github/workflows/ci.yml` runs on pull requests to `main` and on pushes to `main`, `develop` and `distro`. Nothing installs a system; it checks:

| Job | Checks |
|---|---|
| `lint` | `bash -n` and `shellcheck` on scripts (including `~/.local/bin`), valid JSON, `CLAUDE.md` imports `AGENTS.md`, skills have `name` and `description` |
| `plan` | `bootstrap.sh --plan` for 8 configurations (VM, Intel / AMD / NVIDIA / hybrid PCs, T2 Mac, ARM, RISC-V), invalid options rejected, the personal layer only appears with `--user-layer` |
| `packages` | Every listed package exists in the Void repository (aarch64 is informational: some Intel or proprietary packages are missing there) |
| `niri` | `niri validate` on the distribution config and with each personal `local.kdl` |
| `dotfiles` | Dotfiles applied in a clean `HOME` for `generic` and `mac-t2`: no broken link, T2 files only on the T2 machine, agent skills linked, `fili-ai` smoke test, idempotence |

`.github/workflows/distro.yml` (branch `distro`, or by hand) builds the xbps repository and the ISO in a privileged Void container, boots it in QEMU up to the login prompt, and keeps the ISO as an artifact for 7 days.

## Translations

Messages shown by the scripts are written in English in the code and translated at display time. `lib/i18n.sh` picks the language from `FILI_LANG`, else `LC_ALL`, `LC_MESSAGES` or `LANG` (`fr_FR.UTF-8` → `fr`). A catalog `lib/i18n/<lang>.sh` maps each exact English text to its translation; a language without a catalog, or a message without an entry, is shown in English.

```sh
FILI_LIB="$ROOT/lib"
. "$FILI_LIB/i18n.sh"
t 'Installing %s' "$name"          # printf-style, no newline
```

Scripts using it (`bootstrap.sh`, `fili-ai`) define `log`, `warn`, `die`, `say` and `note` on top of `t`; they all take the English text first, then the `printf` arguments. Write the English text in single quotes, without an apostrophe inside, and put variables in arguments, never in the text.

To add or fix a language:

1. Copy `lib/i18n/fr.sh` to `lib/i18n/<lang>.sh` (two letters, as in `LANG`) and translate the right-hand sides, keeping the same `%s` placeholders in the same order.
2. Run `scripts/check-i18n.sh`: it fails on a missing entry, on a different number of placeholders, and on an entry no script uses any more. CI runs it.
3. Try it: `LANG=<lang>_XX.UTF-8 ./bootstrap.sh --plan`.

Not translated yet: the menu, the waybar scripts, the niri shortcut titles, `config.env` comments and the agent skill. Documentation is in English only.

## Rust tools

`apps/<name>/` are ordinary Cargo projects with a committed `Cargo.lock`. `bootstrap.sh` builds them with `cargo build --release --locked` (`cargo` comes from `packages/dev.txt`); the xbps repository ships them pre-built as `fili-apps`.

## Visual identity

Edit `brand/` and `agents/skills/filigrane/references/brand.md` first, then run `scripts/brand-assets.sh` (needs `rsvg-convert`, ImageMagick and the Jost font) to regenerate the wallpaper and the Plymouth theme. Generated images are committed. Downloaded images are never added to the repo (unknown licence).

## Contributing

1. Branch from `develop`, keep commits focused.
2. Run `./bootstrap.sh --plan` and `shellcheck` on what you touched.
3. Do not commit secrets, tokens, e-mail addresses or IPs: the repository is public.
4. Open a pull request; the CI must pass.
