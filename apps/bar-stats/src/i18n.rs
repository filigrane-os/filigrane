// Traductions (partagé avec fili-file: apps/fili-file/src/main.rs): textes écrits en anglais dans le code (tr("Offline"), trf("Battery %1 %", &[&cap])), traduits par le
// catalogue du fili-shell (dotfiles/config/quickshell/i18n/<langue>.json, voir FiliI18n.qml), lu une fois. Dossier du
// catalogue: FILI_I18N (posé par FiliShell.qml), sinon ~/.config/quickshell/i18n. Langue: FILI_LANG, sinon le choix de
// fili-lang ($XDG_STATE_HOME/filigrane/locale), sinon la première posée de LC_ALL, LC_MESSAGES, LANG ("fr_FR.UTF-8" -> fr; C, POSIX -> en). Pas de catalogue ou pas d'entrée: anglais.
use std::{collections::HashMap, env, fmt::Display, fs, sync::OnceLock};

static CATALOG: OnceLock<HashMap<String, String>> = OnceLock::new();

fn lang() -> String {
    // Choix de l'utilisateur (fili-lang), après FILI_LANG; le fili-shell relance bar-stats quand il change
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

// Objet JSON plat {"clé": "valeur", ...}; ce qui n'est pas une paire de chaînes est ignoré
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

// Texte traduit, %1, %2... remplacés par les arguments
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

// Nombre avec d décimales et le séparateur de la langue (clé "@decimal" du catalogue)
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
