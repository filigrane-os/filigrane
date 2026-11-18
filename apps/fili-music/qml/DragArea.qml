// A mouse area that can be dragged to the queue: `activated` on a plain click, a ghost carrying `label` while it is dragged
// (Store.dragMove / dragDrop; the drop is read by Main). `payload` says what is dragged: { ids }, { albumId }, { artistId } or { genreId }.
import QtQuick
import Fili.Baladeur

MouseArea {
    id: area
    property string label: ""
    property var payload: ({})
    signal activated()
    signal pressedAt(real x, real y, int button)
    property real px: 0
    property real py: 0
    property bool dragging: false
    hoverEnabled: true
    // The list this sits in must not take the gesture over (a vertical move would scroll it and cancel the drag: no drop)
    preventStealing: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onPressed: e => {
        px = e.x;
        py = e.y;
        dragging = false;
        pressedAt(e.x, e.y, e.button);
    }
    onPositionChanged: e => {
        if (!pressed || !(pressedButtons & Qt.LeftButton))
            return;
        if (!dragging && Math.hypot(e.x - px, e.y - py) > 8)
            dragging = true;
        if (dragging) {
            const p = area.mapToItem(null, e.x, e.y);
            Store.dragMove(area.label, area.payload, p.x, p.y);
        }
    }
    onReleased: e => {
        if (dragging) {
            const p = area.mapToItem(null, e.x, e.y);
            Store.dragDrop(p.x, p.y);
        } else if (e.button === Qt.LeftButton && containsMouse)
            activated();
        dragging = false;
    }
    onCanceled: {
        dragging = false;
        Store.drag = null;
    }
}
