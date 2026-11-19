#!/bin/sh
# Multitouch trackpad of the T2 Macs: hid-apple (ignores the trackpad) and hid-magicmouse (the driver), out of tree.
# Called by DKMS:  ./build.sh <kernelver> <kernel_source_dir>
# Base v6.18.7 + t2linux/linux-t2-patches (4001 HID part, 4003-4005, pinned revision)
# + 9001 (port of the stable fixes up to v6.18.57) + 9002 (swap_fn_leftctrl limited to one product, the internal keyboard).
# The downloaded files are verified against SHA256SUMS. 6.18 series only.
set -eu
kver="$1" ksrc="$2"
BASE=v6.18.7
REV=4cd1efe5cf92f53bea7fcabf20277e06e41dae95
T2PATCHES="4003-HID-apple-ignore-the-trackpad-on-T2-Macs.patch
4004-HID-magicmouse-Add-support-for-trackpads-found-on-T2.patch
4005-HID-magicmouse-fix-regression-breaking-support-for-M.patch"
case "$kver" in 6.18.*) ;; *) echo "t2-trackpad: noyau $kver hors série 6.18, à rebaser (voir build.sh)" >&2; exit 1 ;; esac

cache=/var/cache/t2-trackpad
mkdir -p "$cache"
get() { # get NOM URL
    [ -s "$cache/$1" ] || { curl -fsSL "$2" -o "$cache/$1.tmp" && mv "$cache/$1.tmp" "$cache/$1"; }
    cp "$cache/$1" "./$1"
}
for f in hid-apple.c hid-magicmouse.c hid-ids.h; do
    get "$f" "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/drivers/hid/$f?h=$BASE"
done
for p in 4001-asahi-trackpad.patch $T2PATCHES; do
    get "$p" "https://raw.githubusercontent.com/t2linux/linux-t2-patches/$REV/$p"
done
sha256sum -c --quiet SHA256SUMS || { echo "t2-trackpad: sources différentes des sommes épinglées" >&2; exit 1; }

w="$(mktemp -d)"
mkdir -p "$w/tree/drivers/hid" "$w/split"
cp hid-apple.c hid-magicmouse.c hid-ids.h "$w/tree/drivers/hid/"
git -C "$w/tree" init -q
# 4001 is an Asahi series of 18 patches: only the parts on these three files are used by the T2
git mailsplit -o"$w/split" 4001-asahi-trackpad.patch >/dev/null
for p in $(find "$w/split" -type f | sort); do
    git -C "$w/tree" apply --include=drivers/hid/hid-apple.c --include=drivers/hid/hid-magicmouse.c \
        --include=drivers/hid/hid-ids.h "$p"
done
for p in $T2PATCHES 9001-stable-6.18.57-fixes.patch 9002-swap-fn-leftctrl-one-product.patch; do
    git -C "$w/tree" apply --whitespace=nowarn "$PWD/$p"
done
cp "$w/tree/drivers/hid/hid-apple.c" "$w/tree/drivers/hid/hid-magicmouse.c" "$w/tree/drivers/hid/hid-ids.h" .
rm -rf "$w"

make -C "$ksrc" M="$PWD" modules
