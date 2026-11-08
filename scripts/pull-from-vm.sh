#!/bin/bash
# Brings the configuration back from the reference VM (ssh host "void").
# On the VM, the dotfiles are links to ~/filigrane (~/void-setup before the renaming): what is changed there lands
# in its copy of the repository. So the configuration folders are fetched as a whole.
# Usage: pull-from-vm.sh [host]   then read the git diff again and commit.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
HOST="${1:-void}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ssh "$HOST" '{ cd ~/filigrane || cd ~/void-setup; } && tar -cf - dotfiles packages services hardware users config.env' | tar -xf - -C .

echo "Paquets installés manuellement sur $HOST mais absents des listes:"
ssh "$HOST" 'xbps-query -m' | sed -E 's/-[^-]+$//' | sort > "$TMP/vm.txt"
cat packages/*.txt | sed -e 's/#.*//' | grep -v '^$' | sort -u > "$TMP/repo.txt"
comm -23 "$TMP/vm.txt" "$TMP/repo.txt" || true

git status --short
