// Theme and window settings of Cassette: ~/.config/filigrane/fili-recorder.toml (optional) over the shared
// ~/.config/filigrane/theme.toml over the defaults of theme.toml (embedded), exactly like Casier (fili-file/src/config.rs).
// Keys `key = value`, sections `[theme]`, `[theme.dark]`, `[theme.light]`, `[theme.accents]`, `[window]`; no dependency.
use std::collections::BTreeMap;
use std::env;
use std::path::PathBuf;

pub fn path() -> PathBuf {
    let home = env::var("HOME").unwrap_or_default();
    let dir = env::var("XDG_CONFIG_HOME").unwrap_or_else(|_| format!("{home}/.config"));
    PathBuf::from(dir).join("filigrane/fili-recorder.toml")
}

// `[window] header = false` / `footer = false` (written by `fili-theme header|footer off`) in fili-file.toml, which takes
// precedence, or in the shared ~/.config/filigrane/theme.toml; the command-line flags --no-header / --header and
// --no-footer / --footer win over both. Absent or invalid: the part is shown.
pub fn window_layers(key: &str, global: &str, user: &str, args: &[String]) -> bool {
    let (on, off) = (format!("--{key}"), format!("--no-{key}"));
    let flag = args.iter().rev().find_map(|a| {
        if *a == off {
            Some(false)
        } else if *a == on {
            Some(true)
        } else {
            None
        }
    });
    let get = |text: &str| match parse_sections(text).get("window").and_then(|s| s.get(key)) {
        Some(Val::Str(v)) if v == "true" => Some(true),
        Some(Val::Str(v)) if v == "false" => Some(false),
        _ => None,
    };
    flag.or_else(|| get(user)).or_else(|| get(global)).unwrap_or(true)
}

pub fn window_part(key: &str, args: &[String]) -> bool {
    let read = |p: PathBuf| std::fs::read_to_string(p).unwrap_or_default();
    window_layers(key, &read(global_path()), &read(path()), args)
}

fn strip_comment(line: &str) -> &str {
    let mut quoted = false;
    for (i, ch) in line.char_indices() {
        match ch {
            '"' => quoted = !quoted,
            '#' if !quoted => return &line[..i],
            _ => {}
        }
    }
    line
}

// ---- Theme -------------------------------------------------------------------------------------------------
// The defaults are in theme.toml (embedded); ~/.config/filigrane/fili-file.toml overrides them key by key.
// Lookup order of a key: the user's [theme.<mode>], their [theme], the defaults' [theme.<mode>], their [theme].

#[derive(Clone, Debug, PartialEq)]
enum Val {
    Str(String),
    List(Vec<String>),
}

type Sections = BTreeMap<String, BTreeMap<String, Val>>;

#[derive(Clone, Copy, PartialEq)]
enum Kind {
    Color,
    Int,
    Str,
}

// (TOML key, type): all of them apply in [theme] and in each mode
const KEYS: &[(&str, Kind)] = &[
    ("background", Kind::Color),
    ("background_deep", Kind::Color),
    ("surface", Kind::Color),
    ("surface_hover", Kind::Color),
    ("surface_active", Kind::Color),
    ("border", Kind::Color),
    ("muted", Kind::Color),
    ("text_secondary", Kind::Color),
    ("text", Kind::Color),
    ("warning", Kind::Color),
    ("danger", Kind::Color),
    ("success", Kind::Color),
    ("accent", Kind::Color),        // optional: without a value, the accent follows fili-theme
    ("accent_bright", Kind::Color), // optional
    ("font", Kind::Str),
    ("mono", Kind::Str),
    ("icons", Kind::Str),
    ("size", Kind::Int),
    ("size_list", Kind::Int),
    ("size_small", Kind::Int),
    ("size_label", Kind::Int),
    ("size_title", Kind::Int),
    ("weight_accent", Kind::Int),
    ("radius_mark", Kind::Int),
    ("radius_control", Kind::Int),
    ("radius_window", Kind::Int),
    ("border_width", Kind::Int),
    ("space_1", Kind::Int),
    ("space_2", Kind::Int),
    ("space_3", Kind::Int),
    ("space_4", Kind::Int),
    ("space_5", Kind::Int),
    ("space_6", Kind::Int),
    ("row_height", Kind::Int),
    ("side_row_height", Kind::Int),
    ("icon_size", Kind::Int),
    ("margin", Kind::Int),
    ("toolbar_height", Kind::Int),
    ("status_height", Kind::Int),
    ("sidebar_width", Kind::Int),
    ("tab_bar_height", Kind::Int),
    ("tab_height", Kind::Int),
];

const DEFAULT_THEME: &str = include_str!("../theme.toml");

fn parse_value(v: &str) -> Val {
    let v = v.trim();
    if let Some(inner) = v.strip_prefix('[').and_then(|r| r.strip_suffix(']')) {
        Val::List(inner.split(',').map(|x| x.trim().trim_matches('"').trim().to_string()).filter(|x| !x.is_empty()).collect())
    } else {
        Val::Str(v.trim_matches('"').trim().to_string())
    }
}

fn parse_sections(text: &str) -> Sections {
    let mut out = Sections::new();
    let mut section = String::new();
    for line in text.lines() {
        let line = strip_comment(line).trim();
        if let Some(name) = line.strip_prefix('[').and_then(|r| r.strip_suffix(']')) {
            section = name.trim().to_string();
        } else if let Some((k, v)) = line.split_once('=') {
            out.entry(section.clone()).or_default().insert(k.trim().to_string(), parse_value(v));
        }
    }
    out
}

fn valid_color(s: &str) -> bool {
    s.strip_prefix('#').is_some_and(|h| matches!(h.len(), 3 | 6 | 8) && h.chars().all(|c| c.is_ascii_hexdigit()))
}

fn valid(kind: Kind, s: &str) -> bool {
    match kind {
        Kind::Color => valid_color(s),
        Kind::Int => s.parse::<u32>().is_ok(),
        Kind::Str => !s.is_empty(),
    }
}

fn json_str(s: &str) -> String {
    let mut o = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => o.push_str("\\\""),
            '\\' => o.push_str("\\\\"),
            c if (c as u32) < 0x20 => o.push(' '),
            c => o.push(c),
        }
    }
    o.push('"');
    o
}

// Accent tones: the user's (4 valid colors) replace the defaults', by name
fn accents_from(layers: &[&Sections]) -> BTreeMap<String, Vec<String>> {
    let mut accents = BTreeMap::new();
    for sections in layers {
        for (name, v) in sections.get("theme.accents").into_iter().flatten() {
            if let Val::List(l) = v {
                if l.len() == 4 && l.iter().all(|c| valid_color(c)) {
                    accents.insert(name.clone(), l.clone());
                }
            }
        }
    }
    accents
}

// `global`: ~/.config/filigrane/theme.toml (shared by Filigrane); `user`: fili-file.toml, which takes precedence
pub fn theme_json_layers(global: &str, user: &str) -> String {
    let defaults = parse_sections(DEFAULT_THEME);
    let global = parse_sections(global);
    let user = parse_sections(user);
    let get = |sections: &Sections, name: &str, key: &str| match sections.get(name).and_then(|s| s.get(key)) {
        Some(Val::Str(v)) => Some(v.clone()),
        _ => None,
    };
    let mut out = String::from("{");
    for (n, mode) in ["dark", "light"].iter().enumerate() {
        if n > 0 {
            out.push(',');
        }
        out.push_str(&format!("{}:{{", json_str(mode)));
        let section = format!("theme.{mode}");
        let mut first = true;
        for (key, kind) in KEYS {
            let found = [
                (&user, section.as_str()),
                (&user, "theme"),
                (&global, section.as_str()),
                (&global, "theme"),
                (&defaults, section.as_str()),
                (&defaults, "theme"),
            ]
            .iter()
            .filter_map(|(s, name)| get(s, name, key))
            .find(|v| valid(*kind, v));
            let Some(v) = found else { continue };
            if !first {
                out.push(',');
            }
            first = false;
            out.push_str(&json_str(key));
            out.push(':');
            out.push_str(&if *kind == Kind::Int { v } else { json_str(&v) });
        }
        out.push('}');
    }
    let accents = accents_from(&[&defaults, &global, &user]);
    let list: Vec<String> = accents
        .iter()
        .map(|(n, l)| format!("{}:[{}]", json_str(n), l.iter().map(|c| json_str(c)).collect::<Vec<_>>().join(",")))
        .collect();
    out.push_str(&format!(",\"accents\":{{{}}}}}", list.join(",")));
    out
}

pub fn global_path() -> PathBuf {
    path().with_file_name("theme.toml")
}

pub fn theme_json() -> String {
    let read = |p: PathBuf| std::fs::read_to_string(p).unwrap_or_default();
    theme_json_layers(&read(global_path()), &read(path()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn window_parts_follow_flag_then_app_then_global() {
        let none: Vec<String> = Vec::new();
        assert!(window_layers("header", "", "", &none), "shown by default");
        assert!(!window_layers("header", "[window]\nheader = false\n", "", &none), "shared file");
        assert!(
            window_layers("header", "[window]\nheader = false\n", "[window]\nheader = true\n", &none),
            "the app wins over the shared file"
        );
        assert!(!window_layers("footer", "", "[window]\nfooter = false\n", &none));
        let off = vec!["--no-header".to_string()];
        assert!(!window_layers("header", "", "[window]\nheader = true\n", &off), "the flag wins over both");
        let on = vec!["--no-header".to_string(), "--header".to_string()];
        assert!(window_layers("header", "[window]\nheader = false\n", "", &on), "the last flag counts");
        assert!(window_layers("header", "[window]\nheader = maybe\n", "", &none), "an invalid value is ignored");
    }

    #[test]
    fn the_user_file_overrides_the_defaults_key_by_key() {
        let json = theme_json_layers("", "[theme]\nsize = 16\n[theme.dark]\nbackground = \"#000000\"\nsize_small = notanumber\n");
        assert!(json.contains("\"size\":16"), "{json}");
        assert!(json.contains("\"background\":\"#000000\""));
        assert!(json.contains("\"size_small\":12"), "an invalid value keeps the default");
        assert!(json.contains("\"light\":{") && json.contains("\"accents\":{"));
    }
}
