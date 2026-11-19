#!/bin/sh
# Builds out of tree the Touch Bar drivers (disabled in the Void kernel config) for a given kernel.
# Called by DKMS:  ./build.sh <kernelver> <kernel_source_dir>
# Sources taken at the stable tag v<version> of the kernel on git.kernel.org, verified against SHA256SUMS (drivers) and a check of the IDs used (hid-ids.h).
set -eu
kver="$1" ksrc="$2"
base="${kver%%_*}"                       # 6.18.57_1 -> 6.18.57
case "$base" in *.*.0) tag="v${base%.0}" ;; *) tag="v$base" ;; esac
url=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain
cache="/var/cache/appletb/$tag"

mkdir -p "$cache"
for p in drivers/hid/hid-appletb-kbd.c drivers/hid/hid-appletb-bl.c drivers/gpu/drm/tiny/appletbdrm.c drivers/hid/hid-ids.h; do
    f="${p##*/}"
    if [ ! -s "$cache/$f" ]; then
        curl -fsSL "$url/$p?h=$tag" -o "$cache/$f.tmp"
        mv "$cache/$f.tmp" "$cache/$f"
    fi
    cp "$cache/$f" "./$f"
done

# hid-ids.h changes with almost every kernel release (new devices only): it is not pinned. The drivers
# only use these three IDs, which must be present with the expected values.
for d in "USB_VENDOR_ID_APPLE 0x05ac" "USB_DEVICE_ID_APPLE_TOUCHBAR_BACKLIGHT 0x8102" "USB_DEVICE_ID_APPLE_TOUCHBAR_DISPLAY 0x8302"; do
    set -- $d
    if ! grep -qE "^#define[[:space:]]+$1[[:space:]]+$2([[:space:]]|\$)" hid-ids.h; then
        echo "appletb: hid-ids.h of $tag no longer defines $1 as $2." >&2
        exit 1
    fi
done

if ! sha256sum -c --quiet SHA256SUMS; then
    echo "appletb: les sources $tag diffèrent des sommes épinglées (SHA256SUMS)." >&2
    echo "appletb: relire le diff ($cache), mettre à jour hardware/mac-t2/appletb/SHA256SUMS et PACKAGE_VERSION." >&2
    exit 1
fi

# Local patches (e.g. listening to the virtual keyboard of keyd), after verifying the upstream sources
for p in 0*.patch; do
    [ -e "$p" ] || continue
    git apply --directory=. -p3 "$p"
done

make -C "$ksrc" M="$PWD" modules
