#!/bin/bash
# Installs Void Linux (glibc, x86_64, UEFI) on a disk, then replays bootstrap.sh.
# Run as root from the Void live ISO, network up, repository cloned/copied onto the live system.
#
#   ./install-void.sh --disk /dev/sda [--user NAME] [--hostname void] [--profile auto|vm|baremetal]
#                    [--machine auto|generic|mac-t2] [--cpu auto|intel|amd|other] [--gpu auto|none|intel,amd,nvidia]
#
# WARNING: erases the WHOLE target disk.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISK=""
USERNAME="user"
HOSTNAME_="void"
PROFILE="auto"
MACHINE="auto"
CPU="auto"
GPU="auto"
REPO="${REPO:-https://repo-default.voidlinux.org/current}"

while [ $# -gt 0 ]; do
    case "$1" in
        --disk) DISK="${2:?}"; shift 2 ;;
        --user) USERNAME="${2:?}"; shift 2 ;;
        --hostname) HOSTNAME_="${2:?}"; shift 2 ;;
        --profile) PROFILE="${2:?}"; shift 2 ;;
        --machine) MACHINE="${2:?}"; shift 2 ;;
        --cpu) CPU="${2:?}"; shift 2 ;;
        --gpu) GPU="${2:?}"; shift 2 ;;
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

[ "$(id -u)" -eq 0 ] || { echo "Run as root" >&2; exit 1; }
[ -b "$DISK" ] || { echo "--disk <block device> required (e.g. /dev/sda, /dev/nvme0n1)" >&2; exit 1; }
[ -d /sys/firmware/efi ] || { echo "Not booted in UEFI mode: unsupported" >&2; exit 1; }
[ "$(uname -m)" = x86_64 ] || { echo "Not an x86_64 machine" >&2; exit 1; }

# nvme0n1 -> nvme0n1p1, sda -> sda1
case "$DISK" in *[0-9]) P="${DISK}p" ;; *) P="$DISK" ;; esac

lsblk "$DISK"
echo
echo "The whole content of $DISK will be ERASED."
read -r -p "Type the disk path again to confirm: " confirm
[ "$confirm" = "$DISK" ] || { echo "Cancelled."; exit 1; }

echo "==> Partitioning"
wipefs -af "$DISK"
parted -s "$DISK" mklabel gpt \
    mkpart ESP fat32 1MiB 513MiB set 1 esp on \
    mkpart root ext4 513MiB 100%
partprobe "$DISK"; sleep 1
mkfs.vfat -F32 -n ESP "${P}1"
mkfs.ext4 -F -L void "${P}2"

echo "==> Mounting"
mount "${P}2" /mnt
mkdir -p /mnt/boot/efi
mount "${P}1" /mnt/boot/efi

echo "==> Base system"
mkdir -p /mnt/var/db/xbps/keys
cp /var/db/xbps/keys/* /mnt/var/db/xbps/keys/
XBPS_ARCH=x86_64 xbps-install -Sy -R "$REPO" -r /mnt base-system grub-x86_64-efi sudo git curl

echo "==> Chroot"
for d in dev proc sys; do
    mount --rbind "/$d" "/mnt/$d"
    mount --make-rslave "/mnt/$d"
done
cp /etc/resolv.conf /mnt/etc/resolv.conf

ROOT_UUID="$(blkid -s UUID -o value "${P}2")"
ESP_UUID="$(blkid -s UUID -o value "${P}1")"
cat > /mnt/etc/fstab <<EOF
UUID=$ROOT_UUID / ext4 defaults 0 1
UUID=$ESP_UUID /boot/efi vfat defaults 0 2
tmpfs /tmp tmpfs defaults,nosuid,nodev 0 0
EOF
echo "$HOSTNAME_" > /mnt/etc/hostname

chroot /mnt useradd -m -G wheel,audio,video -s /bin/bash "$USERNAME"
echo "Root password:"; chroot /mnt passwd root
echo "Password of $USERNAME:"; chroot /mnt passwd "$USERNAME"

echo "==> Bootstrap (packages, services, dotfiles)"
cp -a "$ROOT" "/mnt/home/$USERNAME/void-setup"
chroot /mnt chown -R "$USERNAME:" "/home/$USERNAME/void-setup"
chroot /mnt env TARGET_USER="$USERNAME" "/home/$USERNAME/void-setup/bootstrap.sh" --profile "$PROFILE" --machine "$MACHINE" --cpu "$CPU" --gpu "$GPU"

echo "==> Bootloader"
# --removable: works on any PC/Intel Mac without a dedicated NVRAM entry
chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=void --removable
chroot /mnt xbps-reconfigure -fa

umount -R /mnt
echo "Installation finished. Remove the media and reboot."
