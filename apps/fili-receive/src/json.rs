// Minimal JSON for the localsendd events (`lsend --json watch`, one object per line). No dependency.
use std::{iter::Peekable, str::Chars};

#[derive(Debug, PartialEq, Clone)]
pub enum Json {
    Null,
    Bool(bool),
    Num(f64),
    Str(String),
    Arr(Vec<Json>),
    Obj(Vec<(String, Json)>),
}

impl Json {
    pub fn get(&self, key: &str) -> Option<&Json> {
        match self {
            Json::Obj(o) => o.iter().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }
    pub fn str(&self, key: &str) -> Option<&str> {
        match self.get(key)? {
            Json::Str(s) => Some(s),
            _ => None,
        }
    }
    pub fn num(&self, key: &str) -> Option<f64> {
        match self.get(key)? {
            Json::Num(n) => Some(*n),
            _ => None,
        }
    }
    pub fn bool(&self, key: &str) -> Option<bool> {
        match self.get(key)? {
            Json::Bool(b) => Some(*b),
            _ => None,
        }
    }
    pub fn arr(&self, key: &str) -> &[Json] {
        match self.get(key) {
            Some(Json::Arr(a)) => a,
            _ => &[],
        }
    }
}

pub fn parse(text: &str) -> Option<Json> {
    let mut it = text.chars().peekable();
    let v = value(&mut it)?;
    ws(&mut it);
    it.peek().is_none().then_some(v)
}

fn ws(it: &mut Peekable<Chars>) {
    while it.peek().is_some_and(|c| c.is_whitespace()) {
        it.next();
    }
}

fn value(it: &mut Peekable<Chars>) -> Option<Json> {
    ws(it);
    match *it.peek()? {
        '{' => {
            it.next();
            let mut out = Vec::new();
            loop {
                ws(it);
                match it.peek()? {
                    '}' => {
                        it.next();
                        return Some(Json::Obj(out));
                    }
                    ',' => {
                        it.next();
                    }
                    _ => {
                        let k = string(it)?;
                        ws(it);
                        if it.next()? != ':' {
                            return None;
                        }
                        out.push((k, value(it)?));
                    }
                }
            }
        }
        '[' => {
            it.next();
            let mut out = Vec::new();
            loop {
                ws(it);
                match it.peek()? {
                    ']' => {
                        it.next();
                        return Some(Json::Arr(out));
                    }
                    ',' => {
                        it.next();
                    }
                    _ => out.push(value(it)?),
                }
            }
        }
        '"' => string(it).map(Json::Str),
        _ => {
            let mut w = String::new();
            while it.peek().is_some_and(|c| !matches!(c, ',' | '}' | ']') && !c.is_whitespace()) {
                w.push(it.next()?);
            }
            match w.as_str() {
                "null" => Some(Json::Null),
                "true" => Some(Json::Bool(true)),
                "false" => Some(Json::Bool(false)),
                n => n.parse().ok().map(Json::Num),
            }
        }
    }
}

fn string(it: &mut Peekable<Chars>) -> Option<String> {
    if it.next()? != '"' {
        return None;
    }
    let mut s = String::new();
    loop {
        match it.next()? {
            '"' => return Some(s),
            '\\' => match it.next()? {
                'n' => s.push('\n'),
                't' => s.push('\t'),
                'r' => s.push('\r'),
                'b' => s.push('\u{8}'),
                'f' => s.push('\u{c}'),
                'u' => {
                    let hex: String = it.by_ref().take(4).collect();
                    let mut cp = u32::from_str_radix(&hex, 16).ok()?;
                    // paire de substitution
                    if (0xD800..0xDC00).contains(&cp) && it.peek() == Some(&'\\') {
                        it.next();
                        if it.next()? == 'u' {
                            let lo = u32::from_str_radix(&it.by_ref().take(4).collect::<String>(), 16).ok()?;
                            cp = 0x10000 + ((cp - 0xD800) << 10) + (lo.wrapping_sub(0xDC00) & 0x3FF);
                        }
                    }
                    s.push(char::from_u32(cp).unwrap_or('\u{fffd}'));
                }
                c => s.push(c),
            },
            c => s.push(c),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn incoming_session_event() {
        let j = parse(r#"{"event":"incoming_session","data":{"session_id":"a","peer_alias":"iPhone \"X\"","files":[{"id":"1","file_name":"é.txt","size":811},{"id":"2","file_name":"b","size":0}]}}"#).unwrap();
        let d = j.get("data").unwrap();
        assert_eq!(j.str("event"), Some("incoming_session"));
        assert_eq!(d.str("peer_alias"), Some("iPhone \"X\""));
        let f = d.arr("files");
        assert_eq!(f.len(), 2);
        assert_eq!(f[0].str("file_name"), Some("é.txt"));
        assert_eq!(f[0].num("size"), Some(811.0));
    }

    #[test]
    fn transfer_complete_event() {
        let j = parse(r#"{"event":"transfer_complete","data":{"session_id":"s","file_id":"f","success":true}}"#).unwrap();
        assert_eq!(j.get("data").unwrap().bool("success"), Some(true));
    }

    #[test]
    fn rejects_garbage() {
        assert!(parse("{\"a\":").is_none());
        assert!(parse("nope").is_none());
    }
}
