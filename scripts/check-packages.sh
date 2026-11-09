#!/bin/bash
# Checks that every package of the packages/*.txt lists (and users/*/packages/*.txt) exists in the Void repository of an architecture.
# scripts/check-packages.sh [x86_64|aarch64|riscv64] [--warn-only]     (default: current architecture)
# Without changing the system: the repository database goes into a temporary folder. Code 1 if packages are missing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="${1:-$(uname -m)}"
BASE="${VOID_MIRROR:-https://repo-default.voidlinux.org/current}"
case "$ARCH" in x86_64) SUB="" ;; aarch64|riscv64) SUB="/$ARCH" ;; *) echo "Architecture non prévue: $ARCH" >&2; exit 1 ;; esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export XBPS_ARCH="$ARCH"
REPOS=("--repository=$BASE$SUB" "--repository=$BASE$SUB/nonfree")
mkdir -p "$TMP/var/db/xbps/keys"
cp /var/db/xbps/keys/* "$TMP/var/db/xbps/keys/"  # keys of the current system (like the installer)
xbps-install -r "$TMP" "${REPOS[@]}" -Sy >/dev/null

missing=0
for list in "$ROOT"/packages/*.txt "$ROOT"/users/*/packages/*.txt; do
    [ "${list##*/}" = restricted.txt ] && continue  # built with xbps-src, absent from the repositories
    for pkg in $(sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$list" | grep -v '^$' || true); do
        if ! xbps-query -r "$TMP" "${REPOS[@]}" -R "$pkg" >/dev/null 2>&1; then
            echo "$ARCH: paquet introuvable: $pkg ($(basename "$list"))"
            missing=1
        fi
    done
done
[ "$missing" -eq 0 ] && echo "$ARCH: tous les paquets existent"
# --warn-only: missing ones reported without failing (other architecture: x86 packages are normally missing there)
[ "${2:-}" = --warn-only ] && exit 0
exit "$missing"
