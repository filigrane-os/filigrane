#!/bin/bash
# Rapatrie la configuration depuis la VM de référence (hôte ssh "void").
# Sur la VM, les dotfiles sont des liens vers ~/filigrane (~/void-setup avant le renommage): ce qu'on y modifie atterrit
# dans sa copie du dépôt. On récupère donc les dossiers de configuration en bloc.
# Usage: pull-from-vm.sh [hôte]   puis relire `git diff` et commiter.
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
