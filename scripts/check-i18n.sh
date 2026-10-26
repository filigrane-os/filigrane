#!/bin/bash
# Checks the translation catalogs (lib/i18n/*.sh) against the messages in the scripts.
#
#   scripts/check-i18n.sh
#
# For every script that sources lib/i18n.sh, takes each English message passed to t, log, warn, die, say
# or note, and checks that each catalog has an entry for it with the same number of placeholders (%s).
# Also reports catalog entries no script uses any more. Exit code 1 on any problem.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

mapfile -t scripts < <(grep -rlE '(^|[[:space:]])\. "\$FILI_LIB/i18n\.sh"' --exclude-dir=.git --exclude-dir=target --exclude='*.md' . | sort)
[ ${#scripts[@]} -gt 0 ] || { echo "no script sources lib/i18n.sh"; exit 1; }

# English messages: the first single-quoted argument of the message functions
mapfile -t messages < <(grep -ohP "(?<![\\w./-])(t|log|warn|die|say|note) '\\K[^']*(?=')" "${scripts[@]}" | sort -u)
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
[ "$rc" -eq 0 ] && echo "catalogs OK"
exit "$rc"
