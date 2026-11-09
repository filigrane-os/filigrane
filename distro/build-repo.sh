#!/bin/bash
# Builds the xbps repository of the distribution in distro/out/repo (without root):
# <distro>-<app>   one package per tool of apps/ (Rust, release binary in /usr/bin): no more cargo needed on the machine.
# Version = the one of Cargo.toml, revision _N = number of commits touching apps/<app> (hence one update
# per change of the tool, without a manual bump). Dependencies and description: apps/<app>/package.env
# <distro>-apps    meta-package that depends on all the tools (bootstrap.sh and <distro>-desktop rely on it)
# <distro>-<list> one meta-package per packages/<list>.txt (base, desktop, dev, vm, baremetal, cpu-*, gpu-*...):
# adding a package to a list makes it reach everyone through the next system update
# distro/build-repo.sh [--arch x86_64] [--app NAME]
# --app NAME: only builds that package (NAME = folder of apps/), without the meta-packages: quick iteration.
# FILI_TARGET_DIR: cargo target folder, to keep between two calls so as not to recompile everything
# (default ~/.cache/filigrane-apps, the one of bootstrap.sh).
# A tool already present at the same version is not rebuilt, unless it has uncommitted changes.
# FILI_REUSE=1: same rule for all the packages, meta-packages included (publishing CI, see .github/workflows/repo.yml).
# Signing (repository published online): XBPS_PRIVKEY=<PEM RSA key> distro/build-repo.sh. A local repository (ISO) can stay unsigned.
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

# Version of the meta-packages: date and time of the last commit (grows with every pushed change), _1 = xbps revision
VERSION="0.$(git -C "$ROOT" log -1 --format=%cd --date=format:%Y%m%d.%H%M 2>/dev/null || date +%Y%m%d.%H%M)"
mkdir -p "$OUT"

read_list() { sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$1" | grep -v '^$' || true; }

create() { # create NAME VERSION_REV ARCH "description" "dependencies" DESTDIR [xbps-create options]; license: $LICENSE_OF (default MIT)
    local name="$1" ver="$2" arch="$3" desc="$4" deps="$5" dest="$6"; shift 6
    # FILI_REUSE=1 (publishing CI): a package already there at this version stays as it is, so that its hash
    # in the index stays the one of the file already online
    if [ -n "${FILI_REUSE:-}" ] && [ -f "$OUT/$name-$ver.$arch.xbps" ]; then echo "$name-$ver.$arch"; echo "$name-$ver.$arch.xbps" >>"$WORK/made.txt"; return 0; fi
    rm -f "$OUT/$name-$ver.$arch.xbps"
    (cd "$OUT" && xbps-create -q -A "$arch" -n "$name-$ver" -s "$desc" -D "$deps" \
        -H "$DISTRO_HOMEPAGE" -l "${LICENSE_OF:-MIT}" -m "$DISTRO" "$@" "$dest")
    echo "$name-$ver.$arch"
    echo "$name-$ver.$arch.xbps" >>"$WORK/made.txt"
}

# Package name: the folder of apps/, prefixed by <distro>- if it is not (budget -> fili-budget, avoids collisions with Void)
pkg_name() { case "$1" in "$DISTRO"-*) echo "$1" ;; *) echo "$DISTRO-$1" ;; esac; }

# Source directory of a tool: apps/<app>, or the pinned checkout of a tool that lives in its own repository
# (apps/<app>/upstream, see scripts/upstream-dir)
src_dir() {
    if [ -f "$ROOT/apps/$1/upstream" ]; then "$ROOT/scripts/upstream-dir" "$1"; else echo "$ROOT/apps/$1"; fi
}

# xbps version of a tool: <Cargo version>_<commits that touch apps/<app>> (+1 if modified and uncommitted)
app_version() {
    local app="$1" v rev
    v="$(sed -n 's/^version *= *"\(.*\)".*/\1/p' "$(src_dir "$app")/Cargo.toml" | head -1)"
    rev="$(git -C "$ROOT" rev-list --count HEAD -- "apps/$app" 2>/dev/null || echo 0)"
    [ -n "$(git -C "$ROOT" status --porcelain -- "apps/$app" 2>/dev/null)" ] && rev=$((rev + 1))
    [ "$rev" -ge 1 ] || rev=1
    echo "${v}_${rev}"
}

build_app() { # build_app APP -> writes the package name in $WORK/apps.list
    local app="$1" dir pkg ver dest dirty="" override
    dir="$(src_dir "$app")"
    pkg="$(pkg_name "$app")"
    ver="$(app_version "$app")"
    echo "$pkg" >>"$WORK/apps.list"
    [ -n "$(git -C "$ROOT" status --porcelain -- "apps/$app" 2>/dev/null)" ] && dirty=1
    # A local checkout (FILI_SRC_<NAME>) is work in progress: always rebuilt
    override="FILI_SRC_$(printf '%s' "$app" | tr 'a-z-' 'A-Z_')"
    [ -n "${!override:-}" ] && dirty=1
    if [ -z "$dirty" ] && [ -f "$OUT/$pkg-$ver.$ARCH.xbps" ]; then
        echo "==> $pkg-$ver: déjà construit"; echo "$pkg-$ver.$ARCH.xbps" >>"$WORK/made.txt"; return 0
    fi
    echo "==> $pkg-$ver"
    # Package settings (optional): DESC, DEPENDS, SHLIBS, ALIASES, PKG_LICENSE. Default: a Rust binary that only links libc.
    local DESC="$app, outil de $DISTRO" DEPENDS="glibc>=2.39_1 libgcc>=0" SHLIBS="libc.so.6 libgcc_s.so.1" ALIASES="" PKG_LICENSE="MIT"
    # shellcheck disable=SC1091
    [ -f "$dir/package.env" ] && source "$dir/package.env"
    # QMAKE: cxx-qt (fili-file) finds Qt through it; Void keeps qmake6 outside PATH
    dest="$WORK/$app"
    mkdir -p "$dest"
    if [ -f "$dir/Makefile" ]; then
        # A tool with its own Makefile installs itself (binary, aliases, desktop entry, icon, services, licenses)
        (cd "$dir" && QMAKE="${QMAKE:-/usr/lib/qt6/bin/qmake6}" CARGO_TARGET_DIR="$TARGET" make install PREFIX=/usr DESTDIR="$dest" >/dev/null)
    else
        (cd "$dir" && QMAKE="${QMAKE:-/usr/lib/qt6/bin/qmake6}" CARGO_TARGET_DIR="$TARGET" cargo build -q --release --locked --manifest-path "$dir/Cargo.toml")
        mkdir -p "$dest/usr/bin"
        install -m 755 "$TARGET/release/$app" "$dest/usr/bin/$app"
        # licenses/ of the tool (fonts and other embedded files): /usr/share/licenses/<package>/
        if [ -d "$dir/licenses" ]; then
            mkdir -p "$dest/usr/share/licenses/$pkg"
            cp "$dir"/licenses/* "$dest/usr/share/licenses/$pkg/"
        fi
        # ALIASES (package.env): other command names for the same program
        local alias
        for alias in $ALIASES; do ln -sfn "$app" "$dest/usr/bin/$alias"; done
    fi
    LICENSE_OF="$PKG_LICENSE" create "$pkg" "$ver" "$ARCH" "$DESC" "$DEPENDS" "$dest" --shlib-requires "$SHLIBS"
}

command -v cargo >/dev/null || { echo "cargo requis (xbps-install cargo)" >&2; exit 1; }
if [ -n "$ONLY" ]; then
    [ -f "$ROOT/apps/$ONLY/Cargo.toml" ] || [ -f "$ROOT/apps/$ONLY/upstream" ] || { echo "apps/$ONLY n'est pas un outil Rust du dépôt" >&2; exit 1; }
    build_app "$ONLY"
else
    for d in "$ROOT"/apps/*/; do
        [ -f "$d/Cargo.toml" ] || [ -f "$d/upstream" ] || continue
        build_app "$(basename "$d")"
    done

    echo "==> $DISTRO-apps (méta-paquet des outils)"
    empty="$WORK/empty"
    mkdir -p "$empty"
    create "$DISTRO-apps" "${VERSION}_1" noarch "Outils natifs de $DISTRO (barre, flou du menu, budget ressources, explorateur...)" \
        "$(sed 's/$/>=0/' "$WORK/apps.list" | tr '\n' ' ')" "$empty" >/dev/null

    echo "==> $DISTRO-repo (adresse du dépôt et clé de signature)"
    # The machines take their xbps configuration from this package: changing DISTRO_REPO_URL then publishing = new address everywhere.
    # The public key (distro/repo/keys/<fingerprint>.plist) avoids the import question at the first install.
    rdest="$WORK/repo"
    mkdir -p "$rdest/etc/xbps.d" "$rdest/var/db/xbps/keys"
    printf '# Dépôt de la distribution %s (paquet %s-repo)\nrepository=%s\n' "$DISTRO" "$DISTRO" "$DISTRO_REPO_URL" >"$rdest/etc/xbps.d/10-$DISTRO.conf"
    cp "$ROOT"/distro/repo/keys/*.plist "$rdest/var/db/xbps/keys/"
    # No --config-files: xbps never replaces a configuration file that is already there (the one of bootstrap.sh, for
    # example), and the address must follow the package. Local setting: another file of /etc/xbps.d (20-local.conf...).
    create "$DISTRO-repo" "${VERSION}_1" noarch "Dépôt xbps de $DISTRO: adresse et clé de signature" "" "$rdest" >/dev/null

    echo "==> Méta-paquets (packages/*.txt)"
    for list in "$ROOT"/packages/*.txt; do
        l="$(basename "$list" .txt)"
        [ "$l" = restricted ] && continue  # licences without redistribution: xbps-src locally
        deps="$(read_list "$list" | sed 's/$/>=0/' | tr '\n' ' ')"
        [ "$l" = desktop ] && deps="$deps $DISTRO-apps>=${VERSION}_1"
        [ "$l" = base ] && deps="$deps $DISTRO-repo>=0"
        create "$DISTRO-$l" "${VERSION}_1" noarch "$DISTRO: paquets de la liste $l" "$deps" "$empty"
    done
fi

echo "==> Index"
# Full build: a package nobody builds any more (tool removed from apps/, renamed) must leave the repository, or it stays
# published forever and can conflict with the package that took over its files
if [ -z "$ONLY" ] && [ -s "$WORK/made.txt" ]; then
    for f in "$OUT"/*.xbps; do
        grep -qxF "$(basename "$f")" "$WORK/made.txt" || { echo "removed (not built any more): $(basename "$f")"; rm -f "$f" "$f.sig2"; }
    done
fi
# Index rebuilt from the files present: a package rebuilt under the same version would otherwise have kept the old hash
rm -f "$OUT"/*-repodata "$OUT"/*-stagedata
xbps-rindex -a "$OUT"/*.xbps >/dev/null
xbps-rindex -r "$OUT" >/dev/null  # entries whose file disappeared removed from the index...
xbps-rindex -c "$OUT" >/dev/null  # ...and stale files (no longer in the index) removed from the disk
if [ -n "${XBPS_PRIVKEY:-}" ]; then
    xbps-rindex --sign --signedby "$DISTRO" --privkey "$XBPS_PRIVKEY" "$OUT"
    xbps-rindex --sign-pkg --privkey "$XBPS_PRIVKEY" "$OUT"/*.xbps
fi
echo "Dépôt: $OUT ($(find "$OUT" -name '*.xbps' | wc -l) paquets)"
