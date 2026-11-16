// Window of Baladeur (fili-music): header (title, search, window buttons), sidebar (library views and playlists), the view of the
// library, and on the right the player panel (queue, queue actions, controls), then a footer: the anatomy of every fili-*
// window (app-window.md of the filigrane-ui skill, Casier is the reference). The library, the queue and the playback are
// tornade-core's (src/music.rs); this file is the interface.
// Shortcuts: Space play / pause, Ctrl+Left / Ctrl+Right previous / next, Ctrl+F search, Ctrl+1..5 the views, Ctrl+N new playlist,
// Ctrl+Shift+W window actions, Ctrl+W close.
import QtQuick
import QtQuick.Controls.Basic
import Fili.Baladeur

ApplicationWindow {
    id: win
    // Fonts embedded in the binary: same look on every distribution
    FontLoader { id: fontText; source: "qrc:/qt/qml/Fili/Baladeur/fonts/Jost-Variable.ttf" }
    FontLoader { id: fontMono; source: "qrc:/qt/qml/Fili/Baladeur/fonts/JetBrainsMono-Variable.ttf" }
    FontLoader { id: fontIcons; source: "qrc:/qt/qml/Fili/Baladeur/fonts/FiliIcons.ttf" }
    width: 1280
    height: 780
    minimumWidth: 900
    minimumHeight: 520
    visible: true
    color: FiliTheme.background
    title: "Baladeur"

    // ---- State -------------------------------------------------------------------------------------------------
    // "search", "tracks", "albums", "artists", "genres" or "playlist"
    property string view: ["tracks", "albums", "artists", "genres"].indexOf(Fili.uiState("view")) >= 0 ? Fili.uiState("view") : "tracks"
    property int playlistId: -1
    property var playlists: []
    property string query: ""
    property bool aboutOpen: false
    property bool showHeader: Fili.header()
    property bool showFooter: Fili.footer()
    property bool windowButtons: Fili.windowButtons()
    property real playerWidth: Math.max(260, Math.min(700, Number(Fili.uiState("player_width")) || 350))
    property var stats: ({ track_count: 0, album_count: 0, artist_count: 0, total_duration_seconds: 0 })
    // A notice or error in the footer, and an inline confirmation: { text, label, run }
    property string message: ""
    property bool failed: false
    property var confirm: null
    readonly property bool typing: searchInput.activeFocus || prompt.visible || tagEditor.visible
    readonly property bool modal: aboutOpen || prompt.visible || scanner.visible || tagEditor.visible
    readonly property bool headerShown: showHeader || searchInput.activeFocus || query !== ""
    readonly property bool footerShown: showFooter || message !== "" || confirm !== null || scanner.scanning || scanner.fetching

    readonly property var views: [
        { id: "search", label: Fili.tr("Search"), glyph: "" },
        { id: "tracks", label: Fili.tr("Tracks"), glyph: "♪" },
        { id: "albums", label: Fili.tr("Albums"), glyph: "◫" },
        { id: "artists", label: Fili.tr("Artists"), glyph: "☺" },
        { id: "genres", label: Fili.tr("Genres"), glyph: "♬" }
    ]
    readonly property var playlist: playlists.find(p => p.id === playlistId) || null
    readonly property string viewTitle: view === "playlist" ? (playlist ? playlist.name : Fili.tr("Playlist")) : (views.find(v => v.id === view) || { label: "" }).label

    function show(v) {
        if (v !== "playlist")
            Fili.setUiState("view", v === "search" ? "tracks" : v);
        view = v;
        if (v !== "search")
            searchInput.text = "";
    }
    function loadPlaylists() {
        Store.callAsync("get_playlists", [], d => playlists = d ? d.playlists : []);
    }
    function loadStats() {
        Store.callAsync("get_library_stats", [], d => {
            if (d)
                stats = d;
        });
    }
    function say(text, bad) {
        message = text;
        failed = bad === true;
    }
    function quit() {
        Qt.quit();
    }
    function openSearch() {
        searchInput.forceActiveFocus();
        searchInput.selectAll();
    }
    function newPlaylist(thenAdd) {
        prompt.mode = "new";
        prompt.ids = thenAdd || [];
        prompt.open(Fili.tr("New playlist"), "", [], Fili.tr("Create"), Fili.tr("Name"));
    }
    function saveQueue() {
        prompt.mode = "save";
        prompt.ids = Store.queueIds;
        prompt.open(Fili.tr("Save the queue as a playlist"), "", playlists.map(p => ({ id: p.id, label: p.name })), Fili.tr("Save"), Fili.tr("New playlist"));
    }
    function addToPlaylist(playlistId, ids) {
        let n = 0;
        for (const id of ids)
            if (Store.call("add_track_to_playlist", [playlistId, id]) !== null)
                n++;
        Store.playlistRev++;
        loadPlaylists();
        say(n + " " + Fili.tr("tracks added to the playlist"), false);
    }
    function askDelete(ids) {
        confirm = {
            text: Fili.tr("Delete %1 track(s) from the library? The files stay on disk.").replace("%1", ids.length),
            label: Fili.tr("Delete"),
            run: () => {
                Store.call("delete_tracks", [JSON.stringify(ids)]);
                Store.forget();
                loadStats();
            }
        };
    }

    Component.onCompleted: {
        loadPlaylists();
        loadStats();
        Store.refreshQueue();
        Music.tick();
        // First launch: an empty library starts with the scanner
        const s = Store.call("get_library_stats");
        if (s && s.track_count === 0)
            scanner.open(true);
    }
    onClosing: close => Store.call("pause_playback")
    Connections {
        target: Store
        function onLibraryRevChanged() {
            win.loadStats();
        }
        function onPlaylistRevChanged() {
            win.loadPlaylists();
        }
        function onAlbumRequested(id) {
            Store.pendingAlbumId = id;
            win.show("albums");
        }
        function onArtistRequested(id) {
            Store.pendingArtistId = id;
            win.show("artists");
        }
        function onMenuRequested(x, y, items, handler) {
            win.menuHandler = handler;
            menu.open(x, y, items);
        }
        function onNotice(text, bad) {
            win.say(text, bad);
        }
        function onTagEditorRequested(mode, ids) {
            tagEditor.open(mode, ids);
        }
    }
    Connections {
        target: Fili
        function onThemeChanged() {
            win.showHeader = Fili.header();
            win.showFooter = Fili.footer();
        }
    }
    // The heartbeat of the core (end of track, advance): while something plays or loads; the buttons tick once themselves
    Timer {
        interval: 250
        repeat: true
        running: Store.playing || Store.player.is_loading === true
        onTriggered: Music.tick()
    }
    // A notice goes away by itself, an error stays until it is clicked
    Timer {
        interval: 6000
        running: win.message !== "" && !win.failed
        onTriggered: win.message = ""
    }

    // ---- Menus ---------------------------------------------------------------------------------------------------
    property var menuHandler: null
    ContextMenu {
        id: menu
        onActivated: id => {
            if (win.menuHandler)
                win.menuHandler(id);
        }
    }
    function playlistChoices() {
        return playlists.map(p => ({ id: "pl:" + p.id, label: p.name })).concat([{ id: "pl:new", label: Fili.tr("New playlist…") }]);
    }
    // Menu of a set of tracks (library, album, search); extra entries for a playlist
    function trackMenu(ids, x, y, positions, playlistOf) {
        const items = [
            { id: "play", label: Fili.tr("Play") },
            { id: "queue", label: Fili.tr("Add to queue") },
            { id: "playlist", label: Fili.tr("Add to playlist"), children: playlistChoices() },
            { id: "edit", label: Fili.tr("Edit metadata…") }
        ];
        if (playlistOf !== undefined)
            items.push({ id: "remove", label: Fili.tr("Remove from this playlist") });
        items.push({ id: "separator1", separator: true });
        items.push({ id: "delete", label: Fili.tr("Delete from library…"), hint: "Delete" });
        const several = ids.length > 1;
        Store.menuRequested(x, y, items, id => {
            if (id === "play")
                several ? Store.playNow(ids, 0) : Store.call("play_track", [ids[0]]);
            else if (id === "queue")
                Store.addToQueue(ids);
            else if (id === "edit")
                Store.tagEditorRequested(several ? "tracks" : "track", ids);
            else if (id === "pl:new")
                win.newPlaylist(ids);
            else if (id.startsWith("pl:"))
                win.addToPlaylist(Number(id.slice(3)), ids);
            else if (id === "remove") {
                // Highest position first: the others keep their place
                for (const p of positions)
                    Store.call("remove_track_from_playlist", [playlistOf, p]);
                Store.playlistRev++;
            } else if (id === "delete")
                win.askDelete(ids);
            if (id === "play" && !several) {
                Music.tick();
                Store.refreshQueue();
            }
        });
    }
    function albumMenu(album, x, y) {
        Store.menuRequested(x, y, [
            { id: "play", label: Fili.tr("Play") },
            { id: "queue", label: Fili.tr("Add to queue") },
            { id: "playlist", label: Fili.tr("Add to playlist"), children: playlistChoices() },
            { id: "edit", label: Fili.tr("Edit metadata…") }
        ], id => {
            if (id === "edit") {
                Store.tagEditorRequested("album", [album.id]);
                return;
            }
            Store.callAsync("get_album_tracks", [album.id], d => {
                const ids = d ? d.tracks.map(t => t.id) : [];
                if (id === "play")
                    Store.playNow(ids, 0);
                else if (id === "queue")
                    Store.addToQueue(ids);
                else if (id === "pl:new")
                    win.newPlaylist(ids);
                else if (id.startsWith("pl:"))
                    win.addToPlaylist(Number(id.slice(3)), ids);
            });
        });
    }

    // ---- Commands: the menu of the fili-bar and the assistant (fili-music ctl) --------------------------------------
    readonly property var actions: ({
        "about": { on: () => true, run: () => win.aboutOpen = !win.aboutOpen },
        "view-search": { on: () => true, run: () => win.openSearch() },
        "view-tracks": { on: () => true, run: () => win.show("tracks") },
        "view-albums": { on: () => true, run: () => win.show("albums") },
        "view-artists": { on: () => true, run: () => win.show("artists") },
        "view-genres": { on: () => true, run: () => win.show("genres") },
        "play-pause": { on: () => Store.hasTrack || Store.queueIds.length > 0, run: () => Store.togglePlay() },
        "play-track": { on: () => true, run: arg => Store.addAndPlay(Number(arg)) },
        "next": { on: () => Store.hasTrack, run: () => Store.next() },
        "prev": { on: () => Store.hasTrack, run: () => Store.previous() },
        "seek-back": { on: () => Store.hasTrack, run: () => Store.seek(Math.max(0, (Store.player.position || 0) - 10)) },
        "seek-forward": { on: () => Store.hasTrack, run: () => Store.seek((Store.player.position || 0) + 10) },
        "volume-up": { on: () => true, run: () => Store.setVolume(Math.min(1, (Store.player.volume || 0) + 0.05)) },
        "volume-down": { on: () => true, run: () => Store.setVolume(Math.max(0, (Store.player.volume || 0) - 0.05)) },
        "shuffle": { on: () => true, run: () => Store.toggleShuffle() },
        "repeat": { on: () => true, run: () => Store.toggleRepeat() },
        "add-random": { on: () => true, run: () => Store.callAsync("get_random_tracks", [30], ids => Store.addToQueue(ids || [])) },
        "save-queue": { on: () => Store.queueIds.length > 0, run: () => win.saveQueue() },
        "clear-queue": { on: () => Store.queueIds.length > 0, run: () => Store.clearQueue() },
        "new-playlist": { on: () => true, run: () => win.newPlaylist() },
        "edit-metadata": { on: () => Store.hasTrack && !tagEditor.visible, run: () => Store.tagEditorRequested("track", [Store.currentTrackId]) },
        "scan": { on: () => !scanner.scanning, run: arg => arg ? scanner.scanPath(arg) : scanner.open(false) },
        "search": { on: () => true, run: () => win.openSearch() },
        "settings": { on: () => true, run: () => Fili.openSettings() },
        "toggle-header": { on: () => true, run: () => win.showHeader = !win.showHeader },
        "toggle-footer": { on: () => true, run: () => win.showFooter = !win.showFooter },
        "toggle-window-buttons": { on: () => true, run: () => { win.windowButtons = !win.windowButtons; Fili.setWindowButtons(win.windowButtons); } },
        "window-actions": { on: () => win.windowButtons, run: () => windowPanel.visible ? windowPanel.close() : windowPanel.open() },
        "close": { on: () => true, run: () => win.quit() }
    })
    function runAction(name, arg) {
        const a = actions[name];
        if (!a)
            return { ok: false, error: "unknown action: " + name + " (fili-music ctl actions lists them)" };
        if (!a.on())
            return { ok: false, error: "action disabled now: " + name };
        a.run(arg || "");
        return { ok: true };
    }
    function stateJson() {
        return {
            view: view, playlist: playlistId, tracks: stats.track_count, albums: stats.album_count, artists: stats.artist_count,
            playing: Store.playing, current: Store.currentTrackId, position: Store.player.position || 0, duration: Store.player.duration || 0,
            volume: Store.player.volume, shuffle: Store.player.shuffle === true, repeat: Store.player.repeat_mode, queue: Store.queueIds.length
        };
    }
    Connections {
        target: Fili
        function onCommand(id, verb, arg) {
            let answer;
            if (verb === "action")
                answer = win.runAction(arg.split(" ")[0], arg.split(" ").slice(1).join(" "));
            else if (verb === "actions")
                answer = { ok: true, actions: Object.keys(win.actions).map(n => ({ name: n, enabled: win.actions[n].on() })) };
            else if (verb === "state")
                answer = Object.assign({ ok: true }, win.stateJson());
            else
                answer = { ok: false, error: "unknown command: " + verb };
            Fili.reply(id, JSON.stringify(answer));
        }
    }

    // ---- Shortcuts -----------------------------------------------------------------------------------------------
    Shortcut { sequence: "Ctrl+W"; onActivated: win.quit() }
    Shortcut { sequence: "Ctrl+Q"; onActivated: win.quit() }
    Shortcut { sequence: "Ctrl+F"; onActivated: win.openSearch() }
    Shortcut { sequence: "Ctrl+N"; onActivated: win.newPlaylist() }
    Shortcut { sequence: "Ctrl+1"; onActivated: win.show("tracks") }
    Shortcut { sequence: "Ctrl+2"; onActivated: win.show("albums") }
    Shortcut { sequence: "Ctrl+3"; onActivated: win.show("artists") }
    Shortcut { sequence: "Ctrl+4"; onActivated: win.show("genres") }
    Shortcut { sequence: "Ctrl+Shift+W"; enabled: win.windowButtons; onActivated: windowPanel.visible ? windowPanel.close() : windowPanel.open() }
    Shortcut { sequence: "Space"; enabled: !win.typing && !win.modal; onActivated: win.runAction("play-pause") }
    Shortcut { sequence: "Ctrl+Left"; enabled: Store.hasTrack; onActivated: Store.previous() }
    Shortcut { sequence: "Ctrl+Right"; enabled: Store.hasTrack; onActivated: Store.next() }
    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (win.confirm !== null)
                win.confirm = null;
            else if (win.aboutOpen)
                win.aboutOpen = false;
            else if (win.query !== "" || searchInput.activeFocus) {
                searchInput.text = "";
                win.forceActiveFocus();
                if (win.view === "search")
                    win.show("tracks");
            }
        }
    }

    // ---- Header --------------------------------------------------------------------------------------------------
    Rectangle {
        id: toolbar
        width: parent.width
        height: win.headerShown ? FiliTheme.toolbarHeight : 0
        visible: win.headerShown
        color: FiliTheme.background
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: FiliTheme.borderWidth
            color: FiliTheme.border
        }
        Text {
            anchors { left: parent.left; leftMargin: FiliTheme.margin; right: search.left; rightMargin: FiliTheme.space3; verticalCenter: parent.verticalCenter }
            text: win.viewTitle
            elide: Text.ElideRight
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.size
            font.weight: FiliTheme.weightAccent
            color: FiliTheme.text
        }
        // Window buttons at the far right: close, and the panel of window actions (niri only)
        Rectangle {
            id: closeButton
            visible: win.windowButtons
            anchors { right: parent.right; rightMargin: (toolbar.height - height) / 2; verticalCenter: parent.verticalCenter }
            width: 28
            height: 24
            radius: FiliTheme.radiusControl
            color: closeArea.pressed ? FiliTheme.danger : closeArea.containsMouse ? FiliTheme.alpha(FiliTheme.danger, 0.75) : "transparent"
            WindowGlyph {
                anchors.centerIn: parent
                kind: "close"
                width: 16
                height: 16
                color: closeArea.containsMouse ? "#ffffff" : FiliTheme.text
            }
            MouseArea {
                id: closeArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: win.quit()
            }
            Accessible.role: Accessible.Button
            Accessible.name: Fili.tr("Close window")
        }
        Rectangle {
            id: windowButton
            visible: win.windowButtons
            anchors { right: closeButton.left; rightMargin: FiliTheme.space1; verticalCenter: parent.verticalCenter }
            width: 28
            height: 24
            radius: FiliTheme.radiusControl
            color: windowArea.pressed ? FiliTheme.surfaceActive : windowArea.containsMouse || windowPanel.visible ? FiliTheme.surfaceHover : "transparent"
            WindowGlyph {
                anchors.centerIn: parent
                kind: "window"
                width: 16
                height: 16
            }
            MouseArea {
                id: windowArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: windowPanel.visible ? windowPanel.close() : windowPanel.open()
            }
            Accessible.role: Accessible.Button
            Accessible.name: Fili.tr("Window")
        }
        Rectangle {
            id: search
            anchors { right: windowButton.visible ? windowButton.left : closeButton.visible ? closeButton.left : parent.right; rightMargin: windowButton.visible || closeButton.visible ? FiliTheme.space3 : FiliTheme.margin; verticalCenter: parent.verticalCenter }
            width: 180
            height: 26
            radius: FiliTheme.radiusControl
            color: FiliTheme.surface
            border.width: FiliTheme.borderWidth
            border.color: searchInput.activeFocus ? FiliTheme.accentColor : FiliTheme.border
            Text {
                anchors { left: parent.left; leftMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                visible: searchInput.text === ""
                text: Fili.tr("Search")
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.size
                color: FiliTheme.muted
            }
            TextInput {
                id: searchInput
                anchors { fill: parent; leftMargin: FiliTheme.space2; rightMargin: searchClear.visible ? 22 : FiliTheme.space2 }
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.size
                color: FiliTheme.text
                selectionColor: FiliTheme.surfaceActive
                selectedTextColor: FiliTheme.text
                Accessible.name: Fili.tr("Search")
                onTextChanged: {
                    win.query = text;
                    if (text !== "" && win.view !== "search")
                        win.view = "search";
                    else if (text === "" && win.view === "search" && !activeFocus)
                        win.show("tracks");
                }
            }
            Text {
                id: searchClear
                anchors { right: parent.right; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                visible: searchInput.text !== ""
                text: "×"
                font.family: FiliTheme.font
                font.pixelSize: 16
                color: FiliTheme.muted
                MouseArea { anchors { fill: parent; margins: -6 } onClicked: searchInput.text = "" }
                Accessible.role: Accessible.Button
                Accessible.name: Fili.tr("Clear")
            }
        }
    }

    // ---- Sidebar -------------------------------------------------------------------------------------------------
    Rectangle {
        id: side
        anchors { top: toolbar.bottom; bottom: statusbar.top; left: parent.left }
        width: FiliTheme.sidebarWidth
        color: FiliTheme.backgroundDeep
        Rectangle {
            anchors.right: parent.right
            height: parent.height
            width: FiliTheme.borderWidth
            color: FiliTheme.border
        }
        // Sections folded by the user, for the session
        property var folded: ({})
        readonly property var groups: [
            { key: "library", title: Fili.tr("Library"), rows: win.views.map(v => ({ id: v.id, label: v.label, glyph: v.glyph })), add: false },
            { key: "playlists", title: Fili.tr("Playlists"), rows: win.playlists.map(p => ({ id: "pl:" + p.id, label: p.name, glyph: "≡", count: p.tracks.length })), add: true }
        ]
        Flickable {
            id: sideFlick
            anchors { fill: parent; bottomMargin: scanRow.height; leftMargin: FiliTheme.space2 + 2; rightMargin: FiliTheme.space2 + 2 }
            clip: true
            contentHeight: sideColumn.height
            boundsBehavior: Flickable.StopAtBounds
            KineticScroll {}
            Column {
                id: sideColumn
                width: parent.width
                topPadding: FiliTheme.space1
                Repeater {
                    model: side.groups
                    Column {
                        id: group
                        required property var modelData
                        readonly property bool open: side.folded[modelData.key] !== true
                        width: sideColumn.width
                        Item {
                            width: parent.width
                            height: FiliTheme.sideRowHeight + FiliTheme.space4
                            Rectangle {
                                anchors { fill: parent; topMargin: FiliTheme.space4 }
                                radius: FiliTheme.radiusControl
                                color: headArea.containsMouse ? FiliTheme.alpha(FiliTheme.surfaceHover, 0.5) : "transparent"
                            }
                            Text {
                                id: arrow
                                x: FiliTheme.margin / 2 - (FiliTheme.space2 + 2)
                                anchors { bottom: parent.bottom; bottomMargin: (FiliTheme.sideRowHeight - height) / 2 }
                                text: group.open ? "▾" : "▸"
                                font.pixelSize: FiliTheme.sizeSmall
                                color: FiliTheme.muted
                            }
                            Text {
                                anchors { left: arrow.right; leftMargin: FiliTheme.space2; right: addButton.visible ? addButton.left : parent.right; rightMargin: FiliTheme.space2; bottom: parent.bottom; bottomMargin: (FiliTheme.sideRowHeight - height) / 2 }
                                text: group.modelData.title
                                elide: Text.ElideRight
                                font.family: FiliTheme.font
                                font.pixelSize: FiliTheme.sizeSmall
                                font.weight: FiliTheme.weightAccent
                                color: FiliTheme.muted
                            }
                            MouseArea {
                                id: headArea
                                anchors { fill: parent; topMargin: FiliTheme.space4 }
                                hoverEnabled: true
                                onClicked: {
                                    const next = Object.assign({}, side.folded);
                                    next[group.modelData.key] = group.open;
                                    side.folded = next;
                                }
                            }
                            IconButton {
                                id: addButton
                                visible: group.modelData.add
                                anchors { right: parent.right; rightMargin: FiliTheme.space2; bottom: parent.bottom; bottomMargin: (FiliTheme.sideRowHeight - height) / 2 }
                                glyph: "+"
                                tip: Fili.tr("New playlist")
                                onClicked: win.newPlaylist()
                                Accessible.role: Accessible.Button
                                Accessible.name: Fili.tr("New playlist")
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: group.modelData.title
                        }
                        Repeater {
                            model: group.open ? group.modelData.rows : []
                            Item {
                                id: srow
                                required property var modelData
                                readonly property bool isPlaylist: modelData.id.startsWith("pl:")
                                readonly property bool sel: isPlaylist ? (win.view === "playlist" && "pl:" + win.playlistId === modelData.id) : win.view === modelData.id
                                width: group.width
                                height: FiliTheme.sideRowHeight + 4
                                Rectangle {
                                    anchors { fill: parent; topMargin: 1; bottomMargin: 1 }
                                    radius: FiliTheme.radiusControl
                                    color: srow.sel || rowArea.containsMouse ? FiliTheme.surfaceHover : "transparent"
                                }
                                Text {
                                    id: rowGlyph
                                    x: FiliTheme.margin / 2 - (FiliTheme.space2 + 2)
                                    width: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    text: srow.modelData.glyph
                                    font.family: srow.modelData.id === "search" ? FiliTheme.icons : FiliTheme.font
                                    font.pixelSize: srow.modelData.id === "search" ? 14 : 15
                                    color: srow.sel ? FiliTheme.accentColor : FiliTheme.muted
                                }
                                Text {
                                    id: rowCount
                                    anchors { right: parent.right; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                                    text: srow.modelData.count !== undefined ? srow.modelData.count : ""
                                    font.family: FiliTheme.font
                                    font.pixelSize: FiliTheme.sizeSmall
                                    color: FiliTheme.muted
                                }
                                Text {
                                    anchors { left: rowGlyph.right; leftMargin: FiliTheme.space2; right: rowCount.left; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                                    text: srow.modelData.label
                                    elide: Text.ElideRight
                                    font.family: FiliTheme.font
                                    font.pixelSize: FiliTheme.size
                                    font.weight: srow.sel ? FiliTheme.weightAccent : Font.Normal
                                    color: FiliTheme.text
                                }
                                MouseArea {
                                    id: rowArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: e => {
                                        if (srow.isPlaylist) {
                                            const id = Number(srow.modelData.id.slice(3));
                                            if (e.button === Qt.RightButton) {
                                                const p = rowArea.mapToItem(null, e.x, e.y);
                                                const pl = win.playlists.find(x => x.id === id);
                                                Store.menuRequested(p.x, p.y, [
                                                    { id: "show", label: Fili.tr("Show tracks") },
                                                    { id: "play", label: Fili.tr("Play") },
                                                    { id: "rename", label: Fili.tr("Rename…") },
                                                    { id: "separator1", separator: true },
                                                    { id: "delete", label: Fili.tr("Delete playlist") }
                                                ], act => {
                                                    if (act === "show") {
                                                        win.playlistId = id;
                                                        win.view = "playlist";
                                                    } else if (act === "play")
                                                        Store.playNow(pl.tracks.map(t => t.track_id), 0);
                                                    else if (act === "rename")
                                                        win.renamePlaylist(pl);
                                                    else if (act === "delete")
                                                        win.deletePlaylist(pl);
                                                });
                                            } else {
                                                win.playlistId = id;
                                                win.view = "playlist";
                                            }
                                        } else if (srow.modelData.id === "search")
                                            win.openSearch();
                                        else
                                            win.show(srow.modelData.id);
                                    }
                                    onDoubleClicked: {
                                        if (srow.isPlaylist) {
                                            const pl = win.playlists.find(x => x.id === Number(srow.modelData.id.slice(3)));
                                            if (pl)
                                                Store.playNow(pl.tracks.map(t => t.track_id), 0);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        // Scan: the button, and the progress of what runs in the background
        Item {
            id: scanRow
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: scanner.scanning || scanner.fetching ? 76 : 40
            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: FiliTheme.borderWidth
                color: FiliTheme.border
            }
            Column {
                anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: FiliTheme.space3; rightMargin: FiliTheme.space3; topMargin: FiliTheme.space2 }
                spacing: FiliTheme.space1
                Repeater {
                    model: [
                        { show: scanner.scanning, label: Fili.tr("Scanning"), value: scanner.scanFraction },
                        { show: scanner.fetching, label: Fili.tr("Artwork"), value: scanner.artFraction }
                    ]
                    Column {
                        required property var modelData
                        width: parent.width
                        visible: modelData.show
                        spacing: 2
                        Row {
                            width: parent.width
                            Text {
                                width: parent.width - pct.width
                                text: modelData.label
                                font.family: FiliTheme.font
                                font.pixelSize: FiliTheme.sizeSmall
                                color: FiliTheme.textSecondary
                            }
                            Text {
                                id: pct
                                text: Math.round(modelData.value * 100) + "%"
                                font.family: FiliTheme.font
                                font.pixelSize: FiliTheme.sizeSmall
                                color: FiliTheme.muted
                            }
                        }
                        Rectangle {
                            width: parent.width
                            height: 3
                            radius: 2
                            color: FiliTheme.alpha(FiliTheme.muted, 0.35)
                            Rectangle { width: parent.width * modelData.value; height: parent.height; radius: 2; color: FiliTheme.accentColor }
                        }
                    }
                }
                TextButton {
                    visible: !scanner.scanning && !scanner.fetching
                    label: Fili.tr("Scan the library…")
                    onClicked: scanner.open(false)
                }
            }
            MouseArea {
                anchors.fill: parent
                enabled: scanner.scanning || scanner.fetching
                onClicked: scanner.open(false)
            }
        }
    }

    function renamePlaylist(pl) {
        prompt.mode = "rename";
        prompt.target = pl.id;
        prompt.open(Fili.tr("Rename the playlist"), pl.name, [], Fili.tr("Rename"), Fili.tr("Name"));
    }
    function deletePlaylist(pl) {
        confirm = {
            text: Fili.tr("Delete the playlist “%1”?").replace("%1", pl.name),
            label: Fili.tr("Delete"),
            run: () => {
                Store.call("delete_playlist", [pl.id]);
                if (playlistId === pl.id) {
                    playlistId = -1;
                    show("tracks");
                }
                Store.playlistRev++;
            }
        };
    }

    // ---- Content ---------------------------------------------------------------------------------------------------
    Item {
        id: content
        anchors { top: toolbar.bottom; bottom: statusbar.top; left: side.right; right: player.left }
        clip: true
        // The view is rebuilt when it changes: each one loads its own data
        Loader {
            id: loader
            anchors.fill: parent
            sourceComponent: win.view === "search" ? searchView : win.view === "albums" ? albumsView : win.view === "artists" ? artistsView : win.view === "genres" ? genresView : win.view === "playlist" ? playlistView : tracksView
        }
        Component {
            id: tracksView
            TracksView { onTrackMenu: (ids, x, y) => win.trackMenu(ids, x, y) }
        }
        Component {
            id: albumsView
            AlbumsView {
                onTrackMenu: (ids, x, y) => win.trackMenu(ids, x, y)
                onAlbumMenu: (album, x, y) => win.albumMenu(album, x, y)
            }
        }
        Component {
            id: artistsView
            ArtistsView {
                onAlbumMenu: (album, x, y) => win.albumMenu(album, x, y)
                onOpenAlbum: album => Store.albumRequested(album.id)
            }
        }
        Component {
            id: genresView
            GenresView {
                onAlbumMenu: (album, x, y) => win.albumMenu(album, x, y)
                onOpenAlbum: album => Store.albumRequested(album.id)
            }
        }
        Component {
            id: playlistView
            PlaylistView {
                playlistId: win.playlistId
                onTrackMenu: (ids, x, y, positions) => win.trackMenu(ids, x, y, positions, win.playlistId)
                onRenameRequested: pl => win.renamePlaylist(pl)
                onDeleteRequested: pl => win.deletePlaylist(pl)
            }
        }
        Component {
            id: searchView
            SearchView {
                query: win.query
                onTrackMenu: (ids, x, y) => win.trackMenu(ids, x, y)
                onAlbumMenu: (album, x, y) => win.albumMenu(album, x, y)
                onOpenAlbum: album => { searchInput.text = ""; Store.albumRequested(album.id); }
                onOpenArtist: artist => { searchInput.text = ""; Store.artistRequested(artist.id); }
            }
        }
    }

    // ---- Player panel ----------------------------------------------------------------------------------------------
    Rectangle {
        id: player
        anchors { top: toolbar.bottom; bottom: statusbar.top; right: parent.right }
        width: win.playerWidth
        color: FiliTheme.background
        Rectangle {
            width: FiliTheme.borderWidth
            height: parent.height
            color: FiliTheme.border
        }
        QueuePanel {
            id: queue
            anchors { top: parent.top; bottom: controls.top; left: parent.left; right: parent.right; leftMargin: FiliTheme.borderWidth }
            onSaveRequested: win.saveQueue()
            onMenuRequested: (index, x, y) => Store.menuRequested(x, y, [
                { id: "play", label: Fili.tr("Play") },
                { id: "remove", label: Fili.tr("Remove from queue") }
            ], id => id === "play" ? Store.playQueueAt(index) : Store.removeFromQueue(index))
        }
        Rectangle {
            anchors { bottom: controls.top; left: parent.left; right: parent.right }
            height: FiliTheme.borderWidth
            color: FiliTheme.border
        }
        PlayerControls {
            id: controls
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: FiliTheme.borderWidth }
            height: implicitHeight
            onArtworkClicked: id => Store.albumRequested(id)
        }
        // Resize handle on the left edge
        MouseArea {
            id: grip
            x: -3
            width: 6
            height: parent.height
            hoverEnabled: true
            cursorShape: Qt.SizeHorCursor
            property real startX: 0
            property real startWidth: 0
            onPressed: e => {
                startX = mapToItem(null, e.x, 0).x;
                startWidth = win.playerWidth;
            }
            onPositionChanged: e => {
                if (pressed)
                    win.playerWidth = Math.max(260, Math.min(700, startWidth - (mapToItem(null, e.x, 0).x - startX)));
            }
            onReleased: Fili.setUiState("player_width", String(Math.round(win.playerWidth)))
        }
    }

    // ---- Footer ------------------------------------------------------------------------------------------------------
    Rectangle {
        id: statusbar
        anchors.bottom: parent.bottom
        width: parent.width
        height: win.footerShown ? FiliTheme.statusHeight : 0
        visible: win.footerShown
        // Recessed like Facteur's footer (app-window.md of the filigrane-ui skill)
        color: FiliTheme.backgroundDeep
        Rectangle {
            width: parent.width
            height: FiliTheme.borderWidth
            color: FiliTheme.border
        }
        // An inline confirmation takes the whole bar: the action on the right, Cancel to its left
        Item {
            anchors { fill: parent; topMargin: 1 }
            visible: win.confirm !== null
            Text {
                anchors { left: parent.left; leftMargin: FiliTheme.margin; right: cancelButton.left; rightMargin: FiliTheme.space3; verticalCenter: parent.verticalCenter }
                elide: Text.ElideRight
                text: win.confirm ? win.confirm.text : ""
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeSmall
                color: FiliTheme.text
            }
            TextButton {
                id: cancelButton
                anchors { right: okButton.left; rightMargin: FiliTheme.space1; verticalCenter: parent.verticalCenter }
                label: Fili.tr("Cancel")
                onClicked: win.confirm = null
            }
            TextButton {
                id: okButton
                anchors { right: parent.right; rightMargin: FiliTheme.margin - FiliTheme.space3; verticalCenter: parent.verticalCenter }
                label: win.confirm ? win.confirm.label : ""
                primary: true
                onClicked: {
                    const run = win.confirm.run;
                    win.confirm = null;
                    run();
                }
            }
        }
        // An error or a notice
        Text {
            anchors { fill: parent; leftMargin: FiliTheme.space3; rightMargin: FiliTheme.space3; topMargin: 1 }
            visible: win.confirm === null && win.message !== ""
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideMiddle
            text: win.message
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.sizeSmall
            color: win.failed ? FiliTheme.danger : FiliTheme.textSecondary
            MouseArea { anchors.fill: parent; onClicked: win.message = "" }
        }
        Text {
            anchors { left: parent.left; leftMargin: FiliTheme.margin; right: parent.horizontalCenter; top: parent.top; topMargin: 1; bottom: parent.bottom }
            visible: win.confirm === null && win.message === ""
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: win.stats.track_count + " " + Fili.tr("tracks") + " · " + win.stats.album_count + " " + Fili.tr("albums") + " · " + win.stats.artist_count + " " + Fili.tr("artists") + " · " + Store.longDuration(win.stats.total_duration_seconds)
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.sizeSmall
            color: FiliTheme.textSecondary
        }
        Text {
            anchors { right: parent.right; rightMargin: FiliTheme.margin; left: parent.horizontalCenter; top: parent.top; topMargin: 1; bottom: parent.bottom }
            visible: win.confirm === null && win.message === ""
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideMiddle
            text: Store.queueIds.length > 0 ? Store.queueIds.length + " " + Fili.tr("in the queue") : ""
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.sizeSmall
            color: FiliTheme.textSecondary
        }
    }

    // ---- Window actions, dialogs, About ---------------------------------------------------------------------------
    WindowPanel {
        id: windowPanel
        anchorRight: width - (toolbar.height - closeButton.height) / 2
        anchorTop: toolbar.height + 1
    }
    PromptDialog {
        id: prompt
        // "new", "save" or "rename"; the tracks to put in the new playlist; the playlist to rename
        property string mode: "new"
        property var ids: []
        property int target: -1
        onAccepted: (text, choiceId) => {
            if (mode === "rename") {
                Store.call("rename_playlist", [target, text]);
            } else if (choiceId >= 0) {
                win.addToPlaylist(choiceId, ids);
                return;
            } else {
                const created = Store.call("create_playlist", [text]);
                if (!created) {
                    win.say(Store.lastError || Fili.tr("The playlist could not be created"), true);
                    return;
                }
                for (const id of ids)
                    Store.call("add_track_to_playlist", [created.id, id]);
                win.say(Fili.tr("Playlist created") + ": " + text, false);
            }
            Store.playlistRev++;
            win.loadPlaylists();
        }
    }
    TagEditor {
        id: tagEditor
    }
    ScannerDialog {
        id: scanner
        onFinished: {
            win.loadStats();
            win.show("tracks");
        }
    }

    // About card: in front of the window, closed by Esc or a click outside
    Rectangle {
        id: about
        visible: win.aboutOpen
        anchors.fill: parent
        z: 300
        color: FiliTheme.alpha(FiliTheme.background, 0.6)
        focus: visible
        MouseArea { anchors.fill: parent; onClicked: win.aboutOpen = false }
        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(440, parent.width - 2 * FiliTheme.margin)
            height: cardColumn.implicitHeight + 2 * FiliTheme.space6
            radius: FiliTheme.radiusWindow
            color: FiliTheme.surface
            border.width: FiliTheme.borderWidth
            border.color: FiliTheme.border
            MouseArea { anchors.fill: parent }
            Column {
                id: cardColumn
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: FiliTheme.space6 }
                spacing: FiliTheme.space2
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Baladeur"
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeTitle + 4
                    font.weight: Font.Light
                    color: FiliTheme.text
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: Fili.tr("Plays your music library: albums, artists, genres, playlists and a queue")
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.size
                    color: FiliTheme.textSecondary
                }
                Item { width: 1; height: FiliTheme.space2 }
                Repeater {
                    model: win.aboutOpen ? JSON.parse(Fili.aboutRows()) : []
                    Row {
                        id: aboutRow
                        required property var modelData
                        width: cardColumn.width
                        spacing: FiliTheme.space3
                        Text {
                            width: 120
                            horizontalAlignment: Text.AlignRight
                            text: aboutRow.modelData[0]
                            font.family: FiliTheme.font
                            font.pixelSize: FiliTheme.size
                            color: FiliTheme.muted
                        }
                        Text {
                            width: parent.width - 120 - FiliTheme.space3
                            text: aboutRow.modelData[1]
                            elide: Text.ElideMiddle
                            font.family: FiliTheme.font
                            font.pixelSize: FiliTheme.size
                            color: FiliTheme.text
                        }
                    }
                }
            }
        }
    }
}
