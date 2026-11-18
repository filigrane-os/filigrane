// The queue: a filter field, the tracks (the current one highlighted, double click plays it, the bin removes it) and the bar of
// queue actions (random tracks, repeat, shuffle, save as playlist, clear).
import QtQuick
import Fili.Baladeur

Item {
    id: panel
    signal saveRequested()
    signal menuRequested(int index, real x, real y)

    property string filter: ""
    readonly property bool empty: Store.queueIds.length === 0

    // Width of the number column: room for the biggest number of the queue ("12 345." is wider than "9.")
    TextMetrics {
        id: numberMetrics
        font.family: FiliTheme.font
        font.pixelSize: FiliTheme.size
        font.weight: FiliTheme.weightAccent
        text: "9".repeat(String(Store.queueIds.length).length) + "."
    }
    readonly property real numberWidth: Math.ceil(numberMetrics.advanceWidth) + FiliTheme.space2

    // ---- Rows on demand -------------------------------------------------------------------------------------------------
    // The list is virtual: only the rows on screen exist, and each one asks for its track the first time it is drawn (a
    // queue of the whole library is never loaded). `rows` holds the tracks received, by id, and is emptied when it grows.
    property var rows: ({})
    property int rowsRev: 0
    property int rowCount: 0
    property var wanted: ({})
    readonly property var flags: ({ scheduled: false })
    function rowAt(pos) {
        rowsRev;
        const id = Store.queueIdAt(pos);
        const r = rows[id];
        if (r !== undefined)
            return r;
        wanted[id] = true;
        // `flags` is a plain object: reading `fetchTimer.running` here would make this binding depend on what it starts
        // (a binding loop on the row's `info`)
        if (!flags.scheduled) {
            flags.scheduled = true;
            fetchTimer.start();
        }
        return null;
    }
    // Keep the rows of `list` (tracks of the core); an id the library lost keeps a blank row
    function store(ids, list) {
        if (rowCount > 3000) {
            rows = ({});
            rowCount = 0;
        }
        for (const t of list || []) {
            if (rows[t.id] === undefined)
                rowCount++;
            rows[t.id] = Store.row(t);
        }
        for (const id of ids) {
            if (rows[id] === undefined) {
                rows[id] = { id: id, title: "—", artistId: -1, artists: "", missing: true };
                rowCount++;
            }
        }
        rowsRev++;
    }
    function fetchRows(ids, done) {
        Store.callAsync("tracks_by_ids", [JSON.stringify(ids)], list => {
            panel.store(ids, list);
            if (done)
                done();
        });
    }
    Timer {
        id: fetchTimer
        interval: 30
        onTriggered: {
            panel.flags.scheduled = false;
            const ids = Object.keys(panel.wanted).map(Number).slice(0, 200);
            if (ids.length === 0)
                return;
            for (const id of ids)
                delete panel.wanted[id];
            panel.fetchRows(ids);
            if (Object.keys(panel.wanted).length > 0) {
                panel.flags.scheduled = true;
                fetchTimer.start();
            }
        }
    }
    Connections {
        target: Store
        // Tags or covers changed: the rows are asked again
        function onLibraryRevChanged() {
            panel.rows = ({});
            panel.rowCount = 0;
            panel.rowsRev++;
        }
        function onQueueRevChanged() {
            if (panel.filter !== "")
                filterTimer.restart();
        }
        // Names of artists arrive one by one: the filter looks again
        function onRevChanged() {
            if (panel.filter !== "")
                filterTimer.restart();
        }
    }
    Component.onCompleted: Store.refreshQueue()

    // ---- Filter ---------------------------------------------------------------------------------------------------------
    // null: no filter, the whole queue is shown; else the places of the queue that match. A small queue is read in full; a big
    // one is searched in the library (full-text search, the first 1000 matches) and crossed with the queue.
    property var matches: null
    onFilterChanged: {
        if (filter === "")
            matches = null;
        else
            filterTimer.restart();
    }
    Timer {
        id: filterTimer
        interval: 200
        onTriggered: panel.runFilter()
    }
    function runFilter() {
        const q = panel.filter;
        if (q === "")
            return;
        const total = Store.queueIds.length;
        const done = found => {
            if (panel.filter === q)
                panel.matches = found;
        };
        if (total <= 2000) {
            const missing = Store.queueIds.filter(id => rows[id] === undefined);
            const pick = () => {
                const found = [];
                for (let i = 0; i < total; i++) {
                    const r = rows[Store.queueIdAt(i)];
                    if (r && (r.title.toLowerCase().includes(q) || (r.artists !== "" ? r.artists : Store.artistName(r.artistId)).toLowerCase().includes(q)))
                        found.push(i);
                }
                done(found);
            };
            if (missing.length === 0)
                pick();
            else
                fetchRows(missing, pick);
        } else {
            Store.callAsync("search_tracks", [q, 1000], d => {
                const hit = {};
                for (const t of d ? d.tracks : []) {
                    hit[t.id] = true;
                    if (rows[t.id] === undefined) {
                        rows[t.id] = Store.row(t);
                        rowCount++;
                    }
                }
                rowsRev++;
                const found = [];
                for (let i = 0; i < total; i++)
                    if (hit[Store.queueIdAt(i)])
                        found.push(i);
                done(found);
            });
        }
    }

    // Filter
    Rectangle {
        id: filterBar
        visible: !panel.empty
        width: parent.width
        height: visible ? 36 : 0
        color: FiliTheme.background
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: FiliTheme.borderWidth
            color: FiliTheme.border
        }
        Text {
            id: lens
            x: FiliTheme.space3
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            font.family: FiliTheme.icons
            font.pixelSize: 13
            color: FiliTheme.muted
        }
        Text {
            anchors { left: lens.right; leftMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
            visible: filterInput.text === ""
            text: Fili.tr("Filter the queue")
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.size
            color: FiliTheme.muted
        }
        TextInput {
            id: filterInput
            anchors { left: lens.right; leftMargin: FiliTheme.space2; right: clear.left; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
            clip: true
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.size
            color: FiliTheme.text
            onTextChanged: panel.filter = text.toLowerCase()
            Keys.onEscapePressed: text = ""
        }
        Text {
            id: clear
            anchors { right: parent.right; rightMargin: FiliTheme.space3; verticalCenter: parent.verticalCenter }
            visible: filterInput.text !== ""
            text: "×"
            font.family: FiliTheme.font
            font.pixelSize: 16
            color: FiliTheme.muted
            MouseArea { anchors.fill: parent; onClicked: filterInput.text = "" }
        }
    }

    // Empty queue
    Column {
        anchors.centerIn: list
        visible: panel.empty
        spacing: FiliTheme.space3
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "♫"
            font.pixelSize: 56
            font.family: FiliTheme.font
            color: FiliTheme.muted
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Fili.tr("The queue is empty")
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.sizeTitle
            font.weight: FiliTheme.weightAccent
            color: FiliTheme.text
        }
        Text {
            width: list.width - 2 * FiliTheme.space6
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: Fili.tr("Double-click a track, or drag an album here")
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.size
            color: FiliTheme.textSecondary
        }
    }

    ListView {
        id: list
        anchors { top: filterBar.bottom; bottom: bar.top; left: parent.left; right: parent.right }
        visible: !panel.empty
        model: panel.matches === null ? Store.queueIds.length : panel.matches
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        KineticScroll {}
        // Slot a dragged track would take (-1 when nothing is dragged)
        property int dropIndex: -1
        Rectangle {
            parent: list.contentItem
            z: 10
            visible: list.dropIndex >= 0
            x: 0
            y: list.dropIndex * 44 - 1
            width: list.width
            height: 2
            color: FiliTheme.accentColor
        }
        // The current track is brought into view when it changes
        Connections {
            target: Store
            function onQueueIndexChanged() {
                if (Store.queueIndex >= 0 && panel.matches === null)
                    list.positionViewAtIndex(Math.max(0, Store.queueIndex - 2), ListView.Beginning);
            }
        }
        delegate: Rectangle {
            id: row
            required property int index
            required property var modelData
            // Place in the queue: the row number when the whole queue is shown, else the one the filter kept
            readonly property int position: panel.matches === null ? index : modelData
            readonly property var info: panel.rowAt(position)
            readonly property int id: info ? info.id : -1
            readonly property string title: info ? info.title : ""
            readonly property bool current: position === Store.queueIndex
            readonly property bool unavailable: (Store.player.skipped_track_ids || []).indexOf(id) >= 0
            readonly property string artist: info ? (info.artists !== "" ? info.artists : Store.artistName(info.artistId)) : ""
            width: list.width
            height: 44
            color: current ? FiliTheme.alpha(FiliTheme.accentColor, 0.12) : area.containsMouse ? FiliTheme.alpha(FiliTheme.surfaceHover, 0.5) : "transparent"

            Text {
                id: number
                x: FiliTheme.space3
                width: panel.numberWidth
                anchors.verticalCenter: parent.verticalCenter
                text: (row.position + 1) + "."
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.size
                font.weight: row.current ? FiliTheme.weightAccent : Font.Normal
                color: row.current ? FiliTheme.text : FiliTheme.muted
            }
            Column {
                anchors { left: number.right; right: bin.left; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                spacing: 2
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: row.title
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.size
                    font.weight: row.current ? FiliTheme.weightAccent : Font.Normal
                    color: row.unavailable ? FiliTheme.danger : FiliTheme.text
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: row.artist
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeSmall
                    color: row.unavailable ? FiliTheme.alpha(FiliTheme.danger, 0.7) : FiliTheme.textSecondary
                }
            }
            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onDoubleClicked: Store.playQueueAt(row.position)
                // Drag to reorder: a line shows where the track will land; released on its own place it does nothing
                property real pressY: 0
                property bool dragging: false
                onPressed: e => {
                    pressY = e.y;
                    dragging = false;
                }
                onPositionChanged: e => {
                    if (!pressed || panel.matches !== null || Store.player.shuffle === true)
                        return;
                    if (!dragging && Math.abs(e.y - pressY) > 6)
                        dragging = true;
                    if (dragging) {
                        const y = area.mapToItem(list.contentItem, e.x, e.y).y;
                        list.dropIndex = Math.max(0, Math.min(Store.queueIds.length, Math.round(y / 44)));
                    }
                }
                onReleased: {
                    if (dragging) {
                        let to = list.dropIndex;
                        if (to > row.position)
                            to--;
                        if (to !== row.position && to >= 0)
                            Store.moveInQueue(row.position, to);
                    }
                    dragging = false;
                    list.dropIndex = -1;
                }
                onCanceled: {
                    dragging = false;
                    list.dropIndex = -1;
                }
                onClicked: e => {
                    if (e.button === Qt.RightButton) {
                        const p = area.mapToItem(null, e.x, e.y);
                        panel.menuRequested(row.position, p.x, p.y);
                    }
                }
            }
            Text {
                id: bin
                anchors { right: parent.right; rightMargin: FiliTheme.space3; verticalCenter: parent.verticalCenter }
                visible: area.containsMouse || binArea.containsMouse
                text: ""
                font.family: FiliTheme.icons
                font.pixelSize: 14
                color: binArea.containsMouse ? FiliTheme.danger : FiliTheme.textSecondary
                MouseArea {
                    id: binArea
                    anchors { fill: parent; margins: -6 }
                    hoverEnabled: true
                    onClicked: Store.removeFromQueue(row.position)
                }
                Accessible.name: Fili.tr("Remove from queue")
            }
        }
    }
    FiliScrollBar {
        flick: list
        anchors { top: list.top; bottom: list.bottom; right: list.right }
    }

    // Queue actions
    Rectangle {
        id: bar
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        height: 44
        color: FiliTheme.background
        Rectangle {
            width: parent.width
            height: FiliTheme.borderWidth
            color: FiliTheme.border
        }
        Row {
            anchors.fill: parent
            Repeater {
                model: [
                    { key: "random", glyph: "⚄", tip: Fili.tr("Library and random tracks") },
                    { key: "repeat", glyph: "↻", tip: Fili.tr("Repeat") },
                    { key: "shuffle", glyph: "⇄", tip: Fili.tr("Shuffle") },
                    { key: "save", glyph: "≡+", tip: Fili.tr("Save the queue as a playlist") },
                    { key: "clear", glyph: "", tip: Fili.tr("Clear the queue") }
                ]
                Item {
                    id: qb
                    required property var modelData
                    readonly property bool lit: (modelData.key === "repeat" && Store.player.repeat_mode !== undefined && Store.player.repeat_mode !== "off") || (modelData.key === "shuffle" && Store.player.shuffle === true)
                    readonly property bool off: (modelData.key === "save" || modelData.key === "clear") && panel.empty
                    width: bar.width / 5
                    height: bar.height
                    Text {
                        anchors.centerIn: parent
                        text: qb.modelData.glyph + (qb.modelData.key === "repeat" && Store.player.repeat_mode === "one" ? "¹" : "")
                        font.family: qb.modelData.key === "clear" ? FiliTheme.icons : FiliTheme.font
                        font.pixelSize: qb.lit ? 20 : 17
                        color: qb.off ? FiliTheme.alpha(FiliTheme.muted, 0.5) : qb.lit ? FiliTheme.accentColor : FiliTheme.textSecondary
                    }
                    MouseArea {
                        id: qbArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !qb.off
                        onClicked: {
                            switch (qb.modelData.key) {
                            case "random": {
                                const p = qb.mapToItem(null, 0, 0);
                                Store.menuRequested(p.x, p.y, [
                                    { id: "library-shuffled", label: Fili.tr("Play the whole library, shuffled") },
                                    { id: "library-ordered", label: Fili.tr("Play the whole library, in order") },
                                    { separator: true },
                                    { id: "random-30", label: Fili.tr("Add 30 random tracks") },
                                    { id: "random-50", label: Fili.tr("Add 50 random tracks") },
                                    { id: "random-100", label: Fili.tr("Add 100 random tracks") },
                                    { separator: true },
                                    { id: "top-up", label: Fili.tr("Keep the queue going"), checked: Store.topUp }
                                ], id => {
                                    if (id === "library-shuffled")
                                        Store.playLibrary("random");
                                    else if (id === "library-ordered")
                                        Store.playLibrary("ordered");
                                    else if (id === "top-up")
                                        Store.setTopUp(!Store.topUp);
                                    else
                                        Store.addRandom(Number(id.slice(7)));
                                });
                                break;
                            }
                            case "repeat":
                                Store.toggleRepeat();
                                break;
                            case "shuffle":
                                Store.toggleShuffle();
                                break;
                            case "save":
                                panel.saveRequested();
                                break;
                            default:
                                Store.clearQueue();
                            }
                        }
                    }
                    Rectangle { anchors.fill: parent; z: -1; color: qbArea.containsMouse && !qb.off ? FiliTheme.alpha(FiliTheme.surfaceHover, 0.5) : "transparent" }
                    Accessible.role: Accessible.Button
                    Accessible.name: qb.modelData.tip
                }
            }
        }
    }
}
