#!/bin/bash
# Vérifie que chaque paquet des listes packages/*.txt (et users/*/packages/*.txt) existe dans le dépôt Void d'une architecture.
#
#   scripts/check-packages.sh [x86_64|aarch64|riscv64] [--warn-only]     (défaut: architecture courante)
#
# Sans modifier le système: la base de dépôt va dans un dossier temporaire. Code 1 si des paquets manquent.
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
cp /var/db/xbps/keys/* "$TMP/var/db/xbps/keys/"  # clés du système courant (comme install-void.sh)
xbps-install -r "$TMP" "${REPOS[@]}" -Sy >/dev/null

missing=0
for list in "$ROOT"/packages/*.txt "$ROOT"/users/*/packages/*.txt; do
    [ "${list##*/}" = restricted.txt ] && continue  # construits avec xbps-src, absents des dépôts
    for pkg in $(sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$list" | grep -v '^$' || true); do
        if ! xbps-query -r "$TMP" "${REPOS[@]}" -R "$pkg" >/dev/null 2>&1; then
            echo "$ARCH: paquet introuvable: $pkg ($(basename "$list"))"
            missing=1
        fi
    done
done
[ "$missing" -eq 0 ] && echo "$ARCH: tous les paquets existent"
# --warn-only: manquants signalés sans échec (autre architecture: des paquets x86 y manquent normalement)
[ "${2:-}" = --warn-only ] && exit 0
exit "$missing"
