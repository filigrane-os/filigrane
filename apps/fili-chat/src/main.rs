// fili-chat: le chat de Filigrane. Un démon garde les sessions de l'agent (Claude Code en mode flux, un processus par
// session ouverte) pour que la conversation reste quand le tiroir (FiliChat.qml) se cache; le tiroir s'y connecte.
//
//   fili-chat daemon          démon (lancé par le tiroir au premier affichage; il s'arrête sans client ni agent)
//   fili-chat toggle          Mod+Y: note l'application active (fili-context), puis affiche ou cache le tiroir
//   fili-chat status          sessions en JSON (le démon doit tourner)
//   fili-chat send ID TEXTE   message à une session, réponse affichée sur la sortie (essais en terminal)
//
// Socket: $XDG_RUNTIME_DIR/fili-chat/sock, une ligne JSON par message.
//   client -> démon: {"op":"new"} {"op":"open","id"} {"op":"send","id","text"} {"op":"stop","id"}
//                    {"op":"rename","id","title"} {"op":"delete","id"}
//   démon -> clients: {"ev":"sessions","sessions":[{id,title,state,updated}]} {"ev":"history","id","items":[...]}
//                    {"ev":"msg","id","role":"user"|"assistant","text"} {"ev":"tool","id","name","summary"}
//                    {"ev":"delta","id","text"} (texte en cours, non gardé) {"ev":"state","id","state"}
//                    {"ev":"note","id","code"} (interrupted, error:…)
// Historique: ~/.local/state/filigrane/chat/<id>.jsonl (msg et tool), index sessions.json. Le contexte de l'agent
// est celui de Claude Code (`--resume ID`): un agent arrêté (inactif, redémarrage) reprend où il était.
// Réglages: ~/.config/filigrane/ai.env (FILI_AI_MODEL, FILI_AI_ARGS, FILIGRANE_DIR), prompt: agents/chat-prompt.md.
#[path = "../../fili-ai-session/src/json.rs"]
#[allow(dead_code)]
mod json;

use json::Json;
use std::{
    collections::HashMap,
    env,
    fs::{self, OpenOptions},
    io::{BufRead, BufReader, Write},
    os::unix::net::{UnixListener, UnixStream},
    path::PathBuf,
    process::{Child, ChildStdin, Command, Stdio},
    sync::Mutex,
    thread,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

const IDLE_KILL: i64 = 30 * 60; // un agent inactif depuis ce délai est arrêté (la session se reprend seule)
const IDLE_EXIT: i64 = 120; // sans client ni agent depuis ce délai, le démon s'arrête

fn now() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0)
}
fn home() -> String {
    env::var("HOME").unwrap_or_default()
}
fn runtime_dir() -> PathBuf {
    PathBuf::from(env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".into())).join("fili-chat")
}
fn sock_path() -> PathBuf {
    runtime_dir().join("sock")
}
fn state_dir() -> PathBuf {
    let s = env::var("XDG_STATE_HOME").unwrap_or_else(|_| format!("{}/.local/state", home()));
    PathBuf::from(s).join("filigrane")
}
fn chat_dir() -> PathBuf {
    state_dir().join("chat")
}

// ───── réglages (ai.env) ─────
struct Conf {
    model: String,
    args: Vec<String>,
    dir: String,
}

fn conf() -> Conf {
    let cfg = env::var("XDG_CONFIG_HOME").unwrap_or_else(|_| format!("{}/.config", home()));
    let text = fs::read_to_string(format!("{cfg}/filigrane/ai.env")).unwrap_or_default();
    let mut kv: HashMap<String, String> = HashMap::new();
    for l in text.lines() {
        if let Some((k, v)) = l.split_once('=') {
            kv.insert(k.trim().to_string(), unquote(v.trim()));
        }
    }
    let get = |k: &str| kv.get(k).cloned().unwrap_or_default();
    let mut dir = get("FILIGRANE_DIR");
    if dir.is_empty() {
        dir = format!("{}/Projects/filigrane", home());
    }
    // Comme fili-ai: FILI_AI_ARGS remplace les options de permission par défaut
    let args: Vec<String> = get("FILI_AI_ARGS")
        .split_whitespace()
        .map(|a| if let Some(r) = a.strip_prefix('~') { format!("{}{r}", home()) } else { a.to_string() })
        .collect();
    Conf { model: get("FILI_AI_MODEL"), args, dir }
}

// Valeur d'un fichier shell: 'abc', "abc" ou abc\ def
fn unquote(v: &str) -> String {
    if v.len() >= 2 && ((v.starts_with('\'') && v.ends_with('\'')) || (v.starts_with('"') && v.ends_with('"'))) {
        return v[1..v.len() - 1].to_string();
    }
    let mut out = String::new();
    let mut it = v.chars();
    while let Some(c) = it.next() {
        if c == '\\' {
            if let Some(n) = it.next() {
                out.push(n);
            }
        } else {
            out.push(c);
        }
    }
    out
}

// ───── état ─────
struct Session {
    id: String,
    title: String,
    state: &'static str, // idle | working
    updated: i64,
    started: bool, // l'agent a déjà reçu un message: reprise avec --resume
    child: Option<Child>,
    stdin: Option<ChildStdin>,
    epoch: u64, // numéro du processus courant (la fin d'un ancien processus est ignorée)
}

#[derive(Default)]
struct Daemon {
    sessions: Vec<Session>,
    clients: Vec<(u64, UnixStream)>,
    next_client: u64,
    next_epoch: u64,
    quiet_since: i64,
}

static D: Mutex<Option<Daemon>> = Mutex::new(None);

fn with<R>(f: impl FnOnce(&mut Daemon) -> R) -> R {
    let mut g = D.lock().unwrap_or_else(|e| e.into_inner());
    f(g.get_or_insert_with(Daemon::default))
}

impl Daemon {
    fn send_to(&mut self, client: u64, line: &str) {
        self.clients.retain_mut(|(id, s)| *id != client || writeln!(s, "{line}").is_ok());
    }
    fn broadcast(&mut self, line: &str) {
        self.clients.retain_mut(|(_, s)| writeln!(s, "{line}").is_ok());
    }
    fn session(&mut self, id: &str) -> Option<&mut Session> {
        self.sessions.iter_mut().find(|s| s.id == id)
    }
    fn sessions_json(&self) -> Json {
        let mut list: Vec<&Session> = self.sessions.iter().collect();
        list.sort_by_key(|s| -s.updated);
        let mut o = Json::obj();
        o.set("ev", "sessions");
        o.set(
            "sessions",
            Json::Arr(
                list.iter()
                    .map(|s| {
                        let mut j = Json::obj();
                        j.set("id", s.id.as_str());
                        j.set("title", s.title.as_str());
                        j.set("state", s.state);
                        j.set("updated", s.updated);
                        j
                    })
                    .collect(),
            ),
        );
        o
    }
    fn publish_sessions(&mut self) {
        let line = self.sessions_json().to_string();
        self.broadcast(&line);
        save_index(self);
    }
    fn alive(&self) -> bool {
        self.sessions.iter().any(|s| s.child.is_some())
    }
}

fn index_path() -> PathBuf {
    chat_dir().join("sessions.json")
}

fn save_index(d: &Daemon) {
    let arr = Json::Arr(
        d.sessions
            .iter()
            .map(|s| {
                let mut j = Json::obj();
                j.set("id", s.id.as_str());
                j.set("title", s.title.as_str());
                j.set("updated", s.updated);
                j.set("started", s.started);
                j
            })
            .collect(),
    );
    let tmp = chat_dir().join("sessions.json.tmp");
    if fs::write(&tmp, arr.to_string()).is_ok() {
        let _ = fs::rename(&tmp, index_path());
    }
}

fn load_index() -> Vec<Session> {
    let text = fs::read_to_string(index_path()).unwrap_or_default();
    let Some(Json::Arr(a)) = Json::parse(&text) else { return Vec::new() };
    a.iter()
        .filter_map(|j| {
            Some(Session {
                id: j.get("id").str()?.to_string(),
                title: j.get("title").str().unwrap_or("").to_string(),
                state: "idle",
                updated: j.get("updated").int().unwrap_or(0),
                started: j.get("started").truthy(),
                child: None,
                stdin: None,
                epoch: 0,
            })
        })
        .collect()
}

fn log_path(id: &str) -> PathBuf {
    chat_dir().join(format!("{id}.jsonl"))
}

// Garde un élément de l'historique (msg, tool) et le diffuse
fn store(d: &mut Daemon, item: &Json) {
    let line = item.to_string();
    if let Ok(mut f) = OpenOptions::new().create(true).append(true).open(log_path(item.get("id").str().unwrap_or("x"))) {
        let _ = writeln!(f, "{line}");
    }
    d.broadcast(&line);
}

fn msg(id: &str, role: &str, text: &str) -> Json {
    let mut j = Json::obj();
    j.set("ev", "msg");
    j.set("id", id);
    j.set("role", role);
    j.set("text", text);
    j
}

fn set_state(d: &mut Daemon, id: &str, state: &'static str) {
    if let Some(s) = d.session(id) {
        s.state = state;
        s.updated = now();
    }
    let mut j = Json::obj();
    j.set("ev", "state");
    j.set("id", id);
    j.set("state", state);
    let line = j.to_string();
    d.broadcast(&line);
    d.publish_sessions();
}

fn note(d: &mut Daemon, id: &str, code: &str) {
    let mut j = Json::obj();
    j.set("ev", "note");
    j.set("id", id);
    j.set("code", code);
    let line = j.to_string();
    d.broadcast(&line);
}

// ───── agent ─────
fn uuid() -> String {
    fs::read_to_string("/proc/sys/kernel/random/uuid").map(|s| s.trim().to_string()).unwrap_or_else(|_| format!("{:x}", now()))
}

fn spawn_agent(d: &mut Daemon, id: &str) -> Result<(), String> {
    let c = conf();
    let started = d.session(id).map(|s| s.started).unwrap_or(false);
    d.next_epoch += 1;
    let epoch = d.next_epoch;
    let mut cmd = Command::new("claude");
    cmd.args(["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages"]);
    cmd.args(if started { ["--resume", id] } else { ["--session-id", id] });
    cmd.arg("--add-dir").arg(&c.dir);
    if !c.model.is_empty() {
        cmd.args(["--model", &c.model]);
    }
    if c.args.is_empty() {
        cmd.args(["--permission-mode", "acceptEdits"]);
    } else {
        cmd.args(&c.args);
    }
    let prompt = PathBuf::from(&c.dir).join("agents/chat-prompt.md");
    if prompt.exists() {
        cmd.arg("--append-system-prompt-file").arg(prompt);
    }
    let path = format!("{}/.local/bin:{}", home(), env::var("PATH").unwrap_or_default());
    cmd.current_dir(&c.dir)
        .env("PATH", path)
        .env("FILI_CHAT", "1")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    let mut child = cmd.spawn().map_err(|e| format!("claude: {e}"))?;
    let stdout = child.stdout.take().ok_or("stdout")?;
    let stdin = child.stdin.take().ok_or("stdin")?;
    let sid = id.to_string();
    thread::spawn(move || {
        for line in BufReader::new(stdout).lines().map_while(Result::ok) {
            with(|d| agent_event(d, &sid, epoch, &line));
        }
        with(|d| agent_exit(d, &sid, epoch));
    });
    if let Some(s) = d.session(id) {
        s.child = Some(child);
        s.stdin = Some(stdin);
        s.epoch = epoch;
    }
    Ok(())
}

// Résumé d'un appel d'outil pour une ligne du fil
fn tool_summary(input: &Json) -> String {
    for k in ["command", "file_path", "path", "pattern", "url", "description", "query"] {
        if let Some(v) = input.get(k).str() {
            return v.lines().next().unwrap_or("").chars().take(200).collect();
        }
    }
    String::new()
}

fn agent_event(d: &mut Daemon, id: &str, epoch: u64, line: &str) {
    if d.session(id).map(|s| s.epoch) != Some(epoch) {
        return;
    }
    let Some(ev) = Json::parse(line) else { return };
    match ev.get("type").str().unwrap_or("") {
        "stream_event" => {
            let e = ev.get("event");
            if e.get("type").str() == Some("content_block_delta") && e.path(&["delta", "type"]).str() == Some("text_delta") {
                let mut j = Json::obj();
                j.set("ev", "delta");
                j.set("id", id);
                j.set("text", e.path(&["delta", "text"]).str().unwrap_or(""));
                let l = j.to_string();
                d.broadcast(&l);
            }
        }
        "assistant" => {
            if let Json::Arr(blocks) = ev.path(&["message", "content"]) {
                for b in blocks {
                    match b.get("type").str().unwrap_or("") {
                        "text" => {
                            let t = b.get("text").str().unwrap_or("");
                            if !t.trim().is_empty() {
                                store(d, &msg(id, "assistant", t));
                            }
                        }
                        "tool_use" => {
                            let mut j = Json::obj();
                            j.set("ev", "tool");
                            j.set("id", id);
                            j.set("name", b.get("name").str().unwrap_or("?"));
                            j.set("summary", tool_summary(b.get("input")));
                            store(d, &j);
                        }
                        _ => {}
                    }
                }
            }
        }
        "result" => {
            if ev.get("is_error").truthy() {
                let r = ev.get("result").str().unwrap_or("error");
                store(d, &msg(id, "error", r));
            }
            set_state(d, id, "idle");
        }
        _ => {}
    }
}

fn agent_exit(d: &mut Daemon, id: &str, epoch: u64) {
    let working = match d.session(id) {
        Some(s) if s.epoch == epoch => {
            if let Some(mut c) = s.child.take() {
                let _ = c.wait();
            }
            s.stdin = None;
            s.state == "working"
        }
        _ => return,
    };
    if working {
        store(d, &msg(id, "error", "The agent stopped"));
        set_state(d, id, "idle");
    }
}

fn kill_agent(s: &mut Session) {
    s.stdin = None;
    s.epoch = 0;
    if let Some(mut c) = s.child.take() {
        let _ = c.kill();
        let _ = c.wait();
    }
}

// ───── opérations des clients ─────
fn op_send(d: &mut Daemon, id: &str, text: &str) {
    if d.session(id).is_none() || text.trim().is_empty() {
        return;
    }
    if d.session(id).is_some_and(|s| s.state == "working") {
        return; // un tour à la fois
    }
    if d.session(id).is_some_and(|s| s.child.is_none()) {
        if let Err(e) = spawn_agent(d, id) {
            store(d, &msg(id, "error", &e));
            return;
        }
    }
    let mut m = Json::obj();
    m.set("role", "user");
    m.set("content", text);
    let mut line = Json::obj();
    line.set("type", "user");
    line.set("message", m);
    let ok = d
        .session(id)
        .and_then(|s| s.stdin.as_mut())
        .map(|w| writeln!(w, "{line}").and_then(|_| w.flush()).is_ok())
        .unwrap_or(false);
    if !ok {
        store(d, &msg(id, "error", "The agent is not reachable"));
        if let Some(s) = d.session(id) {
            kill_agent(s);
        }
        return;
    }
    if let Some(s) = d.session(id) {
        s.started = true;
        if s.title.is_empty() {
            s.title = text.lines().next().unwrap_or("").chars().take(48).collect();
        }
    }
    store(d, &msg(id, "user", text));
    set_state(d, id, "working");
}

fn op_history(d: &mut Daemon, client: u64, id: &str) {
    let text = fs::read_to_string(log_path(id)).unwrap_or_default();
    let items: Vec<Json> = text.lines().filter_map(Json::parse).collect();
    let mut j = Json::obj();
    j.set("ev", "history");
    j.set("id", id);
    j.set("items", Json::Arr(items));
    let state = d.session(id).map(|s| s.state).unwrap_or("idle");
    d.send_to(client, &j.to_string());
    let mut st = Json::obj();
    st.set("ev", "state");
    st.set("id", id);
    st.set("state", state);
    d.send_to(client, &st.to_string());
}

fn handle(client: u64, line: &str) {
    let Some(req) = Json::parse(line) else { return };
    let id = req.get("id").str().unwrap_or("").to_string();
    with(|d| match req.get("op").str().unwrap_or("") {
        "new" => {
            let id = uuid();
            d.sessions.push(Session { id: id.clone(), title: String::new(), state: "idle", updated: now(), started: false, child: None, stdin: None, epoch: 0 });
            d.publish_sessions();
            let mut j = Json::obj();
            j.set("ev", "created");
            j.set("id", id.as_str());
            d.send_to(client, &j.to_string());
        }
        "open" => op_history(d, client, &id),
        "send" => op_send(d, &id, req.get("text").str().unwrap_or("")),
        "stop" => {
            if d.session(&id).is_some_and(|s| s.state == "working") {
                if let Some(s) = d.session(&id) {
                    kill_agent(s);
                }
                note(d, &id, "interrupted");
                set_state(d, &id, "idle");
            }
        }
        "rename" => {
            if let Some(s) = d.session(&id) {
                s.title = req.get("title").str().unwrap_or("").chars().take(80).collect();
            }
            d.publish_sessions();
        }
        "delete" => {
            if let Some(i) = d.sessions.iter().position(|s| s.id == id) {
                let mut s = d.sessions.remove(i);
                kill_agent(&mut s);
                let _ = fs::remove_file(log_path(&id));
            }
            d.publish_sessions();
        }
        _ => {}
    });
}

fn serve(stream: UnixStream) {
    let Ok(writer) = stream.try_clone() else { return };
    let _ = writer.set_write_timeout(Some(Duration::from_secs(2)));
    let client = with(|d| {
        d.next_client += 1;
        let c = d.next_client;
        d.clients.push((c, writer));
        let line = d.sessions_json().to_string();
        d.send_to(c, &line);
        c
    });
    for line in BufReader::new(stream).lines().map_while(Result::ok) {
        handle(client, &line);
    }
    with(|d| d.clients.retain(|(c, _)| *c != client));
}

// Arrêt des agents inactifs; le démon s'arrête quand plus rien ne le demande
fn housekeeping() {
    loop {
        thread::sleep(Duration::from_secs(15));
        let quit = with(|d| {
            let t = now();
            for s in d.sessions.iter_mut() {
                if s.child.is_some() && s.state == "idle" && t - s.updated > IDLE_KILL {
                    kill_agent(s);
                }
            }
            if d.clients.is_empty() && !d.alive() {
                if d.quiet_since == 0 {
                    d.quiet_since = t;
                }
                t - d.quiet_since > IDLE_EXIT
            } else {
                d.quiet_since = 0;
                false
            }
        });
        if quit {
            let _ = fs::remove_file(sock_path());
            std::process::exit(0);
        }
    }
}

fn daemon() -> Result<(), String> {
    let dir = runtime_dir();
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let _ = fs::set_permissions(&dir, std::os::unix::fs::PermissionsExt::from_mode(0o700));
    if UnixStream::connect(sock_path()).is_ok() {
        return Ok(()); // déjà lancé
    }
    let _ = fs::remove_file(sock_path());
    fs::create_dir_all(chat_dir()).map_err(|e| e.to_string())?;
    let listener = UnixListener::bind(sock_path()).map_err(|e| e.to_string())?;
    with(|d| d.sessions = load_index());
    thread::spawn(housekeeping);
    for stream in listener.incoming().flatten() {
        thread::spawn(move || serve(stream));
    }
    Ok(())
}

// ───── commandes de l'utilisateur ─────
fn connect() -> Result<UnixStream, String> {
    UnixStream::connect(sock_path()).map_err(|_| "fili-chat: le démon ne tourne pas (le tiroir le lance)".to_string())
}

fn main() {
    let a: Vec<String> = env::args().skip(1).collect();
    let r = match a.first().map(String::as_str) {
        Some("daemon") => daemon(),
        Some("toggle") => {
            let ctx = format!("{}/context.json", state_dir().display());
            let _ = fs::create_dir_all(state_dir());
            let out = Command::new(format!("{}/.local/bin/fili-context", home())).output();
            let _ = fs::write(ctx, out.map(|o| o.stdout).unwrap_or_default());
            Command::new(format!("{}/.local/bin/fili-shell", home())).args(["chat", "toggle"]).status().map(|_| ()).map_err(|e| e.to_string())
        }
        Some("status") => connect().and_then(|s| {
            let mut l = String::new();
            BufReader::new(s).read_line(&mut l).map_err(|e| e.to_string())?;
            print!("{l}");
            Ok(())
        }),
        Some("send") if a.len() >= 3 => connect().and_then(|mut s| {
            let mut j = Json::obj();
            j.set("op", "send");
            j.set("id", a[1].as_str());
            j.set("text", a[2..].join(" "));
            writeln!(s, "{j}").map_err(|e| e.to_string())?;
            for line in BufReader::new(s).lines().map_while(Result::ok) {
                if line.contains("\"ev\":\"msg\"") || line.contains("\"ev\":\"tool\"") {
                    println!("{line}");
                }
                if line.contains("\"ev\":\"state\"") && line.contains("\"state\":\"idle\"") {
                    break;
                }
            }
            Ok(())
        }),
        _ => Err("usage: fili-chat daemon | toggle | status | send ID TEXTE".into()),
    };
    if let Err(e) = r {
        eprintln!("fili-chat: {e}");
        std::process::exit(1);
    }
}
