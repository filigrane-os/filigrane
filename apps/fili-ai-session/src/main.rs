// Sessions de l'agent IA pour la fili-bar (module IA): état de chaque session Claude Code, fenêtre niri où elle tourne,
// contexte, coût et limites du forfait; notification et icône mise en avant quand l'agent attend l'utilisateur.
//
//   fili-ai-session hook        hook de Claude Code (JSON sur l'entrée): SessionStart, UserPromptSubmit, PostToolUse,
//                               Notification, Stop, SessionEnd (hooks de ~/.claude/settings.json)
//   fili-ai-session statusline  status line de Claude Code (JSON sur l'entrée): note contexte, coût et limites, puis
//                               écrit la ligne (modèle, effort, dossier, branche, remplissage du contexte)
//   fili-ai-session focus [ID]  clic sur la barre: la session qui attend (sinon la dernière; encore: la suivante) prend
//                               le focus; aucune session avec une fenêtre: fili-ai comme Mod+Y
//   fili-ai-session new         nouvelle session (comme Mod+Y)
//   fili-ai-session seen ID     l'utilisateur a regardé la session ID (sa fenêtre a le focus): plus de mise en avant
//
// État: $XDG_RUNTIME_DIR/fili-ai/state.json (tmpfs) {sessions: [...], limits}, lu par la fili-bar (BarState.qml,
// inotify), réécrit seulement quand il change; un seul écrivain à la fois (verrou). États: working, waiting
// (permission ou question), done (tour fini sans que la fenêtre ait le focus), idle. Une session dont l'agent est mort
// disparaît. Rien n'est lu dans les identifiants de l'agent: les limites viennent de la status line de Claude Code.
// Un processus par événement, sans jq ni niri msg (socket de niri en direct): ~1 ms.
#[allow(dead_code)]
#[path = "../../bar-stats/src/i18n.rs"]
mod i18n;
mod json;

use i18n::{tr, trf};
use json::Json;

use std::{
    env,
    fs::{self, File, OpenOptions},
    io::{BufRead, BufReader, Read, Write},
    os::unix::net::UnixStream,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

fn now() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0)
}

// ───── niri (socket IPC: une requête JSON par ligne, une réponse {"Ok": ...}) ─────

fn niri(req: &str) -> Option<Json> {
    let mut s = UnixStream::connect(env::var_os("NIRI_SOCKET")?).ok()?;
    s.set_read_timeout(Some(Duration::from_millis(500))).ok()?;
    s.write_all(format!("{req}\n").as_bytes()).ok()?;
    let mut line = String::new();
    BufReader::new(s).read_line(&mut line).ok()?;
    let r = Json::parse(line.trim())?;
    let ok = r.get("Ok");
    (!ok.is_null()).then(|| ok.clone())
}

fn focused_window() -> Option<i64> {
    niri("\"FocusedWindow\"")?.get("FocusedWindow").get("id").int()
}

// ───── processus ─────

fn parent(pid: i64) -> Option<i64> {
    let stat = fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
    // "pid (comm) état ppid ...": comm peut contenir des espaces
    stat.rsplit_once(')')?.1.split_whitespace().nth(1)?.parse().ok()
}

// PID de l'agent: premier ancêtre nommé claude (hooks et status line sont ses enfants)
fn agent_pid() -> Option<i64> {
    let mut p = std::os::unix::process::parent_id() as i64;
    while p > 1 {
        if fs::read_to_string(format!("/proc/{p}/comm")).ok()?.trim() == "claude" {
            return Some(p);
        }
        p = parent(p)?;
    }
    None
}

// Fenêtre niri d'un processus: le premier ancêtre qui en possède une (foot lancé par Mod+Y)
fn window_of(pid: i64) -> Option<i64> {
    let wins = niri("\"Windows\"")?;
    let wins: Vec<(i64, i64)> = match wins.get("Windows") {
        Json::Arr(a) => a.iter().filter_map(|w| Some((w.get("pid").int()?, w.get("id").int()?))).collect(),
        _ => return None,
    };
    let mut p = pid;
    while p > 1 {
        if let Some((_, id)) = wins.iter().find(|(wp, _)| *wp == p) {
            return Some(*id);
        }
        p = parent(p)?;
    }
    None
}

fn alive(pid: i64) -> bool {
    Path::new(&format!("/proc/{pid}")).exists()
}

// ───── état ─────

struct Store {
    path: PathBuf,
    _lock: File,
    old: String,
    state: Json,
}

impl Store {
    // Verrouille et lit l'état (vide s'il manque ou s'il est illisible)
    fn open() -> Store {
        let dir = PathBuf::from(env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".into())).join("fili-ai");
        let _ = fs::create_dir_all(&dir);
        let lock = OpenOptions::new().create(true).truncate(false).write(true).open(dir.join("lock")).expect("lock");
        let _ = lock.lock();
        let path = dir.join("state.json");
        let old = fs::read_to_string(&path).unwrap_or_default();
        let mut state = Json::parse(old.trim()).unwrap_or(Json::Null);
        if !matches!(state.get("sessions"), Json::Arr(_)) {
            state.set("sessions", Json::Arr(Vec::new()));
        }
        Store { path, _lock: lock, old, state }
    }

    fn sessions(&mut self) -> &mut Vec<Json> {
        match &mut self.state {
            Json::Obj(m) => match m.iter_mut().find(|(k, _)| k == "sessions") {
                Some((_, Json::Arr(a))) => a,
                _ => unreachable!(),
            },
            _ => unreachable!(),
        }
    }

    fn find(&mut self, id: &str) -> Option<&mut Json> {
        self.sessions().iter_mut().find(|s| s.get("id").str() == Some(id))
    }

    // Session ID, créée au besoin; PID de l'agent et fenêtre remplis tant qu'ils manquent
    fn session(&mut self, id: &str) -> &mut Json {
        if self.find(id).is_none() {
            let mut s = Json::obj();
            s.set("id", id);
            s.set("agent", "claude");
            s.set("pid", agent_pid());
            self.sessions().push(s);
        }
        let s = self.find(id).expect("session");
        if s.get("window").is_null()
            && let Some(w) = s.get("pid").int().and_then(window_of)
        {
            s.set("window", w);
        }
        s
    }

    // Retire les sessions dont l'agent est mort, trie (la plus récente d'abord) et réécrit le fichier s'il a changé
    fn save(&mut self) {
        let day = now() - 86400;
        let s = self.sessions();
        s.retain(|s| match s.get("pid").int() {
            Some(p) => alive(p),
            None => s.get("updated").int().unwrap_or(0) > day,
        });
        s.sort_by_key(|s| -s.get("updated").int().unwrap_or(0));
        let text = format!("{}\n", self.state);
        if text != self.old {
            // Réécrit en place (la barre surveille ce fichier); une lecture à moitié écrite est ignorée par BarState
            let _ = fs::write(&self.path, &text);
            self.old = text;
        }
    }
}

// ───── hooks ─────

struct Notice {
    id: String,
    urgency: &'static str,
    summary: String,
    body: String,
}

fn project(cwd: &str) -> String {
    Path::new(cwd).file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_else(|| "~".into())
}

// Applique un événement de hook à l'état; focused: fenêtre qui a le focus (demandée seulement quand il le faut)
fn apply_hook(st: &mut Store, input: &Json, t: i64, focused: impl Fn() -> Option<i64>) -> Option<Notice> {
    let id = input.get("session_id").str()?.to_string();
    let event = input.get("hook_event_name").str().unwrap_or("");
    let cwd = input.get("cwd").str().unwrap_or("").to_string();
    if event == "SessionEnd" {
        st.sessions().retain(|s| s.get("id").str() != Some(&id));
        return None;
    }
    if event == "Notification"
        && !matches!(input.get("notification_type").str(), Some("permission_prompt" | "elicitation_dialog"))
    {
        return None;
    }
    let s = st.session(&id);
    if !cwd.is_empty() {
        s.set("cwd", cwd.as_str());
    }
    let set = |s: &mut Json, state: &str, attention: bool, message: &str| {
        s.set("state", state);
        s.set("attention", attention);
        s.set("message", message);
        s.set("updated", t);
    };
    match event {
        "SessionStart" => {
            set(s, "idle", false, "");
            s.set("started", t);
        }
        "UserPromptSubmit" => set(s, "working", false, ""),
        // Permission accordée (ou inutile): de nouveau au travail; inchangé sinon (rien à écrire)
        "PostToolUse" if s.get("state").str() != Some("working") => set(s, "working", false, ""),
        "Notification" => {
            let msg = input.get("message").str().unwrap_or("").to_string();
            let win = s.get("window").int();
            // L'utilisateur regarde la session: icône calme, pas de notification
            let watched = win.is_some() && win == focused();
            set(s, "waiting", !watched, &msg);
            if !watched {
                let body = if msg.is_empty() { tr("A question is waiting").to_string() } else { msg };
                return Some(Notice {
                    id,
                    urgency: "critical",
                    summary: tr("Claude Code needs you").into(),
                    body: format!("{body} ({})", project(&cwd)),
                });
            }
        }
        "Stop" => {
            let win = s.get("window").int();
            if win.is_some() && win == focused() {
                set(s, "idle", false, "");
            } else {
                set(s, "done", true, "");
                let name = project(s.get("cwd").str().unwrap_or(&cwd));
                return Some(Notice {
                    id,
                    urgency: "normal",
                    summary: tr("Claude Code has finished").into(),
                    body: trf("Your turn (%1)", &[&name]),
                });
            }
        }
        _ => {}
    }
    None
}

// Notification; son clic donne le focus à la fenêtre de la session (notify-send attend la réponse, détaché)
fn notify(n: Notice) {
    let exe = env::current_exe().map(|p| p.to_string_lossy().into_owned()).unwrap_or_else(|_| "fili-ai-session".into());
    let _ = Command::new("setsid")
        .args(["-f", "sh", "-c"])
        .arg(r#"r="$(notify-send -a fili-ai -i utilities-terminal -u "$2" -A default="$5" "$3" "$4")" && [ "$r" = default ] && exec "$0" focus "$1""#)
        .args([exe.as_str(), &n.id, n.urgency, &n.summary, &n.body, tr("Open")])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

// ───── status line ─────

// Note contexte, coût, modèle et limites du forfait (gardées après la session, heure du relevé mise à jour quand
// elles changent ou toutes les 5 min)
fn apply_status(st: &mut Store, input: &Json, t: i64) {
    let Some(id) = input.get("session_id").str() else { return };
    let s = st.session(id);
    for (key, path) in [
        ("model", &["model", "display_name"][..]),
        ("ctx", &["context_window", "used_percentage"]),
        ("ctxSize", &["context_window", "context_window_size"]),
        ("cost", &["cost", "total_cost_usd"]),
    ] {
        let v = input.path(path);
        if !v.is_null() {
            s.set(key, v);
        }
    }
    if s.get("cwd").str().unwrap_or("").is_empty()
        && let Some(d) = input.path(&["workspace", "current_dir"]).str()
    {
        s.set("cwd", d);
    }
    if s.get("updated").is_null() {
        s.set("updated", t);
    }
    let rl = input.get("rate_limits");
    if !rl.is_null() {
        let mut old = st.state.get("limits").clone();
        let seen = old.get("seen").int().unwrap_or(0);
        old.remove("seen");
        if &old != rl || t - seen >= 300 {
            let mut l = rl.clone();
            l.set("seen", t);
            st.state.set("limits", l);
        }
    }
}

// Branche git du dossier (lue dans .git/HEAD, sans lancer git), sinon le commit abrégé
fn branch(dir: &str) -> Option<String> {
    let mut d = Path::new(dir);
    loop {
        let g = d.join(".git");
        let gitdir = if g.is_file() {
            // Worktree ou sous-module: "gitdir: CHEMIN"
            let p = fs::read_to_string(&g).ok()?.strip_prefix("gitdir:")?.trim().to_string();
            d.join(p)
        } else {
            g
        };
        if let Ok(head) = fs::read_to_string(gitdir.join("HEAD")) {
            let head = head.trim();
            return Some(match head.strip_prefix("ref: refs/heads/") {
                Some(b) => b.to_string(),
                None => head.chars().take(7).collect(),
            });
        }
        d = d.parent()?;
    }
}

fn kilo(n: i64) -> String {
    if n >= 1000 { format!("{}k", (n as f64 / 1000.0).round() as i64) } else { n.to_string() }
}

// Ligne de la status line: modèle, effort, dossier, branche, remplissage du contexte (barre de 10 cases)
fn status_line(input: &Json) -> String {
    let model = input.path(&["model", "display_name"]).str().unwrap_or("?");
    let effort = input.path(&["effort", "level"]).str().unwrap_or("");
    let dir = input.path(&["workspace", "current_dir"]).str().or(input.get("cwd").str()).unwrap_or(".");
    let size = input.path(&["context_window", "context_window_size"]).int().unwrap_or(200_000);
    let pct = input.path(&["context_window", "used_percentage"]).num().unwrap_or(0.0).max(0.0) as i64;
    let used = size * pct / 100;
    let color = if pct >= 80 {
        31
    } else if pct >= 50 {
        33
    } else {
        32
    };
    let filled = (pct / 10).min(10) as usize;
    let bar = "█".repeat(filled) + &"░".repeat(10 - filled);
    let home = env::var("HOME").unwrap_or_default();
    let shown = match dir.strip_prefix(&home) {
        Some(rest) if !home.is_empty() => format!("~{rest}"),
        _ => dir.to_string(),
    };
    let sep = " \x1b[90m│\x1b[0m ";
    let mut out = format!("\x1b[36m{model}\x1b[0m");
    if !effort.is_empty() {
        out += &format!(" \x1b[33m{effort}\x1b[0m");
    }
    out += &format!("{sep}\x1b[34m{shown}\x1b[0m");
    if let Some(b) = branch(dir) {
        out += &format!("{sep}\x1b[35m {b}\x1b[0m");
    }
    out += &format!("{sep}\x1b[{color}m{bar} {pct}%\x1b[0m \x1b[90m({}/{})\x1b[0m", kilo(used), kilo(size));
    out
}

// ───── clic sur la barre ─────

// Session à montrer: ID demandé, sinon celles qui attendent d'abord puis la plus récente; celle qui a déjà le focus
// passe la main à la suivante. Seulement les sessions qui ont une fenêtre: (id, fenêtre)
fn pick(state: &Json, want: Option<&str>, focused: Option<i64>) -> Option<(String, i64)> {
    let Json::Arr(all) = state.get("sessions") else { return None };
    let with: Vec<&Json> = all.iter().filter(|s| s.get("window").int().is_some()).collect();
    let order: Vec<&Json> = with
        .iter()
        .filter(|s| s.get("attention").truthy())
        .chain(with.iter().filter(|s| !s.get("attention").truthy()))
        .copied()
        .collect();
    let chosen = match want {
        Some(id) => order.iter().find(|s| s.get("id").str() == Some(id)).copied(),
        None => match order.iter().position(|s| s.get("window").int() == focused && focused.is_some()) {
            Some(i) => order.get((i + 1) % order.len()).copied(),
            None => order.first().copied(),
        },
    }?;
    Some((chosen.get("id").str()?.to_string(), chosen.get("window").int()?))
}

fn seen(st: &mut Store, id: &str) {
    if let Some(s) = st.find(id) {
        s.set("attention", false);
        if s.get("state").str() == Some("done") {
            s.set("state", "idle");
        }
    }
}

fn launch() {
    let _ = Command::new("setsid")
        .args(["-f", "foot", "-e", "bash", "-lc", "exec ~/.local/bin/fili-ai"])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

fn stdin_json() -> Json {
    let mut s = String::new();
    let _ = std::io::stdin().read_to_string(&mut s);
    Json::parse(s.trim()).unwrap_or(Json::Null)
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("hook") => {
            let input = stdin_json();
            let mut st = Store::open();
            let notice = apply_hook(&mut st, &input, now(), focused_window);
            st.save();
            drop(st);
            if let Some(n) = notice {
                notify(n);
            }
        }
        Some("statusline") => {
            let input = stdin_json();
            {
                let mut st = Store::open();
                apply_status(&mut st, &input, now());
                st.save();
            }
            print!("{}", status_line(&input));
        }
        Some("focus") => {
            let want = args.get(1).map(String::as_str);
            let mut st = Store::open();
            st.save();
            match pick(&st.state, want, focused_window()) {
                Some((id, win)) => {
                    seen(&mut st, &id);
                    st.save();
                    drop(st);
                    niri(&format!("{{\"Action\":{{\"FocusWindow\":{{\"id\":{win}}}}}}}"));
                }
                None if want.is_none() => launch(),
                None => {}
            }
        }
        Some("new") => launch(),
        Some("seen") if args.len() > 1 => {
            let mut st = Store::open();
            seen(&mut st, &args[1]);
            st.save();
        }
        _ => {
            eprintln!("usage: fili-ai-session hook|statusline|focus [ID]|new|seen ID");
            std::process::exit(1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn store(state: &str) -> Store {
        let dir = env::temp_dir().join(format!("fili-ai-test-{}-{}", std::process::id(), now()));
        fs::create_dir_all(&dir).unwrap();
        Store {
            path: dir.join("state.json"),
            _lock: File::create(dir.join("lock")).unwrap(),
            old: String::new(),
            state: Json::parse(state).unwrap(),
        }
    }
    fn hook(st: &mut Store, s: &str, focused: Option<i64>) -> Option<Notice> {
        apply_hook(st, &Json::parse(s).unwrap(), 100, || focused)
    }
    fn state_of(st: &mut Store, id: &str) -> (String, bool) {
        let s = st.find(id).unwrap();
        (s.get("state").str().unwrap().to_string(), s.get("attention").truthy())
    }

    #[test]
    fn waiting_then_working() {
        let mut st = store(r#"{"sessions":[{"id":"a","pid":1,"window":7,"state":"working"}]}"#);
        let n = hook(
            &mut st,
            r#"{"hook_event_name":"Notification","session_id":"a","notification_type":"permission_prompt","message":"Bash?","cwd":"/x/proj"}"#,
            Some(3),
        );
        assert_eq!(n.map(|n| n.body), Some("Bash? (proj)".into()));
        assert_eq!(state_of(&mut st, "a"), ("waiting".into(), true));
        assert!(hook(&mut st, r#"{"hook_event_name":"PostToolUse","session_id":"a"}"#, None).is_none());
        assert_eq!(state_of(&mut st, "a"), ("working".into(), false));
    }

    #[test]
    fn watched_session_stays_calm() {
        let mut st = store(r#"{"sessions":[{"id":"a","pid":1,"window":7,"state":"working"}]}"#);
        let n = hook(
            &mut st,
            r#"{"hook_event_name":"Notification","session_id":"a","notification_type":"permission_prompt"}"#,
            Some(7),
        );
        assert!(n.is_none());
        assert_eq!(state_of(&mut st, "a"), ("waiting".into(), false));
        assert!(hook(&mut st, r#"{"hook_event_name":"Stop","session_id":"a"}"#, Some(7)).is_none());
        assert_eq!(state_of(&mut st, "a"), ("idle".into(), false));
        assert!(hook(&mut st, r#"{"hook_event_name":"Stop","session_id":"a"}"#, Some(3)).is_some());
        assert_eq!(state_of(&mut st, "a"), ("done".into(), true));
        assert!(
            hook(&mut st, r#"{"hook_event_name":"Notification","session_id":"a","notification_type":"idle_prompt"}"#, None)
                .is_none()
        );
        hook(&mut st, r#"{"hook_event_name":"SessionEnd","session_id":"a"}"#, None);
        assert!(st.find("a").is_none());
    }

    #[test]
    fn status_keeps_limits() {
        let mut st = store(r#"{"sessions":[{"id":"a","pid":1,"window":7}]}"#);
        let input = Json::parse(r#"{"session_id":"a","model":{"display_name":"Opus"},"context_window":{"used_percentage":42.5},"cost":{"total_cost_usd":1.5},"rate_limits":{"five_hour":{"used_percentage":34,"resets_at":5}}}"#).unwrap();
        apply_status(&mut st, &input, 1000);
        apply_status(&mut st, &input, 1100);
        assert_eq!(st.state.path(&["limits", "seen"]).int(), Some(1000));
        apply_status(&mut st, &input, 1300);
        assert_eq!(st.state.path(&["limits", "seen"]).int(), Some(1300));
        let s = st.find("a").unwrap();
        assert_eq!((s.get("model").str(), s.get("ctx").num(), s.get("cost").num()), (Some("Opus"), Some(42.5), Some(1.5)));
    }

    #[test]
    fn pick_order() {
        let st =
            Json::parse(r#"{"sessions":[{"id":"a","window":1},{"id":"b","window":2,"attention":true},{"id":"c"}]}"#).unwrap();
        assert_eq!(pick(&st, None, None), Some(("b".into(), 2)));
        assert_eq!(pick(&st, None, Some(2)), Some(("a".into(), 1)));
        assert_eq!(pick(&st, None, Some(1)), Some(("b".into(), 2)));
        assert_eq!(pick(&st, Some("c"), None), None);
        assert_eq!(pick(&Json::parse(r#"{"sessions":[]}"#).unwrap(), None, None), None);
    }

    #[test]
    fn line() {
        let l = status_line(&Json::parse(r#"{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/"},"context_window":{"used_percentage":55.9,"context_window_size":200000}}"#).unwrap());
        assert!(l.contains("Opus") && l.contains("\x1b[33m█████░░░░░ 55%") && l.contains("(110k/200k)"), "{l:?}");
    }
}
