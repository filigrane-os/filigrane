// Table of tracks (number, title, artist, album, time): sortable headers, multiple selection (click, Ctrl, Shift), double click
// plays, right click asks for a menu. Rows come from a ListModel filled by Store.fill().
import QtQuick
import Fili.Baladeur

Item {
    id: table
    required property ListModel model
    property bool sortable: false
    property bool showAlbum: true
    property bool showArtist: true
    // The number column shows the position in the list, or the number of the track on its disc
    property bool trackNumbers: false
    property string sortBy: ""
    property string sortDir: "asc"
    property var selected: ({})
    property int anchorRow: -1
    property alias list: list
    readonly property int selectedCount: Object.keys(selected).length

    signal activated(int row, bool altHeld)
    signal menuRequested(int row, real x, real y)
    signal sortRequested(string by, string dir)
    signal loadMore()
    signal deleteRequested()

    function selectedIds() {
        return Store.ids(model).filter(id => selected[id] === true);
    }
    function clearSelection() {
        selected = ({});
    }
    function select(row, ctrl, shift) {
        const next = ctrl ? Object.assign({}, selected) : {};
        if (shift && anchorRow >= 0) {
            const a = Math.min(anchorRow, row), b = Math.max(anchorRow, row);
            for (let i = a; i <= b; i++)
                next[model.get(i).id] = true;
        } else {
            const id = model.get(row).id;
            if (ctrl && next[id])
                delete next[id];
            else
                next[id] = true;
            anchorRow = row;
        }
        selected = next;
    }

    // Columns: the ones in `shown` (right click on the header chooses them, the choice is remembered). Fixed widths for the
    // short ones, the text columns share the rest by weight.
    readonly property var catalog: [
        { key: "number", sort: "track_number", label: "#", w: 48, always: true },
        { key: "title", sort: "title", label: Fili.tr("Title"), weight: 4, always: true },
        { key: "artist", sort: "artist", label: Fili.tr("Artist"), weight: 3, need: "showArtist" },
        { key: "album", sort: "album", label: Fili.tr("Album"), weight: 3, need: "showAlbum" },
        { key: "duration", sort: "duration", label: Fili.tr("Time"), w: 64, right: true, always: true },
        { key: "format", sort: "file_type", label: Fili.tr("Format"), w: 130 },
        { key: "trackno", sort: "track_number", label: Fili.tr("Track"), w: 60 },
        { key: "size", sort: "file_size", label: Fili.tr("Size"), w: 76, right: true },
        { key: "added", sort: "created_at", label: Fili.tr("Added"), w: 96 },
        { key: "path", sort: "file_path", label: Fili.tr("Path"), weight: 4 }
    ]
    property var optional: columnsChoice()
    function columnsChoice() {
        try {
            const saved = JSON.parse(Fili.uiState("columns") || "null");
            if (saved)
                return saved;
        } catch (e) {}
        return ["format"];
    }
    readonly property var cols: catalog.filter(c => (c.always && (!c.need || table[c.need])) || (!c.always && !c.need && optional.indexOf(c.key) >= 0) || (c.need && table[c.need]))
    readonly property real fixedWidth: cols.reduce((n, c) => n + (c.w || 0), 0)
    readonly property real totalWeight: cols.reduce((n, c) => n + (c.weight || 0), 0)
    function widthOf(c) {
        return c.w ? c.w : Math.floor(Math.max(0, width - 2 * FiliTheme.margin - fixedWidth) * c.weight / Math.max(1, totalWeight));
    }
    // The columns after the time keep a gap from it
    function spaced(c) {
        return ["format", "trackno", "size", "added", "path"].indexOf(c.key) >= 0;
    }
    function toggleColumn(key) {
        const next = optional.indexOf(key) >= 0 ? optional.filter(k => k !== key) : optional.concat([key]);
        optional = next;
        Fili.setUiState("columns", JSON.stringify(next));
    }
    function columnMenu(x, y) {
        const items = catalog.filter(c => !c.always && !c.need).map(c => ({ id: c.key, label: (optional.indexOf(c.key) >= 0 ? "✓ " : "    ") + c.label }));
        Store.menuRequested(x, y, items, id => table.toggleColumn(id));
    }
    function cellText(c, r) {
        switch (c.key) {
        case "title": return r.title;
        case "artist": return r.artists !== "" ? r.artists : Store.artistName(r.artistId);
        case "album": return Store.albumTitle(r.albumId >= 0 ? r.albumId : null);
        case "duration": return Store.clock(r.duration);
        case "format": return r.format;
        case "trackno": return r.trackNumber > 0 ? (r.discNumber > 1 ? r.discNumber + "-" : "") + r.trackNumber : "";
        case "size": return Store.sizeText(r.size);
        case "added": return r.added.substring(0, 10);
        case "path": return r.path;
        }
        return "";
    }

    // Header
    Rectangle {
        id: head
        width: parent.width
        height: FiliTheme.rowHeight + FiliTheme.space1
        color: FiliTheme.background
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: FiliTheme.borderWidth
            color: FiliTheme.border
        }
        Row {
            x: FiliTheme.margin
            height: parent.height
            Repeater {
                model: table.cols
                Item {
                    id: col
                    required property var modelData
                    width: table.widthOf(modelData)
                    height: head.height
                    Text {
                        anchors { fill: parent; rightMargin: FiliTheme.space2; leftMargin: table.spaced(col.modelData) ? FiliTheme.space3 : 0 }
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: col.modelData.right ? Text.AlignRight : Text.AlignLeft
                        elide: Text.ElideRight
                        text: col.modelData.label + (table.sortBy === col.modelData.sort ? (table.sortDir === "asc" ? "  ▴" : "  ▾") : "")
                        font.family: FiliTheme.font
                        font.pixelSize: FiliTheme.sizeSmall
                        font.weight: FiliTheme.weightAccent
                        color: table.sortBy === col.modelData.sort ? FiliTheme.text : FiliTheme.muted
                    }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        enabled: table.sortable
                        onClicked: table.sortRequested(col.modelData.sort, table.sortBy === col.modelData.sort && table.sortDir === "asc" ? "desc" : "asc")
                    }
                }
            }
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: e => {
                const p = mapToItem(null, e.x, e.y);
                table.columnMenu(p.x, p.y);
            }
        }
    }

    ListView {
        id: list
        anchors { top: head.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        model: table.model
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        activeFocusOnTab: true
        KineticScroll {}
        onAtYEndChanged: if (atYEnd && count > 0)
            table.loadMore()
        Keys.onPressed: e => {
            if (e.key === Qt.Key_A && (e.modifiers & Qt.ControlModifier)) {
                const all = {};
                for (let i = 0; i < table.model.count; i++)
                    all[table.model.get(i).id] = true;
                table.selected = all;
                e.accepted = true;
            } else if (e.key === Qt.Key_Delete && table.selectedCount > 0) {
                table.deleteRequested();
                e.accepted = true;
            } else if (e.key === Qt.Key_Return && table.anchorRow >= 0) {
                table.activated(table.anchorRow, false);
                e.accepted = true;
            } else if ((e.key === Qt.Key_Down || e.key === Qt.Key_Up) && count > 0) {
                const r = Math.max(0, Math.min(count - 1, (table.anchorRow < 0 ? -1 : table.anchorRow) + (e.key === Qt.Key_Down ? 1 : -1)));
                table.select(r, false, e.modifiers & Qt.ShiftModifier);
                positionViewAtIndex(r, ListView.Contain);
                e.accepted = true;
            }
        }

        delegate: Rectangle {
            id: rowItem
            required property int index
            required property int id
            required property string title
            required property int artistId
            required property int albumId
            required property string artists
            required property int duration
            required property int trackNumber
            required property int discNumber
            required property string format
            required property int size
            required property string path
            required property string added
            readonly property bool current: id === Store.currentTrackId
            readonly property bool picked: table.selected[id] === true
            width: list.width
            height: FiliTheme.rowHeight + 4
            color: picked ? FiliTheme.surfaceHover : mouse.containsMouse ? FiliTheme.alpha(FiliTheme.surfaceHover, 0.5) : "transparent"

            Row {
                x: FiliTheme.margin
                height: parent.height
                Repeater {
                    model: table.cols
                    Text {
                        id: cell
                        required property var modelData
                        width: table.widthOf(modelData)
                        height: rowItem.height
                        rightPadding: FiliTheme.space2
                        leftPadding: table.spaced(modelData) ? FiliTheme.space3 : 0
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: modelData.right ? Text.AlignRight : Text.AlignLeft
                        elide: Text.ElideRight
                        text: modelData.key === "number" ? (rowItem.current ? (Store.playing ? "▶" : "▮▮") : String(table.trackNumbers ? (rowItem.trackNumber > 0 ? rowItem.trackNumber : "") : rowItem.index + 1)) : table.cellText(modelData, rowItem)
                        font.family: FiliTheme.font
                        font.pixelSize: FiliTheme.sizeList
                        font.weight: modelData.key === "title" && rowItem.current ? FiliTheme.weightAccent : Font.Normal
                        color: rowItem.current && (modelData.key === "title" || modelData.key === "number") ? FiliTheme.accentColor : modelData.key === "title" ? FiliTheme.text : (modelData.key === "number" || modelData.key === "duration") ? FiliTheme.muted : FiliTheme.textSecondary
                    }
                }
            }
            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onPressed: e => {
                    px = e.x;
                    py = e.y;
                    dragging = false;
                    list.forceActiveFocus();
                    if (e.button === Qt.RightButton) {
                        if (!rowItem.picked)
                            table.select(rowItem.index, false, false);
                    } else
                        table.select(rowItem.index, e.modifiers & Qt.ControlModifier, e.modifiers & Qt.ShiftModifier);
                }
                property real px: 0
                property real py: 0
                property bool dragging: false
                onPositionChanged: e => {
                    if (!pressed || !(pressedButtons & Qt.LeftButton))
                        return;
                    if (!dragging && Math.hypot(e.x - px, e.y - py) > 8)
                        dragging = true;
                    if (dragging) {
                        const ids = rowItem.picked ? table.selectedIds() : [id];
                        const p = mouse.mapToItem(null, e.x, e.y);
                        Store.dragMove(ids.length > 1 ? ids.length + " " + Fili.tr("tracks") : rowItem.title, { ids: ids }, p.x, p.y);
                    }
                }
                onReleased: e => {
                    if (dragging) {
                        const p = mouse.mapToItem(null, e.x, e.y);
                        Store.dragDrop(p.x, p.y);
                    }
                    dragging = false;
                }
                onCanceled: {
                    dragging = false;
                    Store.drag = null;
                }
                onClicked: e => {
                    if (e.button === Qt.RightButton) {
                        const p = mouse.mapToItem(null, e.x, e.y);
                        table.menuRequested(rowItem.index, p.x, p.y);
                    }
                }
                onDoubleClicked: e => {
                    if (e.button === Qt.LeftButton)
                        table.activated(rowItem.index, e.modifiers & Qt.AltModifier);
                }
            }
        }
    }
    FiliScrollBar {
        flick: list
        anchors { top: list.top; bottom: list.bottom; right: list.right }
    }
}
