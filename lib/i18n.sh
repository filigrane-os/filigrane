# shellcheck shell=sh
# Translations for Filigrane scripts. Messages are written in English in the code; another language is
# a catalog, lib/i18n/<lang>.sh, that translates by the exact English text. No catalog, or no entry
# for a message, means English.
#
#   t 'Installing %s' "$name"      printf-style, prints without a newline
#
# Language: FILI_LANG, else the first of LC_ALL, LC_MESSAGES, LANG that is set ("fr_FR.UTF-8" -> fr).
# The caller sets FILI_LIB to the lib/ directory before sourcing this file. POSIX sh only: it is sourced
# by sh and bash scripts alike. To add a language, copy lib/i18n/fr.sh and translate the right-hand sides.

if [ -z "${FILI_LANG:-}" ]; then
    FILI_LANG=${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}
    FILI_LANG=${FILI_LANG%%[_.@]*}
fi
# Letters only: the code ends up in a file name
case $FILI_LANG in '' | *[!a-z]*) FILI_LANG=en ;; esac

if [ "$FILI_LANG" != en ] && [ -r "$FILI_LIB/i18n/$FILI_LANG.sh" ]; then
    # shellcheck source=/dev/null
    . "$FILI_LIB/i18n/$FILI_LANG.sh"
else
    _t_lookup() { :; }
fi

t() {
    _t_fmt=$1
    shift
    _t_lookup "$_t_fmt"
    # shellcheck disable=SC2059
    printf -- "$_t_fmt" "$@"
}
