// File formats of the recordings. The recorder always works in WAV (16-bit stereo, 48 kHz); when it stops, the result is
// compressed to the chosen format and the WAV is removed: Opus (about 29 MB an hour, the best choice for voice), MP3 (about
// 43 MB, plays everywhere) or WAV as it is (about 690 MB). The player cannot read a compressed file directly, so it decodes
// it once into a small cache of WAV files and plays that (exact seek and pause). No library: GStreamer (opusenc, oggmux)
// and lame do the work, both are standard parts of the system.
use std::fs::{self, File};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use crate::recorder::{wav_data, wav_header};

pub const OPUS_BITRATE: u64 = 64_000;
pub const MP3_BITRATE: u64 = 96_000;
const RATE: u64 = 48_000;
/// Decoded files kept in the cache (the one being played and the last ones).
const CACHE_KEEP: usize = 3;

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Format {
    Opus,
    Mp3,
    Wav,
}

impl Format {
    /// "opus", "mp3" or "wav"; anything else is the default, Opus.
    pub fn parse(s: &str) -> Format {
        match s {
            "mp3" => Format::Mp3,
            "wav" => Format::Wav,
            _ => Format::Opus,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Format::Opus => "opus",
            Format::Mp3 => "mp3",
            Format::Wav => "wav",
        }
    }

    /// The format of a recording, by its extension.
    pub fn from_path(path: &Path) -> Option<Format> {
        match path.extension()?.to_str()? {
            "opus" => Some(Format::Opus),
            "mp3" => Some(Format::Mp3),
            "wav" => Some(Format::Wav),
            _ => None,
        }
    }
}

fn program_exists(name: &str) -> bool {
    std::env::var("PATH").unwrap_or_default().split(':').any(|d| Path::new(d).join(name).is_file())
}

/// A path that can go inside a GStreamer description (`location="..."`).
fn quotable(path: &Path) -> Result<String, String> {
    let s = path.to_string_lossy().into_owned();
    if s.contains('"') || s.contains('\\') { Err("the folder name cannot contain a quote or a backslash".into()) } else { Ok(s) }
}

/// Compresses a WAV file to `format` next to it and removes the WAV; returns the path of the result (the WAV itself for
/// Format::Wav). On failure the WAV is left untouched.
pub fn encode(wav: &Path, format: Format) -> Result<PathBuf, String> {
    if format == Format::Wav {
        return Ok(wav.to_path_buf());
    }
    let out = wav.with_extension(format.name());
    let mut cmd = match format {
        Format::Opus => {
            if !program_exists("gst-launch-1.0") {
                return Err("gst-launch-1.0 is missing (package gstreamer1)".into());
            }
            let mut c = Command::new("gst-launch-1.0");
            c.args([
                "-q",
                "fdsrc",
                "fd=0",
                "!",
                "rawaudioparse",
                "format=pcm",
                "pcm-format=s16le",
                "sample-rate=48000",
                "num-channels=2",
                "!",
                "audioconvert",
                "!",
                "opusenc",
            ])
            .arg(format!("bitrate={OPUS_BITRATE}"))
            .args(["bitrate-type=cbr", "!", "oggmux", "!", "filesink"])
            .arg(format!("location=\"{}\"", quotable(&out)?));
            c
        }
        _ => {
            if !program_exists("lame") {
                return Err("lame is missing (package lame)".into());
            }
            let mut c = Command::new("lame");
            c.args([
                "-r",
                "-s",
                "48",
                "--resample",
                "48",
                "--bitwidth",
                "16",
                "--signed",
                "--little-endian",
                "-m",
                "j",
                "-b",
                "96",
                "--cbr",
                "-",
            ])
            .arg(&out);
            c
        }
    };
    let (offset, bytes) = wav_data(wav)?;
    let mut child = cmd.stdin(Stdio::piped()).stdout(Stdio::null()).stderr(Stdio::null()).spawn().map_err(|e| e.to_string())?;
    let mut src = File::open(wav).map_err(|e| e.to_string())?;
    src.seek(SeekFrom::Start(offset)).map_err(|e| e.to_string())?;
    if let Some(mut stdin) = child.stdin.take() {
        // A write error means the encoder quit: its exit status says why
        let _ = std::io::copy(&mut src.take(bytes), &mut stdin);
    }
    let ok = child.wait().map(|s| s.success()).unwrap_or(false);
    if !ok || fs::metadata(&out).map(|m| m.len() == 0).unwrap_or(true) {
        let _ = fs::remove_file(&out);
        return Err(format!("the {} encoder failed", format.name()));
    }
    let _ = fs::remove_file(wav);
    Ok(out)
}

/// Length in seconds of a recording, read from the file itself when the format says it (WAV size, last Ogg page of an
/// Opus file) and from the constant bitrate for MP3.
pub fn duration(path: &Path, format: Format) -> Option<f64> {
    match format {
        Format::Wav => wav_data(path).ok().map(|(_, bytes)| (bytes / 4) as f64 / RATE as f64),
        Format::Mp3 => Some(fs::metadata(path).ok()?.len() as f64 * 8.0 / MP3_BITRATE as f64),
        Format::Opus => opus_duration(path),
    }
}

/// The granule position of the last Ogg page counts the samples at 48 kHz, from which the pre-skip of the Opus header
/// is taken off.
fn opus_duration(path: &Path) -> Option<f64> {
    let mut f = File::open(path).ok()?;
    let len = f.metadata().ok()?.len();
    let mut head = vec![0u8; 256.min(len as usize)];
    f.read_exact(&mut head).ok()?;
    let at = head.windows(8).position(|w| w == b"OpusHead")?;
    let pre_skip = u16::from_le_bytes([*head.get(at + 10)?, *head.get(at + 11)?]) as u64;
    let tail_len = 65_536.min(len);
    f.seek(SeekFrom::Start(len - tail_len)).ok()?;
    let mut tail = vec![0u8; tail_len as usize];
    f.read_exact(&mut tail).ok()?;
    let page = tail.windows(4).rposition(|w| w == b"OggS")?;
    let granule = u64::from_le_bytes(tail.get(page + 6..page + 14)?.try_into().ok()?);
    Some(granule.saturating_sub(pre_skip) as f64 / RATE as f64)
}

fn cache_dir() -> PathBuf {
    let base = std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(".cache"));
    base.join("filigrane/cassette")
}

/// FNV-1a: a short name for the cache file of a recording (path, size and date, so an edited file is decoded again).
fn cache_key(path: &Path, size: u64, modified: u64) -> String {
    let mut h: u64 = 0xcbf29ce484222325;
    for b in path.as_os_str().as_encoded_bytes().iter().chain(size.to_le_bytes().iter()).chain(modified.to_le_bytes().iter()) {
        h = (h ^ *b as u64).wrapping_mul(0x100000001b3);
    }
    format!("{h:016x}")
}

/// The WAV file the player reads for a recording: the file itself for a WAV, else its decoded copy in the cache (made on the
/// first call, a few seconds for an hour of sound).
pub fn playable(path: &Path) -> Result<PathBuf, String> {
    playable_in(path, &cache_dir())
}

fn playable_in(path: &Path, dir: &Path) -> Result<PathBuf, String> {
    let format = Format::from_path(path).ok_or("unknown file type")?;
    if format == Format::Wav {
        return Ok(path.to_path_buf());
    }
    let meta = fs::metadata(path).map_err(|e| e.to_string())?;
    let modified = meta.modified().ok().and_then(|m| m.duration_since(std::time::UNIX_EPOCH).ok()).map_or(0, |d| d.as_secs());
    fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    let dest = dir.join(format!("{}.wav", cache_key(path, meta.len(), modified)));
    if wav_data(&dest).is_ok() {
        // Used again: the newest in the cache
        let _ = File::options().append(true).open(&dest);
        return Ok(dest);
    }
    let part = dest.with_extension("part");
    let result = match format {
        Format::Mp3 => decode_mp3(path, &part),
        _ => decode_opus(path, &part),
    };
    if let Err(e) = result {
        let _ = fs::remove_file(&part);
        return Err(e);
    }
    fs::rename(&part, &dest).map_err(|e| e.to_string())?;
    prune(dir, &dest);
    Ok(dest)
}

fn decode_mp3(src: &Path, dest: &Path) -> Result<(), String> {
    if !program_exists("lame") {
        return Err("lame is missing (package lame)".into());
    }
    let ok = Command::new("lame")
        .arg("--decode")
        .arg(src)
        .arg(dest)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .is_ok_and(|s| s.success());
    if ok { Ok(()) } else { Err("the MP3 file could not be decoded".into()) }
}

fn decode_opus(src: &Path, dest: &Path) -> Result<(), String> {
    if !program_exists("gst-launch-1.0") {
        return Err("gst-launch-1.0 is missing (package gstreamer1)".into());
    }
    let mut child = Command::new("gst-launch-1.0")
        .args(["-q", "filesrc"])
        .arg(format!("location=\"{}\"", quotable(src)?))
        .args([
            "!",
            "decodebin",
            "!",
            "audioconvert",
            "!",
            "audioresample",
            "!",
            "audio/x-raw,format=S16LE,rate=48000,channels=2,layout=interleaved",
            "!",
            "fdsink",
            "fd=1",
        ])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| e.to_string())?;
    let mut file = File::create(dest).map_err(|e| e.to_string())?;
    file.write_all(&wav_header(0)).map_err(|e| e.to_string())?;
    let mut out = child.stdout.take().ok_or("no output")?;
    let bytes = std::io::copy(&mut out, &mut file).map_err(|e| e.to_string())?;
    let ok = child.wait().map(|s| s.success()).unwrap_or(false);
    if !ok || bytes == 0 {
        return Err("the Opus file could not be decoded".into());
    }
    // The header with the real length
    file.seek(SeekFrom::Start(0)).map_err(|e| e.to_string())?;
    file.write_all(&wav_header(bytes)).map_err(|e| e.to_string())
}

/// Keeps the newest CACHE_KEEP decoded files (and `keep`), removes the others and any unfinished one.
fn prune(dir: &Path, keep: &Path) {
    let Ok(read) = fs::read_dir(dir) else { return };
    let mut files: Vec<(std::time::SystemTime, PathBuf)> =
        read.filter_map(|e| e.ok()).filter_map(|e| Some((e.metadata().ok()?.modified().ok()?, e.path()))).collect();
    files.sort_by(|a, b| b.0.cmp(&a.0));
    for (i, (_, path)) in files.iter().enumerate() {
        let part = path.extension().is_some_and(|e| e == "part");
        if path != keep && (i >= CACHE_KEEP || part) {
            let _ = fs::remove_file(path);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("fili-recorder-codec-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    /// `seconds` of a quiet tone as a WAV file.
    fn tone(path: &Path, seconds: u64) {
        let mut f = File::create(path).unwrap();
        let bytes = seconds * RATE * 4;
        f.write_all(&wav_header(bytes)).unwrap();
        let samples: Vec<u8> = (0..seconds * RATE)
            .flat_map(|i| {
                (((i as f64 / 20.0).sin() * 3000.0) as i16)
                    .to_le_bytes()
                    .into_iter()
                    .chain((((i as f64 / 20.0).sin() * 3000.0) as i16).to_le_bytes())
            })
            .collect();
        f.write_all(&samples).unwrap();
    }

    #[test]
    fn formats_by_name_and_extension() {
        assert_eq!(Format::parse("mp3"), Format::Mp3);
        assert_eq!(Format::parse("wav"), Format::Wav);
        assert_eq!(Format::parse("anything"), Format::Opus, "Opus is the default");
        assert_eq!(Format::from_path(Path::new("/x/Recording a.opus")), Some(Format::Opus));
        assert_eq!(Format::from_path(Path::new("a.txt")), None);
        assert_eq!(Format::Mp3.name(), "mp3");
    }

    #[test]
    fn the_cache_name_follows_the_file() {
        let a = cache_key(Path::new("/x/a.opus"), 10, 5);
        assert_eq!(a, cache_key(Path::new("/x/a.opus"), 10, 5));
        assert_ne!(a, cache_key(Path::new("/x/a.opus"), 11, 5), "an edited file is decoded again");
        assert_ne!(a, cache_key(Path::new("/x/b.opus"), 10, 5));
    }

    #[test]
    fn a_quote_in_a_folder_name_is_refused_not_mangled() {
        assert!(quotable(Path::new("/x/a\"b.opus")).is_err());
        assert!(quotable(Path::new("/x/Recording 2026 12.34.opus")).is_ok());
    }

    #[test]
    fn opus_round_trip_keeps_the_length() {
        if !program_exists("gst-launch-1.0") {
            return;
        }
        let d = tmp("opus");
        let wav = d.join("Recording a b.wav");
        tone(&wav, 3);
        let out = encode(&wav, Format::Opus).unwrap();
        assert_eq!(out, d.join("Recording a b.opus"));
        assert!(!wav.exists(), "the WAV is removed once the result is safe");
        assert!(fs::metadata(&out).unwrap().len() < 100_000, "much smaller than the 576 KB of the WAV");
        assert!((duration(&out, Format::Opus).unwrap() - 3.0).abs() < 0.05);
        let play = playable_in(&out, &d.join("cache")).unwrap();
        let (_, bytes) = wav_data(&play).unwrap();
        assert!(((bytes / 4) as f64 / 48000.0 - 3.0).abs() < 0.1, "decoded length");
        assert_eq!(playable_in(&out, &d.join("cache")).unwrap(), play, "decoded once");
        let _ = fs::remove_dir_all(d);
    }

    #[test]
    fn mp3_round_trip_keeps_the_length() {
        if !program_exists("lame") {
            return;
        }
        let d = tmp("mp3");
        let wav = d.join("r.wav");
        tone(&wav, 3);
        let out = encode(&wav, Format::Mp3).unwrap();
        assert!((duration(&out, Format::Mp3).unwrap() - 3.0).abs() < 0.2);
        let play = playable_in(&out, &d.join("cache")).unwrap();
        let (_, bytes) = wav_data(&play).unwrap();
        assert!(((bytes / 4) as f64 / 48000.0 - 3.0).abs() < 0.2, "decoded length");
        let _ = fs::remove_dir_all(d);
    }

    #[test]
    fn a_failed_encoder_leaves_the_wav() {
        let d = tmp("fail");
        let wav = d.join("r.wav");
        tone(&wav, 1);
        // A directory in place of the output: the encoder cannot write it
        fs::create_dir_all(d.join("r.mp3")).unwrap();
        if program_exists("lame") {
            assert!(encode(&wav, Format::Mp3).is_err());
            assert!(wav.exists(), "nothing is lost");
        }
        let _ = fs::remove_dir_all(d);
    }
}
