// JSON minimal, sans dépendance: entrées de Claude Code (hooks, status line), réponses de niri et état du module IA.
// Analyse et écriture; l'ordre des clés est gardé.
use std::fmt;

#[derive(Clone, Debug, PartialEq)]
pub enum Json {
    Null,
    Bool(bool),
    Num(f64),
    Str(String),
    Arr(Vec<Json>),
    Obj(Vec<(String, Json)>),
}

static NULL: Json = Json::Null;

impl Json {
    pub fn parse(s: &str) -> Option<Json> {
        let mut p = Parser { b: s.as_bytes(), i: 0 };
        let v = p.value()?;
        p.ws();
        (p.i == p.b.len()).then_some(v)
    }
    pub fn obj() -> Json {
        Json::Obj(Vec::new())
    }
    pub fn get(&self, k: &str) -> &Json {
        match self {
            Json::Obj(m) => m.iter().find(|(x, _)| x == k).map(|(_, v)| v).unwrap_or(&NULL),
            _ => &NULL,
        }
    }
    pub fn path(&self, p: &[&str]) -> &Json {
        p.iter().fold(self, |v, k| v.get(k))
    }
    pub fn str(&self) -> Option<&str> {
        match self {
            Json::Str(s) => Some(s),
            _ => None,
        }
    }
    pub fn num(&self) -> Option<f64> {
        match self {
            Json::Num(n) => Some(*n),
            _ => None,
        }
    }
    pub fn int(&self) -> Option<i64> {
        self.num().map(|n| n as i64)
    }
    pub fn truthy(&self) -> bool {
        matches!(self, Json::Bool(true))
    }
    pub fn is_null(&self) -> bool {
        matches!(self, Json::Null)
    }
    pub fn set(&mut self, k: &str, v: impl Into<Json>) {
        if !matches!(self, Json::Obj(_)) {
            *self = Json::obj();
        }
        if let Json::Obj(m) = self {
            let v = v.into();
            match m.iter_mut().find(|(x, _)| x == k) {
                Some(e) => e.1 = v,
                None => m.push((k.to_string(), v)),
            }
        }
    }
    pub fn remove(&mut self, k: &str) {
        if let Json::Obj(m) = self {
            m.retain(|(x, _)| x != k);
        }
    }
}

impl From<&str> for Json {
    fn from(s: &str) -> Json {
        Json::Str(s.to_string())
    }
}
impl From<String> for Json {
    fn from(s: String) -> Json {
        Json::Str(s)
    }
}
impl From<bool> for Json {
    fn from(b: bool) -> Json {
        Json::Bool(b)
    }
}
impl From<i64> for Json {
    fn from(n: i64) -> Json {
        Json::Num(n as f64)
    }
}
impl From<Option<i64>> for Json {
    fn from(n: Option<i64>) -> Json {
        n.map_or(Json::Null, Json::from)
    }
}
impl From<&Json> for Json {
    fn from(j: &Json) -> Json {
        j.clone()
    }
}

fn escape(f: &mut fmt::Formatter, s: &str) -> fmt::Result {
    f.write_str("\"")?;
    for c in s.chars() {
        match c {
            '"' => f.write_str("\\\"")?,
            '\\' => f.write_str("\\\\")?,
            '\n' => f.write_str("\\n")?,
            '\t' => f.write_str("\\t")?,
            '\r' => f.write_str("\\r")?,
            c if (c as u32) < 0x20 => write!(f, "\\u{:04x}", c as u32)?,
            c => write!(f, "{c}")?,
        }
    }
    f.write_str("\"")
}

impl fmt::Display for Json {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            Json::Null => f.write_str("null"),
            Json::Bool(b) => write!(f, "{b}"),
            Json::Num(n) if !n.is_finite() => f.write_str("null"),
            Json::Num(n) if n.fract() == 0.0 && n.abs() < 1e15 => write!(f, "{}", *n as i64),
            Json::Num(n) => write!(f, "{n}"),
            Json::Str(s) => escape(f, s),
            Json::Arr(a) => {
                f.write_str("[")?;
                for (i, v) in a.iter().enumerate() {
                    if i > 0 {
                        f.write_str(",")?;
                    }
                    write!(f, "{v}")?;
                }
                f.write_str("]")
            }
            Json::Obj(m) => {
                f.write_str("{")?;
                for (i, (k, v)) in m.iter().enumerate() {
                    if i > 0 {
                        f.write_str(",")?;
                    }
                    escape(f, k)?;
                    write!(f, ":{v}")?;
                }
                f.write_str("}")
            }
        }
    }
}

struct Parser<'a> {
    b: &'a [u8],
    i: usize,
}

impl Parser<'_> {
    fn ws(&mut self) {
        while self.i < self.b.len() && self.b[self.i].is_ascii_whitespace() {
            self.i += 1;
        }
    }
    fn eat(&mut self, s: &str) -> bool {
        let ok = self.b[self.i..].starts_with(s.as_bytes());
        if ok {
            self.i += s.len();
        }
        ok
    }
    fn value(&mut self) -> Option<Json> {
        self.ws();
        match *self.b.get(self.i)? {
            b'{' => {
                self.i += 1;
                let mut m = Vec::new();
                self.ws();
                if self.eat("}") {
                    return Some(Json::Obj(m));
                }
                loop {
                    self.ws();
                    let k = self.string()?;
                    self.ws();
                    self.eat(":").then_some(())?;
                    m.push((k, self.value()?));
                    self.ws();
                    if self.eat("}") {
                        return Some(Json::Obj(m));
                    }
                    self.eat(",").then_some(())?;
                }
            }
            b'[' => {
                self.i += 1;
                let mut a = Vec::new();
                self.ws();
                if self.eat("]") {
                    return Some(Json::Arr(a));
                }
                loop {
                    a.push(self.value()?);
                    self.ws();
                    if self.eat("]") {
                        return Some(Json::Arr(a));
                    }
                    self.eat(",").then_some(())?;
                }
            }
            b'"' => self.string().map(Json::Str),
            b't' => self.eat("true").then_some(Json::Bool(true)),
            b'f' => self.eat("false").then_some(Json::Bool(false)),
            b'n' => self.eat("null").then_some(Json::Null),
            _ => {
                let start = self.i;
                while self.i < self.b.len() && matches!(self.b[self.i], b'-' | b'+' | b'.' | b'e' | b'E' | b'0'..=b'9') {
                    self.i += 1;
                }
                std::str::from_utf8(&self.b[start..self.i]).ok()?.parse().ok().map(Json::Num)
            }
        }
    }
    fn hex4(&mut self) -> Option<u32> {
        let h = std::str::from_utf8(self.b.get(self.i..self.i + 4)?).ok()?;
        self.i += 4;
        u32::from_str_radix(h, 16).ok()
    }
    fn string(&mut self) -> Option<String> {
        self.eat("\"").then_some(())?;
        let mut out = Vec::new();
        loop {
            let c = *self.b.get(self.i)?;
            self.i += 1;
            match c {
                b'"' => return String::from_utf8(out).ok(),
                b'\\' => {
                    let e = *self.b.get(self.i)?;
                    self.i += 1;
                    match e {
                        b'n' => out.push(b'\n'),
                        b't' => out.push(b'\t'),
                        b'r' => out.push(b'\r'),
                        b'b' => out.push(8),
                        b'f' => out.push(12),
                        b'u' => {
                            let mut u = self.hex4()?;
                            // Paire de substitution (caractère hors du plan de base)
                            if (0xd800..0xdc00).contains(&u) && self.eat("\\u") {
                                let lo = self.hex4()?;
                                u = 0x10000 + ((u - 0xd800) << 10) + (lo.wrapping_sub(0xdc00) & 0x3ff);
                            }
                            let mut buf = [0; 4];
                            out.extend_from_slice(char::from_u32(u).unwrap_or('\u{fffd}').encode_utf8(&mut buf).as_bytes());
                        }
                        e => out.push(e),
                    }
                }
                c => out.push(c),
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip() {
        let s = r#"{"a":[1,2.5,-3e2,true,null],"b":{"c":"é \"x\"\n\u0001"},"d":"🤖"}"#;
        let j = Json::parse(s).unwrap();
        assert_eq!(j.path(&["b", "c"]).str(), Some("é \"x\"\n\u{1}"));
        assert_eq!(j.get("d").str(), Some("🤖"));
        assert_eq!(j.get("a"), &Json::Arr(vec![1.0.into_json(), 2.5.into_json(), (-300.0).into_json(), true.into(), Json::Null]));
        assert_eq!(Json::parse(&j.to_string()).unwrap(), j);
        assert_eq!(j.get("a").to_string(), "[1,2.5,-300,true,null]");
    }

    #[test]
    fn rejects_garbage() {
        assert!(Json::parse("{\"a\":").is_none());
        assert!(Json::parse("{} x").is_none());
    }

    #[test]
    fn set_and_remove() {
        let mut j = Json::Null;
        j.set("a", 1);
        j.set("b", "x");
        j.set("a", true);
        j.remove("b");
        assert_eq!(j.to_string(), r#"{"a":true}"#);
    }

    trait IntoJson {
        fn into_json(self) -> Json;
    }
    impl IntoJson for f64 {
        fn into_json(self) -> Json {
            Json::Num(self)
        }
    }
}
