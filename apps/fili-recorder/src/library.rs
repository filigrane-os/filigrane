// The recordings folder as a list (newest first), and the sound devices the recorder can listen to.
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::UNIX_EPOCH;

use crate::codec::{self, Format};
use crate::recorder::json_str;

#[derive(Clone, Debug, PartialEq)]
pub struct Entry {
    pub path: PathBuf,
    /// File name without the extension.
    pub name: String,
    /// When the recording started (seconds since the epoch): its end (the file's date) minus its length.
    pub when: u64,
    pub duration: f64,
    pub size: u64,
    /// "mix" (both sides in one file), "input" or "output" (one side, in the separate mode).
    pub kind: &'static str,
    /// "opus", "mp3" or "wav".
    pub format: &'static str,
}

fn kind_of(stem: &str) -> &'static str {
    if stem.ends_with(" (input)") {
        "input"
    } else if stem.ends_with(" (output)") {
        "output"
    } else {
        "mix"
    }
}

/// The recordings of a folder (WAV, Opus, MP3), newest first; hidden files (the parts of a recording in progress) are left out.
pub fn list(dir: &Path) -> Vec<Entry> {
    let Ok(read) = fs::read_dir(dir) else { return Vec::new() };
    let mut out: Vec<Entry> = read
        .filter_map(|e| e.ok())
        .filter_map(|e| {
            let path = e.path();
            let file = path.file_name()?.to_string_lossy().into_owned();
            if file.starts_with('.') {
                return None;
            }
            let format = Format::from_path(&path)?;
            let stem = path.file_stem()?.to_string_lossy().into_owned();
            let meta = e.metadata().ok()?;
            let duration = codec::duration(&path, format)?;
            let end = meta.modified().ok()?.duration_since(UNIX_EPOCH).ok()?.as_secs();
            Some(Entry {
                kind: kind_of(&stem),
                format: format.name(),
                name: stem,
                when: end.saturating_sub(duration as u64),
                duration,
                size: meta.len(),
                path,
            })
        })
        .collect();
    out.sort_by(|a, b| b.when.cmp(&a.when).then_with(|| b.name.cmp(&a.name)));
    out
}

/// Renames a recording: `name` replaces the file name without its extension (which stays). Returns the new path.
pub fn rename(path: &Path, name: &str) -> Result<PathBuf, String> {
    let name = name.trim();
    if name.is_empty() {
        return Err("the name is empty".into());
    }
    if name.starts_with('.') || name.contains('/') || name.contains('\0') || name.len() > 200 {
        return Err("this name cannot be used (no slash, no leading dot)".into());
    }
    let ext = path.extension().and_then(|e| e.to_str()).ok_or("not a recording")?;
    let target = path.with_file_name(format!("{name}.{ext}"));
    if target == path {
        return Ok(target);
    }
    if target.exists() {
        return Err("a recording with this name already exists".into());
    }
    fs::rename(path, &target).map_err(|e| e.to_string())?;
    Ok(target)
}

pub fn json(entries: &[Entry]) -> String {
    let items: Vec<String> = entries
        .iter()
        .map(|e| {
            format!(
                "{{\"path\":{},\"name\":{},\"when\":{},\"duration\":{:.2},\"size\":{},\"kind\":{},\"format\":{}}}",
                json_str(&e.path.display().to_string()),
                json_str(&e.name),
                e.when,
                e.duration,
                e.size,
                json_str(e.kind),
                json_str(e.format)
            )
        })
        .collect();
    format!("[{}]", items.join(","))
}

fn pactl(args: &[&str]) -> String {
    Command::new("pactl")
        .args(args)
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).into_owned())
        .unwrap_or_default()
}

/// Devices of `pactl list sources|sinks`: (name, description); a source that is the monitor of a sink is not an input.
fn devices(text: &str, inputs: bool) -> Vec<(String, String)> {
    let mut out = Vec::new();
    for block in text.split("\n\n") {
        let field = |key: &str| block.lines().find_map(|l| l.trim().strip_prefix(key)).map(|v| v.trim().to_string());
        let (Some(name), Some(desc)) = (field("Name:"), field("Description:")) else { continue };
        if inputs && field("Monitor of Sink:").is_some_and(|m| m != "n/a") {
            continue;
        }
        out.push((name, desc));
    }
    out
}

/// `{"inputs": [{name, label}], "outputs": [...], "default_input": name, "default_output": name}` for the pickers.
pub fn sources_json() -> String {
    let list = |v: Vec<(String, String)>| -> String {
        v.iter().map(|(n, d)| format!("{{\"name\":{},\"label\":{}}}", json_str(n), json_str(d))).collect::<Vec<_>>().join(",")
    };
    let inputs = devices(&pactl(&["list", "sources"]), true);
    let outputs = devices(&pactl(&["list", "sinks"]), false);
    format!(
        "{{\"inputs\":[{}],\"outputs\":[{}],\"default_input\":{},\"default_output\":{}}}",
        list(inputs),
        list(outputs),
        json_str(pactl(&["get-default-source"]).trim()),
        json_str(pactl(&["get-default-sink"]).trim())
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn kinds_follow_the_names_the_recorder_writes() {
        assert_eq!(kind_of("Recording 2026-11-13 14.36.16"), "mix");
        assert_eq!(kind_of("Recording 2026-11-13 14.36.16 (input)"), "input");
        assert_eq!(kind_of("Recording 2026-11-13 14.36.16 (output)"), "output");
    }

    #[test]
    fn inputs_leave_the_monitors_out() {
        let sources = "Source #1\n\tName: alsa_input.mic\n\tDescription: Mic\n\tMonitor of Sink: n/a\n\nSource #2\n\tName: alsa_output.x.monitor\n\tDescription: Monitor of X\n\tMonitor of Sink: alsa_output.x\n";
        assert_eq!(devices(sources, true), vec![("alsa_input.mic".to_string(), "Mic".to_string())]);
        let sinks =
            "Sink #3\n\tName: alsa_output.x\n\tDescription: Speakers\n\nSink #4\n\tName: alsa_output.y\n\tDescription: HDMI\n";
        assert_eq!(devices(sinks, false).len(), 2);
    }

    #[test]
    fn renames_keep_the_extension_and_refuse_a_clash() {
        let d = std::env::temp_dir().join(format!("fili-recorder-rename-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        fs::write(d.join("Recording a.opus"), b"x").unwrap();
        fs::write(d.join("Taken.opus"), b"y").unwrap();
        let new = rename(&d.join("Recording a.opus"), "  Team meeting 2026.11  ").unwrap();
        assert_eq!(new, d.join("Team meeting 2026.11.opus"));
        assert!(new.exists() && !d.join("Recording a.opus").exists());
        assert!(rename(&new, "Taken").is_err(), "never replaces another recording");
        assert!(rename(&new, "").is_err() && rename(&new, "a/b").is_err() && rename(&new, ".hidden").is_err());
        assert_eq!(rename(&new, "Team meeting 2026.11").unwrap(), new, "same name: nothing to do");
        let _ = fs::remove_dir_all(d);
    }

    #[test]
    fn lists_the_wav_files_newest_first_without_the_parts() {
        let d = std::env::temp_dir().join(format!("fili-recorder-lib-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        let mut header = vec![0u8; 44];
        header[..4].copy_from_slice(b"RIFF");
        header[8..16].copy_from_slice(b"WAVEfmt ");
        header[36..40].copy_from_slice(b"data");
        let mut body = header.clone();
        body.extend(vec![0u8; 48000 * 4 * 2]);
        fs::write(d.join("Recording a (input).wav"), &body).unwrap();
        fs::write(d.join(".Recording b (input).wav.part"), &body).unwrap();
        fs::write(d.join("notes.txt"), b"x").unwrap();
        let list = list(&d);
        assert_eq!(list.len(), 1);
        assert_eq!((list[0].kind, list[0].duration), ("input", 2.0));
        assert!(json(&list).contains("\"duration\":2.00"));
        let _ = fs::remove_dir_all(d);
    }
}
