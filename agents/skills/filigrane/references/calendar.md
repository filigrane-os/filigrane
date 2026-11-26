# Calendar and reminders (`fili-cal`)

One list: a reminder is an event with an alarm at its start. Events are iCalendar files in `~/.local/share/filigrane/calendar/<id>.ics`. No daemon: the fili-bar runs `fili-cal tick` every minute (alarms as notifications, and the file `~/.local/state/filigrane/agenda` read by the clock card).

- Add: `fili-cal add TITLE --at WHEN [--for 1h | --end WHEN] [--place P] [--alarm 10m|none] [--every day|week|month|year [--interval N --count N --until WHEN]]`; reminder: `--reminder` or `fili-cal quick +30m Take the bread out`.
- WHEN: `+2h`, `14:30`, `2026-12-24` (whole day), `2026-12-24 20:00`, `tomorrow 09:00`, `monday 18:00`. Convert natural language to one of these yourself.
- Read: `fili-cal list [--from W --to W | --days N] [--json|--tsv]`, `fili-cal next [N]`, `fili-cal show ID`.
- Change: `fili-cal edit ID ...`, `fili-cal rm ID [--on WHEN]` (one occurrence of a series), `fili-cal import FILE.ics`, `fili-cal export`.
- Source: its own repository `filigrane-os/fili-cal` (Agenda, the window and this command line), pinned in `apps/fili-cal/upstream`; tests: `make test` there, `tests/fili-shell/check-fili-cal.sh` here.
