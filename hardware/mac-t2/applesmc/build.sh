#!/bin/sh
# applesmc with support for the SMC of the T2 Macs (MMIO, fans), built out of tree.
# Called by DKMS:  ./build.sh <kernelver> <kernel_source_dir>
# Base: applesmc.c of the v6.18.7 kernel + 30xx patches of t2linux/linux-t2-patches (pinned revision),
# all verified against SHA256SUMS. 6.18 series only: for another series, rebase and update.
set -eu
kver="$1" ksrc="$2"
BASE=v6.18.7
REV=4cd1efe5cf92f53bea7fcabf20277e06e41dae95
case "$kver" in 6.18.*) ;; *) echo "applesmc-t2: noyau $kver hors série 6.18, à rebaser (voir build.sh)" >&2; exit 1 ;; esac

cache=/var/cache/applesmc-t2
mkdir -p "$cache"
get() { # get NOM URL
    [ -s "$cache/$1" ] || { curl -fsSL "$2" -o "$cache/$1.tmp" && mv "$cache/$1.tmp" "$cache/$1"; }
    cp "$cache/$1" "./$1"
}
get applesmc.c "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/drivers/hwmon/applesmc.c?h=$BASE"
for p in $(sed -n 's/^[0-9a-f]*  \(30.*\.patch\)$/\1/p' SHA256SUMS); do
    get "$p" "https://raw.githubusercontent.com/t2linux/linux-t2-patches/$REV/$p"
done
sha256sum -c --quiet SHA256SUMS || { echo "applesmc-t2: sources différentes des sommes épinglées" >&2; exit 1; }

w="$(mktemp -d)"
mkdir -p "$w/drivers/hwmon"
cp applesmc.c "$w/drivers/hwmon/"
git -C "$w" init -q
for p in $(sed -n 's/^[0-9a-f]*  \(30.*\.patch\)$/\1/p' SHA256SUMS); do
    git -C "$w" apply "$PWD/$p"
done
cp "$w/drivers/hwmon/applesmc.c" ./applesmc.c
rm -rf "$w"

make -C "$ksrc" M="$PWD" modules
