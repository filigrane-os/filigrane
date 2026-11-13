// Commands to an open window: `fili-recorder ctl [--pid PID] action NAME [ARG] | state | actions`. The menu of the fili-bar
// (dotfiles/config/filigrane/appmenu/fili-recorder.json, `%pid` = the active window) and the assistant use it; the window
// answers in Main.qml (runAction). One socket per window: $XDG_RUNTIME_DIR/fili-recorder.<pid>.sock, a line in, a line out.
use std::collections::HashMap;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::sync::{Condvar, Mutex, OnceLock};
use std::time::Duration;

fn runtime_dir() -> PathBuf {
    PathBuf::from(std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".into()))
}

fn socket_path(pid: u32) -> PathBuf {
    runtime_dir().join(format!("fili-recorder.{pid}.sock"))
}

struct Replies {
    answers: Mutex<HashMap<i32, String>>,
    wake: Condvar,
}

fn replies() -> &'static Replies {
    static R: OnceLock<Replies> = OnceLock::new();
    R.get_or_init(|| Replies { answers: Mutex::new(HashMap::new()), wake: Condvar::new() })
}

/// The window answers the command `id` (called from QML, `Fili.reply`).
pub fn reply(id: i32, answer: &str) {
    let r = replies();
    r.answers.lock().unwrap_or_else(|e| e.into_inner()).insert(id, answer.to_string());
    r.wake.notify_all();
}

/// Serves the socket of this window: each line is `verb argument`, handed to `on(id, verb, argument)`; the answer comes back
/// through `reply`. A command nobody answers within three seconds gets an error.
pub fn serve(on: impl Fn(i32, String, String) + Send + 'static) {
    let path = socket_path(std::process::id());
    let _ = std::fs::remove_file(&path);
    let Ok(listener) = UnixListener::bind(&path) else { return };
    std::thread::spawn(move || {
        let mut next = 0;
        for stream in listener.incoming().flatten() {
            let mut line = String::new();
            let mut writer = match stream.try_clone() {
                Ok(w) => w,
                Err(_) => continue,
            };
            if BufReader::new(stream).read_line(&mut line).is_err() {
                continue;
            }
            let (verb, arg) = line.trim_end().split_once(' ').unwrap_or((line.trim_end(), ""));
            next += 1;
            on(next, verb.to_string(), arg.to_string());
            let r = replies();
            let mut answers = r.answers.lock().unwrap_or_else(|e| e.into_inner());
            let end = std::time::Instant::now() + Duration::from_secs(3);
            let answer = loop {
                if let Some(a) = answers.remove(&next) {
                    break a;
                }
                let left = end.saturating_duration_since(std::time::Instant::now());
                if left.is_zero() {
                    break "{\"ok\":false,\"error\":\"no answer from the window\"}".to_string();
                }
                answers = r.wake.wait_timeout(answers, left).unwrap_or_else(|e| e.into_inner()).0;
            };
            let _ = writeln!(writer, "{answer}");
        }
    });
}

/// The pids of the open windows (their sockets answer), stale sockets are removed.
pub fn windows() -> Vec<u32> {
    let Ok(read) = std::fs::read_dir(runtime_dir()) else { return Vec::new() };
    let mut pids: Vec<u32> = read
        .filter_map(|e| e.ok())
        .filter_map(|e| e.file_name().to_string_lossy().strip_prefix("fili-recorder.")?.strip_suffix(".sock")?.parse().ok())
        .filter(|pid| {
            let alive = UnixStream::connect(socket_path(*pid)).is_ok();
            if !alive {
                let _ = std::fs::remove_file(socket_path(*pid));
            }
            alive
        })
        .collect();
    pids.sort();
    pids
}

/// `fili-recorder ctl [--pid PID] VERB [ARGUMENT...]`: the answer of the window (a JSON line).
pub fn client(args: &[String]) -> Result<String, String> {
    let mut args = args.to_vec();
    let mut pid = None;
    if args.first().is_some_and(|a| a == "--pid") {
        pid = args.get(1).and_then(|p| p.parse::<u32>().ok());
        if pid.is_none() {
            return Err("--pid needs a number".into());
        }
        args.drain(..2);
    }
    if args.is_empty() {
        return Err("usage: fili-recorder ctl [--pid PID] action NAME [ARG] | state | actions".into());
    }
    let pid = match pid {
        Some(p) => p,
        None => *windows().first().ok_or("no Cassette window is open")?,
    };
    let mut stream = UnixStream::connect(socket_path(pid)).map_err(|e| format!("window {pid}: {e}"))?;
    stream.set_read_timeout(Some(Duration::from_secs(5))).map_err(|e| e.to_string())?;
    writeln!(stream, "{}", args.join(" ")).map_err(|e| e.to_string())?;
    let mut answer = String::new();
    BufReader::new(stream).read_line(&mut answer).map_err(|e| e.to_string())?;
    Ok(answer.trim_end().to_string())
}
