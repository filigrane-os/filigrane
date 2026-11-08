#!/bin/sh
# Builds out of tree the Touch Bar drivers (disabled in the Void kernel config) for a given kernel.
# Called by DKMS:  ./build.sh <kernelver> <kernel_source_dir>
# Sources taken at the stable tag v<version> of the kernel on git.kernel.org, verified against SHA256SUMS.
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
