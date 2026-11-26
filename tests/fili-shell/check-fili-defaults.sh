#!/bin/sh
# fili-defaults CLI (list, get, candidates, set) with fake applications in an isolated data directory
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FD="$ROOT/dotfiles/home/.local/bin/fili-defaults"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
unset WAYLAND_DISPLAY DISPLAY
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

# "Edit with", applications that are not listed, programs without a desktop entry
app pix Pix "image/png;"
app other Other "text/x-other;"
check "apps lists every visible application whatever its types" '"$FD" apps | cut -f1 | grep -qx other.desktop && ! "$FD" apps | cut -f1 | grep -qx ghost.desktop'
check "set refuses an application that does not list the types unless --any" '! "$FD" set image other.desktop 2> /dev/null && "$FD" set image other.desktop --any && [ "$("$FD" get image)" = other.desktop ]'
check "--any declares the application for the types in [Added Associations]" 'grep -A3 "^\[Added Associations\]" "$MA" | grep -q "^image/png=.*other.desktop;"'
check "--any refuses an application that does not exist" '! "$FD" set image nope.desktop --any 2> /dev/null'
check "there are no editors at first" '[ -z "$("$FD" editors)" ]'
"$FD" editor-add pix.desktop
check "editor-add registers an application once, however many times it is added" '"$FD" editor-add pix.desktop && [ "$("$FD" editors | cut -f1)" = pix.desktop ] && [ "$(wc -l < "$XDG_CONFIG_HOME/filigrane/edit-with.list")" = 1 ]'
check "editor-add refuses an application that does not exist, and a name that is not a desktop id" '! "$FD" editor-add nope.desktop 2> /dev/null && ! "$FD" editor-add pix 2> /dev/null'
id="$("$FD" editor-add --command "sh -c true" "My Editor")"
check "a program without a desktop entry gets one, for images, text, video and audio, and is registered" '[ "$id" = fili-custom-my-editor.desktop ] && grep -q "^Name=My Editor" "$XDG_DATA_HOME/applications/$id" && grep -q "image/png;" "$XDG_DATA_HOME/applications/$id" && grep -q "text/plain;" "$XDG_DATA_HOME/applications/$id" && grep -q "audio/flac;" "$XDG_DATA_HOME/applications/$id" && [ "$("$FD" editors | cut -f1 | tr "\n" " ")" = "pix.desktop $id " ]'
check "the open defaults are untouched by the editors" '[ "$("$FD" get image)" = other.desktop ]'
check "editor-add --command refuses an empty command" '! "$FD" editor-add --command "" 2> /dev/null'
# edit launches the first editor that handles the kind of file
mkdir -p "$T/bin"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/launched"\n' "$T" > "$T/bin/pixedit"; chmod +x "$T/bin/pixedit"
printf '[Desktop Entry]\nType=Application\nName=Pix\nExec=%s/bin/pixedit --edit %%F\nMimeType=image/png;\n' "$T" > "$T/share/applications/pix.desktop"
printf 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==' | base64 -d > "$T/a.png"; cp "$T/a.png" "$T/b.png"
"$FD" edit "$T/a.png" "$T/b.png"
sleep 1
check "edit starts the first editor that handles the type, on all the files" '[ "$(tr "\n" " " < "$T/launched")" = "--edit $T/a.png $T/b.png " ]'
"$FD" editor-rm pix.desktop
check "editor-rm forgets an editor and keeps the others" '[ "$("$FD" editors | cut -f1)" = "$id" ]'
exit $fail
