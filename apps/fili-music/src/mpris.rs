//! MPRIS: the player on the session bus as `org.mpris.MediaPlayer2.fili_music`, so media keys, `playerctl` and the bar see it.
//!
//! The window's heartbeat (`Music::tick`) publishes the core's player state; a thread of this module reads it, looks the
//! current track up when it changes and tells the bus what changed. Commands from the bus go straight to the core.

use std::{
    collections::HashMap,
    sync::Mutex,
    thread,
    time::Duration,
};

use serde_json::Value;
use zbus::{
    blocking::connection::Builder,
    interface,
    zvariant::{ObjectPath, OwnedValue, Value as Var},
};

use crate::music::dispatch;

const PATH: &str = "/org/mpris/MediaPlayer2";

/// What the bus shows, refreshed by the thread of this module
#[derive(Default, Clone, PartialEq)]
struct Shown {
    status: String,
    loop_status: String,
    shuffle: bool,
    volume: f64,
    track_id: i64,
    title: String,
    artists: Vec<String>,
    album: String,
    art_url: String,
    length_us: i64,
    has_track: bool,
}

static STATE: Mutex<Option<Value>> = Mutex::new(None);
static SHOWN: Mutex<Option<Shown>> = Mutex::new(None);
static POSITION_US: Mutex<i64> = Mutex::new(0);

/// Called by the heartbeat with the `data` of get_player_state
pub fn publish(state_json: &str) {
    if let Ok(v) = serde_json::from_str::<Value>(state_json) {
        *STATE.lock().unwrap() = Some(v);
    }
}

fn shown() -> Shown {
    SHOWN.lock().unwrap().clone().unwrap_or_default()
}

fn core(name: &str, args: &str) {
    dispatch(name, args);
}

struct Root;

#[interface(name = "org.mpris.MediaPlayer2")]
impl Root {
    fn raise(&self) {}
    fn quit(&self) {}
    #[zbus(property)]
    fn can_quit(&self) -> bool {
        false
    }
    #[zbus(property)]
    fn can_raise(&self) -> bool {
        false
    }
    #[zbus(property)]
    fn has_track_list(&self) -> bool {
        false
    }
    #[zbus(property)]
    fn identity(&self) -> String {
        "Baladeur".into()
    }
    #[zbus(property)]
    fn desktop_entry(&self) -> String {
        "fili-music".into()
    }
    #[zbus(property)]
    fn supported_uri_schemes(&self) -> Vec<String> {
        vec![]
    }
    #[zbus(property)]
    fn supported_mime_types(&self) -> Vec<String> {
        vec![]
    }
}

struct Player;

#[interface(name = "org.mpris.MediaPlayer2.Player")]
impl Player {
    fn next(&self) {
        core("next_track", "[]");
    }
    fn previous(&self) {
        core("previous_track", "[]");
    }
    fn pause(&self) {
        core("pause_playback", "[]");
    }
    fn play(&self) {
        if shown().status != "Playing" {
            core("resume_playback", "[]");
        }
    }
    fn play_pause(&self) {
        core(if shown().status == "Playing" { "pause_playback" } else { "resume_playback" }, "[]");
    }
    fn stop(&self) {
        core("stop_playback", "[]");
    }
    fn seek(&self, offset_us: i64) {
        let to = (*POSITION_US.lock().unwrap() + offset_us).max(0) as f64 / 1e6;
        core("seek_to_position", &format!("[{to}]"));
    }
    fn set_position(&self, _track: ObjectPath<'_>, position_us: i64) {
        core("seek_to_position", &format!("[{}]", position_us.max(0) as f64 / 1e6));
    }
    fn open_uri(&self, _uri: &str) {}

    #[zbus(property)]
    fn playback_status(&self) -> String {
        shown().status
    }
    #[zbus(property)]
    fn loop_status(&self) -> String {
        shown().loop_status
    }
    #[zbus(property)]
    fn set_loop_status(&self, value: &str) {
        let mode = match value {
            "Track" => "one",
            "Playlist" => "all",
            _ => "off",
        };
        core("set_repeat_mode", &format!("[\"{mode}\"]"));
    }
    #[zbus(property)]
    fn rate(&self) -> f64 {
        1.0
    }
    #[zbus(property)]
    fn minimum_rate(&self) -> f64 {
        1.0
    }
    #[zbus(property)]
    fn maximum_rate(&self) -> f64 {
        1.0
    }
    #[zbus(property)]
    fn shuffle(&self) -> bool {
        shown().shuffle
    }
    #[zbus(property)]
    fn set_shuffle(&self, value: bool) {
        if value != shown().shuffle {
            core("toggle_shuffle", "[]");
        }
    }
    #[zbus(property)]
    fn volume(&self) -> f64 {
        shown().volume
    }
    #[zbus(property)]
    fn set_volume(&self, value: f64) {
        core("set_volume", &format!("[{}]", value.clamp(0.0, 1.0)));
    }
    #[zbus(property(emits_changed_signal = "false"))]
    fn position(&self) -> i64 {
        *POSITION_US.lock().unwrap()
    }
    #[zbus(property)]
    fn metadata(&self) -> HashMap<String, OwnedValue> {
        metadata(&shown())
    }
    #[zbus(property)]
    fn can_go_next(&self) -> bool {
        shown().has_track
    }
    #[zbus(property)]
    fn can_go_previous(&self) -> bool {
        shown().has_track
    }
    #[zbus(property)]
    fn can_play(&self) -> bool {
        shown().has_track
    }
    #[zbus(property)]
    fn can_pause(&self) -> bool {
        shown().has_track
    }
    #[zbus(property)]
    fn can_seek(&self) -> bool {
        shown().has_track
    }
    #[zbus(property)]
    fn can_control(&self) -> bool {
        true
    }
}

fn metadata(s: &Shown) -> HashMap<String, OwnedValue> {
    let mut m: HashMap<String, OwnedValue> = HashMap::new();
    let mut put = |k: &str, v: Var<'_>| {
        if let Ok(v) = OwnedValue::try_from(v) {
            m.insert(k.to_string(), v);
        }
    };
    if !s.has_track {
        return m;
    }
    let id = format!("/org/filigrane/fili_music/track/{}", s.track_id);
    if let Ok(p) = ObjectPath::try_from(id) {
        put("mpris:trackid", Var::from(p));
    }
    put("mpris:length", Var::from(s.length_us));
    put("xesam:title", Var::from(s.title.clone()));
    put("xesam:artist", Var::from(s.artists.clone()));
    put("xesam:album", Var::from(s.album.clone()));
    if !s.art_url.is_empty() {
        put("mpris:artUrl", Var::from(s.art_url.clone()));
    }
    m
}

fn data(reply: &str) -> Value {
    serde_json::from_str::<Value>(reply).ok().and_then(|v| v.get("data").cloned()).unwrap_or(Value::Null)
}

/// What the core says now, with the track looked up again only when it is not the one already shown
fn compute(prev: &Shown, state: &Value) -> Shown {
    let id = state.get("current_track_id").and_then(Value::as_i64);
    let mut s = Shown {
        status: if id.is_none() {
            "Stopped"
        } else if state.get("is_playing").and_then(Value::as_bool) == Some(true) {
            "Playing"
        } else {
            "Paused"
        }
        .into(),
        loop_status: match state.get("repeat_mode").and_then(Value::as_str) {
            Some("one") => "Track",
            Some("all") => "Playlist",
            _ => "None",
        }
        .into(),
        shuffle: state.get("shuffle").and_then(Value::as_bool) == Some(true),
        volume: state.get("volume").and_then(Value::as_f64).unwrap_or(1.0),
        ..Shown::default()
    };
    let Some(id) = id else { return s };
    s.has_track = true;
    s.track_id = id;
    if prev.has_track && prev.track_id == id {
        s.title = prev.title.clone();
        s.artists = prev.artists.clone();
        s.album = prev.album.clone();
        s.art_url = prev.art_url.clone();
        s.length_us = prev.length_us;
        return s;
    }
    let t = data(&dispatch("get_track_by_id", &format!("[{id}]")));
    s.title = t.get("title").and_then(Value::as_str).unwrap_or("").into();
    s.artists = t
        .get("artist_names")
        .and_then(Value::as_array)
        .map(|a| a.iter().filter_map(|n| n.as_str().map(String::from)).collect())
        .unwrap_or_default();
    s.length_us = t.get("duration").and_then(Value::as_i64).unwrap_or(0) * 1000;
    if let Some(album) = t.get("album_id").and_then(Value::as_i64) {
        s.album = data(&dispatch("get_album_by_id", &format!("[{album}]"))).get("title").and_then(Value::as_str).unwrap_or("").into();
        s.art_url = data(&dispatch("get_album_artwork_with_online", &format!("[{album}]"))).as_str().unwrap_or("").into();
    }
    s
}

pub fn start() {
    thread::spawn(|| {
        let conn = match Builder::session()
            .and_then(|b| b.name("org.mpris.MediaPlayer2.fili_music"))
            .and_then(|b| b.serve_at(PATH, Root))
            .and_then(|b| b.serve_at(PATH, Player))
            .and_then(|b| b.build())
        {
            Ok(c) => c,
            Err(e) => {
                log::warn!("mpris: {e}");
                return;
            }
        };
        loop {
            thread::sleep(Duration::from_millis(300));
            let Some(state) = STATE.lock().unwrap().clone() else { continue };
            *POSITION_US.lock().unwrap() = (state.get("position").and_then(Value::as_f64).unwrap_or(0.0) * 1e6) as i64;
            let prev = shown();
            let now = compute(&prev, &state);
            if now == prev {
                continue;
            }
            *SHOWN.lock().unwrap() = Some(now.clone());
            let mut changed: HashMap<&str, Var<'_>> = HashMap::new();
            if now.status != prev.status {
                changed.insert("PlaybackStatus", Var::from(now.status.clone()));
            }
            if now.loop_status != prev.loop_status {
                changed.insert("LoopStatus", Var::from(now.loop_status.clone()));
            }
            if now.shuffle != prev.shuffle {
                changed.insert("Shuffle", Var::from(now.shuffle));
            }
            if now.volume != prev.volume {
                changed.insert("Volume", Var::from(now.volume));
            }
            if now.track_id != prev.track_id || now.has_track != prev.has_track || now.art_url != prev.art_url {
                let meta: HashMap<String, Var<'_>> = metadata(&now).into_iter().map(|(k, v)| (k, Var::from(v))).collect();
                changed.insert("Metadata", Var::from(meta));
                for k in ["CanGoNext", "CanGoPrevious", "CanPlay", "CanPause", "CanSeek"] {
                    changed.insert(k, Var::from(now.has_track));
                }
            }
            if !changed.is_empty() {
                let _ = conn.emit_signal(
                    None::<&str>,
                    PATH,
                    "org.freedesktop.DBus.Properties",
                    "PropertiesChanged",
                    &("org.mpris.MediaPlayer2.Player", changed, Vec::<&str>::new()),
                );
            }
        }
    });
}
