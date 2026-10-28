#!/bin/bash
# Checks the translation catalogs against the English messages in the code. Exit code 1 on any problem.
#
#   scripts/check-i18n.sh
#
# Scripts (lib/i18n/*.sh): for every shell script that sources lib/i18n.sh, each English message passed to t, log,
# warn, die, say, note or item, and every quoted argument of choose (menu); for every Python script with a t() helper (display-save), each t('...'). Each catalog needs
# an entry with the same number of placeholders (%s). The niri shortcut titles (hotkey-overlay-title of
# dotfiles/config/niri/config.kdl) too: fili-hotkeys and the menu translate them.
# fili-shell (dotfiles/config/quickshell/i18n/*.json): each FiliI18n.tr("...") of the QML files and each tr("...") or
# trf("...") of bar-stats (apps/bar-stats/src, tests excluded). Each catalog needs an entry with the same %1, %2...
# Both kinds also report catalog entries nothing uses any more.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

mapfile -t scripts < <(grep -rlE '(^|[[:space:]])\. "\$FILI_LIB/i18n\.sh"' --exclude-dir=.git --exclude-dir=target --exclude='*.md' . | sort)
[ ${#scripts[@]} -gt 0 ] || { echo "no script sources lib/i18n.sh"; exit 1; }

# English messages: the first single-quoted argument of the message functions
mapfile -t python < <(grep -rlE '^def t\(fmt' --exclude-dir=.git --exclude-dir=target dotfiles users 2>/dev/null | sort)
mapfile -t messages < <({ grep -ohP "(?<![\\w./-])(t|log|warn|die|say|note|item) '\\K[^']*(?=')" "${scripts[@]}"
    grep -hP "(?<![\\w./-])choose [\"']" "${scripts[@]}" | sed 's/.*choose //' | grep -oP "'[^']*'" | sed "s/^'//; s/'\$//"
    grep -ohP 'hotkey-overlay-title="\K[^"]*(?=")' dotfiles/config/niri/config.kdl
    [ ${#python[@]} -eq 0 ] || grep -ohP "(?<![\\w.])t\\('\\K[^']*(?=')" "${python[@]}"; } | sort -u)
scripts+=("${python[@]}")
echo "${#scripts[@]} scripts, ${#messages[@]} messages"

count() { local s="${1//%%/}"; s="${s//[^%]/}"; echo "${#s}"; }

rc=0
for catalog in lib/i18n/*.sh; do
    lang="$(basename "$catalog" .sh)"
    unset -f _t_lookup
    # shellcheck source=/dev/null
    . "$catalog"
    for m in "${messages[@]}"; do
        _t_fmt=""
        _t_lookup "$m"
        if [ -z "$_t_fmt" ]; then echo "$lang: missing: $m"; rc=1; continue; fi
        if [ "$(count "$m")" != "$(count "$_t_fmt")" ]; then echo "$lang: placeholders differ: $m"; rc=1; fi
    done
    while IFS= read -r key; do
        printf '%s\n' "${messages[@]}" | grep -qxF -- "$key" || { echo "$lang: unused entry: $key"; rc=1; }
    done < <(sed -n "s/^    '\\(.*\\)') _t_fmt=.*/\\1/p" "$catalog")
done
# fili-shell: catalogues JSON partagés par le QML et bar-stats
python3 - <<'PY' || rc=1
import glob, json, re, sys
keys = set()
for f in glob.glob("dotfiles/config/quickshell/*.qml"):
    keys |= {json.loads('"' + k + '"') for k in re.findall(r'FiliI18n\.tr\("((?:[^"\\]|\\.)*)"', open(f).read())}
for f in glob.glob("apps/bar-stats/src/*.rs"):
    src = open(f).read().split("#[cfg(test)]")[0]
    keys |= {json.loads('"' + k + '"') for k in re.findall(r'\btrf?\("((?:[^"\\]|\\.)*)"', src)}
print(f"fili-shell: {len(keys)} messages")
ph = lambda s: sorted(re.findall(r"%[1-9]", s))
bad = False
for cat in sorted(glob.glob("dotfiles/config/quickshell/i18n/*.json")):
    lang = cat.rsplit("/", 1)[1][:-5]
    c = json.load(open(cat))
    for k in sorted(keys):
        if k not in c:
            print(f"{lang}.json: missing: {k}"); bad = True
        elif ph(k) != ph(c[k]):
            print(f"{lang}.json: placeholders differ: {k}"); bad = True
    for k in sorted(k for k in set(c) - keys if not k.startswith("@")):
        print(f"{lang}.json: unused entry: {k}"); bad = True
sys.exit(1 if bad else 0)
PY
[ "$rc" -eq 0 ] && echo "catalogs OK"
exit "$rc"
