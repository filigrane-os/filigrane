// The queue: a filter field, the tracks (the current one highlighted, double click plays it, the bin removes it) and the bar of
// queue actions (random tracks, repeat, shuffle, save as playlist, clear).
import QtQuick
import Fili.Baladeur

Item {
    id: panel
    signal saveRequested()
    signal menuRequested(int index, real x, real y)

    ListModel { id: tracks }
    property string filter: ""
    readonly property bool empty: Store.queueIds.length === 0

    function reload() {
        const ids = Store.queueIds;
        if (ids.length === 0) {
            tracks.clear();
            return;
        }
        Store.callAsync("tracks_by_ids", [JSON.stringify(ids)], list => {
            tracks.clear();
            if (!list)
                return;
            // A track the library lost keeps its place with the number it had
            const byId = {};
            for (const t of list)
                byId[t.id] = t;
            let i = 0;
            for (const id of ids) {
                const t = byId[id];
                if (t) {
                    const r = Store.row(t);
                    r.position = i;
                    tracks.append(r);
                }
                i++;
            }
        });
    }
    Connections {
        target: Store
        function onQueueRevChanged() {
            panel.reload();
        }
    }
    Component.onCompleted: Store.refreshQueue()

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
        model: tracks
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        KineticScroll {}
        // The current track is brought into view when it changes
        Connections {
            target: Store
            function onQueueIndexChanged() {
                if (Store.queueIndex >= 0 && panel.filter === "")
                    list.positionViewAtIndex(Math.max(0, Store.queueIndex - 2), ListView.Beginning);
            }
        }
        delegate: Rectangle {
            id: row
            required property int index
            required property int id
            required property string title
            required property int artistId
            required property string artists
            required property int position
            readonly property bool current: position === Store.queueIndex
            readonly property bool unavailable: (Store.player.skipped_track_ids || []).indexOf(id) >= 0
            readonly property string artist: artists !== "" ? artists : Store.artistName(artistId)
            readonly property bool shown: panel.filter === "" || title.toLowerCase().includes(panel.filter) || artist.toLowerCase().includes(panel.filter)
            width: list.width
            height: shown ? 44 : 0
            visible: shown
            color: current ? FiliTheme.alpha(FiliTheme.accentColor, 0.12) : area.containsMouse ? FiliTheme.alpha(FiliTheme.surfaceHover, 0.5) : "transparent"

            Text {
                id: number
                x: FiliTheme.space3
                width: 34
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
                    { key: "random", glyph: "⚄", tip: Fili.tr("Add 30 random tracks") },
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
                            case "random":
                                Store.callAsync("get_random_tracks", [30], ids => Store.addToQueue(ids || []));
                                break;
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
