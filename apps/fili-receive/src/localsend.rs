// LocalSend: écoute les événements de localsendd (`lsend --json watch`). Une demande entrante devient une notification
// « Accepter / Refuser » (lsend accept|reject); en fin de transfert, « Reçu de … » avec « Afficher ».
use crate::{
    common::{announce, ask, journal, notify, summary},
    i18n::{tr, trf},
    json::{self, Json},
};
use std::{
    collections::HashMap,
    io::{BufRead, BufReader},
    process::{Command, Stdio},
    sync::{Arc, Mutex},
    thread,
    time::{Duration, Instant},
};

// localsendd abandonne la demande après 30 s
const ASK_MS: u32 = 28000;
// Sans nombre de fichiers connu (session acceptée sans demande), on clôt après ce silence
const IDLE: Duration = Duration::from_secs(3);

struct Session {
    sender: String,
    // id -> (nom, taille)
    files: HashMap<String, (String, u64)>,
    total: Option<usize>,
    ok: Vec<String>,
    failed: usize,
    last: Instant,
}

type Sessions = Arc<Mutex<HashMap<String, Session>>>;

pub fn run(dir: String, always: bool) {
    let sessions: Sessions = Arc::default();
    {
        let (sessions, dir) = (sessions.clone(), dir.clone());
        thread::spawn(move || loop {
            thread::sleep(Duration::from_secs(1));
            let done: Vec<Session> = {
                let mut m = sessions.lock().unwrap();
                let ids: Vec<String> = m
                    .iter()
                    .filter(|(_, s)| s.total.is_none() && s.last.elapsed() > IDLE && s.ok.len() + s.failed > 0)
                    .map(|(k, _)| k.clone())
                    .collect();
                ids.iter().filter_map(|k| m.remove(k)).collect()
            };
            for s in done {
                finish(&dir, s);
            }
        });
    }
    let mut failures = 0;
    loop {
        let child = Command::new("lsend").args(["--json", "watch"]).stdout(Stdio::piped()).stderr(Stdio::null()).spawn();
        let Ok(mut child) = child else {
            eprintln!("fili-receive: lsend introuvable");
            return;
        };
        let started = Instant::now();
        if let Some(out) = child.stdout.take() {
            for line in BufReader::new(out).lines().map_while(Result::ok) {
                if let Some(ev) = json::parse(&line) {
                    handle(&ev, &dir, always, &sessions);
                }
            }
        }
        let _ = child.wait();
        // Le démon s'arrête avec « receive localsend off » (qui nous arrête aussi); sinon on le réessaie un moment
        failures = if started.elapsed() > Duration::from_secs(10) { 0 } else { failures + 1 };
        if failures > 30 {
            return;
        }
        thread::sleep(Duration::from_secs(2));
    }
}

fn handle(ev: &Json, dir: &str, always: bool, sessions: &Sessions) {
    let Some(data) = ev.get("data") else { return };
    let Some(sid) = data.str("session_id") else { return };
    match ev.str("event") {
        Some("incoming_session") => {
            let sender = data.str("peer_alias").unwrap_or("?").to_string();
            let mut files = HashMap::new();
            let mut names = Vec::new();
            let mut total_size = 0;
            for f in data.arr("files") {
                let name = f.str("file_name").unwrap_or("?").to_string();
                let size = f.num("size").unwrap_or(0.0) as u64;
                total_size += size;
                names.push(name.clone());
                files.insert(f.str("id").unwrap_or(&name).to_string(), (name, size));
            }
            let count = files.len();
            sessions.lock().unwrap().insert(
                sid.to_string(),
                Session { sender: sender.clone(), files, total: Some(count), ok: vec![], failed: 0, last: Instant::now() },
            );
            let (sid, sessions) = (sid.to_string(), sessions.clone());
            thread::spawn(move || {
                let title = if names.len() == 1 {
                    trf("%1 wants to send you a file", &[&sender])
                } else {
                    trf("%1 wants to send you files", &[&sender])
                };
                // Réglage confirm = "always": on accepte sans demander (la fin du transfert est annoncée)
                let choice = if always {
                    Some("accept".to_string())
                } else {
                    ask(
                        &title,
                        &summary(&names, total_size),
                        &[("accept", tr("Accept").to_string()), ("reject", tr("Decline").to_string())],
                        ASK_MS,
                    )
                };
                let verb = if choice.as_deref() == Some("accept") { "accept" } else { "reject" };
                let _ = Command::new("lsend").args(["--json", verb, &sid]).stdout(Stdio::null()).stderr(Stdio::null()).status();
                if verb == "reject" {
                    sessions.lock().unwrap().remove(&sid);
                }
            });
        }
        Some("transfer_complete") => {
            let ok = data.bool("success").unwrap_or(false);
            let fid = data.str("file_id").unwrap_or("");
            let done = {
                let mut m = sessions.lock().unwrap();
                let s = m.entry(sid.to_string()).or_insert_with(|| Session {
                    sender: "?".into(),
                    files: HashMap::new(),
                    total: None,
                    ok: vec![],
                    failed: 0,
                    last: Instant::now(),
                });
                s.last = Instant::now();
                if ok {
                    s.ok.push(fid.to_string());
                } else {
                    s.failed += 1;
                }
                match s.total {
                    Some(t) if s.ok.len() + s.failed >= t => m.remove(sid),
                    _ => None,
                }
            };
            if let Some(s) = done {
                finish(dir, s);
            }
        }
        _ => {}
    }
}

fn finish(dir: &str, s: Session) {
    let mut names = Vec::new();
    let mut size = 0;
    for id in &s.ok {
        let (name, sz) = s.files.get(id).cloned().unwrap_or_else(|| (id.clone(), 0));
        journal("localsend", &s.sender, &format!("{dir}/{name}"), sz);
        size += sz;
        names.push(name);
    }
    if s.failed > 0 {
        notify(&trf("Reception from %1 failed", &[&s.sender]), &summary(&names, size));
    } else if !names.is_empty() {
        announce(&trf("Received from %1", &[&s.sender]), &summary(&names, size), dir);
    }
}
