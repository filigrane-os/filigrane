---
name: filigrane
description: Use, configure, update and troubleshoot Filigrane, this Void Linux + niri distribution (xbps, runit, niri/Quickshell bar, network, audio, boot, AI agent), and apply its visual identity (logo, colours, Jost typography, icons). Use to install or remove a package, enable or debug a service, update the system or Filigrane itself, change a setting (keyboard, timezone, autologin, AI agent or model), fix network/audio/display/boot, change the desktop (keys, menu, waybar, wallpaper), before installing anything (resource budget), and for any visual work (wallpaper, waybar/menu styling, plymouth, ISO, README, website, icons). Void + runit, not Debian/Arch/systemd.
---

# Filigrane

Void Linux (glibc, xbps, runit) + niri, described by a git repo that `bootstrap.sh` applies. The OS must stay out of the way: RAM and CPU belong to the browser, agents and containers.

## Where things are

- **Repo**: `$FILIGRANE_DIR` (exported by `fili-ai`; otherwise `fili-ai status`). Its `AGENTS.md` holds the full rules (git, layers, forbidden commands): read it before a durable change.
- **Dotfiles** in `~` and `~/.config` are symlinks into the repo: edit the repo file (the link follows), never replace a link by a copy.
- **Layers**, a later one replaces a file at the same path: distribution (repo root) → hardware (`hardware/<machine>/`) → personal (`users/<login>/`). Active personal layer: `$FILIGRANE_DIR/.user-layer` (`none` = distribution only).

## Hard rules

- xbps, never apt/pacman/dnf/brew/nix/flatpak. runit (`sv`, `/var/service`), never systemctl/journalctl. Root via `sudo`; if sudo asks for a password you cannot type, give the user the exact command (`! <command>` in Claude Code).
- Diagnose read-only first, cause in one or two sentences, then fix.
- Durable change = in the repo, in the right layer (in doubt: personal), then `./bootstrap.sh` (idempotent), then show `git diff` when the repo is a git checkout. Nothing personal (account, service URL, `/home/<login>`) in the distribution layer.
- `niri validate` before saving niri config.
- Never: `install-void.sh`, `mkfs`, `wipefs`, `parted`, `dd` on a disk, editing `/etc/sudoers*`, `~/.ssh`, agent credentials (`~/.claude/.credentials.json`, `~/.codex/auth.json`, `~/.local/share/opencode/auth.json`).
- Ask first: system update (`xbps-install -Su`), `sv restart/stop` of system services, `rm` outside the repo and the agent's work dir, editing `/etc`, bootloader, reboot.

## Before installing

`xbps-query -R -p installed_size <pkg>` and `xbps-query -Rx <pkg>`. Heavy (desktop environment, Electron, Docker daemon, JVM/.NET, permanent DB or indexer, IDE, local LLM, anything always-on): **stop and warn first**, even if asked:

> Avertissement ressources: `<nom>` est lourd (<raison: RAM idle ~X Mo / CPU en tâche de fond / N dépendances / daemon permanent>).
> Alternative légère: `<alt>` (<gain>). Je continue avec `<nom>` ou je prends `<alt>` ?

After a durable install: `budget save avant` before, `budget diff avant` after, report the delta.

## Load only what the task needs

- `references/usage.md`: everyday tasks: packages, services, settings (`config.env`), personal layer, updating the system, Filigrane and the AI agent (`fili-ai`), where to find help (keys, menu).
- `references/system.md`: runit, logs, network (iwd), audio, session, boot, memory.
- `references/niri.md`: niri config, keybinds, menu, Quickshell shell (bar, notifications), wallpaper.
- `references/resources.md`: measuring, chosen light tools, home-made Rust tools in `apps/`.
- `references/brand.md`: logo files, colours, typography, icon and greyscale rules. Read before any visual change.
- `hardware/<machine>/README.md` when the machine has one (`./bootstrap.sh --plan` prints `hardware/<machine>`). Mac T2: `hardware/mac-t2/README.md` (audio, keyboard, Touch Bar, dual boot, Limine, kernels).
