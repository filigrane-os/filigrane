#!/bin/sh
# Filigrane: elogind suspends without going through zzz (suspend key, loginctl): it calls this
# hook with pre|post, and we run the matching /etc/zzz.d hooks.
case "$1" in
    pre) d=/etc/zzz.d/suspend ;;
    post) d=/etc/zzz.d/resume ;;
    *) exit 0 ;;
esac
for h in "$d"/*; do [ -x "$h" ] && "$h"; done
exit 0
