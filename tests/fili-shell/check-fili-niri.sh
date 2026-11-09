#!/bin/sh
# fili-niri (distro/niri/): package version from Void's niri template and the pin, alerts usage, the package kept by
# the full build of repo.yml, workflow wiring. Building needs xbps-src and the network: not done here.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
check() { if eval "$2"; then echo "ok - fili-niri: $1"; else echo "not ok - fili-niri: $1"; fail=1; fi; }

printf 'pkgname=niri\nversion=26.04\nrevision=2\n' > "$T/template"
v="$(FILI_VOID_PACKAGES="$T/none" FILI_NIRI_TEMPLATE="$T/template" bash "$ROOT/distro/niri/build.sh" --version)"
p="$(sed -n 's/^patchrev=//p' "$ROOT/distro/niri/upstream")"
check "version = Void's niri version, revision = Void's revision * 100 + patchrev" '[ "$v" = "fili-niri-26.04_$((200 + p))" ]'
check "the pin has url, a full commit, patchrev and the niri issue" \
    'grep -q "^url=https://github.com/filigrane-os/niri.git$" "$ROOT/distro/niri/upstream" && grep -Eq "^ref=[0-9a-f]{40}$" "$ROOT/distro/niri/upstream" && grep -Eq "^patchrev=[0-9]+$" "$ROOT/distro/niri/upstream" && grep -q "^issue=niri-wm/niri#[0-9]*$" "$ROOT/distro/niri/upstream"'
bash "$ROOT/distro/niri/build.sh" --bogus 2>/dev/null; rc=$?
check "build.sh: unknown option rejected" '[ "$rc" -ne 0 ]'
GITHUB_REPOSITORY=o/r bash "$ROOT/distro/niri/alert.sh" bogus 2>/dev/null; rc=$?
check "alert.sh: unknown command rejected" '[ "$rc" -ne 0 ]'
check "repo.yml keeps fili-niri (DISTRO_EXTERNAL_PACKAGES)" \
    '. "$ROOT/distro/distro.env" && case " $DISTRO_EXTERNAL_PACKAGES " in *" fili-niri "*) true ;; *) false ;; esac && grep -q DISTRO_EXTERNAL_PACKAGES "$ROOT/distro/build-repo.sh"'
check "the workflow builds, publishes and alerts" \
    'for s in "build.sh --version" "build.sh --out" "publish.sh" "alert.sh failed" "alert.sh ok" "alert.sh upstream" "group: repo"; do grep -qF "$s" "$ROOT/.github/workflows/niri.yml" || exit 1; done'
exit "$fail"
