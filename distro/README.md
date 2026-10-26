# distro/: xbps repository and ISO

Prototype of a distribution built from this repository: **Filigrane**, the OS present like a watermark, leaving RAM and CPU to applications. Commands and packages use the short name `fili` (`distro.env`).
It is not a Void fork: the distribution stays downstream of Void (same mirrors, same security updates) and only maintains its own layer.

## How it fits together

| Piece | Role |
|---|---|
| Git repository (root) | The source: package lists, services, system settings, dotfiles, Rust tools. `bootstrap.sh` applies it |
| Layers | distribution (root) → hardware (`hardware/<machine>`) → personal (`users/<login>`, never in the ISO) |
| xbps repository (`build-repo.sh`) | `fili-apps`: the tools from `apps/`, already built, no cargo needed. `fili-<list>`: one meta-package per `packages/<list>.txt` |
| ISO (`build-iso.sh`) | Void console live system (`void-mklive`) with the xbps repository, a generic copy of the git repository and the `fili-install` installer |

Philosophy (see `AGENTS.md`): the OS leaves RAM and CPU to the browser, agents and containers. Native Void packages come first, with no unnecessary daemon, no Electron, JVM or resident Node. Home-made tools are Rust binaries. `budget` measures how well this rule is kept.

## Building

```
distro/build-repo.sh              # no root: distro/out/repo (unsigned packages)
sudo distro/build-iso.sh          # root (void-mklive mounts and chroots): distro/out/fili-live-x86_64-<date>.iso
```

In CI (`.github/workflows/distro.yml`, branch `distro` or manual run): built in a privileged Void container, then the ISO is booted in QEMU up to the login prompt and kept for 7 days as an artifact.

## Installing from the ISO

Boot the ISO (the `anon` session opens automatically), connect the network, then run `fili-install`. The installer asks for the disk, the user and the machine name, then runs `install-void.sh`, which erases the whole disk and asks you to type its path to confirm. Then `bootstrap.sh --user-layer none` runs in the chroot and installs `fili-apps` from the embedded repository.

## Limits of the prototype

- **Network required**: only the distribution's own packages are on the ISO; the ~650 Void packages are downloaded during installation.
- **Console live system**: no niri session to try before installing.
- **No published repository**: the repository is neither hosted nor signed (it would need an `XBPS_PRIVKEY` CI secret and hosting, for example GitHub Pages). Updates therefore go through `git pull` then `./bootstrap.sh`, not yet through `xbps-install -Su`.
- **Unused meta-packages**: `bootstrap.sh` still installs the lists one by one. The `fili-*` meta-packages are ready for the day the repository is published.
- **Repository copy without git history**: to follow updates, clone `DISTRO_GIT` instead.
- **x86_64 only** for the ISO, and UEFI only for installation, like `install-void.sh`.
