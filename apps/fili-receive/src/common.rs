// Ce que partagent les deux protocoles: réglages, notifications avec boutons, journal des fichiers reçus.
use crate::i18n::{num, tr, trf};
use std::{
    env, fs,
    io::Write,
    path::PathBuf,
    process::{Command, Stdio},
    time::{SystemTime, UNIX_EPOCH},
};

pub fn home() -> String {
    env::var("HOME").unwrap_or_default()
}

pub struct Settings {
    pub dir: String,
    pub always: bool,
    pub minutes: u32,
}

// Réglages de réception, dans ~/.config/filigrane/fili-file.toml (le fichier de Casier, entrée « Settings… »):
// receive_dir, receive_confirm = "ask" | "always", receive_minutes
pub fn settings() -> Settings {
    let config = env::var("XDG_CONFIG_HOME").unwrap_or_else(|_| format!("{}/.config", home()));
    parse_settings(&fs::read_to_string(format!("{config}/filigrane/fili-file.toml")).unwrap_or_default())
}

pub fn parse_settings(text: &str) -> Settings {
    let mut s = Settings {
        dir: env::var("XDG_DOWNLOAD_DIR").ok().filter(|d| !d.is_empty()).unwrap_or_else(|| format!("{}/Downloads", home())),
        always: false,
        minutes: 0,
    };
    for line in text.lines() {
        let line = line.split('#').next().unwrap_or("").trim();
        let Some((k, v)) = line.split_once('=') else { continue };
        let v = v.trim().trim_matches('"');
        match k.trim() {
            "receive_dir" if !v.is_empty() => {
                s.dir = match v.strip_prefix('~') {
                    Some(rest) => format!("{}{rest}", home()),
                    None => v.to_string(),
                }
            }
            "receive_confirm" => s.always = v == "always",
            "receive_minutes" => s.minutes = v.parse().unwrap_or(0),
            _ => {}
        }
    }
    s
}

// 811 -> « 811 o », 12 Mo, 1,5 Go
pub fn human(bytes: u64) -> String {
    let units = ["B", "kB", "MB", "GB", "TB"];
    let mut v = bytes as f64;
    let mut i = 0;
    while v >= 1000.0 && i < units.len() - 1 {
        v /= 1000.0;
        i += 1;
    }
    let n = if i == 0 || v >= 100.0 { num(v, 0) } else { num(v, 1) };
    format!("{n} {}", tr(units[i]))
}

// Résumé de fichiers: « a.txt (6 o) » ou « 3 fichiers (12 Mo): a, b, c »
pub fn summary(names: &[String], total: u64) -> String {
    match names {
        [] => String::new(),
        [one] => format!("{one} ({})", human(total)),
        many => {
            let shown: Vec<&str> = many.iter().take(3).map(String::as_str).collect();
            let more = if many.len() > 3 { "…" } else { "" };
            format!("{} ({}): {}{more}", trf("%1 files", &[&many.len()]), human(total), shown.join(", "))
        }
    }
}

// Notification simple
pub fn notify(title: &str, body: &str) {
    let _ = Command::new("notify-send").args(["-a", "fili-share", "-i", "emblem-shared", title, body]).status();
}

// Notification avec boutons (notify-send -A): bloque jusqu'à un clic ou la fermeture; renvoie l'identifiant du bouton
pub fn ask(title: &str, body: &str, actions: &[(&str, String)], timeout_ms: u32) -> Option<String> {
    let mut c = Command::new("notify-send");
    c.args(["-a", "fili-share", "-i", "emblem-shared", "-u", "critical", "-w", "-t", &timeout_ms.to_string()]);
    for (id, label) in actions {
        c.arg("-A").arg(format!("{id}={label}"));
    }
    let out = c.arg(title).arg(body).stdin(Stdio::null()).stderr(Stdio::null()).output().ok()?;
    let id = String::from_utf8_lossy(&out.stdout).trim().to_string();
    (!id.is_empty()).then_some(id)
}

// Reçu: notification avec « Afficher » (ouvre le dossier dans Casier)
pub fn announce(title: &str, body: &str, dir: &str) {
    let show = ask_quiet(title, body, &[("show", tr("Show").to_string())], 12000);
    if show.as_deref() == Some("show") {
        let _ = Command::new("fili-file").arg(dir).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).spawn();
    }
}

fn ask_quiet(title: &str, body: &str, actions: &[(&str, String)], timeout_ms: u32) -> Option<String> {
    let mut c = Command::new("notify-send");
    c.args(["-a", "fili-share", "-i", "emblem-shared", "-w", "-t", &timeout_ms.to_string()]);
    for (id, label) in actions {
        c.arg("-A").arg(format!("{id}={label}"));
    }
    let out = c.arg(title).arg(body).stdin(Stdio::null()).stderr(Stdio::null()).output().ok()?;
    let id = String::from_utf8_lossy(&out.stdout).trim().to_string();
    (!id.is_empty()).then_some(id)
}

fn journal_path() -> PathBuf {
    let state = env::var("XDG_STATE_HOME").unwrap_or_else(|_| format!("{}/.local/state", home()));
    PathBuf::from(state).join("filigrane/received.tsv")
}

// Une ligne par fichier reçu: date (s), protocole, expéditeur, chemin, taille. Lu par « fili-share received »
pub fn journal(proto: &str, sender: &str, path: &str, size: u64) {
    let p = journal_path();
    if let Some(d) = p.parent() {
        let _ = fs::create_dir_all(d);
    }
    let clean = |s: &str| s.replace(['\t', '\n'], " ");
    let now = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
    if let Ok(mut f) = fs::OpenOptions::new().create(true).append(true).open(&p) {
        let _ = writeln!(f, "{now}\t{proto}\t{}\t{}\t{size}", clean(sender), clean(path));
    }
}

// Les n dernières lignes du journal en JSON, la plus récente d'abord
pub fn received_json(n: usize) -> String {
    let text = fs::read_to_string(journal_path()).unwrap_or_default();
    let esc = |s: &str| s.replace('\\', "\\\\").replace('"', "\\\"");
    let items: Vec<String> = text
        .lines()
        .rev()
        .filter_map(|l| {
            let f: Vec<&str> = l.split('\t').collect();
            (f.len() == 5).then(|| {
                format!(
                    r#"{{"time":{},"proto":"{}","sender":"{}","path":"{}","size":{}}}"#,
                    f[0].parse::<u64>().unwrap_or(0),
                    esc(f[1]),
                    esc(f[2]),
                    esc(f[3]),
                    f[4].parse::<u64>().unwrap_or(0)
                )
            })
        })
        .take(n)
        .collect();
    format!("[{}]", items.join(","))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sizes() {
        assert_eq!(human(811), "811 B");
        assert_eq!(human(12_345_678), "12.3 MB");
        assert_eq!(human(123_456_789), "123 MB");
        assert_eq!(human(1_500_000_000), "1.5 GB");
    }

    #[test]
    fn summaries() {
        assert_eq!(summary(&["a.txt".into()], 6), "a.txt (6 B)");
        assert_eq!(
            summary(&["a".into(), "b".into(), "c".into(), "d".into()], 4000),
            "4 files (4.0 kB): a, b, c…"
        );
    }

    #[test]
    fn settings_file() {
        let s = parse_settings("# x\nreceive_dir = \"~/Recus\"\nreceive_confirm = \"always\"\nreceive_minutes = 15 # quart d'heure\n");
        assert!(s.dir.ends_with("/Recus"));
        assert!(s.always);
        assert_eq!(s.minutes, 15);
        let d = parse_settings("");
        assert!(!d.always && d.minutes == 0);
    }
}
