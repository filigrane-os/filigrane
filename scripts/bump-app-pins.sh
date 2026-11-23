#!/usr/bin/env bash
# Newer releases of the applications pinned in apps/*/upstream and of the libraries pinned in libs/*/upstream (url= and ref=, a tag).
#
#   scripts/bump-app-pins.sh [--apply] [NAME...]
#
# Prints "NAME OLD NEW" for each pin whose repository has a newer tag of the same family (v1.2.3, facteur-v1.2.3: the prefix
# of the pinned ref), and with --apply rewrites `ref=` of those pins. No argument: every application. FILI_APPS_DIR replaces
# apps/ (tests). Used by .github/workflows/bump-app-pins.yml; the rest of an update (tests/fili-shell/run.sh, README figures)
# is the user's.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPS_DIR="${FILI_APPS_DIR:-$ROOT/apps}"
LIBS_DIR="${FILI_LIBS_DIR:-$ROOT/libs}"
apply=0
names=()
for arg in "$@"; do
    case "$arg" in
        --apply) apply=1 ;;
        *) names+=("$arg") ;;
    esac
done
if [ ${#names[@]} -eq 0 ]; then
    for pin in "$APPS_DIR"/*/upstream "$LIBS_DIR"/*/upstream; do
        [ -f "$pin" ] && names+=("$(basename "$(dirname "$pin")")")
    done
fi

for name in "${names[@]}"; do
    pin="$APPS_DIR/$name/upstream"
    [ -f "$pin" ] || pin="$LIBS_DIR/$name/upstream"
    [ -f "$pin" ] || continue
    url="$(sed -n 's/^url=//p' "$pin")"
    ref="$(sed -n 's/^ref=//p' "$pin")"
    [ -n "$url" ] && [ -n "$ref" ] || { echo "bump-app-pins: $pin needs url= and ref=" >&2; exit 1; }
    prefix="${ref%%[0-9]*}"
    latest="$({ git ls-remote --tags --refs "$url" | sed 's|.*refs/tags/||' | grep -E "^${prefix}[0-9]+\.[0-9]+\.[0-9]+\$" | sort -V | tail -1; } || true)"
    [ -n "$latest" ] && [ "$latest" != "$ref" ] || continue
    # Only forwards: a pin on a tag newer than the newest one (a tag not pushed yet) stays
    [ "$(printf '%s\n%s\n' "$ref" "$latest" | sort -V | tail -1)" = "$latest" ] || continue
    echo "$name $ref $latest"
    if [ "$apply" = 1 ]; then
        sed -i "s|^ref=.*|ref=$latest|" "$pin"
    fi
done
