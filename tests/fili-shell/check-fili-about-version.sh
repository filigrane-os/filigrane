#!/bin/sh
# The Filigrane version of the About card comes from the tags of the distribution (vX.Y.Z) only: the repository also carries
# the tags of the applications it pins (cassette-v0.1.0...), which must never be shown as the version of the distribution.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/dotfiles/home/.local/bin"
cp "$ROOT/dotfiles/home/.local/bin/fili-about" "$T/dotfiles/home/.local/bin/"
cd "$T" || exit 1
git init -q . && git -c user.name=t -c user.email=t@t add -A && git -c user.name=t -c user.email=t@t commit -q -m one
git tag cassette-v0.1.0
echo x > f && git add f && git -c user.name=t -c user.email=t@t commit -q -m two
fail=0
check() { if eval "$2"; then echo "ok - fili-about: $1"; else echo "not ok - fili-about: $1"; fail=1; fi; }
ver() { sh "$T/dotfiles/home/.local/bin/fili-about" 2> /dev/null | jq -r '.sections[0].rows[] | select(.[0] == "Version" or .[0] == "Version") | .[1]' | head -1; }
check "a tag of an application is not the version of the distribution" '! ver | grep -q cassette'
git tag v1.2.0
check "a tag of the distribution is" 'ver | grep -q "^v1.2.0"'
exit $fail
