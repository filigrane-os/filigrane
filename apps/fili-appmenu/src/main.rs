//! fili-appmenu: menu de l'application active pour la fili-bar (menu global à la Mac OS X).
//!
//! Appelé à la demande par le widget (FiliAppMenu.qml), rien ne reste résident. Le widget sait déjà quelle fenêtre a
//! le focus (Niri.qml); ce programme ne fait que parler à AT-SPI:
//!
//!   fili-appmenu menu PID [TITRE]      barre de menus de l'application (JSON), `null` si elle n'en expose pas
//!   fili-appmenu expand SERVICE CHEMIN sous-menu paresseux (GTK3, Firefox): l'ouvre, lit ses entrées, le referme
//!   fili-appmenu do SERVICE CHEMIN     déclenche une entrée
//!
//! Sortie JSON: {"items":[ENTRÉE...]} ou [ENTRÉE...] pour `expand`, ENTRÉE =
//!   {"label","kind":"item|sub|sep","enabled","check":0|1|2,"svc","path","lazy","children":[...]}
//! Sans accessibilité exportée par l'application (Chrome, foot, Electron sans drapeau...), `menu` rend `null`: le widget
//! affiche alors son menu de repli (dotfiles/config/filigrane/appmenu/).
//!
//! Principe et parcours de l'arbre repris de noctalia-appmenu (yolo-labz, Apache-2.0,
//! https://github.com/yolo-labz/noctalia-appmenu), réécrits en synchrone sans tokio ni serde.
use std::time::{Duration, Instant};
use std::{env, process, thread};

use zbus::blocking::Connection;
use zbus::blocking::connection::Builder;
use zbus::zvariant::{OwnedObjectPath, OwnedValue, Value};

const ACCESSIBLE: &str = "org.a11y.atspi.Accessible";
const ROOT: &str = "/org/a11y/atspi/accessible/root";

// Rôles AT-SPI (atspi-constants.h)
const ROLE_CHECK_MENU_ITEM: u32 = 8;
const ROLE_MENU: u32 = 33;
const ROLE_MENU_BAR: u32 = 34;
const ROLE_RADIO_MENU_ITEM: u32 = 45;
const ROLE_SEPARATOR: u32 = 50;

// États AT-SPI: bits du premier mot
const STATE_CHECKED: u32 = 1 << 4;
const STATE_ENABLED: u32 = 1 << 8;
const STATE_SENSITIVE: u32 = 1 << 24;

/// Profondeur maximale de la recherche de la barre de menus, et de lecture des sous-menus
const FIND_DEPTH: u32 = 8;
const FETCH_DEPTH: u32 = 5;
/// Entrées lues par niveau (borne contre les arbres absurdes)
const MAX_CHILDREN: usize = 200;
/// Temps maximal de la recherche de la barre de menus
const FIND_BUDGET: Duration = Duration::from_millis(1500);
/// Un menu paresseux a besoin d'un instant pour se remplir une fois ouvert
const REALIZE_DELAY: Duration = Duration::from_millis(150);
/// Délai total: une application bloquée ne doit pas figer la barre
const WATCHDOG: Duration = Duration::from_secs(5);

#[derive(Debug, Default, Clone, PartialEq)]
struct Item {
    label: String,
    kind: &'static str,
    enabled: bool,
    check: u8,
    /// Raccourci clavier affiché (« Ctrl+T »), vide s'il n'y en a pas
    keys: String,
    svc: String,
    path: String,
    lazy: bool,
    children: Vec<Item>,
}

struct Atspi {
    c: Connection,
    started: Instant,
}

impl Atspi {
    /// Le bus d'accessibilité est un bus à part, dont la session donne l'adresse
    fn connect() -> zbus::Result<Self> {
        let session = Connection::session()?;
        let reply = session.call_method(
            Some("org.a11y.Bus"),
            "/org/a11y/bus",
            Some("org.a11y.Bus"),
            "GetAddress",
            &(),
        )?;
        let address: String = reply.body().deserialize()?;
        let c = Builder::address(address.as_str())?.build()?;
        Ok(Self { c, started: Instant::now() })
    }

    fn role(&self, svc: &str, path: &str) -> u32 {
        self.c
            .call_method(Some(svc), path, Some(ACCESSIBLE), "GetRole", &())
            .ok()
            .and_then(|m| m.body().deserialize::<u32>().ok())
            .unwrap_or(0)
    }

    fn name(&self, svc: &str, path: &str) -> String {
        self.c
            .call_method(
                Some(svc),
                path,
                Some("org.freedesktop.DBus.Properties"),
                "Get",
                &(ACCESSIBLE, "Name"),
            )
            .ok()
            .and_then(|m| m.body().deserialize::<OwnedValue>().ok())
            .and_then(|v| String::try_from(v).ok())
            .unwrap_or_default()
    }

    /// Premier mot des états (activé, sensible, coché...)
    fn state(&self, svc: &str, path: &str) -> u32 {
        self.c
            .call_method(Some(svc), path, Some(ACCESSIBLE), "GetState", &())
            .ok()
            .and_then(|m| m.body().deserialize::<Vec<u32>>().ok())
            .and_then(|s| s.first().copied())
            .unwrap_or(0)
    }

    fn children(&self, svc: &str, path: &str) -> Vec<(String, String)> {
        self.c
            .call_method(Some(svc), path, Some(ACCESSIBLE), "GetChildren", &())
            .ok()
            .and_then(|m| m.body().deserialize::<Vec<(String, OwnedObjectPath)>>().ok())
            .map(|v| v.into_iter().map(|(s, p)| (s, p.to_string())).collect())
            .unwrap_or_default()
    }

    /// Processus d'un nom du bus d'accessibilité
    fn pid_of(&self, svc: &str) -> Option<u32> {
        self.c
            .call_method(
                Some("org.freedesktop.DBus"),
                "/org/freedesktop/DBus",
                Some("org.freedesktop.DBus"),
                "GetConnectionUnixProcessID",
                &(svc,),
            )
            .ok()
            .and_then(|m| m.body().deserialize::<u32>().ok())
    }

    fn do_action(&self, svc: &str, path: &str) -> bool {
        self.c
            .call_method(Some(svc), path, Some("org.a11y.atspi.Action"), "DoAction", &(0i32,))
            .ok()
            .and_then(|m| m.body().deserialize::<bool>().ok())
            .unwrap_or(false)
    }

    /// Raccourci d'une entrée (Action.GetKeyBinding), texte brut de la boîte à outils
    fn key_binding(&self, svc: &str, path: &str) -> String {
        self.c
            .call_method(Some(svc), path, Some("org.a11y.atspi.Action"), "GetKeyBinding", &(0i32,))
            .ok()
            .and_then(|m| m.body().deserialize::<String>().ok())
            .unwrap_or_default()
    }

    /// Parent d'un nœud (propriété Parent: structure (service, chemin))
    fn parent_of(&self, svc: &str, path: &str) -> Option<(String, String)> {
        let v = self
            .c
            .call_method(Some(svc), path, Some("org.freedesktop.DBus.Properties"), "Get", &(ACCESSIBLE, "Parent"))
            .ok()?
            .body()
            .deserialize::<OwnedValue>()
            .ok()?;
        let st = zbus::zvariant::Structure::try_from(v).ok()?;
        match st.fields() {
            [Value::Str(s), Value::ObjectPath(p)] => Some((s.to_string(), p.to_string())),
            _ => None,
        }
    }

    /// Désélectionne les entrées d'un menu ou d'une barre de menus: referme le menu qu'une expansion a ouvert
    fn clear_selection(&self, svc: &str, path: &str) -> bool {
        self.c
            .call_method(Some(svc), path, Some("org.a11y.atspi.Selection"), "ClearSelection", &())
            .ok()
            .and_then(|m| m.body().deserialize::<bool>().ok())
            .unwrap_or(false)
    }

    /// Fenêtres de l'application `pid`, celle dont le titre ressemble à `title` d'abord
    fn frames(&self, pid: u32, title: &str) -> Vec<(String, String)> {
        let mut frames = Vec::new();
        for (svc, root) in self.children("org.a11y.atspi.Registry", ROOT) {
            if self.pid_of(&svc) != Some(pid) {
                continue;
            }
            for (fsvc, fpath) in self.children(&svc, &root) {
                let name = self.name(&fsvc, &fpath);
                frames.push((rank(&name, title), fsvc, fpath));
            }
        }
        frames.sort_by_key(|f| f.0);
        frames.into_iter().map(|(_, s, p)| (s, p)).collect()
    }

    fn find_menubar(&self, svc: &str, path: &str, depth: u32) -> Option<(String, String)> {
        // Arbre énorme (navigateur avec accessibilité): on abandonne plutôt que de parcourir des milliers de nœuds
        if depth >= FIND_DEPTH || self.started.elapsed() > FIND_BUDGET {
            return None;
        }
        if self.role(svc, path) == ROLE_MENU_BAR {
            return Some((svc.to_owned(), path.to_owned()));
        }
        self.children(svc, path)
            .into_iter()
            .take(MAX_CHILDREN)
            .find_map(|(s, p)| self.find_menubar(&s, &p, depth + 1))
    }

    fn item(&self, svc: &str, path: &str, depth: u32) -> Item {
        let role = self.role(svc, path);
        let state = self.state(svc, path);
        let kids = if depth < FETCH_DEPTH && self.started.elapsed() < WATCHDOG / 2 {
            self.children(svc, path)
        } else {
            Vec::new()
        };
        let mut item = Item {
            label: self.name(svc, path),
            kind: if role == ROLE_SEPARATOR { "sep" } else { "item" },
            enabled: state & STATE_ENABLED != 0 && state & STATE_SENSITIVE != 0,
            check: match role {
                ROLE_CHECK_MENU_ITEM | ROLE_RADIO_MENU_ITEM => 1 + u8::from(state & STATE_CHECKED != 0),
                _ => 0,
            },
            svc: svc.to_owned(),
            path: path.to_owned(),
            ..Item::default()
        };
        if item.kind != "sep" && role != ROLE_MENU_BAR && role != ROLE_MENU {
            item.keys = shortcut(&self.key_binding(svc, path));
        }
        item.children = kids
            .into_iter()
            .take(MAX_CHILDREN)
            .map(|(s, p)| self.item(&s, &p, depth + 1))
            .collect();
        if !item.children.is_empty() || role == ROLE_MENU || role == ROLE_MENU_BAR {
            item.kind = "sub";
        }
        flatten(&mut item);
        item
    }

    /// Sous-menu paresseux: l'ouvrir remplit ses entrées, que l'on lit avant de le refermer. Les chemins des entrées
    /// restent valides une fois refermé.
    fn expand(&self, svc: &str, path: &str) -> Vec<Item> {
        if self.role(svc, path) == 0 {
            return Vec::new();
        }
        self.do_action(svc, path);
        thread::sleep(REALIZE_DELAY);
        let tree = self.item(svc, path, FETCH_DEPTH - 2);
        // Refermer le menu ouvert, seulement s'il s'est bien ouvert. GTK3 ne referme pas par un second clic: on
        // désélectionne dans le parent (les entrées lues restent valides). Repli: bascule du clic (Firefox)
        if !tree.children.is_empty() {
            let closed = self.parent_of(svc, path).is_some_and(|(ps, pp)| self.clear_selection(&ps, &pp));
            if !closed {
                self.do_action(svc, path);
            }
        }
        tree.children
    }
}

/// Raccourci lisible d'une entrée. GTK: « mnémonique;chemin;accélérateur » avec un accélérateur « <Primary><Shift>n »;
/// Qt: les séquences « Ctrl+N » séparées par « ; », on garde la première.
fn shortcut(raw: &str) -> String {
    let fields: Vec<&str> = raw.split(';').collect();
    if fields.len() == 3 && (fields[0].chars().count() <= 1 || fields[1].contains('<')) {
        gtk_accel(fields[2])
    } else {
        fields[0].trim().to_string()
    }
}

/// « <Primary><Shift>n » -> « Ctrl+Shift+N », « space » -> « Space », « F3 » -> « F3 »
fn gtk_accel(acc: &str) -> String {
    let mut parts: Vec<String> = Vec::new();
    let mut rest = acc;
    while let Some(tail) = rest.strip_prefix('<') {
        let Some(end) = tail.find('>') else { return String::new() };
        parts.push(
            match &tail[..end] {
                "Primary" | "Control" | "Ctrl" => "Ctrl",
                "Alt" | "Mod1" => "Alt",
                "Shift" => "Shift",
                "Super" | "Mod4" => "Super",
                "Meta" => "Meta",
                other => other,
            }
            .to_string(),
        );
        rest = &tail[end + 1..];
    }
    if rest.is_empty() {
        return String::new();
    }
    let mut chars = rest.chars();
    let first: String = chars.next().map(|c| c.to_uppercase().collect()).unwrap_or_default();
    parts.push(first + chars.as_str());
    parts.join("+")
}

/// Qt enveloppe le contenu de chaque menu dans un nœud MENU sans nom: on le retire
fn flatten(item: &mut Item) {
    if item.children.len() == 1 && item.children[0].label.is_empty() && !item.children[0].children.is_empty() {
        item.children = std::mem::take(&mut item.children[0].children);
    }
}

/// Plus petit = meilleure fenêtre pour le titre demandé (identique, puis inclus dans l'autre, puis le reste)
fn rank(frame: &str, title: &str) -> u8 {
    if title.is_empty() || frame.is_empty() {
        2
    } else if frame == title {
        0
    } else if title.contains(frame) || frame.contains(title) {
        1
    } else {
        2
    }
}

fn json_str(s: &str, out: &mut String) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
}

fn json_items(items: &[Item], out: &mut String) {
    out.push('[');
    for (i, it) in items.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        out.push_str("{\"label\":");
        json_str(&it.label, out);
        out.push_str(&format!(
            ",\"kind\":\"{}\",\"enabled\":{},\"check\":{},\"lazy\":{},\"keys\":",
            it.kind, it.enabled, it.check, it.lazy
        ));
        json_str(&it.keys, out);
        out.push_str(",\"svc\":");
        json_str(&it.svc, out);
        out.push_str(",\"path\":");
        json_str(&it.path, out);
        out.push_str(",\"children\":");
        json_items(&it.children, out);
        out.push('}');
    }
    out.push(']');
}

fn menu(a: &Atspi, pid: u32, title: &str) -> Option<Vec<Item>> {
    for (svc, frame) in a.frames(pid, title) {
        let Some((bsvc, bpath)) = a.find_menubar(&svc, &frame, 0) else {
            continue;
        };
        let mut bar = a.item(&bsvc, &bpath, 0);
        // Un menu du premier niveau sans entrée est paresseux (GTK3, Firefox): le widget demandera `expand`
        for top in &mut bar.children {
            top.lazy = top.children.is_empty() && top.kind != "sep";
        }
        let tops: Vec<Item> = bar.children.into_iter().filter(|t| !t.label.is_empty()).collect();
        if !tops.is_empty() {
            return Some(tops);
        }
    }
    None
}

fn usage() -> ! {
    eprintln!("usage: fili-appmenu menu PID [TITRE] | expand SERVICE CHEMIN | do SERVICE CHEMIN");
    process::exit(2)
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let Some(cmd) = args.first() else { usage() };
    // Une application AT-SPI bloquée ne doit pas bloquer la barre
    thread::spawn(|| {
        thread::sleep(WATCHDOG);
        process::exit(3);
    });
    let a = match Atspi::connect() {
        Ok(a) => a,
        Err(e) => {
            eprintln!("fili-appmenu: bus d'accessibilité injoignable: {e}");
            println!("null");
            return;
        }
    };
    let mut out = String::new();
    match (cmd.as_str(), args.len()) {
        ("menu", 2 | 3) => {
            let pid: u32 = args[1].parse().unwrap_or_else(|_| usage());
            match menu(&a, pid, args.get(2).map_or("", String::as_str)) {
                Some(items) => {
                    out.push_str("{\"items\":");
                    json_items(&items, &mut out);
                    out.push('}');
                }
                None => out.push_str("null"),
            }
        }
        ("expand", 3) => json_items(&a.expand(&args[1], &args[2]), &mut out),
        ("do", 3) => {
            if !a.do_action(&args[1], &args[2]) {
                eprintln!("fili-appmenu: entrée introuvable ou non actionnable");
                process::exit(1);
            }
        }
        _ => usage(),
    }
    if !out.is_empty() {
        println!("{out}");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn json_echappe() {
        let mut s = String::new();
        json_str("a\"b\\c\nd\u{1}é", &mut s);
        assert_eq!(s, "\"a\\\"b\\\\c\\nd\\u0001é\"");
    }

    #[test]
    fn enveloppe_qt_retiree() {
        let leaf = Item { label: "Ouvrir".into(), kind: "item", ..Item::default() };
        let wrapper = Item { kind: "sub", children: vec![leaf.clone()], ..Item::default() };
        let mut file = Item { label: "Fichier".into(), kind: "sub", children: vec![wrapper], ..Item::default() };
        flatten(&mut file);
        assert_eq!(file.children, vec![leaf]);
    }

    #[test]
    fn enveloppe_vide_gardee() {
        let wrapper = Item { kind: "sub", ..Item::default() };
        let mut file = Item { label: "Fichier".into(), kind: "sub", children: vec![wrapper.clone()], ..Item::default() };
        flatten(&mut file);
        assert_eq!(file.children, vec![wrapper]);
    }

    #[test]
    fn fenetre_choisie_par_titre() {
        assert_eq!(rank("tmp - Thunar", "tmp - Thunar"), 0);
        assert_eq!(rank("Thunar", "tmp - Thunar"), 1);
        assert_eq!(rank("Autre", "tmp - Thunar"), 2);
        assert_eq!(rank("", "tmp - Thunar"), 2);
    }

    #[test]
    fn json_arbre() {
        let it = Item { label: "A".into(), kind: "item", enabled: true, svc: ":1.2".into(), path: "/p".into(), ..Item::default() };
        let mut s = String::new();
        json_items(&[it], &mut s);
        assert_eq!(s, "[{\"label\":\"A\",\"kind\":\"item\",\"enabled\":true,\"check\":0,\"lazy\":false,\"keys\":\"\",\"svc\":\":1.2\",\"path\":\"/p\",\"children\":[]}]");
    }

    #[test]
    fn raccourcis_gtk() {
        assert_eq!(shortcut("t;<Alt>f:t;<Primary>t"), "Ctrl+T");
        assert_eq!(shortcut("f;<Alt>f:f;<Primary><Shift>n"), "Ctrl+Shift+N");
        assert_eq!(shortcut(";;space"), "Space");
        assert_eq!(shortcut("p;<Alt>v:p;F3"), "F3");
        assert_eq!(shortcut("d;<Alt>f:d;"), "");
        assert_eq!(shortcut("<Alt>f;<Alt>f;"), "");
        assert_eq!(shortcut("c;<Alt>e:c;<Control><Alt>Delete"), "Ctrl+Alt+Delete");
        assert_eq!(shortcut(""), "");
    }

    #[test]
    fn raccourcis_qt() {
        assert_eq!(shortcut("Ctrl+N"), "Ctrl+N");
        assert_eq!(shortcut("Ctrl+Shift+N;Ctrl+Alt+N"), "Ctrl+Shift+N");
    }
}
