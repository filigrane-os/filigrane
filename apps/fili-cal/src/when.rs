//! Dates and durations typed on the command line. Times are local ("floating"): nothing here knows about time zones except
//! the conversion to an epoch for the files read by the shell.
use chrono::{Datelike, Duration, Local, NaiveDate, NaiveDateTime, NaiveTime, TimeZone, Weekday};

/// Now, or `FILI_CAL_NOW` (`YYYY-MM-DDTHH:MM`) so that the tests do not depend on the clock.
pub fn now() -> NaiveDateTime {
    if let Ok(v) = std::env::var("FILI_CAL_NOW")
        && let Ok(dt) = NaiveDateTime::parse_from_str(&v, "%Y-%m-%dT%H:%M")
    {
        return dt;
    }
    Local::now().naive_local()
}

/// Epoch of a local time (the earlier one when the hour exists twice, one hour later when it does not exist).
pub fn to_epoch(dt: NaiveDateTime) -> i64 {
    match Local.from_local_datetime(&dt) {
        chrono::LocalResult::Single(t) | chrono::LocalResult::Ambiguous(t, _) => t.timestamp(),
        chrono::LocalResult::None => Local.from_local_datetime(&(dt + Duration::hours(1))).earliest().map_or(0, |t| t.timestamp()),
    }
}

pub fn from_epoch(e: i64) -> NaiveDateTime {
    Local.timestamp_opt(e, 0).earliest().map_or(chrono::DateTime::UNIX_EPOCH.naive_utc(), |t| t.naive_local())
}

/// "90s", "10m", "2h", "1d", "1w", "1h30m", "10" (minutes) → seconds
pub fn parse_duration(s: &str) -> Result<i64, String> {
    let s = s.trim().to_lowercase();
    if s.is_empty() {
        return Err("empty duration".into());
    }
    if s.chars().all(|c| c.is_ascii_digit()) {
        return s.parse::<i64>().map(|m| m * 60).map_err(|e| e.to_string());
    }
    let (mut total, mut num) = (0i64, String::new());
    for c in s.chars() {
        if c.is_ascii_digit() {
            num.push(c);
            continue;
        }
        let n: i64 = num.parse().map_err(|_| format!("bad duration: {s}"))?;
        num.clear();
        total += n * match c {
            's' => 1,
            'm' => 60,
            'h' => 3600,
            'd' => 86400,
            'w' => 604800,
            _ => return Err(format!("bad duration: {s} (use 30s, 10m, 2h, 1d, 1w)")),
        };
    }
    if !num.is_empty() {
        return Err(format!("bad duration: {s} (a unit is missing)"));
    }
    Ok(total)
}

fn parse_time(s: &str) -> Option<NaiveTime> {
    let s = s.replace('h', ":");
    let s = if s.ends_with(':') { format!("{s}00") } else { s };
    NaiveTime::parse_from_str(&s, "%H:%M").ok().or_else(|| NaiveTime::parse_from_str(&s, "%H:%M:%S").ok())
}

fn weekday(s: &str) -> Option<Weekday> {
    Some(match s {
        "mon" | "monday" | "lundi" => Weekday::Mon,
        "tue" | "tuesday" | "mardi" => Weekday::Tue,
        "wed" | "wednesday" | "mercredi" => Weekday::Wed,
        "thu" | "thursday" | "jeudi" => Weekday::Thu,
        "fri" | "friday" | "vendredi" => Weekday::Fri,
        "sat" | "saturday" | "samedi" => Weekday::Sat,
        "sun" | "sunday" | "dimanche" => Weekday::Sun,
        _ => return None,
    })
}

fn parse_date(s: &str, today: NaiveDate) -> Option<NaiveDate> {
    match s {
        "today" | "aujourd'hui" | "aujourdhui" => return Some(today),
        "tomorrow" | "demain" => return Some(today + Duration::days(1)),
        _ => {}
    }
    if let Some(w) = weekday(s) {
        let mut d = today + Duration::days(1);
        while d.weekday() != w {
            d += Duration::days(1);
        }
        return Some(d);
    }
    NaiveDate::parse_from_str(s, "%Y-%m-%d").ok()
}

/// A moment typed by the user. Returns the time and whether it is a whole day (no time given).
/// `+2h`, `+3d` (from now) · `14:30` or `14h30` (the next one) · `2026-12-24` (whole day) · `2026-12-24 20:00` ·
/// `2026-12-24T20:00` · `today|tomorrow|demain|monday|lundi [14:30]` (a weekday is the next one).
pub fn parse_when(input: &str, now: NaiveDateTime) -> Result<(NaiveDateTime, bool), String> {
    // "2026-12-24T20:00": the T between two digits is a space (never the t of "today" or "tuesday")
    let lower: Vec<char> = input.trim().to_lowercase().chars().collect();
    let s: String = lower
        .iter()
        .enumerate()
        .map(|(i, &c)| if c == 't' && i > 0 && lower[i - 1].is_ascii_digit() && lower.get(i + 1).is_some_and(|n| n.is_ascii_digit()) { ' ' } else { c })
        .collect();
    if let Some(rest) = s.strip_prefix('+') {
        return Ok((now + Duration::seconds(parse_duration(rest)?), false));
    }
    let toks: Vec<&str> = s.split_whitespace().collect();
    let bad = || format!("cannot read the date: {input} (try 14:30, tomorrow 09:00, 2026-12-24 20:00, +2h)");
    match toks.as_slice() {
        [one] => {
            if let Some(t) = parse_time(one) {
                let today = now.date().and_time(t);
                return Ok((if today > now { today } else { today + Duration::days(1) }, false));
            }
            let d = parse_date(one, now.date()).ok_or_else(bad)?;
            Ok((d.and_time(NaiveTime::MIN), true))
        }
        [d, t] => {
            let d = parse_date(d, now.date()).ok_or_else(bad)?;
            let t = parse_time(t).ok_or_else(bad)?;
            Ok((d.and_time(t), false))
        }
        _ => Err(bad()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn n() -> NaiveDateTime {
        NaiveDateTime::parse_from_str("2026-11-25T10:00", "%Y-%m-%dT%H:%M").unwrap() // a Wednesday
    }
    fn w(s: &str) -> (String, bool) {
        let (d, a) = parse_when(s, n()).unwrap();
        (d.format("%Y-%m-%d %H:%M").to_string(), a)
    }
    #[test]
    fn durations() {
        assert_eq!(parse_duration("10m").unwrap(), 600);
        assert_eq!(parse_duration("1h30m").unwrap(), 5400);
        assert_eq!(parse_duration("10").unwrap(), 600);
        assert_eq!(parse_duration("1w").unwrap(), 604800);
        assert!(parse_duration("5x").is_err());
        assert!(parse_duration("1h30").is_err());
    }
    #[test]
    fn moments() {
        assert_eq!(w("14:30"), ("2026-11-25 14:30".into(), false));
        assert_eq!(w("09:00"), ("2026-11-26 09:00".into(), false)); // already past today: tomorrow
        assert_eq!(w("14h30"), ("2026-11-25 14:30".into(), false));
        assert_eq!(w("2026-12-24"), ("2026-12-24 00:00".into(), true));
        assert_eq!(w("2026-12-24 20:00"), ("2026-12-24 20:00".into(), false));
        assert_eq!(w("2026-12-24T20:00"), ("2026-12-24 20:00".into(), false));
        assert_eq!(w("tomorrow 09:00"), ("2026-11-26 09:00".into(), false));
        assert_eq!(w("demain"), ("2026-11-26 00:00".into(), true));
        assert_eq!(w("+2h"), ("2026-11-25 12:00".into(), false));
        assert_eq!(w("+3d"), ("2026-11-28 10:00".into(), false));
        assert_eq!(w("friday 18:00"), ("2026-11-27 18:00".into(), false));
        assert_eq!(w("mercredi 08:00"), ("2026-12-02 08:00".into(), false)); // the next Wednesday, not today
        assert_eq!(w("tuesday"), ("2026-12-01 00:00".into(), true));
        assert!(parse_when("nonsense", n()).is_err());
        assert!(parse_when("2026-13-45", n()).is_err());
    }
}
