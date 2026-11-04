<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="brand/filigrane-empile-sombre.svg">
    <img src="brand/filigrane-empile-clair.svg" alt="Filigrane" width="420">
  </picture>
</p>

<p align="center"><em>The OS, discreetly.</em></p>

<p align="center">
  <img src="docs/img/desktop.png" alt="The Filigrane desktop: niri, the fili-bar and the AI drawer over a misty forest" width="860">
</p>

**Filigrane** is a light, modern Linux desktop built on Void and niri. It is described entirely by a git repository, so any x86_64 machine can replay it: a virtual machine, a PC or an Intel Mac.

## The idea

A *filigrane* is a watermark: visible when you look for it, invisible when you read the page. That is the design brief for an operating system.

- **It gets out of the way.** The system is a thin veil. Idle, it takes about 0.8 GB of RAM and almost no CPU, so memory, cycles and battery go to what you actually run: the browser, your tools, containers, AI agents.
- **Light by construction.** Native Void packages, runit instead of systemd, no resident Electron, JVM or Node. Home-made tools are small Rust binaries. A `budget` tool measures the cost of everything installed.
- **Modern where it counts.** A scrollable-tiling Wayland compositor (niri), a Quickshell shell with a thin one-line bar, fine-stroke icons, Jost typography, an interface that follows one written guideline (inspired by classic Mac OS X) rather than whatever each toolkit does.
- **Agentic.** An AI agent is a first-class citizen, not an add-on. `Mod+Y` opens it, it knows the machine's rules (xbps, runit, layers, resource budget), sees what you were looking at ("rename these files" works), and every change it makes to your files is one `fili-tx undo` away.
- **Declarative and yours.** Packages, services, settings and dotfiles live in the repo. `bootstrap.sh` applies them, idempotently. Your personal accounts and tastes sit in their own layer and never fork the distribution.
- **Universal.** Developed on an Intel MacBook, built for any PC: one x86_64, glibc, UEFI image of the system, with hardware layers (`hardware/<machine>`) for what differs, such as the T2 drivers of recent Macs.

## What is inside

- **Void Linux**: xbps packages, runit services, no systemd, rolling release.
- **niri + Quickshell**: bar, global application menu, notifications, launcher, panels, all in one coherent shell (the *fili-shell*) with foot as terminal.
- **Fili apps**: small native tools that share one standard: an *About* card, their own icon, a global menu exposed to the bar, and an editable config file (`~/.config/filigrane/<app>.toml`) for settings and theme. The first is **Casier**, the file manager; **Archiveur** (`fili-archive`, `archiveur`) is its compress and extract engine without a window, shipped in the same binary.
- **Layered configuration**: distribution → hardware → personal.
- **AI agent built in**: Claude Code, Codex, opencode or local models (Ollama). `Mod+Y` opens a chat drawer (sessions kept while hidden); `Mod+Shift+Y` starts the agent in a terminal.

## Quick start

On a Void Linux system that is already installed:

```
git clone https://github.com/filigrane-os/filigrane ~/filigrane && cd ~/filigrane
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
