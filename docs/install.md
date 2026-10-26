# Install

Filigrane runs on x86_64 machines booting in UEFI mode: virtual machines, PCs and Intel Macs (including those with a T2 chip). `bootstrap.sh` also resolves packages for `aarch64` and `riscv64`, but those are not tested on hardware.

There are three ways in:

| Starting point | Method |
|---|---|
| Filigrane live ISO | `fili-install` (see [distro/README.md](../distro/README.md)) |
| Void Linux live ISO | `install-void.sh` |
| Void Linux already installed | `bootstrap.sh` |

## From the Void Linux live ISO

> `install-void.sh` **erases the whole target disk**. It asks you to type the disk path to confirm.

1. Boot the Void live ISO (glibc, x86_64) with a working network. Log in as `root`, password `voidlinux`.
2. Get the repository:
   ```
   xbps-install -Sy git
   git clone https://github.com/thooams/filigrane && cd filigrane
   ```
3. Install, choosing the disk, your login and the machine name:
   ```
   ./install-void.sh --disk /dev/sda --user <login> --hostname <name>
   ```
   On NVMe the disk is `/dev/nvme0n1`.
4. Type the disk path to confirm, set the passwords, reboot.

The script partitions the disk, installs the Void base system, runs `bootstrap.sh` in a chroot, then installs GRUB with `--removable`: no NVRAM entry, so booting works the same on PCs and Intel Macs.

It accepts the same hardware options as `bootstrap.sh` (`--profile`, `--machine`, `--cpu`, `--gpu`), see [configuration.md](configuration.md).

## On an existing Void Linux system

```
git clone https://github.com/thooams/filigrane ~/filigrane && cd ~/filigrane
./bootstrap.sh                  # everything (asks for the sudo password)
./bootstrap.sh --dotfiles-only  # symlinks and Rust tools only, no packages or services
./bootstrap.sh --plan           # print what would be applied, change nothing
```

- Existing dotfiles are moved to `*.bak.<date>` before being replaced by symlinks.
- Keep the repository where you cloned it: the symlinks point into it. Links to files later moved or deleted from the repo are cleaned up on the next run.
- `bootstrap.sh` is idempotent: run it again after every change to the repo.

Without access to GitHub, copy the repository from another machine (base Void has no `rsync`):

```
tar --exclude=.git -C ~/filigrane -cf - . | ssh <host> 'mkdir -p ~/filigrane && tar -xf - -C ~/filigrane'
ssh -t <host> 'cd ~/filigrane && ./bootstrap.sh'
```

`-t` gives a terminal for the sudo password.

## Intel Macs with a T2 chip

MacBook Pro/Air 2018-2020, Mac mini 2018, iMac 2020, iMac Pro and Mac Pro 2019 need extra drivers, built with DKMS by `bootstrap.sh`. Read [hardware/mac-t2/README.md](../hardware/mac-t2/README.md) **before** installing: secure boot must be turned off in macOS Recovery, and you need a USB keyboard, mouse and Ethernet adapter during installation.

## After the first boot

- The session starts niri from `tty1` (`~/.zprofile`). Auto-login is on in VMs and off on physical machines (`AUTOLOGIN` in [configuration.md](configuration.md)).
- `Mod+Shift+/` lists the keyboard shortcuts, `Mod+Space` opens the menu. See [usage.md](usage.md).
- `Mod+Y` starts the AI agent. Sign in on first launch, see [ai-agent.md](ai-agent.md).
- Personal settings (keyboard layout, timezone, your own packages) go in a personal layer, see [configuration.md](configuration.md#personal-layer).
