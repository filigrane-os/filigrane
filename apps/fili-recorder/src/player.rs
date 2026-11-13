// Playback of the recordings: the WAV files written by the recorder (16-bit stereo, 48 kHz) are read by a thread of this
// process and fed to `pw-cat --playback` through a small pipe, so pause, seek and the position are exact and no other
// player is needed. Nothing runs while nothing plays: the thread sleeps on a condition variable.
use std::fs::File;
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Arc, Condvar, Mutex};
use std::time::Duration;

use crate::recorder::wav_data;

pub const RATE: u64 = 48000;
const FRAME: u64 = 4;
/// Frames per write: 25 ms, the grain of the position and of a seek.
const CHUNK_FRAMES: u64 = RATE / 40;

#[derive(Default)]
struct State {
    path: Option<PathBuf>,
    /// Frame about to be written.
    pos: u64,
    total: u64,
    paused: bool,
    /// Frame to jump to, set by `seek_to` and taken by the thread.
    seek: Option<u64>,
    /// A new file was asked for (or a stop): the thread restarts its sink.
    generation: u64,
    /// The file played to its end (the window goes on to the next one).
    ended: bool,
    quit: bool,
}

struct Shared {
    state: Mutex<State>,
    wake: Condvar,
}

pub struct Player {
    shared: Arc<Shared>,
}

/// What the interface shows: playing (a file is loaded, paused or not), paused, position and length in seconds, ended.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Snapshot {
    pub playing: bool,
    pub paused: bool,
    pub path: String,
    pub position: f64,
    pub duration: f64,
    pub ended: bool,
}

impl Player {
    /// `sink`: the program that plays the raw samples read on its standard input (pw-cat in the application).
    pub fn new(sink: Vec<String>) -> Player {
        let shared = Arc::new(Shared { state: Mutex::new(State::default()), wake: Condvar::new() });
        let thread_shared = shared.clone();
        std::thread::spawn(move || worker(thread_shared, sink));
        Player { shared }
    }

    pub fn pw_cat() -> Player {
        let args = [
            "pw-cat",
            "--playback",
            "--raw",
            "--format",
            "s16",
            "--rate",
            "48000",
            "--channels",
            "2",
            "--latency",
            "60ms",
            "-P",
            "application.name=Cassette",
            "-",
        ];
        Player::new(args.iter().map(|s| s.to_string()).collect())
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, State> {
        self.shared.state.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// Starts a file from the beginning (or from `at` seconds).
    pub fn play(&self, path: &Path, at: f64) -> Result<(), String> {
        let (_, bytes) = wav_data(path)?;
        let mut s = self.lock();
        s.path = Some(path.to_path_buf());
        s.total = bytes / FRAME;
        s.pos = ((at.max(0.0) * RATE as f64) as u64).min(s.total);
        s.paused = false;
        s.ended = false;
        s.seek = None;
        s.generation += 1;
        self.shared.wake.notify_all();
        Ok(())
    }

    pub fn stop(&self) {
        let mut s = self.lock();
        s.path = None;
        s.paused = false;
        s.ended = false;
        s.generation += 1;
        self.shared.wake.notify_all();
    }

    pub fn toggle_pause(&self) {
        let mut s = self.lock();
        if s.path.is_some() {
            s.paused = !s.paused;
            self.shared.wake.notify_all();
        }
    }

    /// Jumps to a position (seconds), kept inside the file.
    pub fn seek_to(&self, seconds: f64) {
        let mut s = self.lock();
        if s.path.is_some() {
            let frame = ((seconds.max(0.0) * RATE as f64) as u64).min(s.total);
            s.seek = Some(frame);
            s.pos = frame;
            s.ended = false;
            self.shared.wake.notify_all();
        }
    }

    pub fn seek_by(&self, delta: f64) {
        let now = self.snapshot().position;
        self.seek_to(now + delta);
    }

    pub fn snapshot(&self) -> Snapshot {
        let s = self.lock();
        Snapshot {
            playing: s.path.is_some(),
            paused: s.paused,
            path: s.path.as_ref().map(|p| p.display().to_string()).unwrap_or_default(),
            position: s.pos as f64 / RATE as f64,
            duration: s.total as f64 / RATE as f64,
            ended: s.ended,
        }
    }

    /// Takes the "ended" flag: true once per end of file.
    pub fn take_ended(&self) -> bool {
        let mut s = self.lock();
        std::mem::take(&mut s.ended)
    }
}

impl Drop for Player {
    fn drop(&mut self) {
        let mut s = self.lock();
        s.quit = true;
        s.generation += 1;
        self.shared.wake.notify_all();
    }
}

/// A pipe of one page: the sound that is already written when a pause or a seek comes is about 20 ms.
fn shrink_pipe(sink: &std::process::ChildStdin) {
    use std::os::fd::AsRawFd;
    // F_SETPIPE_SZ
    unsafe { libc::fcntl(sink.as_raw_fd(), 1031, 4096) };
}

fn spawn_sink(sink: &[String]) -> Option<std::process::Child> {
    let child = Command::new(sink.first()?)
        .args(&sink[1..])
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .ok()?;
    if let Some(stdin) = child.stdin.as_ref() {
        shrink_pipe(stdin);
    }
    Some(child)
}

fn worker(shared: Arc<Shared>, sink: Vec<String>) {
    fn lock(s: &Shared) -> std::sync::MutexGuard<'_, State> {
        s.state.lock().unwrap_or_else(|e| e.into_inner())
    }
    loop {
        // Wait for a file to play
        let (path, generation) = {
            let mut s = lock(&shared);
            loop {
                if s.quit {
                    return;
                }
                if s.path.is_some() && !s.ended {
                    break;
                }
                s = shared.wake.wait(s).unwrap_or_else(|e| e.into_inner());
            }
            (s.path.clone().unwrap_or_default(), s.generation)
        };
        let Ok((offset, _)) = wav_data(&path) else {
            let mut s = lock(&shared);
            s.path = None;
            continue;
        };
        let (Ok(mut file), Some(mut child)) = (File::open(&path), spawn_sink(&sink)) else {
            let mut s = lock(&shared);
            s.path = None;
            continue;
        };
        let mut stdin = child.stdin.take();
        let mut buf = vec![0u8; (CHUNK_FRAMES * FRAME) as usize];
        let mut at = u64::MAX;
        // Feed until the file ends, a new file is asked for, or the sink goes away
        loop {
            let (frame, total) = {
                let mut s = lock(&shared);
                loop {
                    if s.quit || s.generation != generation {
                        break;
                    }
                    if s.paused {
                        s = shared.wake.wait_timeout(s, Duration::from_millis(500)).unwrap_or_else(|e| e.into_inner()).0;
                        continue;
                    }
                    break;
                }
                if s.quit || s.generation != generation {
                    break;
                }
                if let Some(to) = s.seek.take() {
                    s.pos = to;
                }
                (s.pos, s.total)
            };
            if frame >= total {
                let mut s = lock(&shared);
                if s.generation == generation {
                    s.ended = true;
                }
                break;
            }
            if at != frame && file.seek(SeekFrom::Start(offset + frame * FRAME)).is_err() {
                break;
            }
            let want = ((total - frame).min(CHUNK_FRAMES) * FRAME) as usize;
            let Ok(n) = file.read(&mut buf[..want]) else { break };
            if n == 0 {
                let mut s = lock(&shared);
                if s.generation == generation {
                    s.ended = true;
                }
                break;
            }
            let n = n / FRAME as usize * FRAME as usize;
            if stdin.as_mut().is_none_or(|w| w.write_all(&buf[..n]).is_err()) {
                // The sink died (no sound server): stop, do not spin
                let mut s = lock(&shared);
                if s.generation == generation {
                    s.path = None;
                }
                break;
            }
            at = frame + n as u64 / FRAME;
            let mut s = lock(&shared);
            // A seek that came during the write keeps its target
            if s.generation == generation && s.seek.is_none() {
                s.pos = at;
            }
        }
        // End of the file: let the sink play what it has, else cut it at once
        drop(stdin);
        let finished = {
            let s = lock(&shared);
            s.generation == generation && s.ended
        };
        if finished {
            let _ = child.wait();
        } else {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Instant;

    fn wav(dir: &Path, name: &str, frames: u64) -> PathBuf {
        let path = dir.join(name);
        let mut f = File::create(&path).unwrap();
        let data = frames * FRAME;
        let mut h = Vec::new();
        h.extend_from_slice(b"RIFF");
        h.extend_from_slice(&(36 + data as u32).to_le_bytes());
        h.extend_from_slice(b"WAVEfmt ");
        h.extend_from_slice(&16u32.to_le_bytes());
        h.extend_from_slice(&1u16.to_le_bytes());
        h.extend_from_slice(&2u16.to_le_bytes());
        h.extend_from_slice(&48000u32.to_le_bytes());
        h.extend_from_slice(&(48000u32 * 4).to_le_bytes());
        h.extend_from_slice(&4u16.to_le_bytes());
        h.extend_from_slice(&16u16.to_le_bytes());
        h.extend_from_slice(b"data");
        h.extend_from_slice(&(data as u32).to_le_bytes());
        f.write_all(&h).unwrap();
        f.write_all(&vec![0u8; data as usize]).unwrap();
        path
    }

    fn until(what: &str, mut ok: impl FnMut() -> bool) {
        let end = Instant::now() + Duration::from_secs(5);
        while Instant::now() < end {
            if ok() {
                return;
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        panic!("timed out: {what}");
    }

    fn dir(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("fili-recorder-player-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn plays_to_the_end_and_says_so() {
        let d = dir("end");
        let p = Player::new(vec!["cat".into()]);
        p.play(&wav(&d, "a.wav", RATE), 0.0).unwrap();
        assert!(p.snapshot().playing);
        assert!((p.snapshot().duration - 1.0).abs() < 1e-9);
        until("the end", || p.snapshot().ended);
        assert!((p.snapshot().position - 1.0).abs() < 1e-9);
        assert!(p.take_ended());
        assert!(!p.take_ended(), "the end is reported once");
        let _ = std::fs::remove_dir_all(d);
    }

    #[test]
    fn pause_holds_the_position_and_seek_moves_it() {
        let d = dir("pause");
        // A slow sink (it reads 4 KiB, then waits) so that the file is still playing when we pause
        let p = Player::new(vec!["sh".into(), "-c".into(), "while head -c 4096 >/dev/null; do sleep 0.02; done".into()]);
        p.play(&wav(&d, "a.wav", RATE * 20), 0.0).unwrap();
        until("some progress", || p.snapshot().position > 0.05);
        p.toggle_pause();
        std::thread::sleep(Duration::from_millis(200));
        let held = p.snapshot().position;
        std::thread::sleep(Duration::from_millis(200));
        assert_eq!(p.snapshot().position, held, "paused: the position does not move");
        assert!(p.snapshot().paused);
        p.seek_to(10.0);
        assert!((p.snapshot().position - 10.0).abs() < 1e-9, "seek while paused");
        p.seek_by(-4.0);
        assert!((p.snapshot().position - 6.0).abs() < 1e-9, "relative seek");
        p.seek_by(-100.0);
        assert_eq!(p.snapshot().position, 0.0, "kept inside the file");
        p.toggle_pause();
        until("playing again", || p.snapshot().position > 0.05);
        p.stop();
        assert!(!p.snapshot().playing);
        let _ = std::fs::remove_dir_all(d);
    }

    #[test]
    fn a_missing_sink_stops_instead_of_spinning() {
        let d = dir("nosink");
        let p = Player::new(vec!["/nonexistent/player".into()]);
        p.play(&wav(&d, "a.wav", RATE), 0.0).unwrap();
        until("stopped", || !p.snapshot().playing);
        let _ = std::fs::remove_dir_all(d);
    }

    #[test]
    fn rejects_what_is_not_a_wav() {
        let d = dir("bad");
        std::fs::write(d.join("x.wav"), b"nope").unwrap();
        assert!(Player::new(vec!["cat".into()]).play(&d.join("x.wav"), 0.0).is_err());
        let _ = std::fs::remove_dir_all(d);
    }
}
