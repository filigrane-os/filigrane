// Translations (shared with fili-file: fili-file/src/main.rs): texts written in English in the code (tr("Offline"), trf("Battery %1 %", &[&cap])), translated by the
// catalog of the fili-shell (dotfiles/config/quickshell/i18n/<language>.json, see FiliI18n.qml), read once. Catalog
// folder: FILI_I18N (set by FiliShell.qml), else ~/.config/quickshell/i18n. Language: FILI_LANG, else the choice of
// fili-lang ($XDG_STATE_HOME/filigrane/locale), else the first one set of LC_ALL, LC_MESSAGES, LANG ("fr_FR.UTF-8" -> fr; C, POSIX -> en). No catalog or no entry: English.
use std::{collections::HashMap, env, fmt::Display, fs, sync::OnceLock};

static CATALOG: OnceLock<HashMap<String, String>> = OnceLock::new();

fn lang() -> String {
    // The tests expect the English texts of the code, whatever the language chosen by the user (the catalog
    // is frozen by the first call: a test that does not set FILI_LANG would make the others fail)
    if cfg!(test) {
        return "en".into();
    }
    // Choice of the user (fili-lang), after FILI_LANG; the fili-shell restarts bar-stats when it changes
    let state = env::var("XDG_STATE_HOME").unwrap_or_else(|_| format!("{}/.local/state", env::var("HOME").unwrap_or_default()));
    let choice = fs::read_to_string(format!("{state}/filigrane/locale")).map(|s| s.trim().to_string()).unwrap_or_default();
    let v = env::var("FILI_LANG")
        .ok()
        .filter(|v| !v.is_empty())
        .or(Some(choice).filter(|v| !v.is_empty()))
        .or_else(|| ["LC_ALL", "LC_MESSAGES", "LANG"].iter().find_map(|k| env::var(k).ok().filter(|v| !v.is_empty())))
        .unwrap_or_default();
    let l: String = v.chars().take_while(|c| !matches!(c, '_' | '.' | '@')).collect();
    if !l.is_empty() && l.chars().all(|c| c.is_ascii_lowercase()) { l } else { "en".into() }
}

fn catalog() -> &'static HashMap<String, String> {
    CATALOG.get_or_init(|| {
        let lang = lang();
        if lang == "en" {
            return HashMap::new();
        }
        let dir = env::var("FILI_I18N").unwrap_or_else(|_| {
            let config =
                env::var("XDG_CONFIG_HOME").unwrap_or_else(|_| format!("{}/.config", env::var("HOME").unwrap_or_default()));
            format!("{config}/quickshell/i18n")
        });
        fs::read_to_string(format!("{dir}/{lang}.json")).map(|t| parse(&t)).unwrap_or_default()
    })
}

// Flat JSON object {"key": "value", ...}; whatever is not a pair of strings is ignored
fn parse(text: &str) -> HashMap<String, String> {
    let mut out = HashMap::new();
    let mut it = text.chars().peekable();
    let mut strings = Vec::new();
    while let Some(c) = it.next() {
        if c != '"' {
            continue;
        }
        let mut s = String::new();
        while let Some(c) = it.next() {
            match c {
                '"' => break,
                '\\' => match it.next() {
                    Some('n') => s.push('\n'),
                    Some('t') => s.push('\t'),
                    Some('u') => {
                        let hex: String = it.by_ref().take(4).collect();
                        s.extend(u32::from_str_radix(&hex, 16).ok().and_then(char::from_u32));
                    }
                    Some(c) => s.push(c),
                    None => break,
                },
                c => s.push(c),
            }
        }
        strings.push(s);
        if strings.len() == 2 {
            let v = strings.pop().unwrap_or_default();
            out.insert(strings.pop().unwrap_or_default(), v);
        }
    }
    out
}

pub fn tr(s: &str) -> &str {
    catalog().get(s).map(String::as_str).unwrap_or(s)
}

// Translated text, %1, %2... replaced by the arguments
pub fn trf(s: &str, args: &[&dyn Display]) -> String {
    let t = tr(s);
    let mut out = String::with_capacity(t.len() + 16);
    let mut chars = t.chars().peekable();
    while let Some(c) = chars.next() {
        match (c, chars.peek().and_then(|d| d.to_digit(10))) {
            ('%', Some(n)) if n >= 1 && (n as usize) <= args.len() => {
                chars.next();
                out.push_str(&args[n as usize - 1].to_string());
            }
            _ => out.push(c),
        }
    }
    out
}

// Number with d decimals and the separator of the language ("@decimal" key of the catalog)
pub fn num(v: f64, d: usize) -> String {
    let s = format!("{v:.d$}");
    match catalog().get("@decimal") {
        Some(sep) => s.replacen('.', sep, 1),
        None => s,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_flat_object() {
        let c = parse(r#"{"Offline": "Hors ligne", "a \"b\"": "é\n", "@decimal": ","}"#);
        assert_eq!(c["Offline"], "Hors ligne");
        assert_eq!(c["a \"b\""], "é\n");
        assert_eq!(c["@decimal"], ",");
    }

    #[test]
    fn english_without_catalog() {
        assert_eq!(trf("Battery %1 %, %2", &[&66, &"x"]), "Battery 66 %, x");
        assert_eq!(trf("100 % %3", &[&1]), "100 % %3");
    }
}
