// The tracks of an album in one column, or two when there is room (the first half on the left, the rest on the right): number,
// title, time. Selection with click, Ctrl and Shift; a double click plays (Alt adds to the queue); a right click asks for a menu;
// a row can be dragged to the queue. Rows come from a ListModel filled by Store.fill().
import QtQuick
import Fili.Baladeur

Item {
    id: cols
    required property ListModel model
    property int threshold: 480
    property var selected: ({})
    property int anchorRow: -1
    readonly property int selectedCount: Object.keys(selected).length
    readonly property bool twoColumns: width >= threshold && model.count > 1
    readonly property int split: twoColumns ? Math.ceil(model.count / 2) : model.count
    readonly property int rowHeight: 32
    readonly property int gutter: FiliTheme.space6

    signal activated(int row, bool altHeld)
    signal menuRequested(int row, real x, real y)

    implicitHeight: split * rowHeight
    height: implicitHeight

    function selectedIds() {
        return Store.ids(model).filter(id => selected[id] === true);
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

    Repeater {
        model: cols.model
        delegate: Rectangle {
            id: line
            required property int index
            required property int id
            required property string title
            required property int duration
            required property int trackNumber
            readonly property bool second: cols.twoColumns && index >= cols.split
            readonly property bool current: id === Store.currentTrackId
            readonly property bool picked: cols.selected[id] === true
            width: cols.twoColumns ? (cols.width - cols.gutter) / 2 : cols.width
            height: cols.rowHeight - 2
            x: second ? width + cols.gutter : 0
            y: (second ? index - cols.split : index) * cols.rowHeight
            radius: FiliTheme.radiusControl
            color: picked ? FiliTheme.alpha(FiliTheme.accentColor, 0.18) : mouse.containsMouse ? FiliTheme.alpha(FiliTheme.surfaceHover, 0.6) : "transparent"

            Text {
                id: num
                x: FiliTheme.space2
                width: 28
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: line.current ? (Store.playing ? "▶" : "▮▮") : String(line.trackNumber > 0 ? line.trackNumber : line.index + 1)
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeList
                color: line.current ? FiliTheme.accentColor : FiliTheme.muted
            }
            Text {
                anchors { left: num.right; leftMargin: FiliTheme.space2; right: time.left; rightMargin: FiliTheme.space2 }
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                text: line.title
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeList
                font.weight: line.current ? FiliTheme.weightAccent : Font.Normal
                color: line.current ? FiliTheme.accentColor : FiliTheme.text
            }
            Text {
                id: time
                anchors { right: parent.right; rightMargin: FiliTheme.space2 }
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: Store.clock(line.duration)
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeSmall
                color: FiliTheme.muted
            }
            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                property real px: 0
                property real py: 0
                property bool dragging: false
                onPressed: e => {
                    px = e.x;
                    py = e.y;
                    dragging = false;
                    if (e.button === Qt.RightButton) {
                        if (!line.picked)
                            cols.select(line.index, false, false);
                    } else
                        cols.select(line.index, e.modifiers & Qt.ControlModifier, e.modifiers & Qt.ShiftModifier);
                }
                onPositionChanged: e => {
                    if (!pressed || !(pressedButtons & Qt.LeftButton))
                        return;
                    if (!dragging && Math.hypot(e.x - px, e.y - py) > 8)
                        dragging = true;
                    if (dragging) {
                        const ids = line.picked ? cols.selectedIds() : [line.id];
                        const p = mouse.mapToItem(null, e.x, e.y);
                        Store.dragMove(ids.length > 1 ? ids.length + " " + Fili.tr("tracks") : line.title, { ids: ids }, p.x, p.y);
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
                        cols.menuRequested(line.index, p.x, p.y);
                    }
                }
                onDoubleClicked: e => {
                    if (e.button === Qt.LeftButton)
                        cols.activated(line.index, e.modifiers & Qt.AltModifier);
                }
            }
        }
    }
}
