#!/bin/bash
# Puts a built fili-niri into a copy of the published repository and rebuilds its index, so that the workflow uploads
# the new package, then the index, then removes the old package (same order as .github/workflows/repo.yml).
#
#   distro/niri/publish.sh REPO_DIR PACKAGE.xbps
#
# REPO_DIR holds every published package (downloaded from the "repo" release): the index is rebuilt from the files
# present, like distro/build-repo.sh does. Signed when XBPS_PRIVKEY (path to the PEM key) is set.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=distro/distro.env
source "$ROOT/distro/distro.env"
repo="${1:?usage: publish.sh REPO_DIR PACKAGE.xbps}"
pkg="${2:?usage: publish.sh REPO_DIR PACKAGE.xbps}"
[ -f "$pkg" ] || { echo "publish.sh: $pkg does not exist" >&2; exit 1; }

for f in "$repo"/fili-niri-[0-9]*.xbps; do
    [ -e "$f" ] || continue
    [ "$(basename "$f")" = "$(basename "$pkg")" ] || { echo "replaced: $(basename "$f")"; rm -f "$f" "$f.sig2"; }
done
cp "$pkg" "$repo/"
rm -f "$repo"/*-repodata "$repo"/*-stagedata
xbps-rindex -a "$repo"/*.xbps >/dev/null
xbps-rindex -r "$repo" >/dev/null
xbps-rindex -c "$repo" >/dev/null
if [ -n "${XBPS_PRIVKEY:-}" ]; then
    xbps-rindex --sign --signedby "$DISTRO" --privkey "$XBPS_PRIVKEY" "$repo"
    xbps-rindex --sign-pkg --privkey "$XBPS_PRIVKEY" "$repo/$(basename "$pkg")"
fi
echo "Repository: $repo ($(find "$repo" -name '*.xbps' | wc -l) packages)"
