#!/bin/sh
# fili-cal CLI (add, edit, rm, list, next, tick, import, export) in an isolated home, with a fake clock and a fake notifier
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# Agenda lives in its own repository: the pinned version (apps/fili-cal/upstream), or FILI_SRC_FILI_CAL for a local clone
SRC="$("$ROOT/scripts/upstream-dir" fili-cal)" || { echo "not ok - fili-cal: source not available"; exit 1; }
(cd "$SRC" && QMAKE="${QMAKE:-/usr/lib/qt6/bin/qmake6}" cargo build -q --release --locked 2>&1) || { echo "not ok - fili-cal: cargo build"; exit 1; }
FC="${CARGO_TARGET_DIR:-$SRC/target}/release/fili-cal"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home" XDG_DATA_HOME="$T/home/.local/share" XDG_STATE_HOME="$T/home/.local/state"
mkdir -p "$HOME"
cat > "$T/notify" <<'N'
#!/bin/sh
printf '%s | %s\n' "$1" "$2" >> "$(dirname "$0")/shown"
N
chmod +x "$T/notify"
export FILI_CAL_NOTIFY="$T/notify" FILI_CAL_NOW="2026-11-25T10:00"
SHOWN="$T/shown"
fail=0
check() { if eval "$2"; then echo "ok - fili-cal: $1"; else echo "not ok - fili-cal: $1"; fail=1; fi; }

d="$("$FC" add "Dentist" --at "2026-11-25 14:00" --for 1h --place "Rue 1")"
# Events live in one folder per calendar (personal is the default one)
check "add prints an id and writes an .ics file" '[ -f "$XDG_DATA_HOME/filigrane/calendar/personal/$d.ics" ] && grep -q "^SUMMARY:Dentist" "$XDG_DATA_HOME/filigrane/calendar/personal/$d.ics"'
check "an event has a 10 minute alarm by default" 'grep -q "^TRIGGER:-PT10M" "$XDG_DATA_HOME/filigrane/calendar/personal/$d.ics"'
r="$("$FC" add "Call the bank" --at +30m --reminder)"
check "a reminder is an event with an alarm at its start" 'grep -q "^TRIGGER:PT0S" "$XDG_DATA_HOME/filigrane/calendar/personal/$r.ics" && ! grep -q "^DTEND" "$XDG_DATA_HOME/filigrane/calendar/personal/$r.ics"'
b="$("$FC" add "Birthday" --at 2026-12-24 --every year)"
check "a whole day has no alarm by default" '! grep -q "VALARM" "$XDG_DATA_HOME/filigrane/calendar/personal/$b.ics" && grep -q "^DTSTART;VALUE=DATE:20261224" "$XDG_DATA_HOME/filigrane/calendar/personal/$b.ics"'
check "add without --at fails" '! "$FC" add "Nothing" 2> /dev/null'
check "add refuses an end before the start" '! "$FC" add "Bad" --at 14:00 --end 13:00 2> /dev/null'
check "an option that needs --every fails without it" '! "$FC" add "Bad" --at 14:00 --count 3 2> /dev/null'

check "list shows the events of the window in order" '[ "$("$FC" list --tsv | cut -f5 | tr "\n" ",")" = "Call the bank,Dentist,Birthday," ]'
check "list --json is valid JSON with the id and the start" '"$FC" list --json | python3 -c "import json,sys; v=json.load(sys.stdin); assert v[1][\"title\"]==\"Dentist\" and v[1][\"start\"]==\"2026-11-25T14:00:00\" and v[1][\"id\"]==\"$d\""'
check "next 1 is the first coming event" '[ "$("$FC" next 1 --tsv | cut -f5)" = "Call the bank" ]'

# alarms
"$FC" tick
check "nothing is due at 10:00" '[ ! -f "$SHOWN" ]'
check "tick writes the file of the clock card (epoch, title, place)" '[ "$(cut -f2 "$XDG_STATE_HOME/filigrane/agenda" | tr "\n" ",")" = "Call the bank,Dentist," ] && [ "$(cut -f3 "$XDG_STATE_HOME/filigrane/agenda" | grep -v "^$")" = "Rue 1" ]'
FILI_CAL_NOW="2026-11-25T13:50" "$FC" tick
check "the 10 minute alarm goes off at 13:50 with the time and the place" 'grep -q "^Dentist | 14:00, in 10 min · Rue 1$" "$SHOWN"'
check "the reminder went off at its time (10:30 seen from 13:50)" 'grep -q "^Call the bank | 10:30$" "$SHOWN"'
FILI_CAL_NOW="2026-11-25T13:55" "$FC" tick
check "an alarm goes off only once" '[ "$(grep -c "^Dentist" "$SHOWN")" = 1 ]'
FILI_CAL_NOW="2026-11-26T09:00" "$FC" tick
check "an alarm older than 12 hours is not shown late" '[ "$(wc -l < "$SHOWN")" = 2 ]'
FILI_CAL_NOW="2026-12-24T09:30" "$FC" add "Late" --at 2026-12-24T09:45 --alarm 15m > /dev/null
FILI_CAL_NOW="2026-12-24T09:30" "$FC" tick
check "a whole-day alarm needs an explicit --alarm: the birthday has none, the later event does" '! grep -q "^Birthday" "$SHOWN" && grep -q "^Late | 09:45, in 15 min$" "$SHOWN"'

# quick (one line, for the text field of the calendar)
q1="$("$FC" quick demain à 9h Appeler la banque)"
check "quick: a day and an hour then the title, with the default alarm" '"$FC" list --from 2026-11-26 --to 2026-11-27 --tsv | grep -q "^$q1	2026-11-26 09:00		false	Appeler la banque"; grep -q "^TRIGGER:-PT10M" "$XDG_DATA_HOME/filigrane/calendar/personal/$q1.ics"'
q2="$("$FC" quick +45m Take the bread out)"
check "quick: a relative time is a reminder (alarm at the start)" 'grep -q "^TRIGGER:PT0S" "$XDG_DATA_HOME/filigrane/calendar/personal/$q2.ics" && ! grep -q "^TRIGGER:-" "$XDG_DATA_HOME/filigrane/calendar/personal/$q2.ics"'
q3="$("$FC" quick 2026-12-25 Christmas lunch)"
check "quick: a date alone is a whole day" 'grep -q "^DTSTART;VALUE=DATE:20261225" "$XDG_DATA_HOME/filigrane/calendar/personal/$q3.ics" && grep -q "^SUMMARY:Christmas lunch" "$XDG_DATA_HOME/filigrane/calendar/personal/$q3.ics"'
check "quick fails without a date, and without a title" '! "$FC" quick Dentist 2> /dev/null && ! "$FC" quick 14:00 2> /dev/null'

# series
w="$("$FC" add "Standup" --at "monday 09:00" --every week --count 3)"
check "a weekly series lists its occurrences" '[ "$("$FC" list --from 2026-11-01 --to 2027-01-01 --tsv | grep -c "Standup")" = 3 ]'
"$FC" rm "$w" --on "2026-12-07 09:00"
check "rm --on removes one occurrence only" '[ "$("$FC" list --from 2026-11-01 --to 2027-01-01 --tsv | grep "Standup" | cut -f2 | tr "\n" ",")" = "2026-11-30 09:00,2026-12-14 09:00," ]'
check "rm --on an day without occurrence fails" '! "$FC" rm "$w" --on "2026-12-08 09:00" 2> /dev/null'

# edit, rm, import, export
"$FC" edit "$d" --at "2026-11-25 15:00" --title "Dentist (moved)"
check "edit moves the start and keeps the length" '"$FC" list --tsv | grep "Dentist (moved)" | grep -q "2026-11-25 15:00	2026-11-25 16:00"'
"$FC" rm "$d"
check "rm deletes the file" '[ ! -f "$XDG_DATA_HOME/filigrane/calendar/personal/$d.ics" ]'
check "rm refuses an id that is not an id" '! "$FC" rm "../x" 2> /dev/null'
printf 'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:ext-1\r\nDTSTART:20270105T080000\r\nSUMMARY:Imported\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n' > "$T/in.ics"
"$FC" import "$T/in.ics" > /dev/null
"$FC" import "$T/in.ics" > /dev/null
check "import adds the events once, even when imported twice" '[ "$("$FC" list --from 2027-01-01 --to 2027-02-01 --tsv | grep -c Imported)" = 1 ]'
check "export gives a single calendar with every event" '[ "$("$FC" export | grep -c "^BEGIN:VCALENDAR")" = 1 ] && "$FC" export | grep -q "^SUMMARY:Imported"'
exit $fail
