// fili-recorder ("Cassette"): records the sound of the machine, an input (microphone...) and an output (what
// the speakers play), either of them optional, without ever touching the sound itself: it only listens, through two
// PipeWire capture streams (pw-record), like any recording application.
//
//   fili-recorder start [--input NAME|default|none] [--output NAME|default|none]
//   fili-recorder stop | toggle
//   fili-recorder status [--json|--bar]
//   fili-recorder set input|output NAME|default|none     choice kept for the next recordings
//   fili-recorder set mode mix|separate                  one mixed file, or one file per source
//   fili-recorder folder                                 opens the recordings folder (created if it is missing)
//
// Each source is recorded to its own hidden `.part` file; `stop` finalizes them into the recordings folder, mixed in
// one WAV file (default) or as one file per source (`mode = "separate"`). Nothing stays resident: `start` leaves the
// two pw-record processes running on their own and `stop` ends them. Options: ~/.config/filigrane/fili-recorder.toml;
// choices of use: ~/.local/state/filigrane/fili-recorder.toml (see dotfiles/config/filigrane/fili-recorder.toml).
use crate::codec::{self, Format};
use std::collections::HashMap;
use std::fs::{self, File};
use std::io::{BufReader, BufWriter, Read, Write};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode, Stdio};
use std::thread::sleep;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// Signal of the fili-bar module (`fili-shell bar refresh N`).
const BAR_SIGNAL: &str = "19";
const RATE: u32 = 48000;
const CHANNELS: u16 = 2;
const FRAME: usize = 4; // 16-bit stereo

fn home() -> PathBuf {
    PathBuf::from(std::env::var_os("HOME").unwrap_or_default())
}

fn config_file() -> PathBuf {
    let base = std::env::var_os("XDG_CONFIG_HOME").map(PathBuf::from).unwrap_or_else(|| home().join(".config"));
    base.join("filigrane/fili-recorder.toml")
}

fn state_file() -> PathBuf {
    let base = std::env::var_os("XDG_STATE_HOME").map(PathBuf::from).unwrap_or_else(|| home().join(".local/state"));
    base.join("filigrane/fili-recorder.toml")
}

/// The running recording: kept in the runtime folder, so a reboot forgets it.
fn session_file() -> PathBuf {
    let base = std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/tmp"));
    base.join("fili-recorder.session")
}

/// `key = value` lines (`#` comments, optional quotes): the whole syntax of the two settings files.
fn parse_kv(text: &str) -> HashMap<String, String> {
    let mut map = HashMap::new();
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') || line.starts_with('[') {
            continue;
        }
        if let Some((k, v)) = line.split_once('=') {
            let v = v.split(" #").next().unwrap_or("").trim().trim_matches('"');
            map.insert(k.trim().to_string(), v.to_string());
        }
    }
    map
}

fn read_kv(path: &Path) -> HashMap<String, String> {
    fs::read_to_string(path).map(|t| parse_kv(&t)).unwrap_or_default()
}

fn expand(path: &str) -> PathBuf {
    match path.strip_prefix("~/") {
        Some(rest) => home().join(rest),
        None => PathBuf::from(path),
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Settings {
    pub dir: PathBuf,
    pub mix: bool,
    pub input: String,
    pub output: String,
    pub format: Format,
}

pub fn load_settings() -> Settings {
    let conf = read_kv(&config_file());
    let state = read_kv(&state_file());
    let choice = |k: &str| state.get(k).filter(|v| !v.is_empty()).cloned().unwrap_or_else(|| "default".to_string());
    Settings {
        dir: conf.get("dir").filter(|d| !d.is_empty()).map(|d| expand(d)).unwrap_or_else(|| home().join("Music/Recordings")),
        // The choice made in the window (state of use) takes precedence over the options file
        mix: state.get("mode").or(conf.get("mode")).map(|m| m != "separate").unwrap_or(true),
        input: choice("input"),
        output: choice("output"),
        format: Format::parse(state.get("format").or(conf.get("format")).map(String::as_str).unwrap_or("opus")),
    }
}

pub fn save_choice(key: &str, value: &str) -> std::io::Result<()> {
    let path = state_file();
    let mut kv = read_kv(&path);
    kv.insert(key.to_string(), value.to_string());
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir)?;
    }
    let mut keys: Vec<_> = kv.keys().cloned().collect();
    keys.sort();
    let text: String = keys.iter().map(|k| format!("{k} = \"{}\"\n", kv[k])).collect();
    fs::write(path, text)
}

// ---- the session -------------------------------------------------------------------------------------------------

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Session {
    pub start: u64,
    pub mix: bool,
    pub saving: bool,
    pub dir: PathBuf,
    /// Name of the recording without extension, e.g. "Recording 2026-11-13 14.05.12".
    pub name: String,
    pub input: String,
    pub output: String,
    /// "opus", "mp3" or "wav": the format the recording is saved in at the end (empty: WAV, as before this field).
    pub format: String,
    pub input_pid: u32,
    pub output_pid: u32,
}

impl Session {
    fn part(&self, which: &str) -> PathBuf {
        self.dir.join(format!(".{} ({which}).wav.part", self.name))
    }
    fn final_path(&self, which: Option<&str>) -> PathBuf {
        match which {
            Some(w) => self.dir.join(format!("{} ({w}).wav", self.name)),
            None => self.dir.join(format!("{}.wav", self.name)),
        }
    }
    fn render(&self) -> String {
        format!(
            "start={}\nmix={}\nsaving={}\ndir={}\nname={}\ninput={}\noutput={}\nformat={}\ninput_pid={}\noutput_pid={}\n",
            self.start,
            self.mix as u8,
            self.saving as u8,
            self.dir.display(),
            self.name,
            self.input,
            self.output,
            self.format,
            self.input_pid,
            self.output_pid
        )
    }
    fn parse(text: &str) -> Session {
        let mut s = Session::default();
        for line in text.lines() {
            let Some((k, v)) = line.split_once('=') else { continue };
            match k {
                "start" => s.start = v.parse().unwrap_or(0),
                "mix" => s.mix = v == "1",
                "saving" => s.saving = v == "1",
                "dir" => s.dir = PathBuf::from(v),
                "name" => s.name = v.to_string(),
                "input" => s.input = v.to_string(),
                "output" => s.output = v.to_string(),
                "format" => s.format = v.to_string(),
                "input_pid" => s.input_pid = v.parse().unwrap_or(0),
                "output_pid" => s.output_pid = v.parse().unwrap_or(0),
                _ => {}
            }
        }
        s
    }
}

/// The captures this process started and has not waited for yet: when the window starts a recording, the pw-record processes
/// are its children, and a child that ended stays a zombie until its parent waits for it.
static CHILDREN: std::sync::Mutex<Vec<u32>> = std::sync::Mutex::new(Vec::new());

/// Waits (without blocking) for the captures that ended: no zombie is left behind. Called by the window while it runs.
pub fn reap() {
    let mut children = CHILDREN.lock().unwrap_or_else(|e| e.into_inner());
    children.retain(|pid| {
        let mut status = 0;
        // 0: still running (kept); the pid: just reaped; -1: not ours (any more)
        unsafe { libc::waitpid(*pid as i32, &mut status, libc::WNOHANG) == 0 }
    });
}

/// Whether the process runs: a zombie (ended, not waited for) does not.
fn alive(pid: u32) -> bool {
    if pid == 0 {
        return false;
    }
    reap();
    match fs::read_to_string(format!("/proc/{pid}/stat")) {
        // "pid (name) S ...": the state is the first field after the closing parenthesis
        Ok(stat) => !stat.rsplit(')').next().unwrap_or("").trim_start().starts_with('Z'),
        Err(_) => false,
    }
}

/// The recording in progress, or None. A session whose processes are all gone (crash, killed shell) is a leftover:
/// its parts are finalized by the next `stop`, so it is still returned while a part exists on disk.
pub fn load_session() -> Option<Session> {
    let text = fs::read_to_string(session_file()).ok()?;
    let s = Session::parse(&text);
    (!s.name.is_empty()).then_some(s)
}

pub fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

fn refresh_bar() {
    let _ = Command::new("fili-shell").args(["bar", "refresh", BAR_SIGNAL]).stdout(Stdio::null()).stderr(Stdio::null()).status();
}

fn notify(title: &str, body: &str) {
    let _ = Command::new("notify-send").args(["-a", "Cassette", "-i", "audio-input-microphone", title, body]).status();
}

// ---- WAV ---------------------------------------------------------------------------------------------------------

/// Where the samples of a 16-bit stereo WAV file start and how many bytes they cover. pw-record writes the sizes of
/// its header only from time to time while it runs, so the end of the file decides, never the header.
pub fn wav_data(path: &Path) -> Result<(u64, u64), String> {
    let mut f = File::open(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let len = f.metadata().map_err(|e| e.to_string())?.len();
    let mut head = [0u8; 12];
    f.read_exact(&mut head).map_err(|_| format!("{}: not a WAV file", path.display()))?;
    if &head[0..4] != b"RIFF" || &head[8..12] != b"WAVE" {
        return Err(format!("{}: not a WAV file", path.display()));
    }
    let mut pos = 12u64;
    loop {
        let mut ch = [0u8; 8];
        f.read_exact(&mut ch).map_err(|_| format!("{}: no sample data", path.display()))?;
        let size = u32::from_le_bytes([ch[4], ch[5], ch[6], ch[7]]) as u64;
        pos += 8;
        if &ch[0..4] == b"data" {
            let bytes = len.saturating_sub(pos) / FRAME as u64 * FRAME as u64;
            return Ok((pos, bytes));
        }
        pos += size + (size & 1);
        std::io::Seek::seek(&mut f, std::io::SeekFrom::Start(pos)).map_err(|e| e.to_string())?;
    }
}

pub fn wav_header(data_len: u64) -> Vec<u8> {
    let data = data_len.min(u32::MAX as u64 - 36) as u32;
    let mut h = Vec::with_capacity(44);
    h.extend_from_slice(b"RIFF");
    h.extend_from_slice(&(36 + data).to_le_bytes());
    h.extend_from_slice(b"WAVEfmt ");
    h.extend_from_slice(&16u32.to_le_bytes());
    h.extend_from_slice(&1u16.to_le_bytes());
    h.extend_from_slice(&CHANNELS.to_le_bytes());
    h.extend_from_slice(&RATE.to_le_bytes());
    h.extend_from_slice(&(RATE * FRAME as u32).to_le_bytes());
    h.extend_from_slice(&(FRAME as u16).to_le_bytes());
    h.extend_from_slice(&16u16.to_le_bytes());
    h.extend_from_slice(b"data");
    h.extend_from_slice(&data.to_le_bytes());
    h
}

/// Rewrites a part as a clean WAV file (header with the real sizes): a part cut short by a crash stays playable.
fn finish_one(part: &Path, out: &Path, skip: u64) -> Result<(), String> {
    let (offset, bytes) = wav_data(part)?;
    let dropped = (skip * FRAME as u64).min(bytes);
    let (offset, bytes) = (offset + dropped, bytes - dropped);
    let mut src = File::open(part).map_err(|e| e.to_string())?;
    std::io::Seek::seek(&mut src, std::io::SeekFrom::Start(offset)).map_err(|e| e.to_string())?;
    let mut dst = BufWriter::new(File::create(out).map_err(|e| format!("{}: {e}", out.display()))?);
    dst.write_all(&wav_header(bytes)).map_err(|e| e.to_string())?;
    std::io::copy(&mut src.take(bytes), &mut dst).map_err(|e| e.to_string())?;
    dst.flush().map_err(|e| e.to_string())
}

/// Level the speech of a track is brought to before mixing (typical RMS of its active parts, 16-bit scale).
const TARGET_RMS: f64 = 3500.0;
/// The voice sits about 5 dB above what the speakers play: it is what the recording is for, and a video or a call is
/// heard at a steady, loud level while speech has pauses.
const VOICE_BOOST: f64 = 1.8;
/// A window of 100 ms is active (not silence) above this RMS.
const ACTIVE_RMS: f64 = 30.0;
/// The start of a capture is dropped: the microphone of a jack headset clicks for a moment when the stream opens.
const START_SKIP: u64 = RATE as u64 * 3 / 10;

/// Typical level of the parts of a track that are not silence (median RMS of the 100 ms windows above silence, after
/// the start): a microphone is much quieter than what the speakers play, and summing them as they are would bury the
/// voice under the other side of a call. The median, not the mean, so that a click or a loud word does not decide it.
fn typical_rms(path: &Path, skip: u64) -> Result<f64, String> {
    let (off, len) = wav_data(path)?;
    let skip_bytes = (skip * FRAME as u64).min(len);
    let mut f = File::open(path).map_err(|e| e.to_string())?;
    std::io::Seek::seek(&mut f, std::io::SeekFrom::Start(off + skip_bytes)).map_err(|e| e.to_string())?;
    let mut r = BufReader::new(f.take(len - skip_bytes));
    let mut buf = vec![0u8; RATE as usize / 10 * FRAME];
    let mut levels = Vec::new();
    loop {
        let n = fill(&mut r, &mut buf)?;
        if n == 0 {
            break;
        }
        let sum: f64 = buf[..n].as_chunks::<2>().0.iter().map(|c| (i16::from_le_bytes([c[0], c[1]]) as f64).powi(2)).sum();
        let rms = (sum / (n / 2) as f64).sqrt();
        if rms >= ACTIVE_RMS {
            levels.push(rms);
        }
    }
    levels.sort_by(|a, b| a.total_cmp(b));
    Ok(levels.get(levels.len() / 2).copied().unwrap_or(0.0))
}

/// Gain that brings a track to the target level; a track with nothing in it is left alone. A strong boost is capped
/// (it would only raise the noise) and so is a cut (a loud track is never silenced).
fn gain_for(rms: f64, target: f64) -> f64 {
    if rms < ACTIVE_RMS { 1.0 } else { (target / rms).clamp(0.25, 16.0) }
}

/// Soft limiter: the samples are untouched up to 3/4 of the range, above they bend towards the limit instead of
/// clipping, so a voice raised for the mix does not crackle.
fn limit(x: f64) -> i16 {
    const KNEE: f64 = 24000.0;
    const HEAD: f64 = 32767.0 - KNEE;
    let a = x.abs();
    let y = if a <= KNEE { a } else { KNEE + HEAD * ((a - KNEE) / HEAD).tanh() };
    (y.copysign(x)).round() as i16
}

/// Mixes two parts, each one brought to a comparable level first (see `typical_rms`).
fn mix(a: &Path, b: &Path, out: &Path) -> Result<(), String> {
    // `a` is the input (the voice), `b` the output
    mix_with(
        a,
        b,
        out,
        gain_for(typical_rms(a, START_SKIP)?, TARGET_RMS * VOICE_BOOST),
        gain_for(typical_rms(b, START_SKIP)?, TARGET_RMS),
        START_SKIP,
    )
}

/// Sums two parts sample by sample with their gains, the longer one goes on alone once the shorter one ends.
fn mix_with(a: &Path, b: &Path, out: &Path, gain_a: f64, gain_b: f64, skip: u64) -> Result<(), String> {
    let (off_a, len_a) = wav_data(a)?;
    let (off_b, len_b) = wav_data(b)?;
    // The same start is dropped from both, they stay in step
    let drop = |len: u64| (skip * FRAME as u64).min(len);
    let (off_a, len_a, off_b, len_b) = (off_a + drop(len_a), len_a - drop(len_a), off_b + drop(len_b), len_b - drop(len_b));
    let open = |p: &Path, off: u64, len: u64| -> Result<_, String> {
        let mut f = File::open(p).map_err(|e| e.to_string())?;
        std::io::Seek::seek(&mut f, std::io::SeekFrom::Start(off)).map_err(|e| e.to_string())?;
        Ok(BufReader::new(f.take(len)))
    };
    let (mut ra, mut rb) = (open(a, off_a, len_a)?, open(b, off_b, len_b)?);
    let mut dst = BufWriter::new(File::create(out).map_err(|e| format!("{}: {e}", out.display()))?);
    dst.write_all(&wav_header(len_a.max(len_b))).map_err(|e| e.to_string())?;
    let (mut ba, mut bb) = (vec![0u8; 1 << 16], vec![0u8; 1 << 16]);
    loop {
        let na = fill(&mut ra, &mut ba)?;
        let nb = fill(&mut rb, &mut bb)?;
        if na == 0 && nb == 0 {
            break;
        }
        let n = na.max(nb);
        for i in (0..n).step_by(2) {
            let x = if i < na { i16::from_le_bytes([ba[i], ba[i + 1]]) as f64 * gain_a } else { 0.0 };
            let y = if i < nb { i16::from_le_bytes([bb[i], bb[i + 1]]) as f64 * gain_b } else { 0.0 };
            dst.write_all(&limit(x + y).to_le_bytes()).map_err(|e| e.to_string())?;
        }
    }
    dst.flush().map_err(|e| e.to_string())
}

/// Reads until the buffer is full or the input ends; returns the byte count (always a multiple of the frame size).
fn fill(r: &mut impl Read, buf: &mut [u8]) -> Result<usize, String> {
    let mut n = 0;
    while n < buf.len() {
        let got = r.read(&mut buf[n..]).map_err(|e| e.to_string())?;
        if got == 0 {
            break;
        }
        n += got;
    }
    Ok(n / FRAME * FRAME)
}

// ---- commands ----------------------------------------------------------------------------------------------------

fn spawn_capture(output: bool, choice: &str, part: &Path) -> Result<u32, String> {
    let mut cmd = Command::new("pw-record");
    cmd.args(["--rate", &RATE.to_string(), "--channels", &CHANNELS.to_string(), "--format", "s16"]);
    // Shown as "Cassette" in the mixers; the outputs are recorded through the monitor of the sink
    let props = if output { "stream.capture.sink=true application.name=Cassette" } else { "application.name=Cassette" };
    cmd.args(["-P", props]);
    if choice != "default" {
        cmd.args(["--target", choice]);
    }
    cmd.arg(part);
    // Its own process group: a ^C or the end of the terminal that started it must not end the recording
    cmd.stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).process_group(0);
    let child = cmd.spawn().map_err(|e| format!("pw-record: {e} (package pipewire)"))?;
    CHILDREN.lock().unwrap_or_else(|e| e.into_inner()).push(child.id());
    Ok(child.id())
}

fn kill(pid: u32, signal: &str) {
    let _ = Command::new("kill").arg(format!("-{signal}")).arg(pid.to_string()).stderr(Stdio::null()).status();
}

fn stop_process(pid: u32) {
    if !alive(pid) {
        return;
    }
    kill(pid, "INT");
    for _ in 0..50 {
        if !alive(pid) {
            return;
        }
        sleep(Duration::from_millis(100));
    }
    kill(pid, "KILL");
}

pub fn cmd_start(args: &[String]) -> Result<(), String> {
    if load_session().is_some() {
        return Err("already recording".into());
    }
    let mut set = load_settings();
    let mut it = args.iter();
    while let Some(a) = it.next() {
        match a.as_str() {
            "--input" => set.input = it.next().ok_or("--input needs a value")?.clone(),
            "--output" => set.output = it.next().ok_or("--output needs a value")?.clone(),
            "--format" => set.format = Format::parse(it.next().ok_or("--format needs a value")?),
            other => return Err(format!("unknown option {other}")),
        }
    }
    if set.input == "none" && set.output == "none" {
        return Err("nothing to record: choose an input or an output".into());
    }
    fs::create_dir_all(&set.dir).map_err(|e| format!("{}: {e}", set.dir.display()))?;
    let stamp = Command::new("date").arg("+%Y-%m-%d %H.%M.%S").output().ok().and_then(|o| String::from_utf8(o.stdout).ok());
    let mut s = Session {
        start: now(),
        mix: set.mix,
        dir: set.dir,
        name: format!("Recording {}", stamp.unwrap_or_else(|| now().to_string()).trim()),
        input: set.input,
        output: set.output,
        format: set.format.name().to_string(),
        ..Default::default()
    };
    if s.input != "none" {
        s.input_pid = spawn_capture(false, &s.input, &s.part("input"))?;
    }
    if s.output != "none" {
        match spawn_capture(true, &s.output, &s.part("output")) {
            Ok(pid) => s.output_pid = pid,
            Err(e) => {
                stop_process(s.input_pid);
                return Err(e);
            }
        }
    }
    // A source that does not exist makes pw-record quit at once: say so rather than "recording" nothing
    sleep(Duration::from_millis(500));
    let dead: Vec<&str> = [("input", s.input_pid), ("output", s.output_pid)]
        .iter()
        .filter(|(_, pid)| *pid != 0 && !alive(*pid))
        .map(|(n, _)| *n)
        .collect();
    if !dead.is_empty() {
        stop_process(s.input_pid);
        stop_process(s.output_pid);
        let _ = fs::remove_file(s.part("input"));
        let _ = fs::remove_file(s.part("output"));
        return Err(format!("the {} could not be recorded (unplugged or unknown source?)", dead.join(" and the ")));
    }
    fs::write(session_file(), s.render()).map_err(|e| e.to_string())?;
    refresh_bar();
    println!("{}", s.dir.join(&s.name).display());
    Ok(())
}

pub fn cmd_stop() -> Result<(), String> {
    let mut s = load_session().ok_or("not recording")?;
    s.saving = true;
    let _ = fs::write(session_file(), s.render());
    refresh_bar();
    stop_process(s.input_pid);
    stop_process(s.output_pid);
    let result = finalize(&s);
    let _ = fs::remove_file(session_file());
    refresh_bar();
    match result {
        Ok((files, warning)) => {
            for f in &files {
                println!("{}", f.display());
            }
            let name = files.first().and_then(|f| f.file_name()).map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
            match warning {
                // The recording is safe as a WAV file: say why it was not compressed
                Some(w) => {
                    eprintln!("fili-recorder: kept as WAV: {w}");
                    notify("Recording saved as WAV", &format!("{name}: {w}"));
                }
                None => notify("Recording saved", &name),
            }
            Ok(())
        }
        Err(e) => {
            notify("Recording failed", &e);
            Err(e)
        }
    }
}

/// Turns the parts into the final files; the parts are removed only once their content is safe.
fn finalize(s: &Session) -> Result<(Vec<PathBuf>, Option<String>), String> {
    let (pi, po) = (s.part("input"), s.part("output"));
    let have = |p: &Path| wav_data(p).map(|(_, n)| n > 0).unwrap_or(false);
    let (hi, ho) = (have(&pi), have(&po));
    let mut files = Vec::new();
    if s.mix || !(hi && ho) {
        let out = s.final_path(None);
        match (hi, ho) {
            (true, true) => mix(&pi, &po, &out)?,
            (true, false) => finish_one(&pi, &out, START_SKIP)?,
            (false, true) => finish_one(&po, &out, START_SKIP)?,
            (false, false) => return Err("nothing was recorded".into()),
        }
        files.push(out);
    } else {
        for (part, which) in [(&pi, "input"), (&po, "output")] {
            let out = s.final_path(Some(which));
            finish_one(part, &out, START_SKIP)?;
            files.push(out);
        }
    }
    let _ = fs::remove_file(&pi);
    let _ = fs::remove_file(&po);
    // The WAV files are the safe result; compressing them is the last step, and a failure keeps them
    let format = if s.format.is_empty() { Format::Wav } else { Format::parse(&s.format) };
    let mut warning = None;
    let files = files
        .into_iter()
        .map(|f| match codec::encode(&f, format) {
            Ok(done) => done,
            Err(e) => {
                warning = Some(e);
                f
            }
        })
        .collect();
    Ok((files, warning))
}

/// The folder is created on the first recording: opening it before that must still work.
pub fn cmd_folder() -> Result<(), String> {
    let dir = load_settings().dir;
    fs::create_dir_all(&dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    Command::new("xdg-open")
        .arg(&dir)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .process_group(0)
        .spawn()
        .map_err(|e| format!("xdg-open: {e}"))?;
    Ok(())
}

fn cmd_set(args: &[String]) -> Result<(), String> {
    match args {
        [key, value] if key == "input" || key == "output" => save_choice(key, value).map_err(|e| e.to_string()),
        [key, value] if key == "mode" && (value == "mix" || value == "separate") => {
            save_choice(key, value).map_err(|e| e.to_string())
        }
        [key, value] if key == "format" && matches!(value.as_str(), "opus" | "mp3" | "wav") => {
            save_choice(key, value).map_err(|e| e.to_string())
        }
        _ => {
            Err("usage: fili-recorder set input|output NAME|default|none | set mode mix|separate | set format opus|mp3|wav"
                .into())
        }
    }
}

pub fn json_str(s: &str) -> String {
    let mut o = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => o.push_str("\\\""),
            '\\' => o.push_str("\\\\"),
            '\n' => o.push_str("\\n"),
            c if (c as u32) < 0x20 => o.push_str(&format!("\\u{:04x}", c as u32)),
            c => o.push(c),
        }
    }
    o.push('"');
    o
}

fn status_json() -> String {
    let set = load_settings();
    let s = load_session();
    let (rec, saving) = (s.is_some(), s.as_ref().is_some_and(|s| s.saving));
    let d = s.unwrap_or_default();
    let mix = if rec { d.mix } else { set.mix };
    // What the next (or this) recording uses
    let (input, output) = if rec { (d.input.clone(), d.output.clone()) } else { (set.input.clone(), set.output.clone()) };
    format!(
        "{{\"recording\":{rec},\"saving\":{saving},\"start\":{},\"input\":{},\"output\":{},\"dir\":{},\"mode\":{},\"format\":{}}}",
        d.start,
        json_str(&input),
        json_str(&output),
        json_str(&if rec { d.dir.clone() } else { set.dir.clone() }.display().to_string()),
        json_str(if mix { "mix" } else { "separate" }),
        json_str(if rec && !d.format.is_empty() { &d.format } else { set.format.name() })
    )
}

/// One line for the fili-bar (BarScript): the record mark with REC while recording, the mark alone at rest (class
/// "idle": the module then lives in the drawer).
fn status_bar() -> String {
    if load_session().is_some() {
        "{\"text\":\"\u{f2f10} REC\",\"class\":\"rec\"}".into()
    } else {
        "{\"text\":\"\u{f2f10}\",\"class\":\"idle\"}".into()
    }
}

fn cmd_status(args: &[String]) -> Result<(), String> {
    match args.first().map(String::as_str) {
        Some("--json") => println!("{}", status_json()),
        Some("--bar") => println!("{}", status_bar()),
        None => match load_session() {
            Some(s) => println!("recording since {}s: {}", now().saturating_sub(s.start), s.dir.join(&s.name).display()),
            None => println!("not recording"),
        },
        Some(other) => return Err(format!("unknown option {other}")),
    }
    Ok(())
}

fn usage() -> String {
    "usage: fili-recorder start [--input NAME|default|none] [--output NAME|default|none]\n       fili-recorder stop | toggle\n       fili-recorder status [--json|--bar]\n       fili-recorder set input|output NAME|default|none\n       fili-recorder folder".into()
}

fn run(args: &[String]) -> Result<(), String> {
    let rest = args.get(1..).unwrap_or(&[]);
    match args.first().map(String::as_str) {
        Some("start") => cmd_start(rest),
        Some("stop") => cmd_stop(),
        Some("toggle") => {
            if load_session().is_some() {
                cmd_stop()
            } else {
                cmd_start(rest)
            }
        }
        Some("status") => cmd_status(rest),
        Some("set") => cmd_set(rest),
        Some("folder") => cmd_folder(),
        _ => Err(usage()),
    }
}

/// The command line (`fili-recorder start|stop|toggle|status|set|folder`): runs before Qt starts.
pub fn cli(args: &[String]) -> ExitCode {
    match run(args) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("fili-recorder: {e}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("fili-recorder-test-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    /// A WAV file as pw-record writes it, with a header whose size lags behind the samples.
    fn write_wav(path: &Path, samples: &[i16], header_len: u32) {
        let mut h = wav_header(samples.len() as u64 * 2);
        h[40..44].copy_from_slice(&header_len.to_le_bytes());
        let mut f = File::create(path).unwrap();
        f.write_all(&h).unwrap();
        for s in samples {
            f.write_all(&s.to_le_bytes()).unwrap();
        }
    }

    fn read_samples(path: &Path) -> Vec<i16> {
        let (off, len) = wav_data(path).unwrap();
        let bytes = fs::read(path).unwrap();
        bytes[off as usize..(off + len) as usize].chunks(2).map(|c| i16::from_le_bytes([c[0], c[1]])).collect()
    }

    #[test]
    fn config_lines() {
        let kv = parse_kv("# comment\n[recording]\ndir = \"~/Music/x\" # where\nmode=separate\n\n");
        assert_eq!(kv["dir"], "~/Music/x");
        assert_eq!(kv["mode"], "separate");
    }

    #[test]
    fn session_round_trip() {
        let s = Session {
            start: 12,
            mix: true,
            saving: true,
            dir: "/tmp/r".into(),
            name: "Recording a b".into(),
            input: "default".into(),
            output: "alsa_output.x".into(),
            format: "opus".into(),
            input_pid: 7,
            output_pid: 9,
        };
        assert_eq!(Session::parse(&s.render()), s);
        assert_eq!(s.part("input"), PathBuf::from("/tmp/r/.Recording a b (input).wav.part"));
    }

    #[test]
    fn mixes_with_the_limiter_and_unequal_lengths() {
        let d = tmp("mix");
        write_wav(&d.join("a.wav"), &[100, -100, 30000, 30000, 7, 7], 0);
        write_wav(&d.join("b.wav"), &[1, 2, 30000, -30000], 4);
        mix_with(&d.join("a.wav"), &d.join("b.wav"), &d.join("out.wav"), 1.0, 1.0, 0).unwrap();
        let got = read_samples(&d.join("out.wav"));
        assert_eq!(&got[..2], &[101, -98]);
        assert!(got[2] > 30000, "soft limit, never wrapping: {}", got[2]);
        assert_eq!(&got[3..], &[0, 7, 7]);
        // The header of the result tells the real length
        let h = fs::read(d.join("out.wav")).unwrap();
        assert_eq!(u32::from_le_bytes([h[40], h[41], h[42], h[43]]), 12);
        let _ = fs::remove_dir_all(d);
    }

    #[test]
    fn a_quiet_voice_is_not_buried_by_a_loud_track() {
        let d = tmp("level");
        // 2 s of a quiet "voice" (RMS ~ 300) against 2 s of a loud track (RMS ~ 6000), both over 100 ms windows
        let tone =
            |amp: f64| -> Vec<i16> { (0..RATE as usize * 2 * 2).map(|i| (amp * (i as f64 / 40.0).sin()) as i16).collect() };
        write_wav(&d.join("mic.wav"), &tone(420.0), 0);
        write_wav(&d.join("out.wav"), &tone(8500.0), 0);
        let (rm, ro) = (typical_rms(&d.join("mic.wav"), 0).unwrap(), typical_rms(&d.join("out.wav"), 0).unwrap());
        assert!((rm - 297.0).abs() < 15.0 && (ro - 6010.0).abs() < 100.0, "{rm} {ro}");
        let (gm, go) = (gain_for(rm, TARGET_RMS), gain_for(ro, TARGET_RMS));
        // After the gains the two tracks sit within 1 dB of each other
        assert!((20.0 * ((rm * gm) / (ro * go)).log10()).abs() < 1.0);
        assert!(gm > 5.0 && go < 1.0);
        // Silence is left alone, a nearly empty track is not boosted into noise
        assert_eq!(gain_for(0.0, TARGET_RMS), 1.0);
        assert_eq!(gain_for(31.0, TARGET_RMS), 16.0);
        let _ = fs::remove_dir_all(d);
    }

    #[test]
    fn a_start_click_and_one_loud_word_do_not_decide_the_level() {
        let d = tmp("click");
        let win = RATE as usize / 10 * 2; // samples of 100 ms, stereo
        let mut v: Vec<i16> = Vec::new();
        let tone = |amp: f64, n: usize, v: &mut Vec<i16>| v.extend((0..n).map(|i| (amp * (i as f64 / 9.0).sin()) as i16));
        tone(20000.0, win * 3, &mut v); // the click when the stream opens (300 ms)
        for k in 0..20 {
            tone(if k == 10 { 12000.0 } else { 500.0 }, win, &mut v); // quiet speech, one loud word
        }
        write_wav(&d.join("mic.wav"), &v, 0);
        let rms = typical_rms(&d.join("mic.wav"), START_SKIP).unwrap();
        assert!((rms - 354.0).abs() < 25.0, "typical level of the speech, not of the click: {rms}");
        // The skipped start is not in the output either, and the two sides stay in step
        write_wav(&d.join("out.wav"), &v, 0);
        mix_with(&d.join("mic.wav"), &d.join("out.wav"), &d.join("m.wav"), 1.0, 1.0, START_SKIP).unwrap();
        assert_eq!(read_samples(&d.join("m.wav")).len(), v.len() - win * 3);
        let _ = fs::remove_dir_all(d);
    }

    #[test]
    fn the_limiter_keeps_small_samples_and_bends_large_ones() {
        assert_eq!(limit(1234.0), 1234);
        assert_eq!(limit(-24000.0), -24000);
        assert!(limit(40000.0) > 30000);
        assert_eq!(limit(1.0e9), 32767);
        assert_eq!(limit(-1.0e9), -32767);
    }

    #[test]
    fn a_lone_part_is_repaired_not_mixed() {
        let d = tmp("one");
        write_wav(&d.join("a.part"), &[5, 6, 7, 8], 0xFFFF_FFFF);
        finish_one(&d.join("a.part"), &d.join("a.wav"), 0).unwrap();
        assert_eq!(read_samples(&d.join("a.wav")), vec![5, 6, 7, 8]);
        let _ = fs::remove_dir_all(d);
    }

    #[test]
    fn rejects_what_is_not_a_wav() {
        let d = tmp("bad");
        fs::write(d.join("x.wav"), b"not a wav file at all").unwrap();
        assert!(wav_data(&d.join("x.wav")).is_err());
        let _ = fs::remove_dir_all(d);
    }

    #[test]
    fn a_zombie_is_not_alive_and_is_reaped() {
        let child = Command::new("true").spawn().unwrap();
        let pid = child.id();
        CHILDREN.lock().unwrap().push(pid);
        // `true` ends at once; until it is waited for, it is a zombie
        for _ in 0..100 {
            if !alive(pid) {
                break;
            }
            sleep(Duration::from_millis(10));
        }
        assert!(!alive(pid));
        assert!(!Path::new(&format!("/proc/{pid}")).exists(), "reaped: the process is gone from /proc");
        assert!(!alive(0));
    }

    #[test]
    fn json_escapes() {
        assert_eq!(json_str("a\"b\\c\n"), "\"a\\\"b\\\\c\\n\"");
    }
}
