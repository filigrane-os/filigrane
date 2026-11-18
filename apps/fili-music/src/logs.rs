// The log of the application, for the Debug panel (View > Debug Logs) and for whoever looks into a bug afterwards.
// Everything the application says goes to three places: stderr (as before, RUST_LOG decides), a ring buffer in memory (the
// last KEEP entries, read by the panel) and a file, ~/.local/state/filigrane/logs/<app>.log (kept across a crash, rotated at
// FILE_MAX). Three sources feed it: the `log` crate (the application and tornade-core), the messages of Qt (QML errors,
// console.log) and panics, all of it in Rust (no C++ in the project). The module has no dependency on this application: the other fili-* apps copy it
// with their name in `init` (see agents/skills/filigrane-ui/references/app-window.md, "Debug panel").
// Level of the buffer and the file: info and above; FILI_LOG=debug (or trace) keeps more.
use std::{
    collections::VecDeque,
    fs,
    io::Write,
    path::PathBuf,
    sync::{Mutex, OnceLock},
};

use cxx_qt_lib::{QMessageLogContext, QString, QtMsgType, q_format_log_message};
use log::{Level, LevelFilter, Log, Metadata, Record};

const KEEP: usize = 2000;
const FILE_MAX: u64 = 1_000_000;

// Levels as the panel knows them
pub const DEBUG: u8 = 0;
pub const INFO: u8 = 1;
pub const WARN: u8 = 2;
pub const ERROR: u8 = 3;

/// The last entries, each with a number that only grows: a reader asks for what came after the last one it saw.
#[derive(Default)]
pub struct Ring {
    next: u64,
    entries: VecDeque<(u64, u8, String)>,
}

impl Ring {
    pub fn push(&mut self, level: u8, text: String) {
        self.next += 1;
        self.entries.push_back((self.next, level, text));
        while self.entries.len() > KEEP {
            self.entries.pop_front();
        }
    }

    /// Entries after number `seq` (0: all of them) and the number of the last one.
    pub fn since(&self, seq: u64) -> (u64, Vec<(u8, String)>) {
        let out = self.entries.iter().filter(|(n, _, _)| *n > seq).map(|(_, l, t)| (*l, t.clone())).collect();
        (self.next, out)
    }

    pub fn clear(&mut self) {
        self.entries.clear();
    }
}

struct State {
    ring: Ring,
    file: Option<fs::File>,
    written: u64,
    path: PathBuf,
}

static STATE: OnceLock<Mutex<State>> = OnceLock::new();

pub fn log_path(app: &str) -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_default();
    let state = std::env::var("XDG_STATE_HOME").unwrap_or_else(|_| format!("{home}/.local/state"));
    PathBuf::from(state).join("filigrane/logs").join(format!("{app}.log"))
}

fn open(path: &PathBuf) -> Option<fs::File> {
    fs::create_dir_all(path.parent()?).ok()?;
    fs::OpenOptions::new().create(true).append(true).open(path).ok()
}

fn clock() -> String {
    // Local time, to the millisecond
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default();
    let secs = now.as_secs() as libc::time_t;
    let mut tm: libc::tm = unsafe { std::mem::zeroed() };
    unsafe { libc::localtime_r(&secs, &mut tm) };
    format!("{:02}:{:02}:{:02}.{:03}", tm.tm_hour, tm.tm_min, tm.tm_sec, now.subsec_millis())
}

fn level_name(level: u8) -> &'static str {
    match level {
        ERROR => "ERROR",
        WARN => "WARN ",
        INFO => "INFO ",
        _ => "DEBUG",
    }
}

/// Adds an entry to the buffer and the file.
pub fn push(level: u8, target: &str, message: &str) {
    let Some(state) = STATE.get() else { return };
    let line = format!("{} {} {target}: {message}", clock(), level_name(level));
    let Ok(mut s) = state.lock() else { return };
    if let Some(file) = s.file.as_mut() {
        let _ = writeln!(file, "{line}");
        s.written += line.len() as u64 + 1;
    }
    if s.written > FILE_MAX {
        // The old half is kept as <app>.log.1, one generation
        let old = s.path.with_extension("log.1");
        let _ = fs::rename(&s.path, old);
        s.file = open(&s.path);
        s.written = 0;
    }
    s.ring.push(level, line);
}

/// Entries after number `seq` and the number of the last one (see [`Ring::since`]).
pub fn since(seq: u64) -> (u64, Vec<(u8, String)>) {
    match STATE.get().and_then(|s| s.lock().ok()) {
        Some(s) => s.ring.since(seq),
        None => (0, Vec::new()),
    }
}

pub fn clear() {
    if let Some(mut s) = STATE.get().and_then(|s| s.lock().ok()) {
        s.ring.clear();
    }
}

pub fn path() -> PathBuf {
    STATE.get().and_then(|s| s.lock().ok()).map(|s| s.path.clone()).unwrap_or_default()
}

struct Logger {
    stderr: env_logger::Logger,
    keep: LevelFilter,
}

impl Log for Logger {
    fn enabled(&self, metadata: &Metadata) -> bool {
        metadata.level() <= self.keep || self.stderr.enabled(metadata)
    }

    fn log(&self, record: &Record) {
        if self.stderr.matches(record) {
            eprintln!("[{} {}] {}", record.level(), record.target(), record.args());
        }
        if record.level() <= self.keep {
            let level = match record.level() {
                Level::Error => ERROR,
                Level::Warn => WARN,
                Level::Info => INFO,
                _ => DEBUG,
            };
            push(level, record.target(), &record.args().to_string());
        }
    }

    fn flush(&self) {}
}

/// Starts the log of application `app` (its file is <app>.log): `log` macros, Qt messages and panics all end up in it.
pub fn init(app: &str) {
    let path = log_path(app);
    // A file left big by a previous run is rotated now
    if fs::metadata(&path).map(|m| m.len() > FILE_MAX).unwrap_or(false) {
        let _ = fs::rename(&path, path.with_extension("log.1"));
    }
    let file = open(&path);
    let written = file.as_ref().and_then(|f| f.metadata().ok()).map(|m| m.len()).unwrap_or(0);
    let _ = STATE.set(Mutex::new(State { ring: Ring::default(), file, written, path }));
    let keep = match std::env::var("FILI_LOG").as_deref() {
        Ok("trace") => LevelFilter::Trace,
        Ok("debug") => LevelFilter::Debug,
        _ => LevelFilter::Info,
    };
    let stderr = env_logger::Builder::from_default_env().build();
    let max = keep.max(stderr.filter());
    if log::set_boxed_logger(Box::new(Logger { stderr, keep })).is_ok() {
        log::set_max_level(max);
    }
    // A panic is written before the default message (the release build aborts right after)
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        push(ERROR, "panic", &info.to_string());
        previous(info);
    }));
    log::info!("{app} {} started", option_env!("FILI_MUSIC_GIT").unwrap_or(env!("CARGO_PKG_VERSION")));
}

// Qt has no Rust API to install a message handler (cxx-qt-lib only formats messages), so the function is declared here by its
// symbol in libQt6Core: qInstallMessageHandler(QtMessageHandler), whose handler takes (QtMsgType, const QMessageLogContext &,
// const QString &): C++ references are plain pointers in the C calling convention, and QtMsgType is an int. The symbol is
// checked at link time: if a Qt version renames it, the build fails instead of silently losing the messages.
type QtHandler = extern "C" fn(QtMsgType, &QMessageLogContext<'_>, &QString);

unsafe extern "C" {
    #[link_name = "_Z22qInstallMessageHandlerPFv9QtMsgTypeRK18QMessageLogContextRK7QStringE"]
    fn q_install_message_handler(handler: Option<QtHandler>) -> Option<QtHandler>;
}

extern "C" fn qt_handler(kind: QtMsgType, context: &QMessageLogContext<'_>, message: &QString) {
    // What Qt's own handler would print (file and line of a QML error included), then the entry of the log
    eprintln!("{}", q_format_log_message(kind, context, message));
    let category = context.category().to_string_lossy();
    // console.log of the QML ("js", "qml") is what the application wrote on purpose: kept at info
    let ours = matches!(&*category, "js" | "qml" | "default");
    let level = if kind == QtMsgType::QtWarningMsg {
        WARN
    } else if kind == QtMsgType::QtCriticalMsg || kind == QtMsgType::QtFatalMsg {
        ERROR
    } else if kind == QtMsgType::QtInfoMsg || ours {
        INFO
    } else {
        DEBUG
    };
    push(level, &format!("qt/{category}"), &message.to_string());
}

/// Routes the messages of Qt (QML errors and warnings, console.log) into the log; they still reach stderr.
pub fn capture_qt() {
    unsafe { q_install_message_handler(Some(qt_handler)) };
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ring_gives_what_came_after_a_number() {
        let mut r = Ring::default();
        r.push(INFO, "a".into());
        r.push(WARN, "b".into());
        let (last, all) = r.since(0);
        assert_eq!((last, all.len()), (2, 2));
        r.push(ERROR, "c".into());
        let (last, news) = r.since(2);
        assert_eq!(last, 3);
        assert_eq!(news, vec![(ERROR, "c".to_string())]);
        assert!(r.since(3).1.is_empty());
    }

    #[test]
    fn ring_keeps_the_last_entries_and_numbers_go_on() {
        let mut r = Ring::default();
        for i in 0..KEEP + 10 {
            r.push(INFO, i.to_string());
        }
        let (last, all) = r.since(0);
        assert_eq!(all.len(), KEEP);
        assert_eq!(all[0].1, "10");
        assert_eq!(last, (KEEP + 10) as u64);
        // A reader that was behind the dropped entries gets what is left
        assert_eq!(r.since(5).1.len(), KEEP);
        r.clear();
        assert!(r.since(0).1.is_empty());
        r.push(INFO, "after".into());
        assert_eq!(r.since(last).1.len(), 1);
    }

    #[test]
    fn levels_have_names_of_one_width() {
        assert!([DEBUG, INFO, WARN, ERROR].iter().all(|l| level_name(*l).len() == 5));
    }
}
