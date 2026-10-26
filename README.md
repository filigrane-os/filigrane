# Filigrane

A light Void Linux + niri desktop, described by a git repository and replayable on a VM, a PC or an Intel Mac (x86_64, glibc, UEFI).

The OS stays in the background, like a watermark (*filigrane* in French): RAM, CPU and battery go to the browser, AI agents and containers, not to the system.

- **Void Linux**: xbps packages, runit services, no systemd, rolling release.
- **niri**: a scrollable-tiling Wayland compositor, with waybar, fuzzel, mako and foot.
- **Declarative**: packages, services, settings and dotfiles live in this repo. `bootstrap.sh` applies them and is idempotent.
- **Layered**: distribution → hardware → personal. Your own accounts, services and tastes stay in `users/<login>/` and override the distribution without forking it.
- **AI agent built in**: `Mod+Y` starts Claude Code, Codex, opencode or local models (Ollama). The agent knows the system's rules (xbps, runit, layers, resource budget) through the `filigrane` skill.

## Quick start

On a Void Linux system that is already installed:

```
git clone https://github.com/thooams/filigrane ~/filigrane && cd ~/filigrane
./bootstrap.sh
```

To install from scratch (erases a whole disk), see [docs/install.md](docs/install.md).

## Documentation

| Guide | Contents |
|---|---|
| [Install](docs/install.md) | Live ISO, `install-void.sh`, an existing Void system, Intel Macs with a T2 chip |
| [Using the desktop](docs/usage.md) | Session, keys, menu, screenshots, packages, services, updates |
| [Configuration and layers](docs/configuration.md) | `config.env`, distribution / hardware / personal layers, `bootstrap.sh` options, hardware detection |
| [AI agent](docs/ai-agent.md) | `fili-ai`, choosing an agent and a model, signing in, safety rules |
| [Development](docs/development.md) | Repo layout, test workflow, CI, Rust tools, translations, contributing |
| [Distribution](distro/README.md) | xbps repository and live ISO |
| [Intel Mac with T2 chip](hardware/mac-t2/README.md) | Drivers, audio, Touch Bar, dual boot, kernels |

## Why: Void + niri against macOS

Measured on the same MacBook (T2), idle, shortly after boot. On the Mac, Spotlight indexing was turned off (otherwise `mds_stores` pushes the load to 40).

| | Void + niri | macOS (indexing off) |
|---|---|---|
| RAM, system only (no applications) | ~0.8 GB | ~6.5 GB (2.7 GB of it "wired" kernel memory) |
| CPU idle | 92-94% idle | ~94% idle |
| Total power (whole machine, screen included, on battery) | 19.4 W, Chromium open | ~24 W, no browser |
| Swap | 0 | 0 |

- **RAM**: macOS uses about 8 times more than Void without applications. Its kernel alone is more than 3 times the whole Linux system.
- **CPU**: the same at idle once indexing is done, yet `WindowServer` stays at ~16% for a static screen, with no equivalent under niri.
- **Power**: the Mac draws ~4.6 W more (+24%) with fewer applications open.

What macOS does not allow on this Mac and works natively here, with no adapter or third-party software:

- **DisplayPort MST**: several separate screens daisy-chained or through a hub on a single port, where macOS only mirrors.
- **Bluetooth LDAC**: headphones (Sony WH-1000XM4) in LDAC, where macOS stops at AAC and SBC.

## Known limits

- UEFI only, no legacy BIOS or 32-bit EFI. `install-void.sh` uses the whole disk, with no LUKS or LVM.
- Not tested end to end: `install-void.sh`, the `baremetal` profile, the `mac-t2` machine.
- Broadcom Wi-Fi on older Macs (without T2): proprietary driver not included.
- The ISO and its xbps repository are a prototype: see [distro/README.md](distro/README.md).
