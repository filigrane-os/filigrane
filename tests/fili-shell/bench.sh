#!/bin/sh
# Cost of the running fili-shell (Quickshell and its child processes), to compare before / after an optimisation:
# memory (PSS, sharing of libraries split), CPU time during the measuring window (Quickshell, resident
# children and finished children: module commands, cards...) and processes created on the whole machine.
# Usage: tests/fili-shell/bench.sh [seconds]   (default 60; at rest, or while hovering / opening what you want to measure)
set -u
secs="${1:-60}"
q="$(pgrep -xo quickshell)" || { echo "quickshell ne tourne pas" >&2; exit 1; }
hz="$(getconf CLK_TCK)"

pss() { awk '/^Pss:/ { print $2 }' "/proc/$1/smaps_rollup" 2>/dev/null; }
# utime+stime (and cutime+cstime with "all") in ticks; the name can contain spaces: cut after the last ")"
ticks() { sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | awk -v all="${2:-}" '{ print $12 + $13 + (all ? $14 + $15 : 0) }'; }
kids() { pgrep -P "$q"; }
sum_kids() { t=0; for p in $(kids); do t=$((t + $(ticks "$p" || echo 0))); done; echo "$t"; }
forks() { awk '/^processes/ { print $2 }' /proc/stat; }

echo "# mémoire (PSS, kio)"
total=0
for p in "$q" $(kids); do
    v="$(pss "$p")"; [ -n "$v" ] || continue
    total=$((total + v))
    printf '%-8s %-14s %8s  %s\n' "$p" "$(cat "/proc/$p/comm")" "$v" "$(tr '\0' ' ' < "/proc/$p/cmdline" | cut -c1-60)"
done
printf '%-23s %8s\n' "total" "$total"

q0="$(ticks "$q" all)"; k0="$(sum_kids)"; f0="$(forks)"
sleep "$secs"
q1="$(ticks "$q" all)"; k1="$(sum_kids)"; f1="$(forks)"
ms() { echo $(($1 * 1000 / hz)); }
echo "# CPU sur $secs s (ms)"
echo "quickshell + enfants terminés  $(ms $((q1 - q0)))"
echo "enfants résidents              $(ms $((k1 - k0)))   (approché: enfants présents au début et à la fin)"
echo "processus créés (machine)      $((f1 - f0))"
