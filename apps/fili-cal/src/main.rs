// fili-cal: the calendar and the reminders of Filigrane, one list. A reminder is an event with an alarm at its start, so there
// is a single thing to learn, to show in the bar and to ask the assistant for. No daemon: the events are iCalendar files
// (~/.local/share/filigrane/calendar/<id>.ics, readable by any calendar program) and `fili-cal tick`, run every minute by the
// fili-bar, shows the alarms that are due and rewrites the file the clock card reads.
//
// fili-cal add TITLE --at WHEN [--end WHEN | --for DURATION] [--place P] [--note N] [--alarm DURATION|none]...
//                    [--every day|week|month|year] [--interval N] [--count N] [--until WHEN]
//                                  add an event; prints its id. --reminder = alarm at the start (the default alarm of an
//                                  event is 10 minutes before; none for a whole day)
// fili-cal quick WHEN TITLE...     the same on one line, for a text field: "tomorrow 14:30 Dentist", "demain à 9h Appeler la banque",
//                                  "2026-12-24 Christmas Eve" (whole day), "+30m Take the bread out" (a reminder: alarm at the start)
// fili-cal edit ID [the options of add, and --title T]   change an event
// fili-cal rm ID [--on WHEN]        delete an event, or only one occurrence of a series
// fili-cal show ID                  one event
// fili-cal list [--from WHEN] [--to WHEN | --days N] [--tsv | --json]   occurrences (default: today and the next 30 days)
// fili-cal next [N]                 the next N occurrences (default 5)
// fili-cal tick                     alarms due since the last tick (notification), and the file of the clock card
// fili-cal import FILE.ics          add the events of an iCalendar file (the same event twice is replaced)
// fili-cal export [ID]              iCalendar text of every event, or one
// WHEN: +2h · 14:30 or 14h30 (the next one) · 2026-12-24 (whole day) · 2026-12-24 20:00 · tomorrow 09:00 · monday 18:00 (the
// next one; French names work too). DURATION: 30s 10m 2h 1d 1w 1h30m (a bare number is minutes).
// Environment: FILI_CAL_NOW=YYYY-MM-DDTHH:MM replaces the clock, FILI_CAL_NOTIFY the command that shows an alarm (default
// notify-send), both for the tests.
mod ics;
mod when;

use std::{
    collections::hash_map::DefaultHasher,
    env, fs,
    hash::{Hash, Hasher},
    path::PathBuf,
    process::{Command, ExitCode},
};

use chrono::{Duration, NaiveDateTime, Timelike};
use ics::{Event, Freq, Rule};
use serde_json::json;

fn home() -> String {
    env::var("HOME").unwrap_or_default()
}
fn dir(var: &str, fallback: &str, tail: &str) -> PathBuf {
    PathBuf::from(env::var(var).unwrap_or_else(|_| format!("{}/{fallback}", home()))).join(tail)
}
fn store() -> PathBuf {
    dir("XDG_DATA_HOME", ".local/share", "filigrane/calendar")
}
fn state() -> PathBuf {
    dir("XDG_STATE_HOME", ".local/state", "filigrane")
}

pub fn short_hash(s: &str) -> String {
    let mut h = DefaultHasher::new();
    s.hash(&mut h);
    format!("{:08x}", h.finish() as u32)
}

fn new_id() -> String {
    let nanos = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_nanos());
    short_hash(&format!("{nanos}{}", std::process::id()))
}

fn path_of(id: &str) -> Result<PathBuf, String> {
    if id.is_empty() || !id.chars().all(|c| c.is_ascii_alphanumeric()) {
        return Err(format!("not an event id: {id}"));
    }
    Ok(store().join(format!("{id}.ics")))
}

/// (id, event) of every file of the store
fn load_all() -> Vec<(String, Event)> {
    let mut out = Vec::new();
    let Ok(rd) = fs::read_dir(store()) else { return out };
    for f in rd.flatten() {
        let p = f.path();
        if p.extension().is_some_and(|e| e == "ics")
            && let (Some(id), Ok(text)) = (p.file_stem().and_then(|s| s.to_str()), fs::read_to_string(&p))
            && let Some(e) = ics::parse_ics(&text).into_iter().next()
        {
            out.push((id.to_string(), e));
        }
    }
    out.sort_by_key(|(id, e)| (e.start, id.clone()));
    out
}

fn load(id: &str) -> Result<Event, String> {
    let text = fs::read_to_string(path_of(id)?).map_err(|_| format!("no such event: {id}"))?;
    ics::parse_ics(&text).into_iter().next().ok_or_else(|| format!("unreadable event: {id}"))
}

fn save(id: &str, e: &Event) -> Result<(), String> {
    fs::create_dir_all(store()).map_err(|x| x.to_string())?;
    let p = path_of(id)?;
    let tmp = p.with_extension("ics.new");
    fs::write(&tmp, ics::to_ics(e)).map_err(|x| x.to_string())?;
    fs::rename(&tmp, &p).map_err(|x| x.to_string())
}

// ───── options ─────

#[derive(Default)]
struct Opts {
    words: Vec<String>,
    one: std::collections::HashMap<String, String>,
    alarms: Vec<String>,
    flags: Vec<String>,
}

fn parse_opts(args: &[String]) -> Result<Opts, String> {
    let mut o = Opts::default();
    let mut it = args.iter();
    while let Some(a) = it.next() {
        match a.strip_prefix("--") {
            Some(name @ ("reminder" | "tsv" | "json")) => o.flags.push(name.to_string()),
            Some("alarm") => o.alarms.push(it.next().ok_or("--alarm needs a duration")?.clone()),
            Some(name @ ("at" | "end" | "for" | "place" | "note" | "every" | "interval" | "count" | "until" | "title" | "on" | "from" | "to" | "days")) => {
                o.one.insert(name.to_string(), it.next().ok_or(format!("--{name} needs a value"))?.clone());
            }
            Some(other) => return Err(format!("unknown option: --{other}")),
            None => o.words.push(a.clone()),
        }
    }
    Ok(o)
}

/// Apply the options of add / edit to an event
fn apply(e: &mut Event, o: &Opts, now: NaiveDateTime, adding: bool) -> Result<(), String> {
    if let Some(t) = o.one.get("title") {
        e.summary.clone_from(t);
    }
    if let Some(p) = o.one.get("place") {
        e.place.clone_from(p);
    }
    if let Some(n) = o.one.get("note") {
        e.note.clone_from(n);
    }
    let old_len = e.length();
    if let Some(at) = o.one.get("at") {
        let (d, all) = when::parse_when(at, now)?;
        (e.start, e.all_day) = (d, all);
        // the length of the event is kept when only the start moves
        if !adding && e.end.is_some() && !o.one.contains_key("end") && !o.one.contains_key("for") {
            e.end = Some(d + old_len);
        }
    }
    if let Some(end) = o.one.get("end") {
        // a time alone is on the day of the start (a duration is counted from the start)
        let base = if end.starts_with('+') { e.start } else { e.start.date().and_hms_opt(0, 0, 0).unwrap_or(e.start) };
        let (d, _) = when::parse_when(end, base)?;
        e.end = Some(d);
    }
    if let Some(len) = o.one.get("for") {
        e.end = Some(e.start + Duration::seconds(when::parse_duration(len)?));
    }
    if let Some(end) = e.end
        && end < e.start
    {
        return Err("the end is before the start".into());
    }
    if o.flags.iter().any(|f| f == "reminder") {
        e.alarms = vec![0];
    }
    if !o.alarms.is_empty() {
        e.alarms = o.alarms.iter().filter(|a| a.as_str() != "none").map(|a| when::parse_duration(a)).collect::<Result<_, _>>()?;
    } else if adding && !o.flags.iter().any(|f| f == "reminder") {
        e.alarms = if e.all_day { vec![] } else { vec![600] };
    }
    if let Some(freq) = o.one.get("every") {
        e.rule = if freq == "none" {
            None
        } else {
            Some(Rule { freq: Freq::parse(freq).ok_or("--every: day, week, month, year or none")?, interval: 1, count: None, until: None })
        };
    }
    if let Some(r) = e.rule.as_mut() {
        if let Some(i) = o.one.get("interval") {
            r.interval = i.parse::<u32>().ok().filter(|n| *n > 0).ok_or("--interval needs a positive number")?;
        }
        if let Some(c) = o.one.get("count") {
            r.count = Some(c.parse().map_err(|_| "--count needs a number")?);
        }
        if let Some(u) = o.one.get("until") {
            r.until = Some(when::parse_when(u, now)?.0);
        }
    } else if ["interval", "count", "until"].iter().any(|k| o.one.contains_key(*k)) {
        return Err("--interval, --count and --until need --every".into());
    }
    Ok(())
}

// ───── output ─────

fn when_text(d: NaiveDateTime, all_day: bool) -> String {
    if all_day { d.format("%Y-%m-%d").to_string() } else { d.format("%Y-%m-%d %H:%M").to_string() }
}

struct Occ<'a> {
    id: &'a str,
    ev: &'a Event,
    start: NaiveDateTime,
}

fn window<'a>(all: &'a [(String, Event)], from: NaiveDateTime, to: NaiveDateTime) -> Vec<Occ<'a>> {
    let mut v: Vec<Occ> = all.iter().flat_map(|(id, ev)| ics::occurrences(ev, from, to).into_iter().map(move |start| Occ { id, ev, start })).collect();
    v.sort_by(|a, b| (a.start, &a.ev.summary).cmp(&(b.start, &b.ev.summary)));
    v
}

fn print_occ(v: &[Occ], mode: &str) {
    if mode == "json" {
        let rows: Vec<_> = v
            .iter()
            .map(|o| {
                let end = o.ev.end.map(|e| e + (o.start - o.ev.start));
                json!({"v": 1, "id": o.id, "title": o.ev.summary, "start": o.start.format("%Y-%m-%dT%H:%M:%S").to_string(),
                    "end": end.map(|e| e.format("%Y-%m-%dT%H:%M:%S").to_string()), "all_day": o.ev.all_day, "place": o.ev.place,
                    "note": o.ev.note, "alarms": o.ev.alarms, "every": o.ev.rule.as_ref().map(|r| r.freq.name())})
            })
            .collect();
        println!("{}", json!(rows));
        return;
    }
    for o in v {
        if mode == "tsv" {
            let end = o.ev.end.map(|e| when_text(e + (o.start - o.ev.start), o.ev.all_day)).unwrap_or_default();
            println!("{}\t{}\t{}\t{}\t{}\t{}", o.id, when_text(o.start, o.ev.all_day), end, o.ev.all_day, o.ev.summary, o.ev.place);
        } else {
            let place = if o.ev.place.is_empty() { String::new() } else { format!("  ({})", o.ev.place) };
            let every = o.ev.rule.as_ref().map_or(String::new(), |r| format!("  ↻ {}", r.freq.name().to_lowercase()));
            println!("{}  {}{}{}  [{}]", when_text(o.start, o.ev.all_day), o.ev.summary, place, every, o.id);
        }
    }
}

// ───── tick ─────

/// File of the clock card: `epoch<TAB>title<TAB>place` of the next timed events (whole days are not listed)
fn write_agenda(all: &[(String, Event)], now: NaiveDateTime) {
    let rows: String = window(all, now - Duration::hours(1), now + Duration::days(14))
        .iter()
        .filter(|o| !o.ev.all_day)
        .take(20)
        .map(|o| format!("{}\t{}\t{}\n", when::to_epoch(o.start), o.ev.summary.replace(['\t', '\n'], " "), o.ev.place.replace(['\t', '\n'], " ")))
        .collect();
    let dir = state();
    let _ = fs::create_dir_all(&dir);
    let tmp = dir.join("agenda.new");
    if fs::write(&tmp, rows).is_ok() {
        let _ = fs::rename(tmp, dir.join("agenda"));
    }
}

fn notify(title: &str, body: &str) {
    let cmd = env::var("FILI_CAL_NOTIFY").unwrap_or_else(|_| "notify-send".into());
    let mut c = Command::new(&cmd);
    if cmd == "notify-send" {
        c.args(["-a", "Agenda", "-i", "appointment-soon"]);
    }
    let _ = c.arg(title).arg(body).status();
}

fn tick() -> Result<(), String> {
    let now = when::now();
    let all = load_all();
    let fired_path = state().join("calendar-fired");
    let fired_text = fs::read_to_string(&fired_path).unwrap_or_default();
    let mut fired: Vec<String> = fired_text.lines().map(str::to_string).collect();
    let (horizon, catch_up) = (Duration::days(1), Duration::hours(12));
    let mut changed = false;
    for (id, ev) in &all {
        let longest = ev.alarms.iter().copied().max().unwrap_or(0).max(0);
        // an alarm that is due started between (now - catch_up) and now, for an occurrence that starts at most `longest` later
        let from = now - catch_up - Duration::hours(24);
        for start in ics::occurrences(ev, from, now + Duration::seconds(longest) + horizon) {
            for a in &ev.alarms {
                // the alarm of a whole day goes off at 09:00 that day
                let base = if ev.all_day { start.date().and_hms_opt(9, 0, 0).unwrap_or(start) } else { start };
                let at = base - Duration::seconds(*a);
                if at > now || at < now - catch_up {
                    continue;
                }
                let key = format!("{id} {}", when::to_epoch(at));
                if fired.contains(&key) {
                    continue;
                }
                let body = if ev.all_day {
                    start.format("%Y-%m-%d").to_string()
                } else if *a > 0 {
                    format!("{:02}:{:02}, in {} min{}", start.hour(), start.minute(), a / 60, if ev.place.is_empty() { String::new() } else { format!(" · {}", ev.place) })
                } else {
                    format!("{:02}:{:02}{}", start.hour(), start.minute(), if ev.place.is_empty() { String::new() } else { format!(" · {}", ev.place) })
                };
                notify(&ev.summary, &body);
                fired.push(key);
                changed = true;
            }
        }
    }
    // forget the old ones (their alarm is older than 3 days)
    let cutoff = when::to_epoch(now - Duration::days(3));
    let kept: Vec<String> = fired.into_iter().filter(|k| k.rsplit(' ').next().and_then(|e| e.parse::<i64>().ok()).is_some_and(|e| e >= cutoff)).collect();
    if changed || kept.len() != fired_text.lines().count() {
        let _ = fs::create_dir_all(state());
        let _ = fs::write(&fired_path, kept.join("\n") + "\n");
    }
    write_agenda(&all, now);
    Ok(())
}

// ───── commands ─────

fn run(args: &[String]) -> Result<(), String> {
    let now = when::now();
    let cmd = args.first().map_or("list", String::as_str);
    let o = parse_opts(args.get(1..).unwrap_or(&[]))?;
    match cmd {
        "add" => {
            let title = o.words.join(" ");
            if title.trim().is_empty() {
                return Err("add needs a title".into());
            }
            if !o.one.contains_key("at") {
                return Err("add needs --at WHEN".into());
            }
            let id = new_id();
            let mut e = Event { uid: format!("{id}@filigrane"), summary: title, place: String::new(), note: String::new(), start: now, end: None, all_day: false, alarms: vec![], rule: None, skip: vec![] };
            apply(&mut e, &o, now, true)?;
            save(&id, &e)?;
            println!("{id}");
            let _ = tick();
        }
        "quick" => {
            let words = &o.words;
            // the longest start of the line that is a date (a "à" or "at" between the day and the hour is ignored)
            let found = (1..=words.len().min(3)).rev().find_map(|n| {
                let head: Vec<&str> = words[..n].iter().map(String::as_str).enumerate().filter(|(i, w)| !(*i == 1 && matches!(*w, "à" | "at"))).map(|(_, w)| w).collect();
                when::parse_when(&head.join(" "), now).ok().map(|w| (n, w))
            });
            let Some((n, (start, all_day))) = found else {
                return Err("quick: the line starts with a date (14:30, tomorrow 09:00, 2026-12-24, +30m...), then the title".into());
            };
            let title = words[n..].join(" ");
            if title.trim().is_empty() {
                return Err("quick: the title is missing".into());
            }
            let id = new_id();
            let alarms = if words[0].starts_with('+') { vec![0] } else if all_day { vec![] } else { vec![600] };
            let e = Event { uid: format!("{id}@filigrane"), summary: title, place: String::new(), note: String::new(), start, end: None, all_day, alarms, rule: None, skip: vec![] };
            save(&id, &e)?;
            println!("{id}");
            let _ = tick();
        }
        "edit" => {
            let id = o.words.first().ok_or("edit needs an id")?;
            let mut e = load(id)?;
            apply(&mut e, &o, now, false)?;
            save(id, &e)?;
            let _ = tick();
        }
        "rm" => {
            let id = o.words.first().ok_or("rm needs an id")?;
            let mut e = load(id)?;
            if let Some(on) = o.one.get("on") {
                let (d, _) = when::parse_when(on, e.start)?;
                let d = if e.all_day { d.date().and_hms_opt(0, 0, 0).unwrap_or(d) } else { d };
                if e.rule.is_none() || !ics::occurrences(&e, d, d + Duration::seconds(1)).contains(&d) {
                    return Err(format!("no occurrence of {id} on {on}"));
                }
                e.skip.push(d);
                save(id, &e)?;
            } else {
                fs::remove_file(path_of(id)?).map_err(|x| x.to_string())?;
            }
            let _ = tick();
        }
        "show" => {
            let id = o.words.first().ok_or("show needs an id")?;
            let e = load(id)?;
            print!("{}", ics::to_ics(&e).replace("\r\n", "\n"));
        }
        "list" | "next" => {
            let all = load_all();
            let mode = if o.flags.iter().any(|f| f == "json") { "json" } else if o.flags.iter().any(|f| f == "tsv") { "tsv" } else { "text" };
            let today = now.date().and_hms_opt(0, 0, 0).unwrap_or(now);
            if cmd == "next" {
                let n: usize = o.words.first().map_or(Ok(5), |s| s.parse()).map_err(|_| "next takes a number")?;
                let v = window(&all, now, now + Duration::days(366 * 2));
                print_occ(&v[..v.len().min(n)], mode);
            } else {
                let from = o.one.get("from").map(|f| when::parse_when(f, now)).transpose()?.map_or(today, |p| p.0);
                let to = match (o.one.get("to"), o.one.get("days")) {
                    (Some(t), _) => when::parse_when(t, now)?.0,
                    (None, Some(d)) => from + Duration::days(d.parse().map_err(|_| "--days needs a number")?),
                    _ => from + Duration::days(31),
                };
                print_occ(&window(&all, from, to), mode);
            }
        }
        "tick" => tick()?,
        "import" => {
            let file = o.words.first().ok_or("import needs a file")?;
            let text = fs::read_to_string(file).map_err(|x| format!("{file}: {x}"))?;
            let events = ics::parse_ics(&text);
            for e in &events {
                save(&short_hash(&e.uid), e)?;
            }
            println!("{}", events.len());
            let _ = tick();
        }
        "export" => {
            let list: Vec<Event> = match o.words.first() {
                Some(id) => vec![load(id)?],
                None => load_all().into_iter().map(|(_, e)| e).collect(),
            };
            // one calendar with every event: the VEVENT blocks of each file inside a single VCALENDAR
            let mut out = String::from("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Filigrane//fili-cal//EN\r\n");
            for e in &list {
                let t = ics::to_ics(e);
                let a = t.find("BEGIN:VEVENT").unwrap_or(0);
                let b = t.rfind("END:VCALENDAR").unwrap_or(t.len());
                out.push_str(&t[a..b]);
            }
            out.push_str("END:VCALENDAR\r\n");
            print!("{out}");
        }
        "-h" | "--help" | "help" => {
            println!("fili-cal add|edit|rm|show|list|next|tick|import|export (see the header of apps/fili-cal/src/main.rs)");
        }
        other => return Err(format!("unknown command: {other} (add, quick, edit, rm, show, list, next, tick, import, export)")),
    }
    Ok(())
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();
    match run(&args) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("fili-cal: {e}");
            ExitCode::FAILURE
        }
    }
}
