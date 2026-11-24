#!/bin/sh
# fili-defaults CLI (list, get, candidates, set) with fake applications in an isolated data directory
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FD="$ROOT/dotfiles/home/.local/bin/fili-defaults"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_DATA_HOME="$T/home/.local/share" XDG_DATA_DIRS="$T/share"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$T/share/applications"
app() { printf '[Desktop Entry]\nType=Application\nName=%s\nExec=%s\nMimeType=%s\n%s\n' "$2" "$1" "$3" "${4:-}" > "$T/share/applications/$1.desktop"; }
app casier Casier "inode/directory;"
app fm Zeta "inode/directory;"
app ghost Ghost "inode/directory;" "NoDisplay=true"
app facteur Facteur "x-scheme-handler/mailto;"
fail=0
check() { if eval "$2"; then echo "ok - fili-defaults: $1"; else echo "not ok - fili-defaults: $1"; fail=1; fi; }

check "candidates lists the applications of the category, sorted by name, without hidden ones" \
    '[ "$("$FD" candidates files | cut -f2 | tr "\n" " ")" = "Casier Zeta " ]'
check "candidates ignores applications of another category" '! "$FD" candidates files | grep -q Facteur'
check "set writes every type of the category" '"$FD" set files fm.desktop && [ "$("$FD" get files)" = fm.desktop ]'
check "set can change it again" '"$FD" set files casier.desktop && [ "$("$FD" get files)" = casier.desktop ]'
check "set refuses an application that cannot take the category" '! "$FD" set files facteur.desktop 2> /dev/null && [ "$("$FD" get files)" = casier.desktop ]'
check "set refuses an unknown category" '! "$FD" set nope fm.desktop 2> /dev/null'
check "set refuses an id that is not a desktop id" '! "$FD" set files fm 2> /dev/null'
check "list shows every category with its current application" \
    '"$FD" list | grep -q "^files	.*	casier.desktop$" && [ "$("$FD" list | wc -l)" = 8 ]'
MA="$XDG_CONFIG_HOME/mimeapps.list"
check "set writes a single line per type, in [Default Applications]" '[ "$(grep -c "^inode/directory=" "$MA")" = 1 ] && [ "$(grep -c "^\[Default Applications\]" "$MA")" = 1 ]'
printf '[Added Associations]\ninode/directory=fm.desktop;\n\n[Default Applications]\nx-scheme-handler/mailto=other.desktop;\ninode/directory=fm.desktop;\n\n[Removed Associations]\nfoo/bar=a.desktop;\n' > "$MA"
"$FD" set files casier.desktop
check "set replaces the line of the right section and keeps the other sections" \
    '[ "$("$FD" get files)" = casier.desktop ] && grep -q "^\[Added Associations\]" "$MA" && grep -q "^foo/bar=a.desktop;" "$MA" && grep -q "^x-scheme-handler/mailto=other.desktop;" "$MA" && [ "$(grep -c "^inode/directory=casier.desktop" "$MA")" = 1 ]'
printf '[Default Applications]\nfoo/bar=a.desktop;\n' > "$MA"
"$FD" set files fm.desktop
check "set adds the line at the end of a [Default Applications] that is the last section" '[ "$("$FD" get files)" = fm.desktop ] && grep -q "^foo/bar=a.desktop;" "$MA"'
exit $fail
