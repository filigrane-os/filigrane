// Objects exposed to QML (module Fili.Cassette): Fili, the environment (live theme, translations, window management, like
// Casier's), and Cassette, the recordings, the player and the recorder of the window.
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
        // Counts the changes of the settings files (fili-recorder.toml, theme.toml): bindings that read it, and the
        // headless header (Main.qml, onThemeChanged), follow a change made while the window is open
        #[qproperty(i32, settings_rev, cxx_name = "settingsRev", READ, NOTIFY = theme_changed)]
        #[qproperty(bool, key_nav, cxx_name = "keyNav")]
        type Fili = super::FiliRust;

        #[qsignal]
        #[cxx_name = "themeChanged"]
        fn theme_changed(self: Pin<&mut Fili>);
        // Command of `fili-recorder ctl` (the menu of the fili-bar, the assistant): number to reply with, verb, argument
        #[qsignal]
        fn command(self: Pin<&mut Fili>, id: i32, verb: &QString, arg: &QString);
        // Answer to a command (see Main.qml, onCommand)
        #[qinvokable]
        fn reply(self: &Fili, id: i32, answer: &QString);

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
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        // The recordings of the folder as JSON: [{path, name, when, duration, size, kind}], newest first
        #[qproperty(QString, recordings, READ, NOTIFY = changed)]
        #[qproperty(i32, count, READ, NOTIFY = changed)]
        #[qproperty(f64, total, READ, NOTIFY = changed)]
        // Player: a file is loaded (playing or paused), paused, its path, position and length in seconds
        #[qproperty(bool, playing, READ, NOTIFY = changed)]
        #[qproperty(bool, paused, READ, NOTIFY = changed)]
        #[qproperty(QString, current, READ, NOTIFY = changed)]
        #[qproperty(f64, position, READ, NOTIFY = changed)]
        #[qproperty(f64, duration, READ, NOTIFY = changed)]
        // Recorder: running, mixing the files at the end, start (seconds since the epoch), choices of the sources
        #[qproperty(bool, recording, READ, NOTIFY = changed)]
        #[qproperty(bool, saving, READ, NOTIFY = changed)]
        #[qproperty(f64, rec_start, cxx_name = "recStart", READ, NOTIFY = changed)]
        #[qproperty(QString, input, READ, NOTIFY = changed)]
        #[qproperty(QString, output, READ, NOTIFY = changed)]
        #[qproperty(bool, mix, READ, NOTIFY = changed)]
        #[qproperty(QString, dir, READ, NOTIFY = changed)]
        // Result of the last action: where the file went, or the error
        #[qproperty(QString, message, READ, NOTIFY = changed)]
        #[qproperty(bool, failed, READ, NOTIFY = changed)]
        type Cassette = super::CassetteRust;

        #[qsignal]
        fn changed(self: Pin<&mut Cassette>);

        // Reads the folder, the choices and the recording in progress again
        #[qinvokable]
        fn refresh(self: Pin<&mut Cassette>);
        // Once every 250 ms while something plays or records: position, end of file, state of the recorder
        #[qinvokable]
        fn tick(self: Pin<&mut Cassette>);
        #[qinvokable]
        fn play(self: Pin<&mut Cassette>, path: &QString);
        #[qinvokable]
        #[cxx_name = "togglePause"]
        fn toggle_pause(self: Pin<&mut Cassette>);
        #[qinvokable]
        #[cxx_name = "stopPlay"]
        fn stop_play(self: Pin<&mut Cassette>);
        #[qinvokable]
        fn next(self: Pin<&mut Cassette>);
        #[qinvokable]
        fn prev(self: Pin<&mut Cassette>);
        #[qinvokable]
        #[cxx_name = "seekBy"]
        fn seek_by(self: Pin<&mut Cassette>, seconds: f64);
        #[qinvokable]
        #[cxx_name = "seekTo"]
        fn seek_to(self: Pin<&mut Cassette>, seconds: f64);
        #[qinvokable]
        #[cxx_name = "startRecord"]
        fn start_record(self: Pin<&mut Cassette>);
        #[qinvokable]
        #[cxx_name = "stopRecord"]
        fn stop_record(self: Pin<&mut Cassette>);
        // "input" or "output": none, default or the name of a device
        #[qinvokable]
        #[cxx_name = "setChoice"]
        fn set_choice(self: Pin<&mut Cassette>, which: &QString, value: &QString);
        // Devices the recorder can listen to, as JSON (see library::sources_json)
        #[qinvokable]
        fn sources(self: &Cassette) -> QString;
        #[qinvokable]
        fn trash(self: Pin<&mut Cassette>, path: &QString);
        #[qinvokable]
        #[cxx_name = "openFolder"]
        fn open_folder(self: &Cassette);
        #[qinvokable]
        fn reveal(self: &Cassette, path: &QString);
        #[qinvokable]
        #[cxx_name = "clearMessage"]
        fn clear_message(self: Pin<&mut Cassette>);
    }

    impl cxx_qt::Threading for Fili {}
    impl cxx_qt::Initialize for Fili {}
    impl cxx_qt::Threading for Cassette {}
    impl cxx_qt::Initialize for Cassette {}
}

use std::{path::PathBuf, pin::Pin};

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;

use crate::{i18n, library, player::Player, recorder, theme, window};

fn home() -> String {
    std::env::var("HOME").unwrap_or_default()
}

fn state_dir() -> PathBuf {
    PathBuf::from(std::env::var("XDG_STATE_HOME").unwrap_or_else(|_| format!("{}/.local/state", home()))).join("filigrane")
}

fn ui_file() -> PathBuf {
    state_dir().join("fili-recorder-ui")
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
        // The settings directory (fili-recorder.toml, theme.toml written by `fili-theme font|header` or by hand)
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
        // Commands from `fili-recorder ctl`
        let qt = self.qt_thread();
        crate::ctl::serve(move |id, verb, arg| {
            let _ = qt.queue(move |mut f| f.as_mut().command(id, &QString::from(&verb), &QString::from(&arg)));
        });
    }
}

impl qobject::Fili {
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
            option_env!("FILI_RECORDER_GIT").map(str::to_string).unwrap_or_else(|| env!("CARGO_PKG_VERSION").to_string());
        let set = recorder::load_settings();
        let rows = [
            (i18n::tr("Also known as"), "fili-recorder (k7)".to_string()),
            (i18n::tr("Part of"), "Filigrane".to_string()),
            (i18n::tr("Version"), version),
            (i18n::tr("Recordings"), set.dir.display().to_string()),
            (i18n::tr("Format"), "WAV · 16 bit · stereo · 48 kHz".to_string()),
            (i18n::tr("Settings"), "~/.config/filigrane/fili-recorder.toml".to_string()),
        ];
        let items: Vec<String> =
            rows.iter().map(|(k, v)| format!("[{},{}]", recorder::json_str(k), recorder::json_str(v))).collect();
        QString::from(&format!("[{}]", items.join(",")))
    }

    pub fn open_settings(&self) {
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

pub struct CassetteRust {
    recordings: QString,
    count: i32,
    total: f64,
    playing: bool,
    paused: bool,
    current: QString,
    position: f64,
    duration: f64,
    recording: bool,
    saving: bool,
    rec_start: f64,
    input: QString,
    output: QString,
    mix: bool,
    dir: QString,
    message: QString,
    failed: bool,
    entries: Vec<library::Entry>,
    player: Option<Player>,
}

impl Default for CassetteRust {
    fn default() -> Self {
        CassetteRust {
            recordings: QString::from("[]"),
            count: 0,
            total: 0.0,
            playing: false,
            paused: false,
            current: QString::default(),
            position: 0.0,
            duration: 0.0,
            recording: false,
            saving: false,
            rec_start: 0.0,
            input: QString::from("default"),
            output: QString::from("default"),
            mix: true,
            dir: QString::default(),
            message: QString::default(),
            failed: false,
            entries: Vec::new(),
            player: None,
        }
    }
}

impl CassetteRust {
    // The player starts with the first file played: nothing runs before
    fn player(&mut self) -> &Player {
        self.player.get_or_insert_with(Player::pw_cat)
    }
}

impl cxx_qt::Initialize for qobject::Cassette {
    fn initialize(self: Pin<&mut Self>) {
        self.refresh();
    }
}

impl qobject::Cassette {
    // The recorder's state: settings (folder, sources, mode) and the recording in progress
    fn read_recorder(mut self: Pin<&mut Self>) -> bool {
        recorder::reap();
        let set = recorder::load_settings();
        let session = recorder::load_session();
        let (recording, saving, start) = session.as_ref().map_or((false, false, 0.0), |s| (true, s.saving, s.start as f64));
        let (input, output) =
            session.as_ref().map_or((set.input.clone(), set.output.clone()), |s| (s.input.clone(), s.output.clone()));
        let dir = set.dir.display().to_string();
        let same = self.recording == recording
            && self.saving == saving
            && self.rec_start == start
            && self.input.to_string() == input
            && self.output.to_string() == output
            && self.mix == set.mix
            && self.dir.to_string() == dir;
        if !same {
            let mut me = self.as_mut().rust_mut();
            me.recording = recording;
            me.saving = saving;
            me.rec_start = start;
            me.input = QString::from(&input);
            me.output = QString::from(&output);
            me.mix = set.mix;
            me.dir = QString::from(&dir);
        }
        !same
    }

    fn read_folder(mut self: Pin<&mut Self>) -> bool {
        let dir = PathBuf::from(self.dir.to_string());
        let entries = library::list(&dir);
        if entries == self.entries {
            return false;
        }
        let json = library::json(&entries);
        let mut me = self.as_mut().rust_mut();
        me.count = entries.len() as i32;
        me.total = entries.iter().map(|e| e.duration).sum();
        me.recordings = QString::from(&json);
        me.entries = entries;
        true
    }

    pub fn refresh(mut self: Pin<&mut Self>) {
        let a = self.as_mut().read_recorder();
        let b = self.as_mut().read_folder();
        if a || b {
            self.as_mut().changed();
        }
    }

    // Index of the file being played in the list
    fn index_of(&self, path: &str) -> Option<usize> {
        self.entries.iter().position(|e| e.path.display().to_string() == path)
    }

    pub fn tick(mut self: Pin<&mut Self>) {
        let mut dirty = self.as_mut().read_recorder();
        if self.recording {
            // A recording that just ended: the new file is in the folder
            dirty |= self.as_mut().read_folder();
        }
        let snap = self.player.as_ref().map(|p| p.snapshot()).unwrap_or_default();
        {
            let mut me = self.as_mut().rust_mut();
            if me.playing != snap.playing
                || me.paused != snap.paused
                || me.position != snap.position
                || me.duration != snap.duration
            {
                me.playing = snap.playing;
                me.paused = snap.paused;
                me.position = snap.position;
                me.duration = snap.duration;
                me.current = QString::from(&snap.path);
                dirty = true;
            }
        }
        if self.player.as_ref().is_some_and(|p| p.take_ended()) {
            // The file played to its end: playback stops, it does not go on to the next recording
            self.as_mut().stop_play();
            return;
        }
        if dirty {
            self.as_mut().changed();
        }
    }

    pub fn play(mut self: Pin<&mut Self>, path: &QString) {
        let path = path.to_string();
        let result = self.as_mut().rust_mut().player().play(std::path::Path::new(&path), 0.0);
        if let Err(e) = result {
            let mut me = self.as_mut().rust_mut();
            me.message = QString::from(&e);
            me.failed = true;
        }
        self.as_mut().tick();
        self.as_mut().changed();
    }

    pub fn toggle_pause(mut self: Pin<&mut Self>) {
        if let Some(p) = self.player.as_ref() {
            p.toggle_pause();
        }
        self.as_mut().tick();
    }

    pub fn stop_play(mut self: Pin<&mut Self>) {
        if let Some(p) = self.player.as_ref() {
            p.stop();
        }
        self.as_mut().tick();
    }

    pub fn next(mut self: Pin<&mut Self>) {
        let target =
            self.index_of(&self.current.to_string()).and_then(|i| self.entries.get(i + 1)).map(|e| e.path.display().to_string());
        match target {
            Some(p) => self.as_mut().play(&QString::from(&p)),
            None => self.as_mut().stop_play(),
        }
    }

    pub fn prev(mut self: Pin<&mut Self>) {
        // After the first three seconds, "previous" restarts the file, as in every player
        if self.position > 3.0 {
            self.as_mut().seek_to(0.0);
            return;
        }
        let target = self
            .index_of(&self.current.to_string())
            .filter(|i| *i > 0)
            .and_then(|i| self.entries.get(i - 1))
            .map(|e| e.path.display().to_string());
        match target {
            Some(p) => self.as_mut().play(&QString::from(&p)),
            None => self.as_mut().seek_to(0.0),
        }
    }

    pub fn seek_by(mut self: Pin<&mut Self>, seconds: f64) {
        if let Some(p) = self.player.as_ref() {
            p.seek_by(seconds);
        }
        self.as_mut().tick();
    }

    pub fn seek_to(mut self: Pin<&mut Self>, seconds: f64) {
        if let Some(p) = self.player.as_ref() {
            p.seek_to(seconds);
        }
        self.as_mut().tick();
    }

    fn report(mut self: Pin<&mut Self>, result: Result<(), String>, saved: bool) {
        let mut me = self.as_mut().rust_mut();
        match result {
            Ok(()) => {
                me.failed = false;
                if !saved {
                    me.message = QString::default();
                }
            }
            Err(e) => {
                me.failed = true;
                me.message = QString::from(&e);
            }
        }
        self.as_mut().refresh();
        self.as_mut().changed();
    }

    pub fn start_record(self: Pin<&mut Self>) {
        if self.recording {
            return;
        }
        let qt = self.qt_thread();
        std::thread::spawn(move || {
            let r = recorder::cmd_start(&[]);
            let _ = qt.queue(move |f| f.report(r, false));
        });
    }

    pub fn stop_record(mut self: Pin<&mut Self>) {
        if !self.recording || self.saving {
            return;
        }
        // Mixing a long recording takes a moment: off the interface thread; the session says "saving" meanwhile
        self.as_mut().rust_mut().saving = true;
        self.as_mut().changed();
        let qt = self.qt_thread();
        std::thread::spawn(move || {
            let r = recorder::cmd_stop();
            let _ = qt.queue(move |mut f| {
                if r.is_ok() {
                    f.as_mut().rust_mut().message = QString::from(i18n::tr("Recording saved"));
                }
                f.report(r, true);
            });
        });
    }

    pub fn set_choice(mut self: Pin<&mut Self>, which: &QString, value: &QString) {
        let (which, value) = (which.to_string(), value.to_string());
        if recorder::save_choice(&which, &value).is_ok() {
            let mut me = self.as_mut().rust_mut();
            match which.as_str() {
                "input" => me.input = QString::from(&value),
                "output" => me.output = QString::from(&value),
                "mode" => me.mix = value != "separate",
                _ => {}
            }
            self.as_mut().changed();
        }
    }

    pub fn sources(&self) -> QString {
        QString::from(&library::sources_json())
    }

    pub fn trash(mut self: Pin<&mut Self>, path: &QString) {
        let path = path.to_string();
        // Stop the player first: the file goes away from under it
        if self.current.to_string() == path {
            self.as_mut().stop_play();
        }
        let ok = std::process::Command::new("gio")
            .args(["trash", &path])
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .is_ok_and(|s| s.success());
        self.as_mut()
            .report(if ok { Ok(()) } else { Err(i18n::tr("The recording could not be moved to the trash").to_string()) }, false);
    }

    pub fn open_folder(&self) {
        let _ = recorder::cmd_folder();
    }

    pub fn reveal(&self, path: &QString) {
        // Casier opens the folder of the recording
        let dir = std::path::Path::new(&path.to_string()).parent().map(|p| p.to_path_buf()).unwrap_or_default();
        let _ = std::process::Command::new("xdg-open")
            .arg(dir)
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn();
    }

    pub fn clear_message(mut self: Pin<&mut Self>) {
        let mut me = self.as_mut().rust_mut();
        me.message = QString::default();
        me.failed = false;
        self.as_mut().changed();
    }
}
