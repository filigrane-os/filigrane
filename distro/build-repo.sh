#!/bin/bash
# Construit le dépôt xbps de la distribution dans distro/out/repo (sans root):
#   <distro>-apps    les outils maison de apps/ compilés en release (/usr/bin): plus besoin de cargo sur la machine
#   <distro>-<liste> un méta-paquet par packages/<liste>.txt (base, desktop, dev, vm, baremetal, cpu-*, gpu-*...):
#                    ajouter un paquet à une liste le fait arriver chez tout le monde par `xbps-install -Su`
#
#   distro/build-repo.sh [--arch x86_64]
#
# Signature (dépôt publié en ligne): XBPS_PRIVKEY=<clé RSA PEM> distro/build-repo.sh. Un dépôt local (ISO) peut rester non signé.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=distro/distro.env
source "$ROOT/distro/distro.env"
ARCH="$(uname -m)"
[ "${1:-}" = --arch ] && ARCH="${2:?architecture manquante}"
OUT="$ROOT/distro/out/repo"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Version: date et heure du dernier commit (croît à chaque changement poussé), _1 = révision xbps
VERSION="0.$(git -C "$ROOT" log -1 --format=%cd --date=format:%Y%m%d.%H%M 2>/dev/null || date +%Y%m%d.%H%M)"
mkdir -p "$OUT"

read_list() { sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$1" | grep -v '^$' || true; }

create() { # create NOM ARCH "description" "dépendances" DESTDIR [options xbps-create]
    local name="$1" arch="$2" desc="$3" deps="$4" dest="$5"; shift 5
    rm -f "$OUT/$name-$VERSION"_1."$arch".xbps
    (cd "$OUT" && xbps-create -q -A "$arch" -n "$name-${VERSION}_1" -s "$desc" -D "$deps" \
        -H "$DISTRO_HOMEPAGE" -l MIT -m "$DISTRO" "$@" "$dest")
    echo "$name-${VERSION}_1.$arch"
}

echo "==> $DISTRO-apps (apps/*, Rust)"
command -v cargo >/dev/null || { echo "cargo requis (xbps-install cargo)" >&2; exit 1; }
dest="$WORK/apps"
mkdir -p "$dest/usr/bin"
for manifest in "$ROOT"/apps/*/Cargo.toml; do
    name="$(basename "$(dirname "$manifest")")"
    (cd "$(dirname "$manifest")" && CARGO_TARGET_DIR="$WORK/target" cargo build -q --release --locked --manifest-path "$manifest")
    install -m 755 "$WORK/target/release/$name" "$dest/usr/bin/$name"
done
# fili-file: Qt Quick (déjà là pour Quickshell), qt6-svg pour les icônes
create "$DISTRO-apps" "$ARCH" "Outils natifs de $DISTRO (barre, flou du menu, budget ressources, explorateur)" \
    "glibc>=2.39_1 libgcc>=0 qt6-declarative>=0 qt6-svg>=0" "$dest" \
    --shlib-requires "libc.so.6 libgcc_s.so.1 libstdc++.so.6 libQt6Core.so.6 libQt6Gui.so.6 libQt6Qml.so.6"

echo "==> Méta-paquets (packages/*.txt)"
empty="$WORK/empty"
mkdir -p "$empty"
for list in "$ROOT"/packages/*.txt; do
    l="$(basename "$list" .txt)"
    [ "$l" = restricted ] && continue  # licences sans redistribution: xbps-src en local
    deps="$(read_list "$list" | sed 's/$/>=0/' | tr '\n' ' ')"
    [ "$l" = desktop ] && deps="$deps $DISTRO-apps>=${VERSION}_1"
    create "$DISTRO-$l" noarch "$DISTRO: paquets de la liste $l" "$deps" "$empty"
done

echo "==> Index"
xbps-rindex -a "$OUT"/*.xbps >/dev/null
xbps-rindex -r "$OUT" >/dev/null  # anciennes versions retirées de l'index...
find "$OUT" -name "$DISTRO-*.xbps" ! -name "*-${VERSION}_1.*" -delete  # ...et du disque
if [ -n "${XBPS_PRIVKEY:-}" ]; then
    xbps-rindex --sign --signedby "$DISTRO" --privkey "$XBPS_PRIVKEY" "$OUT"
    xbps-rindex --sign-pkg --privkey "$XBPS_PRIVKEY" "$OUT"/*.xbps
fi
echo "Dépôt: $OUT ($(find "$OUT" -name '*.xbps' | wc -l) paquets, version $VERSION)"
