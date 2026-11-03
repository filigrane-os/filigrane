#!/bin/bash
# Construit le dépôt xbps de la distribution dans distro/out/repo (sans root):
#   <distro>-<app>   un paquet par outil de apps/ (Rust, binaire en release dans /usr/bin): plus besoin de cargo sur la machine.
#                    Version = celle de Cargo.toml, révision _N = nombre de commits touchant apps/<app> (donc une mise à jour
#                    par changement de l'outil, sans bump à la main). Dépendances et description: apps/<app>/package.env
#   <distro>-apps    méta-paquet qui dépend de tous les outils (bootstrap.sh et <distro>-desktop s'appuient dessus)
#   <distro>-<liste> un méta-paquet par packages/<liste>.txt (base, desktop, dev, vm, baremetal, cpu-*, gpu-*...):
#                    ajouter un paquet à une liste le fait arriver chez tout le monde par `xbps-install -Su`
#
#   distro/build-repo.sh [--arch x86_64] [--app NOM]
#
# --app NOM: ne construit que ce paquet (NOM = dossier de apps/), sans les méta-paquets: itération rapide.
# FILI_TARGET_DIR: dossier cible de cargo, à garder entre deux appels pour ne pas tout recompiler
# (par défaut ~/.cache/filigrane-apps, celui de bootstrap.sh).
# Un outil déjà présent à la même version n'est pas reconstruit, sauf s'il a des modifications non commitées.
# FILI_REUSE=1: même règle pour tous les paquets, méta-paquets compris (CI de publication, voir .github/workflows/repo.yml).
#
# Signature (dépôt publié en ligne): XBPS_PRIVKEY=<clé RSA PEM> distro/build-repo.sh. Un dépôt local (ISO) peut rester non signé.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=distro/distro.env
source "$ROOT/distro/distro.env"
ARCH="$(uname -m)"
ONLY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --arch) ARCH="${2:?architecture manquante}"; shift 2 ;;
        --app) ONLY="${2:?nom de outil manquant}"; shift 2 ;;
        *) echo "usage: distro/build-repo.sh [--arch ARCH] [--app NOM]" >&2; exit 2 ;;
    esac
done
OUT="$ROOT/distro/out/repo"
TARGET="${FILI_TARGET_DIR:-$HOME/.cache/filigrane-apps}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Version des méta-paquets: date et heure du dernier commit (croît à chaque changement poussé), _1 = révision xbps
VERSION="0.$(git -C "$ROOT" log -1 --format=%cd --date=format:%Y%m%d.%H%M 2>/dev/null || date +%Y%m%d.%H%M)"
mkdir -p "$OUT"

read_list() { sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$1" | grep -v '^$' || true; }

create() { # create NOM VERSION_REV ARCH "description" "dépendances" DESTDIR [options xbps-create]; license: $LICENSE_OF (default MIT)
    local name="$1" ver="$2" arch="$3" desc="$4" deps="$5" dest="$6"; shift 6
    # FILI_REUSE=1 (CI de publication): un paquet déjà là à cette version reste tel quel, pour que son empreinte
    # dans l'index reste celle du fichier déjà en ligne
    if [ -n "${FILI_REUSE:-}" ] && [ -f "$OUT/$name-$ver.$arch.xbps" ]; then echo "$name-$ver.$arch"; return 0; fi
    rm -f "$OUT/$name-$ver.$arch.xbps"
    (cd "$OUT" && xbps-create -q -A "$arch" -n "$name-$ver" -s "$desc" -D "$deps" \
        -H "$DISTRO_HOMEPAGE" -l "${LICENSE_OF:-MIT}" -m "$DISTRO" "$@" "$dest")
    echo "$name-$ver.$arch"
}

# Nom du paquet: le dossier de apps/, préfixé par <distro>- s'il ne l'est pas (budget -> fili-budget, évite les collisions avec Void)
pkg_name() { case "$1" in "$DISTRO"-*) echo "$1" ;; *) echo "$DISTRO-$1" ;; esac; }

# Version xbps d'un outil: <version Cargo>_<commits qui touchent apps/<app>> (+1 si modifié et non commité)
app_version() {
    local app="$1" v rev
    v="$(sed -n 's/^version *= *"\(.*\)".*/\1/p' "$ROOT/apps/$app/Cargo.toml" | head -1)"
    rev="$(git -C "$ROOT" rev-list --count HEAD -- "apps/$app" 2>/dev/null || echo 0)"
    [ -n "$(git -C "$ROOT" status --porcelain -- "apps/$app" 2>/dev/null)" ] && rev=$((rev + 1))
    [ "$rev" -ge 1 ] || rev=1
    echo "${v}_${rev}"
}

build_app() { # build_app APP -> écrit le nom du paquet dans $WORK/apps.list
    local app="$1" dir="$ROOT/apps/$1" pkg ver dest dirty=""
    pkg="$(pkg_name "$app")"
    ver="$(app_version "$app")"
    echo "$pkg" >>"$WORK/apps.list"
    [ -n "$(git -C "$ROOT" status --porcelain -- "apps/$app" 2>/dev/null)" ] && dirty=1
    if [ -z "$dirty" ] && [ -f "$OUT/$pkg-$ver.$ARCH.xbps" ]; then
        echo "==> $pkg-$ver: déjà construit"; return 0
    fi
    echo "==> $pkg-$ver"
    # Réglages du paquet (facultatif): DESC, DEPENDS, SHLIBS, ALIASES, PKG_LICENSE. Défaut: un binaire Rust qui ne lie que la libc.
    local DESC="$app, outil de $DISTRO" DEPENDS="glibc>=2.39_1 libgcc>=0" SHLIBS="libc.so.6 libgcc_s.so.1" ALIASES="" PKG_LICENSE="MIT"
    # shellcheck disable=SC1091
    [ -f "$dir/package.env" ] && source "$dir/package.env"
    # QMAKE: cxx-qt (fili-file) finds Qt through it; Void keeps qmake6 outside PATH
    (cd "$dir" && QMAKE="${QMAKE:-/usr/lib/qt6/bin/qmake6}" CARGO_TARGET_DIR="$TARGET" cargo build -q --release --locked --manifest-path "$dir/Cargo.toml")
    dest="$WORK/$app"
    mkdir -p "$dest/usr/bin"
    install -m 755 "$TARGET/release/$app" "$dest/usr/bin/$app"
    # licenses/ of the tool (fonts and other embedded files): /usr/share/licenses/<package>/
    if [ -d "$dir/licenses" ]; then
        mkdir -p "$dest/usr/share/licenses/$pkg"
        cp "$dir"/licenses/* "$dest/usr/share/licenses/$pkg/"
    fi
    # ALIASES (package.env): other command names for the same program (casier -> fili-file)
    local alias
    for alias in $ALIASES; do ln -s "$app" "$dest/usr/bin/$alias"; done
    LICENSE_OF="$PKG_LICENSE" create "$pkg" "$ver" "$ARCH" "$DESC" "$DEPENDS" "$dest" --shlib-requires "$SHLIBS"
}

command -v cargo >/dev/null || { echo "cargo requis (xbps-install cargo)" >&2; exit 1; }
if [ -n "$ONLY" ]; then
    [ -f "$ROOT/apps/$ONLY/Cargo.toml" ] || { echo "apps/$ONLY n'est pas un outil Rust du dépôt" >&2; exit 1; }
    build_app "$ONLY"
else
    for manifest in "$ROOT"/apps/*/Cargo.toml; do
        build_app "$(basename "$(dirname "$manifest")")"
    done

    echo "==> $DISTRO-apps (méta-paquet des outils)"
    empty="$WORK/empty"
    mkdir -p "$empty"
    create "$DISTRO-apps" "${VERSION}_1" noarch "Outils natifs de $DISTRO (barre, flou du menu, budget ressources, explorateur...)" \
        "$(sed 's/$/>=0/' "$WORK/apps.list" | tr '\n' ' ')" "$empty" >/dev/null

    echo "==> $DISTRO-repo (adresse du dépôt et clé de signature)"
    # Les machines tiennent leur configuration xbps de ce paquet: changer DISTRO_REPO_URL puis publier = nouvelle adresse partout.
    # La clé publique (distro/repo/keys/<empreinte>.plist) évite la question d'import au premier xbps-install.
    rdest="$WORK/repo"
    mkdir -p "$rdest/etc/xbps.d" "$rdest/var/db/xbps/keys"
    printf '# Dépôt de la distribution %s (paquet %s-repo)\nrepository=%s\n' "$DISTRO" "$DISTRO" "$DISTRO_REPO_URL" >"$rdest/etc/xbps.d/10-$DISTRO.conf"
    cp "$ROOT"/distro/repo/keys/*.plist "$rdest/var/db/xbps/keys/"
    # Pas de --config-files: xbps ne remplace jamais un fichier de configuration déjà présent (celui de bootstrap.sh, par
    # exemple), et l'adresse doit suivre le paquet. Réglage local: un autre fichier de /etc/xbps.d (20-local.conf...).
    create "$DISTRO-repo" "${VERSION}_1" noarch "Dépôt xbps de $DISTRO: adresse et clé de signature" "" "$rdest" >/dev/null

    echo "==> Méta-paquets (packages/*.txt)"
    for list in "$ROOT"/packages/*.txt; do
        l="$(basename "$list" .txt)"
        [ "$l" = restricted ] && continue  # licences sans redistribution: xbps-src en local
        deps="$(read_list "$list" | sed 's/$/>=0/' | tr '\n' ' ')"
        [ "$l" = desktop ] && deps="$deps $DISTRO-apps>=${VERSION}_1"
        [ "$l" = base ] && deps="$deps $DISTRO-repo>=0"
        create "$DISTRO-$l" "${VERSION}_1" noarch "$DISTRO: paquets de la liste $l" "$deps" "$empty"
    done
fi

echo "==> Index"
# Index refait depuis les fichiers présents: un paquet reconstruit sous la même version aurait sinon gardé l'ancienne empreinte
rm -f "$OUT"/*-repodata "$OUT"/*-stagedata
xbps-rindex -a "$OUT"/*.xbps >/dev/null
xbps-rindex -r "$OUT" >/dev/null  # entrées dont le fichier a disparu retirées de l'index...
xbps-rindex -c "$OUT" >/dev/null  # ...et fichiers périmés (plus dans l'index) retirés du disque
if [ -n "${XBPS_PRIVKEY:-}" ]; then
    xbps-rindex --sign --signedby "$DISTRO" --privkey "$XBPS_PRIVKEY" "$OUT"
    xbps-rindex --sign-pkg --privkey "$XBPS_PRIVKEY" "$OUT"/*.xbps
fi
echo "Dépôt: $OUT ($(find "$OUT" -name '*.xbps' | wc -l) paquets)"
