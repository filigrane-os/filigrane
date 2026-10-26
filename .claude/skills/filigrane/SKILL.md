---
name: filigrane
description: Administer Filigrane, this Void Linux + niri machine and distribution (xbps, runit, niri/waybar, network, audio, boot on Mac T2), and apply its visual identity (logo, colours, Jost typography, icons). Use to install or remove a package, enable or debug a service, update the system, fix network/audio/display/boot, change the desktop, before installing anything (resource budget), and for any visual work (wallpaper, waybar/menu styling, plymouth, ISO, README, website, icons). Void + runit, not Debian/Arch/systemd.
---

# Filigrane

Rules, declarative workflow, git, forbidden commands: repo `CLAUDE.md`.

Before installing: `xbps-query -R -p installed_size <pkg>` and `xbps-query -Rx <pkg>`. Heavy (desktop environment, Electron, Docker daemon, JVM/.NET, permanent DB or indexer, IDE, anything always-on): **stop and warn first**, even if asked:

> Avertissement ressources: `<nom>` est lourd (<raison: RAM idle ~X Mo / CPU en tâche de fond / N dépendances / daemon permanent>).
> Alternative légère: `<alt>` (<gain>). Je continue avec `<nom>` ou je prends `<alt>` ?

Load only what the task needs:

- `references/system.md`: this machine's runit, logs, network (iwd), audio, boot (Limine, LUKS, btrfs), kernels.
- `references/niri.md`: niri config, keybinds (bépo), menu, waybar, wallpaper.
- `references/resources.md`: measuring, chosen light tools, home-made Rust tools in `apps/`.
- `references/brand.md`: logo files, colours, typography, icon and greyscale rules. Read before any visual change.
- `hardware/mac-t2/README.md`: Mac T2 specifics (audio, keyboard, Touch Bar, dual boot).
