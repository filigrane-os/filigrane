#!/bin/sh
# Tests de fili-file (Casier): une instance isolée, sans affichage (QT_QPA_PLATFORM=offscreen), pilotée par
# `fili-file ctl` (le canal de l'assistant) et vérifiée par `ctl state` et par le système de fichiers. Rien ne touche à
# la session: HOME, dossier d'exécution et données temporaires, pas de Wayland ni de niri, faux wl-copy/wl-paste (le
# presse-papiers réel de l'utilisateur reste intact). Textes en anglais. Code 0 si tout passe.
# Usage: tests/fili-file/run.sh [-v]   Binaire: $FILI_FILE_BIN, sinon le build de bootstrap (~/.cache/filigrane-apps).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${FILI_FILE_BIN:-${CARGO_TARGET_DIR:-$HOME/.cache/filigrane-apps}/release/fili-file}"
[ -x "$BIN" ] || { echo "not ok - fili-file introuvable ($BIN): cd apps/fili-file && CARGO_TARGET_DIR=\$HOME/.cache/filigrane-apps cargo build --release" >&2; exit 1; }
# Un binaire plus ancien que les sources testerait autre chose que le dépôt
stale="$(find "$ROOT/apps/fili-file/src" "$ROOT/apps/fili-file/qml" "$ROOT/apps/bar-stats/src/i18n.rs" -newer "$BIN" -type f 2>/dev/null | head -3)"
if [ -n "$stale" ]; then
    echo "not ok - binaire périmé, à recompiler (cd apps/fili-file && CARGO_TARGET_DIR=\$HOME/.cache/filigrane-apps cargo build --release); plus récents que $BIN:"
    printf '%s\n' "$stale" | sed 's/^/#   /'
    exit 1
fi
# Chemin court: le socket Unix du contexte est limité à 108 caractères
T="$(mktemp -d /tmp/fili-file-test.XXXXXX)"
trap 'kill $(cat "$T/pid" 2>/dev/null) 2>/dev/null; rm -rf "$T"' EXIT INT TERM
mkdir -m 700 "$T/run" "$T/bin" "$T/clip"
mkdir -p "$T/home/data"

# Faux wl-copy / wl-paste: le « presse-papiers » est un dossier (un fichier par type MIME)
cat > "$T/bin/wl-copy" <<'SH'
#!/bin/sh
d="${FAKE_CLIP:?}"; type=text/plain
while [ $# -gt 0 ]; do
    case "$1" in
        --clear) rm -f "$d"/*; exit 0 ;;
        --type) type="$2"; shift 2 ;;
        --) shift; rm -f "$d"/*; printf %s "$*" > "$d/$(echo "$type" | tr / _)"; exit 0 ;;
        *) shift ;;
    esac
done
rm -f "$d"/*; cat > "$d/$(echo "$type" | tr / _)"
SH
cat > "$T/bin/wl-paste" <<'SH'
#!/bin/sh
d="${FAKE_CLIP:?}"; type=
while [ $# -gt 0 ]; do
    case "$1" in
        --list-types) for f in "$d"/*; do [ -e "$f" ] && basename "$f" | tr _ /; done; exit 0 ;;
        --type) type="$2"; shift 2 ;;
        *) shift ;;
    esac
done
f="$d/$(echo "$type" | tr / _)"
[ -e "$f" ] && cat "$f" || exit 1
SH
chmod +x "$T/bin/wl-copy" "$T/bin/wl-paste"

env -i PATH="$T/bin:$PATH" HOME="$T/home" XDG_RUNTIME_DIR="$T/run" FAKE_CLIP="$T/clip" QT_QPA_PLATFORM=offscreen \
    FILI_LANG=en LANG=C.UTF-8 FILI_TEST_ROOT="$T" FILI_FILE_BIN="$BIN" FILI_VERBOSE="$([ "${1:-}" = -v ] && echo 1)" \
    timeout 240 python3 -I "$ROOT/tests/fili-file/scenarios.py"
