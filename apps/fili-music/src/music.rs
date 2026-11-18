// Calls into tornade-core, the Rust core of the Tornade player (library, playback, queue, playlists, tags). The core's
// entry points take scalars and answer JSON; the interface calls them by name with a JSON array of arguments, so the
// QML sees exactly the calls the macOS interface of Tornade makes.
use std::{
    collections::hash_map::DefaultHasher,
    hash::{Hash, Hasher},
    path::PathBuf,
};

use serde_json::Value;
use tornade_core::ffi;

fn arg(a: &[Value], n: usize) -> Option<&Value> {
    a.get(n)
}

fn int(a: &[Value], n: usize) -> i64 {
    arg(a, n).and_then(|v| v.as_i64().or_else(|| v.as_f64().map(|f| f as i64))).unwrap_or(0)
}

fn num(a: &[Value], n: usize) -> f64 {
    arg(a, n).and_then(Value::as_f64).unwrap_or(0.0)
}

fn flag(a: &[Value], n: usize) -> bool {
    arg(a, n).and_then(Value::as_bool).unwrap_or(false)
}

fn text(a: &[Value], n: usize) -> &str {
    arg(a, n).and_then(Value::as_str).unwrap_or("")
}

pub fn json_str(s: &str) -> String {
    Value::String(s.to_string()).to_string()
}

fn err(message: &str) -> String {
    serde_json::json!({ "success": false, "error": message }).to_string()
}

fn cache_dir() -> PathBuf {
    let base = std::env::var("XDG_CACHE_HOME")
        .unwrap_or_else(|_| format!("{}/.cache", std::env::var("HOME").unwrap_or_default()));
    PathBuf::from(base).join("filigrane/fili-music/art")
}

// Artwork comes from the core as bytes; the interface needs a file to show. The name carries a hash of the bytes, so a
// changed cover is a new file and no cache needs invalidating.
fn bytes_reply(kind: &str, id: i64, bytes: Vec<u8>) -> String {
    if bytes.is_empty() {
        return serde_json::json!({ "success": true, "data": "" }).to_string();
    }
    let mut h = DefaultHasher::new();
    bytes.hash(&mut h);
    let dir = cache_dir();
    let path = dir.join(format!("{kind}-{id}-{:x}.img", h.finish()));
    if !path.exists() {
        let _ = std::fs::create_dir_all(&dir);
        if std::fs::write(&path, &bytes).is_err() {
            return err("cannot write the artwork cache");
        }
    }
    serde_json::json!({ "success": true, "data": format!("file://{}", path.display()) }).to_string()
}

pub fn library_dir() -> String {
    tornade_core::utils::AppPaths::new().map(|p| p.database_path().display().to_string()).unwrap_or_default()
}

/// The `data` of a get_player_state reply as JSON text, and the id of the current track (0 when none)
pub fn player_state(reply: &str) -> (String, i64) {
    let v: Value = serde_json::from_str(reply).unwrap_or(Value::Null);
    let data = v.get("data").cloned().unwrap_or(Value::Null);
    let track = data.get("current_track_id").and_then(Value::as_i64).unwrap_or(0);
    (data.to_string(), track)
}

// Several tracks in one call (the queue, a playlist): `ids` is a JSON array of track ids, the reply the tracks in the
// same order (an id the library no longer knows is left out)
fn tracks_by_ids(ids: &str) -> String {
    let Ok(Value::Array(ids)) = serde_json::from_str::<Value>(ids) else {
        return err("the ids must be a JSON array");
    };
    let tracks: Vec<Value> = ids
        .iter()
        .filter_map(Value::as_i64)
        .filter_map(|id| {
            let reply: Value = serde_json::from_str(&ffi::get_track_by_id(id)).ok()?;
            reply.get("data").cloned().filter(|d| !d.is_null())
        })
        .collect();
    serde_json::json!({ "success": true, "data": tracks }).to_string()
}

// Ids of the whole library, read straight from the core's database (read only): "random" in a random order, anything else
// by artist, album year, album, disc and track. One query, so the ids never go through the interface (50 000 tracks are ~400 KB).
fn library_ids(order: &str, exclude: &std::collections::HashSet<i64>, limit: usize) -> Result<Vec<i64>, String> {
    use rusqlite::{Connection, OpenFlags};
    let conn = Connection::open_with_flags(library_dir(), OpenFlags::SQLITE_OPEN_READ_ONLY).map_err(|e| e.to_string())?;
    let sql = if order == "random" {
        "SELECT id FROM tracks ORDER BY RANDOM()"
    } else {
        "SELECT t.id FROM tracks t JOIN artists ar ON ar.id = t.artist_id LEFT JOIN albums al ON al.id = t.album_id \
         ORDER BY ar.name COLLATE NOCASE, al.year, al.title COLLATE NOCASE, t.disc_number, t.track_number, t.title COLLATE NOCASE"
    };
    let mut stmt = conn.prepare(sql).map_err(|e| e.to_string())?;
    let rows = stmt.query_map([], |r| r.get::<_, i64>(0)).map_err(|e| e.to_string())?;
    Ok(rows.filter_map(Result::ok).filter(|id| !exclude.contains(id)).take(limit).collect())
}

fn queue_items() -> std::collections::HashSet<i64> {
    let reply: Value = serde_json::from_str(&ffi::get_queue()).unwrap_or(Value::Null);
    reply["data"]["items"].as_array().map(|a| a.iter().filter_map(Value::as_i64).collect()).unwrap_or_default()
}

fn succeeded(reply: &str) -> bool {
    serde_json::from_str::<Value>(reply).ok().and_then(|v| v["success"].as_bool()).unwrap_or(false)
}

// The whole library in the queue: `replace` puts it in place of the queue and starts the first track, else it goes at the end.
// The reply carries the number of tracks added.
fn queue_library(order: &str, replace: bool) -> String {
    let ids = match library_ids(order, &Default::default(), usize::MAX) {
        Ok(ids) => ids,
        Err(e) => return err(&e),
    };
    let json = Value::from(ids.clone()).to_string();
    let reply = if replace { ffi::set_queue(&json) } else { ffi::add_tracks_to_queue(&json) };
    if !succeeded(&reply) {
        return reply;
    }
    if replace && !ids.is_empty() {
        ffi::jump_to_queue_index(0);
    }
    serde_json::json!({ "success": true, "data": { "count": ids.len() } }).to_string()
}

// `count` random tracks of the library that are not in the queue yet, added at the end of it
fn add_random(count: i64) -> String {
    let queued = queue_items();
    let ids = match library_ids("random", &queued, count.clamp(0, 1000) as usize) {
        Ok(ids) => ids,
        Err(e) => return err(&e),
    };
    if !ids.is_empty() && !succeeded(&ffi::add_tracks_to_queue(&Value::from(ids.clone()).to_string())) {
        return err("the tracks could not be added to the queue");
    }
    serde_json::json!({ "success": true, "data": { "count": ids.len() } }).to_string()
}

/// One call of the core: `name` of an entry point of tornade-core's FFI, `args` a JSON array
pub fn dispatch(name: &str, args: &str) -> String {
    let Ok(Value::Array(a)) = serde_json::from_str::<Value>(args) else {
        return err("the arguments must be a JSON array");
    };
    let a = a.as_slice();
    match name {
        "tracks_by_ids" => tracks_by_ids(text(a, 0)),
        "queue_library" => queue_library(text(a, 0), flag(a, 1)),
        "add_random_to_queue" => add_random(int(a, 0)),
        "get_library_stats" => ffi::get_library_stats(),
        "scan_library" => ffi::scan_library(text(a,0)),
        "get_scan_progress" => ffi::get_scan_progress(),
        "get_tracks_page" => ffi::get_tracks_page(int(a,0) as u32, int(a,1) as u32, text(a,2), text(a,3)),
        "get_track_by_id" => ffi::get_track_by_id(int(a,0)),
        "get_random_tracks" => ffi::get_random_tracks(int(a,0) as u32),
        "search_tracks" => ffi::search_tracks(text(a,0), int(a,1) as u32),
        "delete_tracks" => ffi::delete_tracks(text(a,0)),
        "get_albums_page" => ffi::get_albums_page(int(a,0) as u32, int(a,1) as u32),
        "get_album_by_id" => ffi::get_album_by_id(int(a,0)),
        "get_album_tracks" => ffi::get_album_tracks(int(a,0)),
        "get_album_artwork" => bytes_reply("album", int(a,0), ffi::get_album_artwork(int(a,0))),
        "get_artists_page" => ffi::get_artists_page(int(a,0) as u32, int(a,1) as u32),
        "get_artist_by_id" => ffi::get_artist_by_id(int(a,0)),
        "get_artist_albums" => ffi::get_artist_albums(int(a,0)),
        "get_genres" => ffi::get_genres(),
        "search_genres" => ffi::search_genres(text(a,0), int(a,1) as u32),
        "get_genre_tracks" => ffi::get_genre_tracks(int(a,0)),
        "get_genre_artists" => ffi::get_genre_artists(int(a,0)),
        "get_similar_artists" => ffi::get_similar_artists(int(a,0)),
        "get_genre_albums" => ffi::get_genre_albums(int(a,0)),
        "get_album_genres" => ffi::get_album_genres(int(a,0)),
        "get_artist_genres" => ffi::get_artist_genres(int(a,0)),
        "get_track_genres" => ffi::get_track_genres(int(a,0)),
        "get_album_featuring_artists" => ffi::get_album_featuring_artists(int(a,0), int(a,1)),
        "get_playlists" => ffi::get_playlists(),
        "create_playlist" => ffi::create_playlist(text(a,0)),
        "rename_playlist" => ffi::rename_playlist(int(a,0), text(a,1)),
        "delete_playlist" => ffi::delete_playlist(int(a,0)),
        "add_track_to_playlist" => ffi::add_track_to_playlist(int(a,0), int(a,1)),
        "remove_track_from_playlist" => ffi::remove_track_from_playlist(int(a,0), int(a,1)),
        "import_m3u_playlist" => ffi::import_m3u_playlist(text(a,0)),
        "play_track" => ffi::play_track(int(a,0)),
        "pause_playback" => ffi::pause_playback(),
        "resume_playback" => ffi::resume_playback(),
        "stop_playback" => ffi::stop_playback(),
        "next_track" => ffi::next_track(),
        "previous_track" => ffi::previous_track(),
        "jump_to_queue_index" => ffi::jump_to_queue_index(int(a,0)),
        "get_player_state" => ffi::get_player_state(),
        "get_queue" => ffi::get_queue(),
        "add_to_queue" => ffi::add_to_queue(int(a,0)),
        "add_tracks_to_queue" => ffi::add_tracks_to_queue(text(a,0)),
        "set_queue" => ffi::set_queue(text(a,0)),
        "clear_queue" => ffi::clear_queue(),
        "reorder_queue" => ffi::reorder_queue(text(a,0)),
        "set_volume" => ffi::set_volume(num(a,0)),
        "seek_to_position" => ffi::seek_to_position(num(a,0)),
        "toggle_shuffle" => ffi::toggle_shuffle(),
        "set_shuffle" => ffi::set_shuffle(flag(a,0)),
        "toggle_repeat" => ffi::toggle_repeat(),
        "set_repeat_mode" => ffi::set_repeat_mode(text(a,0)),
        "clean_library" => ffi::clean_library(),
        "clear_unavailable_tracks" => ffi::clear_unavailable_tracks(),
        "import_files" => ffi::import_files(text(a,0)),
        "fetch_all_artwork" => ffi::fetch_all_artwork(flag(a,0), flag(a,1)),
        "fetch_artist_photos" => ffi::fetch_artist_photos(flag(a,0)),
        "fetch_album_artwork" => ffi::fetch_album_artwork(int(a,0)),
        "get_artwork_fetch_progress" => ffi::get_artwork_fetch_progress(),
        "cancel_artwork_fetch" => ffi::cancel_artwork_fetch(),
        "get_album_artwork_with_online" => bytes_reply("album", int(a,0), ffi::get_album_artwork_with_online(int(a,0))),
        "get_artist_photo" => bytes_reply("artist", int(a,0), ffi::get_artist_photo(int(a,0))),
        "update_track_metadata" => ffi::update_track_metadata(int(a,0), text(a,1)),
        "update_album_metadata" => ffi::update_album_metadata(int(a,0), text(a,1)),
        "write_track_file_tags" => ffi::write_track_file_tags(int(a,0)),
        "write_album_file_tags" => ffi::write_album_file_tags(int(a,0)),
        "get_metadata_suggestions" => ffi::get_metadata_suggestions(text(a,0)),
        "scrape_track_metadata" => ffi::scrape_track_metadata(int(a,0)),
        "scrape_album_metadata" => ffi::scrape_album_metadata(int(a,0)),
        "scrape_track_by_query" => ffi::scrape_track_by_query(text(a,0), text(a,1)),
        "scrape_album_by_query" => ffi::scrape_album_by_query(text(a,0), text(a,1)),
        "set_track_artwork_from_path" => ffi::set_track_artwork_from_path(int(a,0), text(a,1)),
        "set_album_artwork_from_path" => ffi::set_album_artwork_from_path(int(a,0), text(a,1)),
        "remove_track_artwork" => ffi::remove_track_artwork(int(a,0)),
        "remove_album_artwork" => ffi::remove_album_artwork(int(a,0)),
        "set_track_artwork_from_scrape" => ffi::set_track_artwork_from_scrape(int(a,0), text(a,1)),
        "set_album_artwork_from_scrape" => ffi::set_album_artwork_from_scrape(int(a,0), text(a,1)),
        "update_multiple_tracks_metadata" => ffi::update_multiple_tracks_metadata(text(a,0), text(a,1)),
        "write_multiple_tracks_file_tags" => ffi::write_multiple_tracks_file_tags(text(a,0)),
        _ => err(&format!("unknown call: {name}")),
    }
}
