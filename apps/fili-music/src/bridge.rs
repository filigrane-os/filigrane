// Objects exposed to QML (module Fili.Baladeur): Fili, the environment (live theme, translations, window management, like
// Casier's), and Baladeur, the recordings, the player and the recorder of the window.
#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qml_singleton]
        #[qproperty(bool, light, READ, NOTIFY = theme_changed)]
        #[qproperty(QString, accent, READ, NOTIFY = theme_changed)]
        // Counts the changes of the settings files (fili-music.toml, theme.toml): bindings that read it, and the
        // headless header (Main.qml, onThemeChanged), follow a change made while the window is open
        #[qproperty(i32, settings_rev, cxx_name = "settingsRev", READ, NOTIFY = theme_changed)]
        #[qproperty(bool, key_nav, cxx_name = "keyNav")]
        type Fili = super::FiliRust;

        #[qsignal]
        #[cxx_name = "themeChanged"]
        fn theme_changed(self: Pin<&mut Fili>);
        // Command of `fili-music ctl` (the menu of the fili-bar, the assistant): number to reply with, verb, argument
        #[qsignal]
        fn command(self: Pin<&mut Fili>, id: i32, verb: &QString, arg: &QString);
        // Answer to a command (see Main.qml, onCommand)
        #[qinvokable]
        fn reply(self: &Fili, id: i32, answer: &QString);
        // Ends the program (Qt.quit() does not stop the event loop once the last window is hidden)
        #[qinvokable]
        fn quit(self: &Fili);

        #[qinvokable]
        #[cxx_name = "themeJson"]
        fn theme_json(self: &Fili) -> QString;
        #[qinvokable]
        fn tr(self: &Fili, text: &QString) -> QString;
        #[qinvokable]
        #[cxx_name = "windowControl"]
        fn window_control(self: &Fili) -> bool;
        #[qinvokable]
        #[cxx_name = "windowState"]
        fn window_state(self: &Fili) -> QString;
        #[qinvokable]
        fn header(self: &Fili) -> bool;
        #[qinvokable]
        fn footer(self: &Fili) -> bool;
        #[qinvokable]
        #[cxx_name = "windowButtons"]
        fn window_buttons(self: &Fili) -> bool;
        #[qinvokable]
        #[cxx_name = "setWindowButtons"]
        fn set_window_buttons(self: &Fili, on: bool);
        #[qinvokable]
        #[cxx_name = "windowAction"]
        fn window_action(self: &Fili, name: &QString) -> bool;
        // Small interface state kept between two launches, value as text, empty when absent
        #[qinvokable]
        #[cxx_name = "uiState"]
        fn ui_state(self: &Fili, key: &QString) -> QString;
        #[qinvokable]
        #[cxx_name = "setUiState"]
        fn set_ui_state(self: &Fili, key: &QString, value: &QString);
        // About card: rows [[label, value]] as JSON
        #[qinvokable]
        #[cxx_name = "aboutRows"]
        fn about_rows(self: &Fili) -> QString;
        #[qinvokable]
        #[cxx_name = "copyText"]
        fn copy_text(self: &Fili, text: &QString);
        // Opens the options file in the default editor
        #[qinvokable]
        #[cxx_name = "openSettings"]
        fn open_settings(self: &Fili);
        // A plain setting of fili-music.toml ("" when absent): section, key
        #[qinvokable]
        fn setting(self: &Fili, section: &QString, key: &QString) -> QString;
        // Writes a text file (a playlist exported as M3U); false when it cannot be written
        #[qinvokable]
        #[cxx_name = "writeText"]
        fn write_text(self: &Fili, path: &QString, text: &QString) -> bool;
        // The music folder of the user (xdg-user-dir MUSIC, else ~/Music): where a first scan starts
        #[qinvokable]
        #[cxx_name = "musicDir"]
        fn music_dir(self: &Fili) -> QString;
        // Whether a folder exists (the quick access folders of the scanner)
        #[qinvokable]
        #[cxx_name = "dirExists"]
        fn dir_exists(self: &Fili, path: &QString) -> bool;
        // The newest report the core wrote for "artwork" or "scan" (reports folder of the core): its path, "" when none
        #[qinvokable]
        #[cxx_name = "reportPath"]
        fn report_path(self: &Fili, kind: &QString) -> QString;
        // Opens a file with the default application (xdg-open)
        #[qinvokable]
        #[cxx_name = "openPath"]
        fn open_path(self: &Fili, path: &QString);
        // Debug panel: the log entries after number `since` as JSON {"seq": last number, "entries": [[level, text], ...]}
        // (level 0 debug, 1 info, 2 warning, 3 error), the file of the log, and a way to empty the panel
        #[qinvokable]
        fn logs(self: &Fili, since: i32) -> QString;
        #[qinvokable]
        #[cxx_name = "logFile"]
        fn log_file(self: &Fili) -> QString;
        #[qinvokable]
        #[cxx_name = "clearLogs"]
        fn clear_logs(self: &Fili);
        // "Report a problem" of the panel: records an incident with the last log lines and asks Rob to look at it; the id, "" when
        // it could not be written
        #[qinvokable]
        #[cxx_name = "reportProblem"]
        fn report_problem(self: &Fili, text: &QString) -> QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qml_singleton]
        // Player state as JSON (the `data` of get_player_state), refreshed by tick()
        #[qproperty(QString, state, READ, NOTIFY = state_changed)]
        type Music = super::MusicRust;

        #[qsignal]
        #[cxx_name = "stateChanged"]
        fn state_changed(self: Pin<&mut Music>);
        // The track being played changed (or playback stopped): the queue and the "now playing" views reload
        #[qsignal]
        #[cxx_name = "trackChanged"]
        fn track_changed(self: Pin<&mut Music>);
        // Answer of callAsync: the number it was given and the JSON reply of the core
        #[qsignal]
        fn reply(self: Pin<&mut Music>, id: i32, json: &QString);

        // One call of the core by name with its arguments as a JSON array: the reply is the JSON of the core
        // ({"success": true, "data": ...} or {"success": false, "error": ...}); same names as tornade-core's FFI
        #[qinvokable]
        fn call(self: &Music, name: &QString, args: &QString) -> QString;
        // The same call on a worker thread, answered by the `reply` signal (scans, network, big queries)
        #[qinvokable]
        #[cxx_name = "callAsync"]
        fn call_async(self: &Music, id: i32, name: &QString, args: &QString);
        // Once every 250 ms: heartbeat of the core (end of track, advance) and the state property
        #[qinvokable]
        fn tick(self: Pin<&mut Music>);
    }

    impl cxx_qt::Threading for Fili {}
    impl cxx_qt::Initialize for Fili {}
    impl cxx_qt::Threading for Music {}
}

use std::{path::PathBuf, pin::Pin};

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;

use crate::{i18n, mpris, music, theme, window};

fn home() -> String {
    std::env::var("HOME").unwrap_or_default()
}

fn state_dir() -> PathBuf {
    PathBuf::from(std::env::var("XDG_STATE_HOME").unwrap_or_else(|_| format!("{}/.local/state", home()))).join("filigrane")
}

fn ui_file() -> PathBuf {
    state_dir().join("fili-music-ui")
}

// `key=value` lines: reading of a key
fn ui_get(text: &str, key: &str) -> String {
    text.lines().find_map(|l| l.split_once('=').filter(|(k, _)| *k == key).map(|(_, v)| v.trim().to_string())).unwrap_or_default()
}

// The same text with the key set (or removed when the value is empty)
fn ui_set(text: &str, key: &str, value: &str) -> String {
    let clean = |s: &str| s.replace(['\n', '\r'], " ");
    let (key, value) = (clean(key).replace('=', "-"), clean(value));
    let mut lines: Vec<String> =
        text.lines().filter(|l| l.split_once('=').is_none_or(|(k, _)| k != key)).map(String::from).collect();
    if !value.trim().is_empty() {
        lines.push(format!("{key}={}", value.trim()));
    }
    lines.sort();
    if lines.is_empty() { String::new() } else { lines.join("\n") + "\n" }
}

fn ui_store(key: &str, value: &str) {
    let path = ui_file();
    let text = ui_set(&std::fs::read_to_string(&path).unwrap_or_default(), key, value);
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let _ = std::fs::write(path, text);
}

// State of fili-theme ("light" or "dark"), like FiliTheme.qml of the fili-shell
fn read_light() -> bool {
    std::fs::read_to_string(state_dir().join("theme")).map(|t| t.trim() == "light").unwrap_or(false)
}

fn read_accent() -> String {
    std::fs::read_to_string(state_dir().join("accent")).map(|t| t.trim().to_string()).unwrap_or_else(|_| "default".into())
}

pub fn args() -> Vec<String> {
    std::env::args().skip(1).collect()
}

/// Waits for changes in a directory (inotify, blocked on read: nothing wakes up while nothing changes) and calls `then`
/// until it returns false.
fn watch_dir(dir: PathBuf, then: impl Fn() -> bool + Send + 'static) {
    std::thread::spawn(move || {
        let _ = std::fs::create_dir_all(&dir);
        let Ok(c) = std::ffi::CString::new(dir.as_os_str().as_encoded_bytes()) else { return };
        let fd = unsafe { libc::inotify_init1(libc::IN_CLOEXEC) };
        if fd < 0
            || unsafe { libc::inotify_add_watch(fd, c.as_ptr(), libc::IN_CLOSE_WRITE | libc::IN_MOVED_TO | libc::IN_CREATE) } < 0
        {
            return;
        }
        let mut buf = [0u8; 4096];
        loop {
            if unsafe { libc::read(fd, buf.as_mut_ptr().cast(), buf.len()) } <= 0 || !then() {
                return;
            }
        }
    });
}

#[derive(Default)]
pub struct FiliRust {
    light: bool,
    accent: QString,
    settings_rev: i32,
    key_nav: bool,
}

impl cxx_qt::Initialize for qobject::Fili {
    fn initialize(mut self: Pin<&mut Self>) {
        self.as_mut().rust_mut().light = read_light();
        self.as_mut().rust_mut().accent = QString::from(&read_accent());
        // The settings directory (fili-music.toml, theme.toml written by `fili-theme font|header` or by hand)
        let qt = self.qt_thread();
        if let Some(dir) = theme::path().parent() {
            watch_dir(dir.to_path_buf(), move || {
                qt.queue(|mut f| {
                    let rev = f.settings_rev.wrapping_add(1);
                    f.as_mut().rust_mut().settings_rev = rev;
                    f.as_mut().theme_changed();
                })
                .is_ok()
            });
        }
        // The state directory (light or dark, accent)
        let qt = self.qt_thread();
        watch_dir(state_dir(), move || {
            let (light, accent) = (read_light(), read_accent());
            qt.queue(move |mut f| {
                if f.light != light || f.accent.to_string() != accent {
                    f.as_mut().rust_mut().light = light;
                    f.as_mut().rust_mut().accent = QString::from(&accent);
                    f.as_mut().theme_changed();
                }
            })
            .is_ok()
        });
        // Commands from `fili-music ctl`
        let qt = self.qt_thread();
        crate::ctl::serve(move |id, verb, arg| {
            let _ = qt.queue(move |mut f| f.as_mut().command(id, &QString::from(&verb), &QString::from(&arg)));
        });
    }
}

impl qobject::Fili {
    pub fn quit(&self) {
        log::info!("quit");
        std::process::exit(0);
    }

    pub fn reply(&self, id: i32, answer: &QString) {
        crate::ctl::reply(id, &answer.to_string());
    }

    pub fn theme_json(&self) -> QString {
        QString::from(&theme::theme_json())
    }

    pub fn tr(&self, text: &QString) -> QString {
        QString::from(i18n::tr(&text.to_string()))
    }

    pub fn window_control(&self) -> bool {
        window::available()
    }

    pub fn window_state(&self) -> QString {
        QString::from(&window::state())
    }

    // Header of the window (toolbar): false = headless (settings and --no-header)
    pub fn header(&self) -> bool {
        theme::window_part("header", &args())
    }

    // Footer (status bar): false = hidden until it has something to say (settings and --no-footer)
    pub fn footer(&self) -> bool {
        theme::window_part("footer", &args())
    }

    pub fn window_buttons(&self) -> bool {
        ui_get(&std::fs::read_to_string(ui_file()).unwrap_or_default(), "window_buttons") != "0"
    }

    pub fn set_window_buttons(&self, on: bool) {
        ui_store("window_buttons", if on { "1" } else { "0" });
    }

    pub fn window_action(&self, name: &QString) -> bool {
        window::run(&name.to_string())
    }

    pub fn ui_state(&self, key: &QString) -> QString {
        QString::from(&ui_get(&std::fs::read_to_string(ui_file()).unwrap_or_default(), &key.to_string()))
    }

    pub fn set_ui_state(&self, key: &QString, value: &QString) {
        ui_store(&key.to_string(), &value.to_string());
    }

    pub fn about_rows(&self) -> QString {
        let version =
            option_env!("FILI_MUSIC_GIT").map(str::to_string).unwrap_or_else(|| env!("CARGO_PKG_VERSION").to_string());
        let rows = [
            (i18n::tr("Also known as"), "fili-music".to_string()),
            (i18n::tr("Part of"), "Filigrane".to_string()),
            (i18n::tr("Version"), version),
            (i18n::tr("Library"), music::library_dir()),
            (i18n::tr("Core"), "tornade-core (MIT)".to_string()),
            (i18n::tr("Settings"), "~/.config/filigrane/fili-music.toml".to_string()),
        ];
        let items: Vec<String> =
            rows.iter().map(|(k, v)| format!("[{},{}]", music::json_str(k), music::json_str(v))).collect();
        QString::from(&format!("[{}]", items.join(",")))
    }

    pub fn report_path(&self, kind: &QString) -> QString {
        let prefix = format!("{}_", kind);
        let dir = tornade_core::utils::AppPaths::new().map(|p| p.reports_dir()).ok();
        let newest = dir
            .and_then(|d| std::fs::read_dir(d).ok())
            .into_iter()
            .flatten()
            .flatten()
            .filter(|e| e.file_name().to_string_lossy().starts_with(&prefix))
            .max_by_key(|e| e.file_name());
        QString::from(&newest.map(|e| e.path().display().to_string()).unwrap_or_default())
    }

    pub fn logs(&self, since: i32) -> QString {
        let (seq, entries) = crate::logs::since(since.max(0) as u64);
        QString::from(&serde_json::json!({ "seq": seq, "entries": entries }).to_string())
    }

    pub fn log_file(&self) -> QString {
        QString::from(&crate::logs::path().display().to_string())
    }

    pub fn clear_logs(&self) {
        crate::logs::clear();
    }

    pub fn report_problem(&self, text: &QString) -> QString {
        let said = text.to_string();
        let message = if said.trim().is_empty() { "Problem reported from the Debug panel".to_string() } else { said };
        QString::from(&crate::logs::incident("manual", &message, true).unwrap_or_default())
    }

    pub fn open_path(&self, path: &QString) {
        let _ = std::process::Command::new("xdg-open").arg(path.to_string()).spawn();
    }

    pub fn dir_exists(&self, path: &QString) -> bool {
        std::path::Path::new(&path.to_string()).is_dir()
    }

    pub fn music_dir(&self) -> QString {
        let from_xdg = std::process::Command::new("xdg-user-dir")
            .arg("MUSIC")
            .output()
            .ok()
            .filter(|o| o.status.success())
            .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
            .filter(|p| !p.is_empty() && *p != home());
        QString::from(&from_xdg.unwrap_or_else(|| format!("{}/Music", home())))
    }

    pub fn setting(&self, section: &QString, key: &QString) -> QString {
        QString::from(theme::setting(&section.to_string(), &key.to_string()).unwrap_or_default())
    }

    pub fn write_text(&self, path: &QString, text: &QString) -> bool {
        std::fs::write(path.to_string(), text.to_string()).is_ok()
    }

    pub fn open_settings(&self) {
        // The file is optional: a first opening writes a commented one so that there is something to edit
        let file = theme::path();
        if !file.exists() {
            if let Some(dir) = file.parent() {
                let _ = std::fs::create_dir_all(dir);
            }
            let _ = std::fs::write(
                &file,
                "# Baladeur settings (optional). The theme keys live in [theme], see ~/.config/filigrane/theme.toml.\n\n[behavior]\n# A double click on a track adds it to the queue instead of playing it (Alt then plays)\n# invert_queue = true\n",
            );
        }
        let _ = std::process::Command::new("xdg-open")
            .arg(theme::path())
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn();
    }

    pub fn copy_text(&self, text: &QString) {
        use std::io::Write;
        if let Ok(mut c) = std::process::Command::new("wl-copy")
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn()
            && let Some(mut stdin) = c.stdin.take()
        {
            let _ = stdin.write_all(text.to_string().as_bytes());
        }
    }
}

#[derive(Default)]
pub struct MusicRust {
    state: QString,
    // Id of the track played at the last tick: a change is announced by trackChanged
    last_track: i64,
}

impl qobject::Music {
    pub fn call(&self, name: &QString, args: &QString) -> QString {
        QString::from(&music::dispatch(&name.to_string(), &args.to_string()))
    }

    pub fn call_async(&self, id: i32, name: &QString, args: &QString) {
        let (name, args) = (name.to_string(), args.to_string());
        let qt = self.qt_thread();
        std::thread::spawn(move || {
            let json = music::dispatch(&name, &args);
            let _ = qt.queue(move |mut m| m.as_mut().reply(id, &QString::from(&json)));
        });
    }

    pub fn tick(mut self: Pin<&mut Self>) {
        let json = music::dispatch("get_player_state", "[]");
        let (state, track) = music::player_state(&json);
        mpris::publish(&state);
        if self.state.to_string() != state {
            self.as_mut().rust_mut().state = QString::from(&state);
            self.as_mut().state_changed();
        }
        if self.last_track != track {
            self.as_mut().rust_mut().last_track = track;
            self.as_mut().track_changed();
        }
    }
}
