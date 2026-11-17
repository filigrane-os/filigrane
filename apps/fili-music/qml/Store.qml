pragma Singleton
// What every view shares: calls of the core, the player state, the queue, names of artists and albums, artwork.
// The core answers {"success": true, "data": ...}; call() gives the data (null on failure, the reason in lastError).
import QtQuick
import Fili.Baladeur

QtObject {
    id: store

    property string lastError: ""
    // Bumped (coalesced) when a name, a cover or a track arrives: bindings that read it re-evaluate
    property int rev: 0
    property var artistNames: ({})
    property var albumTitles: ({})
    property var covers: ({})
    property var trackCache: ({})
    property var asked: ({})
    property var callbacks: ({})
    // Read and written from bindings (a cover asked while a view is built): kept in an object, so that counting is not a
    // change of a property, which would make the binding depend on itself
    readonly property var counter: ({ serial: 1 })

    // Player (data of get_player_state) and queue
    property var player: ({ is_playing: false, current_track_id: null, position: 0, duration: 0, volume: 1, shuffle: false, repeat_mode: "off", is_loading: false, skipped_track_ids: [] })
    readonly property bool playing: player.is_playing === true
    readonly property bool hasTrack: player.current_track_id !== null && player.current_track_id !== undefined
    readonly property int currentTrackId: hasTrack ? player.current_track_id : -1
    property var queueIds: []
    property int queueIndex: -1
    property var currentTrack: null
    // Counts the changes of the library (scan, tags, deletion, playlists): the views reload when it moves
    property int libraryRev: 0
    property int playlistRev: 0
    // Navigation asked from anywhere (the cover of the player, a track menu): Main shows the album, then the artist
    property int pendingAlbumId: -1
    property int pendingArtistId: -1
    signal albumRequested(int albumId)
    signal artistRequested(int artistId)
    // The album or artist shown in its view changed (-1: none): Main keeps the history. closeDetails: back to the list
    // Ctrl+F: the filter field of the view on screen takes the keyboard
    signal focusFilter()
    signal detailChanged(string kind, int id)
    signal closeDetails(string kind)
    // A context menu is asked at window coordinates: Main draws it and calls handler(id) with the entry chosen
    signal menuRequested(real x, real y, var items, var handler)
    // Drag and drop between views: a source calls dragMove while the pointer is down past a few pixels and dragDrop on release
    // (window coordinates); payload is {ids: [...]} or {albumId}. Main draws the ghost and the queue takes the drop
    property var drag: null
    signal dropped(real x, real y, var payload)
    function dragMove(label, payload, x, y) {
        drag = { label: label, payload: payload, x: x, y: y };
    }
    function dragDrop(x, y) {
        const d = drag;
        drag = null;
        if (d)
            dropped(x, y, d.payload);
    }
    // A notice for the footer
    signal notice(string text, bool failed)

    function parse(json) {
        try {
            return JSON.parse(json);
        } catch (e) {
            return { success: false, error: String(e) };
        }
    }
    function call(name, args) {
        const r = parse(Music.call(name, JSON.stringify(args || [])));
        lastError = r.success ? "" : (r.error || "");
        return r.success ? r.data : null;
    }
    // A call the user asked for (play, next…): a failure is told in the footer
    function act(name, args) {
        const d = call(name, args);
        if (lastError !== "")
            notice(lastError, true);
        // The state is read again: the heartbeat of Main only runs while something plays. A track that starts is read after a
        // moment: the core's end-of-track check, asked before the audio callback has the new source, takes it for finished
        if (name === "pause_playback" || name === "resume_playback" || name === "seek_to_position" || name === "set_volume")
            Music.tick();
        else
            kick.restart();
        return d;
    }
    function callAsync(name, args, done) {
        const id = counter.serial++;
        callbacks[id] = done;
        Music.callAsync(id, name, JSON.stringify(args || []));
    }
    // Like callAsync, but done(reply) gets the whole reply of the core ({success, data, error}): a failure can carry data
    // (the files a tag write could not update)
    function callAsyncRaw(name, args, done) {
        const id = counter.serial++;
        callbacks[id] = { raw: done };
        Music.callAsync(id, name, JSON.stringify(args || []));
    }
    // The tag editor is asked for a track, an album or several tracks: Main shows it
    signal tagEditorRequested(string mode, var ids)
    readonly property Connections link: Connections {
        target: Music
        function onReply(id, json) {
            const cb = store.callbacks[id];
            delete store.callbacks[id];
            const r = store.parse(json);
            if (cb && cb.raw)
                cb.raw(r);
            else if (cb)
                cb(r.success ? r.data : null, r.success ? "" : (r.error || ""));
        }
        function onStateChanged() {
            store.player = store.parse(Music.state);
        }
        function onTrackChanged() {
            store.refreshQueue();
        }
    }
    readonly property Timer kick: Timer {
        interval: 300
        onTriggered: {
            Music.tick();
            store.refreshQueue();
        }
    }
    readonly property Timer settle: Timer {
        interval: 40
        onTriggered: store.rev++
    }
    function touch() {
        settle.restart();
    }

    // ---- Names and covers ---------------------------------------------------------------------------------------------
    function artistName(id) {
        rev;
        const n = artistNames[id];
        if (n !== undefined)
            return n;
        if (!asked["a" + id]) {
            asked["a" + id] = true;
            callAsync("get_artist_by_id", [id], d => {
                artistNames[id] = d ? d.name : "";
                touch();
            });
        }
        return "";
    }
    function albumTitle(id) {
        rev;
        if (id === null || id === undefined)
            return "";
        const n = albumTitles[id];
        if (n !== undefined)
            return n;
        if (!asked["b" + id]) {
            asked["b" + id] = true;
            callAsync("get_album_by_id", [id], d => {
                albumTitles[id] = d ? d.title : "";
                touch();
            });
        }
        return "";
    }
    // Artists of a track: the names the core gave, else the primary artist looked up
    function trackArtist(t) {
        return t.artist_names && t.artist_names.length > 0 ? t.artist_names.join(", ") : artistName(t.artist_id);
    }
    // (an album cover comes from get_album_artwork_with_online: the covers fetched online are kept apart from the embedded ones,
    // and get_album_artwork alone would never show them)
    // File of the cover of an album ("" while it loads or when there is none); kind "album" or "artist"
    function cover(kind, id) {
        rev;
        const key = kind + id;
        const c = covers[key];
        if (c !== undefined)
            return c;
        if (!asked["c" + key]) {
            asked["c" + key] = true;
            callAsync(kind === "album" ? "get_album_artwork_with_online" : "get_artist_photo", [id], d => {
                covers[key] = d || "";
                touch();
            });
        }
        return "";
    }
    // After a change of tags or artwork: covers and names are asked again
    function forget() {
        covers = ({});
        albumTitles = ({});
        artistNames = ({});
        asked = ({});
        trackCache = ({});
        libraryRev++;
        touch();
    }

    // ---- Formats ------------------------------------------------------------------------------------------------------
    function clock(ms) {
        const s = Math.max(0, Math.floor(ms / 1000));
        const p = v => (v < 10 ? "0" : "") + v;
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60;
        return h > 0 ? h + ":" + p(m) + ":" + p(s % 60) : m + ":" + p(s % 60);
    }
    function clockSeconds(s) {
        return clock(s * 1000);
    }
    function formatInfo(t) {
        const parts = [String(t.file_type || "").toUpperCase()];
        if (t.bit_depth)
            parts.push(t.bit_depth + "bit");
        if (t.sample_rate)
            parts.push(Math.floor(t.sample_rate / 1000) + "kHz");
        return parts.join(" ");
    }
    function sizeText(bytes) {
        const mb = bytes / 1048576;
        return mb >= 1000 ? (mb / 1024).toFixed(1) + " GB" : mb.toFixed(1) + " MB";
    }
    function longDuration(seconds) {
        const h = Math.floor(seconds / 3600), m = Math.floor(seconds / 60) % 60;
        return h > 0 ? h + " h " + m + " min" : m + " min";
    }

    // ---- Tracks in a ListModel ---------------------------------------------------------------------------------------
    // A row of a track list: only plain values (a ListModel turns arrays into sub-models)
    function row(t) {
        trackCache[t.id] = t;
        return {
            id: t.id, title: t.title || "", artistId: t.artist_id, albumId: t.album_id === null || t.album_id === undefined ? -1 : t.album_id,
            artists: t.artist_names ? t.artist_names.join(", ") : "", duration: t.duration || 0, trackNumber: t.track_number || 0,
            discNumber: t.disc_number || 1, fileType: t.file_type || "", rating: t.rating || 0, playCount: t.play_count || 0,
            format: formatInfo(t), size: t.file_size || 0, path: t.file_path || "", added: t.created_at || ""
        };
    }
    function fill(model, tracks, append) {
        if (!append)
            model.clear();
        for (const t of tracks)
            model.append(row(t));
    }
    function ids(model, from) {
        const out = [];
        for (let i = from || 0; i < model.count; i++)
            out.push(model.get(i).id);
        return out;
    }

    // ---- Playback and queue ------------------------------------------------------------------------------------------
    function refreshQueue() {
        const q = call("get_queue");
        if (!q)
            return;
        queueIds = q.items || [];
        queueIndex = q.current_index === undefined ? -1 : q.current_index;
        queueRev++;
        const id = currentTrackId;
        if (id < 0)
            currentTrack = null;
        else
            callAsync("get_track_by_id", [id], t => currentTrack = t);
    }
    property int queueRev: 0
    function playNow(trackIds, start) {
        if (!trackIds || trackIds.length === 0)
            return;
        act("set_queue", [JSON.stringify(trackIds)]);
        act("jump_to_queue_index", [start || 0]);
        refreshQueue();
    }
    function addToQueue(trackIds) {
        if (!trackIds || trackIds.length === 0)
            return;
        call("add_tracks_to_queue", [JSON.stringify(trackIds)]);
        refreshQueue();
    }
    // The tracks of an artist: those of its albums in album order, then the ones without an album (found by paging the library)
    function artistSingles(artistId, done) {
        const found = [];
        const page = offset => callAsync("get_tracks_page", [offset, 1000, "title", "asc"], d => {
            const tracks = d ? d.tracks : [];
            for (const t of tracks)
                if (t.artist_id === artistId && (t.album_id === null || t.album_id === undefined))
                    found.push(t);
            if (tracks.length === 1000)
                page(offset + 1000);
            else
                done(found);
        });
        page(0);
    }
    function artistTrackIds(artistId, done) {
        callAsync("get_artist_albums", [artistId], d => {
            const albums = d ? d.albums : [];
            const parts = new Array(albums.length);
            let left = albums.length;
            const finish = () => artistSingles(artistId, singles => done([].concat(...parts, singles.map(t => t.id))));
            if (left === 0) {
                finish();
                return;
            }
            albums.forEach((al, i) => callAsync("get_album_tracks", [al.id], t => {
                parts[i] = t ? t.tracks.map(x => x.id) : [];
                if (--left === 0)
                    finish();
            }));
        });
    }
    // A double click plays the track, Alt adds it to the queue; `invert_queue = true` in the settings swaps them
    function wantsPlay(alt) {
        return Fili.setting("behavior", "invert_queue") === "true" ? !!alt : !alt;
    }
    // Add tracks right after the one playing
    function addNext(trackIds) {
        if (!trackIds || trackIds.length === 0)
            return;
        const before = queueIds.length;
        call("add_tracks_to_queue", [JSON.stringify(trackIds)]);
        refreshQueue();
        if (before === 0 || queueIndex < 0 || queueIndex + 1 >= before)
            return;
        const list = queueIds.slice();
        const added = list.splice(before, trackIds.length);
        list.splice(queueIndex + 1, 0, ...added);
        call("reorder_queue", [JSON.stringify(list)]);
        refreshQueue();
    }
    // Add one track at the end of the queue and play it at once (a double click on a track of a list)
    function addAndPlay(trackId) {
        act("add_to_queue", [trackId]);
        refreshQueue();
        act("jump_to_queue_index", [queueIds.length - 1]);
        refreshQueue();
    }
    function playQueueAt(index) {
        act("jump_to_queue_index", [index]);
        refreshQueue();
    }
    function togglePlay() {
        if (!hasTrack) {
            if (queueIds.length > 0)
                playQueueAt(Math.max(0, queueIndex));
            return;
        }
        act(playing ? "pause_playback" : "resume_playback");
    }
    function next() {
        act("next_track");
        refreshQueue();
    }
    function previous() {
        act("previous_track");
        refreshQueue();
    }
    function seek(seconds) {
        act("seek_to_position", [seconds]);
    }
    function setVolume(v) {
        act("set_volume", [v]);
    }
    function toggleShuffle() {
        call("toggle_shuffle");
        Music.tick();
        refreshQueue();
    }
    function toggleRepeat() {
        call("toggle_repeat");
        Music.tick();
        refreshQueue();
    }
    function clearQueue() {
        call("clear_queue");
        Music.tick();
        refreshQueue();
    }
    function removeFromQueue(index) {
        const keep = queueIds.slice();
        keep.splice(index, 1);
        const was = queueIndex;
        call("reorder_queue", [JSON.stringify(keep)]);
        refreshQueue();
    }
    function moveInQueue(from, to) {
        const list = queueIds.slice();
        const [x] = list.splice(from, 1);
        list.splice(to, 0, x);
        call("reorder_queue", [JSON.stringify(list)]);
        refreshQueue();
    }
}
