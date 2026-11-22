#!/bin/bash
# Builds fili-niri: Void's niri template (same dependencies and options) with the Filigrane patch of the fork pinned in
# distro/niri/upstream, rebased on the niri release Void ships.
#
#   distro/niri/build.sh [--version] [--prepare] [--out DIR]
#   --version   prints the package name and version to build (fili-niri-26.04_201), builds nothing
#   --prepare   writes srcpkgs/fili-niri in the void-packages checkout (template and patches), builds nothing
#   --out DIR   copies the built package there (default distro/out/niri)
#
# FILI_VOID_PACKAGES: void-packages checkout (default ~/.cache/filigrane-void-packages, cloned shallow when missing)
# FILI_SRC_NIRI: local clone of the fork to use instead of the pinned commit (its "filigrane" branch)
# FILI_NIRI_TEMPLATE: Void's niri template to read the version from (--version only, tests)
# In a container running as root, xbps-src needs XBPS_CHROOT_CMD=ethereal (see .github/workflows/niri.yml).
# Exit status: 0 built, 3 the patch does not apply to the new niri release, 4 the build failed, 1 other error.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PIN="$ROOT/distro/niri/upstream"
VP="${FILI_VOID_PACKAGES:-${XDG_CACHE_HOME:-$HOME/.cache}/filigrane-void-packages}"
OUT="$ROOT/distro/out/niri"
MODE=build
while [ $# -gt 0 ]; do
    case "$1" in
        --version) MODE=version; shift ;;
        --prepare) MODE=prepare; shift ;;
        --out) OUT="${2:?missing directory}"; shift 2 ;;
        *) echo "usage: distro/niri/build.sh [--version] [--prepare] [--out DIR]" >&2; exit 1 ;;
    esac
done

pin() { sed -n "s/^$1=//p" "$PIN" | head -1; }
url="$(pin url)"; ref="$(pin ref)"; patchrev="$(pin patchrev)"
[ -n "$url" ] && [ -n "$ref" ] && [ -n "$patchrev" ] || { echo "build.sh: url=, ref= and patchrev= are required in $PIN" >&2; exit 1; }

# Void's niri template: from the checkout, or (version only) a given file or the one on GitHub
if [ "$MODE" = version ] && [ ! -f "$VP/srcpkgs/niri/template" ]; then
    template="${FILI_NIRI_TEMPLATE:-}"
    if [ -z "$template" ]; then
        template="$(mktemp)"
        trap 'rm -f "$template"' EXIT
        curl -fsSL https://raw.githubusercontent.com/void-linux/void-packages/master/srcpkgs/niri/template -o "$template"
    fi
else
    if [ ! -d "$VP/.git" ]; then
        echo "==> void-packages (shallow clone)"
        git clone -q --depth 1 https://github.com/void-linux/void-packages "$VP"
    elif [ -z "${FILI_VOID_PACKAGES_KEEP:-}" ]; then
        git -C "$VP" fetch -q --depth 1 origin master && git -C "$VP" reset -q --hard FETCH_HEAD
    fi
    template="$VP/srcpkgs/niri/template"
fi
version="$(sed -n 's/^version=//p' "$template" | head -1)"
revision="$(sed -n 's/^revision=//p' "$template" | head -1)"
[ -n "$version" ] && [ -n "$revision" ] || { echo "build.sh: no version/revision in $template" >&2; exit 1; }
pkgrev=$((revision * 100 + patchrev))
pkgver="fili-niri-${version}_${pkgrev}"
if [ "$MODE" = version ]; then
    echo "$pkgver"
    exit 0
fi

# Patch: the commits of the fork (except FILIGRANE.md) replayed on the niri release Void ships
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
src="$WORK/niri"
echo "==> niri $version + patch $ref"
if [ -n "${FILI_SRC_NIRI:-}" ]; then
    git clone -q --no-checkout "$FILI_SRC_NIRI" "$src"
    git -C "$src" fetch -q "$FILI_SRC_NIRI" filigrane
    ref="$(git -C "$src" rev-parse FETCH_HEAD)"
else
    git clone -q --no-checkout --filter=blob:none "$url" "$src"
fi
git -C "$src" fetch -q https://github.com/niri-wm/niri.git "refs/tags/v$version:refs/tags/v$version"
base="$(git -C "$src" merge-base "$ref" "v$version")"
mapfile -t commits < <(git -C "$src" rev-list --reverse "$base..$ref" -- . ':(exclude)FILIGRANE.md')
[ "${#commits[@]}" -gt 0 ] || { echo "build.sh: no patch commit between $base and $ref" >&2; exit 1; }
git -C "$src" -c advice.detachedHead=false checkout -q "v$version"
for c in "${commits[@]}"; do
    if ! git -C "$src" -c user.name=fili -c user.email=fili@localhost cherry-pick -x "$c" >/dev/null 2>"$WORK/pick.log"; then
        echo "build.sh: commit $c of the patch does not apply to niri $version:" >&2
        cat "$WORK/pick.log" >&2
        git -C "$src" diff --name-only --diff-filter=U >&2 || true
        exit 3
    fi
done

# Package: Void's niri template renamed, replacing niri, with the patch next to Void's own patches. Shell completions
# keep the command name (niri), not the package name
pkg="$VP/srcpkgs/fili-niri"
rm -rf "$pkg"
cp -r "$VP/srcpkgs/niri" "$pkg"
mkdir -p "$pkg/patches"
git -C "$src" diff "v$version" HEAD -- . ':(exclude)FILIGRANE.md' > "$pkg/patches/filigrane-crtc.patch"
# shellcheck disable=SC2016  # ${sh} is expanded by xbps-src, not here
sed -i \
    -e 's/^pkgname=niri$/pkgname=fili-niri/' \
    -e "s/^revision=.*/revision=$pkgrev/" \
    -e 's|^short_desc=.*|short_desc="Scrollable-tiling Wayland compositor (Filigrane patch)"|' \
    -e 's|^homepage=.*|homepage="https://github.com/filigrane-os/niri"|' \
    -e 's|vcompletion "niri.${sh}" "${sh}"$|vcompletion "niri.${sh}" "${sh}" niri|' \
    "$pkg/template"
# The tarball still unpacks to niri-<version>; installing fili-niri removes niri, which is no longer pulled back.
# After revision=: the template is a shell script, ${version} must already be set
# shellcheck disable=SC2016  # ${version} is expanded by xbps-src, not here
sed -i '/^revision=/a wrksrc="niri-${version}"\nprovides="niri-${version}_1"\nreplaces="niri>=0"' "$pkg/template"
if ! grep -q '^replaces="niri>=0"$' "$pkg/template" || ! grep -q '^pkgname=fili-niri$' "$pkg/template"; then
    echo "build.sh: the niri template changed shape, $pkg/template not generated" >&2
    exit 1
fi
echo "==> $pkg ($pkgver)"
if [ "$MODE" = prepare ]; then
    exit 0
fi

echo "==> xbps-src pkg fili-niri"
cd "$VP"
[ -d masterdir ] || [ -d masterdir-x86_64 ] || ./xbps-src binary-bootstrap || exit 4
./xbps-src -f pkg fili-niri || exit 4
built="$(find hostdir/binpkgs -name "$pkgver.*.xbps" | head -1)"
[ -n "$built" ] || { echo "build.sh: $pkgver.*.xbps not found in hostdir/binpkgs" >&2; exit 4; }
mkdir -p "$OUT"
cp "$built" "$OUT/"
echo "==> $OUT/$(basename "$built")"
