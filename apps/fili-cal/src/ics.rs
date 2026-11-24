//! The events: model, iCalendar (RFC 5545) reading and writing, and recurrence. Times are local ("floating"), so that a
//! recurring event stays at the same hour across daylight saving time. A reminder is an event with an alarm at its start.
use chrono::{Datelike, Duration, NaiveDate, NaiveDateTime, NaiveTime, TimeZone, Utc};

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Freq {
    Daily,
    Weekly,
    Monthly,
    Yearly,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Rule {
    pub freq: Freq,
    pub interval: u32,
    pub count: Option<u32>,
    pub until: Option<NaiveDateTime>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Event {
    pub uid: String,
    pub summary: String,
    pub place: String,
    pub note: String,
    pub start: NaiveDateTime,
    pub end: Option<NaiveDateTime>,
    pub all_day: bool,
    /// Seconds before the start (0 = at the start, negative = after it)
    pub alarms: Vec<i64>,
    pub rule: Option<Rule>,
    /// Occurrences that were deleted one by one (the start of the occurrence)
    pub skip: Vec<NaiveDateTime>,
}

impl Freq {
    pub fn name(self) -> &'static str {
        match self {
            Freq::Daily => "DAILY",
            Freq::Weekly => "WEEKLY",
            Freq::Monthly => "MONTHLY",
            Freq::Yearly => "YEARLY",
        }
    }
    pub fn parse(s: &str) -> Option<Freq> {
        Some(match s.to_lowercase().as_str() {
            "daily" | "day" | "d" => Freq::Daily,
            "weekly" | "week" | "w" => Freq::Weekly,
            "monthly" | "month" | "m" => Freq::Monthly,
            "yearly" | "year" | "y" => Freq::Yearly,
            _ => return None,
        })
    }
}

impl Event {
    /// Length of one occurrence
    pub fn length(&self) -> Duration {
        self.end.map_or(Duration::zero(), |e| e - self.start)
    }
}

// ───── text ─────

fn escape(s: &str) -> String {
    s.replace('\\', "\\\\").replace(';', "\\;").replace(',', "\\,").replace('\n', "\\n")
}
fn unescape(s: &str) -> String {
    let mut out = String::new();
    let mut it = s.chars();
    while let Some(c) = it.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        match it.next() {
            Some('n' | 'N') => out.push('\n'),
            Some(o) => out.push(o),
            None => {}
        }
    }
    out
}

/// Lines folded at 75 octets, continuation lines start with a space
fn fold(line: &str) -> String {
    let mut out = String::new();
    let mut len = 0;
    for c in line.chars() {
        let n = c.len_utf8();
        if len + n > 74 {
            out.push_str("\r\n ");
            len = 1;
        }
        out.push(c);
        len += n;
    }
    out
}

fn fmt_dt(d: NaiveDateTime) -> String {
    d.format("%Y%m%dT%H%M%S").to_string()
}
fn fmt_trigger(secs: i64) -> String {
    let (sign, n) = if secs > 0 { ("-", secs) } else { ("", -secs) };
    if n == 0 {
        return "PT0S".into();
    }
    let (d, h, m, s) = (n / 86400, n % 86400 / 3600, n % 3600 / 60, n % 60);
    let mut t = String::new();
    if h > 0 {
        t += &format!("{h}H");
    }
    if m > 0 {
        t += &format!("{m}M");
    }
    if s > 0 {
        t += &format!("{s}S");
    }
    format!("{sign}P{}{}", if d > 0 { format!("{d}D") } else { String::new() }, if t.is_empty() { String::new() } else { format!("T{t}") })
}

pub fn to_ics(e: &Event) -> String {
    let mut l: Vec<String> = vec!["BEGIN:VCALENDAR".into(), "VERSION:2.0".into(), "PRODID:-//Filigrane//fili-cal//EN".into(), "BEGIN:VEVENT".into()];
    l.push(format!("UID:{}", e.uid));
    l.push(format!("DTSTAMP:{}Z", Utc::now().format("%Y%m%dT%H%M%S")));
    if e.all_day {
        l.push(format!("DTSTART;VALUE=DATE:{}", e.start.format("%Y%m%d")));
        if let Some(end) = e.end {
            l.push(format!("DTEND;VALUE=DATE:{}", end.format("%Y%m%d")));
        }
    } else {
        l.push(format!("DTSTART:{}", fmt_dt(e.start)));
        if let Some(end) = e.end {
            l.push(format!("DTEND:{}", fmt_dt(end)));
        }
    }
    l.push(format!("SUMMARY:{}", escape(&e.summary)));
    if !e.place.is_empty() {
        l.push(format!("LOCATION:{}", escape(&e.place)));
    }
    if !e.note.is_empty() {
        l.push(format!("DESCRIPTION:{}", escape(&e.note)));
    }
    if let Some(r) = &e.rule {
        let mut s = format!("RRULE:FREQ={};INTERVAL={}", r.freq.name(), r.interval);
        if let Some(c) = r.count {
            s += &format!(";COUNT={c}");
        }
        if let Some(u) = r.until {
            s += &format!(";UNTIL={}", fmt_dt(u));
        }
        l.push(s);
    }
    for x in &e.skip {
        l.push(if e.all_day { format!("EXDATE;VALUE=DATE:{}", x.format("%Y%m%d")) } else { format!("EXDATE:{}", fmt_dt(*x)) });
    }
    for a in &e.alarms {
        l.push("BEGIN:VALARM".into());
        l.push("ACTION:DISPLAY".into());
        l.push(format!("DESCRIPTION:{}", escape(&e.summary)));
        l.push(format!("TRIGGER:{}", fmt_trigger(*a)));
        l.push("END:VALARM".into());
    }
    l.push("END:VEVENT".into());
    l.push("END:VCALENDAR".into());
    l.iter().map(|x| fold(x) + "\r\n").collect()
}

// ───── reading ─────

/// A date or a date-time of a property: (time, whole day). A UTC time is converted to local time.
fn parse_dt(v: &str) -> Option<(NaiveDateTime, bool)> {
    let v = v.trim();
    if v.len() == 8 {
        return Some((NaiveDate::parse_from_str(v, "%Y%m%d").ok()?.and_time(NaiveTime::MIN), true));
    }
    let utc = v.ends_with('Z');
    let dt = NaiveDateTime::parse_from_str(v.trim_end_matches('Z'), "%Y%m%dT%H%M%S").ok()?;
    if utc {
        return Some((crate::when::from_epoch(Utc.from_utc_datetime(&dt).timestamp()), false));
    }
    Some((dt, false))
}

/// "-PT10M", "PT0S", "-P1D", "-P1W", "-PT1H30M" → seconds before the start
fn parse_trigger(v: &str) -> Option<i64> {
    let v = v.trim();
    let (neg, v) = match v.strip_prefix('-') {
        Some(r) => (true, r),
        None => (false, v.strip_prefix('+').unwrap_or(v)),
    };
    let v = v.strip_prefix('P')?;
    let (mut total, mut num) = (0i64, String::new());
    for c in v.chars() {
        if c.is_ascii_digit() {
            num.push(c);
            continue;
        }
        if c == 'T' {
            continue;
        }
        let n: i64 = num.parse().ok()?;
        num.clear();
        total += n * match c {
            'W' => 604800,
            'D' => 86400,
            'H' => 3600,
            'M' => 60,
            'S' => 1,
            _ => return None,
        };
    }
    Some(if neg { total } else { -total })
}

fn parse_rule(v: &str) -> Option<Rule> {
    let (mut freq, mut interval, mut count, mut until) = (None, 1, None, None);
    for part in v.split(';') {
        let (k, val) = part.split_once('=')?;
        match k {
            "FREQ" => freq = Some(Freq::parse(val)?),
            "INTERVAL" => interval = val.parse().ok()?,
            "COUNT" => count = Some(val.parse().ok()?),
            "UNTIL" => until = Some(parse_dt(val)?.0),
            _ => {}
        }
    }
    Some(Rule { freq: freq?, interval: u32::max(interval, 1), count, until })
}

fn unfold(text: &str) -> Vec<String> {
    let mut lines: Vec<String> = Vec::new();
    for raw in text.lines() {
        if (raw.starts_with(' ') || raw.starts_with('\t')) && !lines.is_empty() {
            lines.last_mut().unwrap().push_str(&raw[1..]);
        } else {
            lines.push(raw.to_string());
        }
    }
    lines
}

/// Every VEVENT of an iCalendar text (a VEVENT that has no start is left out)
pub fn parse_ics(text: &str) -> Vec<Event> {
    let mut out = Vec::new();
    let mut cur: Option<Event> = None;
    let mut in_alarm = false;
    for line in unfold(text) {
        let (name, value) = match line.split_once(':') {
            Some(p) => p,
            None => continue,
        };
        let prop = name.split(';').next().unwrap_or("").to_uppercase();
        match (prop.as_str(), cur.as_mut()) {
            ("BEGIN", _) if value == "VEVENT" => {
                cur = Some(Event { uid: String::new(), summary: String::new(), place: String::new(), note: String::new(), start: chrono::DateTime::UNIX_EPOCH.naive_utc(), end: None, all_day: false, alarms: vec![], rule: None, skip: vec![] });
            }
            ("BEGIN", Some(_)) if value == "VALARM" => in_alarm = true,
            ("END", Some(_)) if value == "VALARM" => in_alarm = false,
            ("END", Some(_)) if value == "VEVENT" => {
                let mut e = cur.take().unwrap();
                if e.start != chrono::DateTime::UNIX_EPOCH.naive_utc() {
                    if e.uid.is_empty() {
                        e.uid = format!("{}@import", crate::short_hash(&format!("{}{}", e.summary, e.start)));
                    }
                    out.push(e);
                }
            }
            ("TRIGGER", Some(e)) if in_alarm => {
                if let Some(s) = parse_trigger(value) {
                    e.alarms.push(s);
                }
            }
            (_, Some(_)) if in_alarm => {}
            ("UID", Some(e)) => e.uid = value.trim().to_string(),
            ("SUMMARY", Some(e)) => e.summary = unescape(value),
            ("LOCATION", Some(e)) => e.place = unescape(value),
            ("DESCRIPTION", Some(e)) => e.note = unescape(value),
            ("DTSTART", Some(e)) => {
                if let Some((d, all)) = parse_dt(value) {
                    e.start = d;
                    e.all_day = all;
                }
            }
            ("DTEND", Some(e)) => e.end = parse_dt(value).map(|p| p.0),
            ("DURATION", Some(e)) => {
                if let Some(s) = parse_trigger(value) {
                    e.end = Some(e.start - Duration::seconds(s));
                }
            }
            ("RRULE", Some(e)) => e.rule = parse_rule(value),
            ("EXDATE", Some(e)) => e.skip.extend(value.split(',').filter_map(|v| parse_dt(v).map(|p| p.0))),
            _ => {}
        }
    }
    out
}

// ───── recurrence ─────

/// The k-th occurrence of a series (None when the date does not exist, e.g. the 31st of a short month)
fn nth(start: NaiveDateTime, rule: &Rule, k: u32) -> Option<NaiveDateTime> {
    let n = i64::from(rule.interval) * i64::from(k);
    match rule.freq {
        Freq::Daily => Some(start + Duration::days(n)),
        Freq::Weekly => Some(start + Duration::weeks(n)),
        Freq::Monthly | Freq::Yearly => {
            let months = if rule.freq == Freq::Monthly { n } else { n * 12 };
            let total = i64::from(start.year()) * 12 + i64::from(start.month0()) + months;
            let (y, m) = (i32::try_from(total.div_euclid(12)).ok()?, u32::try_from(total.rem_euclid(12)).ok()? + 1);
            Some(NaiveDate::from_ymd_opt(y, m, start.day())?.and_time(start.time()))
        }
    }
}

/// Starts of the occurrences that overlap [from, to): an event that has not ended by `from`, or starts in the window.
pub fn occurrences(e: &Event, from: NaiveDateTime, to: NaiveDateTime) -> Vec<NaiveDateTime> {
    let len = e.length();
    let visible = |s: NaiveDateTime| s < to && (s >= from || s + len > from) && !e.skip.contains(&s);
    let Some(rule) = &e.rule else {
        return if visible(e.start) { vec![e.start] } else { vec![] };
    };
    // Daily and weekly series: jump close to the window instead of walking from the first occurrence
    let period = match rule.freq {
        Freq::Daily => Duration::days(i64::from(rule.interval)),
        Freq::Weekly => Duration::weeks(i64::from(rule.interval)),
        _ => Duration::zero(),
    };
    let mut k = if period > Duration::zero() && from > e.start + len { u32::try_from(((from - e.start - len).num_seconds() / period.num_seconds() - 1).max(0)).unwrap_or(0) } else { 0 };
    let mut out = Vec::new();
    for _ in 0..20000 {
        if rule.count.is_some_and(|c| k >= c) {
            break;
        }
        if let Some(s) = nth(e.start, rule, k) {
            if s >= to || rule.until.is_some_and(|u| s > u) {
                break;
            }
            if visible(s) {
                out.push(s);
            }
        }
        k += 1;
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    fn dt(s: &str) -> NaiveDateTime {
        NaiveDateTime::parse_from_str(s, "%Y-%m-%dT%H:%M").unwrap()
    }
    fn ev() -> Event {
        Event { uid: "u1@filigrane".into(), summary: "Dentist, 2nd floor; bring card".into(), place: "Rue 1".into(), note: "line1\nline2".into(), start: dt("2026-11-25T14:00"), end: Some(dt("2026-11-25T15:00")), all_day: false, alarms: vec![600, 0], rule: None, skip: vec![] }
    }
    #[test]
    fn round_trip() {
        let mut e = ev();
        e.rule = Some(Rule { freq: Freq::Weekly, interval: 2, count: Some(5), until: None });
        e.skip = vec![dt("2026-12-09T14:00")];
        let text = to_ics(&e);
        assert!(text.contains("TRIGGER:-PT10M") && text.contains("TRIGGER:PT0S"));
        assert_eq!(parse_ics(&text), vec![e]);
    }
    #[test]
    fn long_lines_fold_and_unfold() {
        let mut e = ev();
        e.summary = "é".repeat(100);
        let text = to_ics(&e);
        assert!(text.lines().all(|l| l.len() <= 75));
        assert_eq!(parse_ics(&text)[0].summary, e.summary);
    }
    #[test]
    fn all_day_and_utc() {
        let e = parse_ics("BEGIN:VEVENT\r\nUID:a\r\nDTSTART;VALUE=DATE:20261224\r\nSUMMARY:Eve\r\nEND:VEVENT\r\n");
        assert_eq!((e[0].all_day, e[0].start), (true, dt("2026-12-24T00:00")));
        let u = parse_ics("BEGIN:VEVENT\r\nUID:b\r\nDTSTART:20261224T120000Z\r\nSUMMARY:x\r\nEND:VEVENT\r\n");
        assert_eq!(u[0].start, crate::when::from_epoch(Utc.with_ymd_and_hms(2026, 12, 24, 12, 0, 0).unwrap().timestamp()));
    }
    #[test]
    fn triggers() {
        assert_eq!(parse_trigger("-PT10M"), Some(600));
        assert_eq!(parse_trigger("PT0S"), Some(0));
        assert_eq!(parse_trigger("-P1DT2H"), Some(93600));
        assert_eq!(parse_trigger("PT5M"), Some(-300));
        assert_eq!(fmt_trigger(93600), "-P1DT2H");
        assert_eq!(fmt_trigger(-300), "PT5M");
    }
    #[test]
    fn single_event_window() {
        let e = ev();
        assert_eq!(occurrences(&e, dt("2026-11-25T00:00"), dt("2026-11-26T00:00")), vec![e.start]);
        assert!(occurrences(&e, dt("2026-11-26T00:00"), dt("2026-11-27T00:00")).is_empty());
        // still running at 14:30
        assert_eq!(occurrences(&e, dt("2026-11-25T14:30"), dt("2026-11-25T16:00")), vec![e.start]);
    }
    #[test]
    fn weekly_series_with_skip_and_count() {
        let mut e = ev();
        e.rule = Some(Rule { freq: Freq::Weekly, interval: 1, count: Some(4), until: None });
        e.skip = vec![dt("2026-12-02T14:00")];
        let got = occurrences(&e, dt("2026-11-01T00:00"), dt("2027-01-01T00:00"));
        assert_eq!(got, vec![dt("2026-11-25T14:00"), dt("2026-12-09T14:00"), dt("2026-12-16T14:00")]);
    }
    #[test]
    fn daily_series_far_in_the_past_jumps() {
        let mut e = ev();
        e.start = dt("2020-01-01T08:00");
        e.end = None;
        e.rule = Some(Rule { freq: Freq::Daily, interval: 1, count: None, until: None });
        let got = occurrences(&e, dt("2026-11-25T00:00"), dt("2026-11-28T00:00"));
        assert_eq!(got, vec![dt("2026-11-25T08:00"), dt("2026-11-26T08:00"), dt("2026-11-27T08:00")]);
    }
    #[test]
    fn monthly_on_the_31st_skips_short_months_and_until_stops() {
        let mut e = ev();
        e.start = dt("2026-01-31T09:00");
        e.end = None;
        e.rule = Some(Rule { freq: Freq::Monthly, interval: 1, count: None, until: Some(dt("2026-05-31T09:00")) });
        let got = occurrences(&e, dt("2026-01-01T00:00"), dt("2027-01-01T00:00"));
        assert_eq!(got, vec![dt("2026-01-31T09:00"), dt("2026-03-31T09:00"), dt("2026-05-31T09:00")]);
    }
    #[test]
    fn yearly() {
        let mut e = ev();
        e.start = dt("2024-02-29T00:00");
        e.end = None;
        e.all_day = true;
        e.rule = Some(Rule { freq: Freq::Yearly, interval: 1, count: None, until: None });
        let got = occurrences(&e, dt("2024-01-01T00:00"), dt("2029-01-01T00:00"));
        assert_eq!(got, vec![dt("2024-02-29T00:00"), dt("2028-02-29T00:00")]);
    }
}
