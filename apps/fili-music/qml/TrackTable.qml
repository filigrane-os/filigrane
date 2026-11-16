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

    // Column widths: number and time are fixed, the rest shares what is left
    readonly property int numberWidth: 48
    readonly property int timeWidth: 64
    readonly property int textWidth: width - numberWidth - timeWidth - 2 * FiliTheme.margin
    readonly property real titleShare: showArtist && showAlbum ? 0.4 : (showArtist || showAlbum ? 0.5 : 1)
    readonly property int titleWidth: Math.floor(textWidth * titleShare)
    readonly property int artistWidth: showArtist ? (showAlbum ? Math.floor(textWidth * 0.3) : textWidth - titleWidth) : 0
    readonly property int albumWidth: showAlbum ? textWidth - titleWidth - artistWidth : 0

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
                model: [
                    { key: "track_number", label: "#", w: table.numberWidth, right: false },
                    { key: "title", label: Fili.tr("Title"), w: table.titleWidth, right: false },
                    { key: "artist", label: Fili.tr("Artist"), w: table.artistWidth, right: false },
                    { key: "album", label: Fili.tr("Album"), w: table.albumWidth, right: false },
                    { key: "duration", label: Fili.tr("Time"), w: table.timeWidth, right: true }
                ]
                Item {
                    id: col
                    required property var modelData
                    width: modelData.w
                    height: head.height
                    visible: width > 0
                    Text {
                        anchors { fill: parent; rightMargin: FiliTheme.space2 }
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: col.modelData.right ? Text.AlignRight : Text.AlignLeft
                        elide: Text.ElideRight
                        text: col.modelData.label + (table.sortBy === col.modelData.key ? (table.sortDir === "asc" ? "  ▴" : "  ▾") : "")
                        font.family: FiliTheme.font
                        font.pixelSize: FiliTheme.sizeSmall
                        font.weight: FiliTheme.weightAccent
                        color: table.sortBy === col.modelData.key ? FiliTheme.text : FiliTheme.muted
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: table.sortable
                        onClicked: table.sortRequested(col.modelData.key, table.sortBy === col.modelData.key && table.sortDir === "asc" ? "desc" : "asc")
                    }
                }
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
            readonly property bool current: id === Store.currentTrackId
            readonly property bool picked: table.selected[id] === true
            width: list.width
            height: FiliTheme.rowHeight + 4
            color: picked ? FiliTheme.surfaceHover : mouse.containsMouse ? FiliTheme.alpha(FiliTheme.surfaceHover, 0.5) : "transparent"

            Row {
                x: FiliTheme.margin
                height: parent.height
                Text {
                    width: table.numberWidth
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: rowItem.current ? (Store.playing ? "▶" : "▮▮") : String(table.trackNumbers ? (rowItem.trackNumber > 0 ? rowItem.trackNumber : "") : rowItem.index + 1)
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeList
                    color: rowItem.current ? FiliTheme.accentColor : FiliTheme.muted
                }
                Text {
                    width: table.titleWidth
                    height: parent.height
                    rightPadding: FiliTheme.space2
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    text: rowItem.title
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeList
                    font.weight: rowItem.current ? FiliTheme.weightAccent : Font.Normal
                    color: rowItem.current ? FiliTheme.accentColor : FiliTheme.text
                }
                Text {
                    width: table.artistWidth
                    height: parent.height
                    visible: width > 0
                    rightPadding: FiliTheme.space2
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    text: rowItem.artists !== "" ? rowItem.artists : Store.artistName(rowItem.artistId)
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeList
                    color: FiliTheme.textSecondary
                }
                Text {
                    width: table.albumWidth
                    height: parent.height
                    visible: width > 0
                    rightPadding: FiliTheme.space2
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    text: Store.albumTitle(rowItem.albumId >= 0 ? rowItem.albumId : null)
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeList
                    color: FiliTheme.textSecondary
                }
                Text {
                    width: table.timeWidth
                    height: parent.height
                    rightPadding: FiliTheme.space2
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignRight
                    text: Store.clock(rowItem.duration)
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeList
                    color: FiliTheme.muted
                }
            }
            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onPressed: e => {
                    list.forceActiveFocus();
                    if (e.button === Qt.RightButton) {
                        if (!rowItem.picked)
                            table.select(rowItem.index, false, false);
                    } else
                        table.select(rowItem.index, e.modifiers & Qt.ControlModifier, e.modifiers & Qt.ShiftModifier);
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
