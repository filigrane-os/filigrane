// Thin scroll bar of a list (ListView, Flickable), placed next to it (not inside), on the right:
// `FiliScrollBar { view: list; anchors { right: list.right; top: list.top; bottom: list.bottom } }`.
// Discreet like on macOS: the handle only appears while scrolling (wheel, touchpad with its momentum, keyboard),
// on hover and while dragging, then disappears after 0.8 s. No animation (shell rule: only the niri blur).
// Drag it with the mouse; a click in the gutter jumps to that place. `released` fires on release (the list recomputes
// if it follows its end).
import QtQuick

Item {
    id: bar
    required property Flickable view
    signal released

    readonly property real total: view.contentHeight + view.topMargin + view.bottomMargin
    readonly property real range: Math.max(1, total - view.height)
    readonly property real thumbH: Math.max(28, Math.min(height, height * view.height / Math.max(1, total)))
    readonly property real thumbY: (height - thumbH) * Math.max(0, Math.min(1, (view.contentY - view.originY) / range))
    property bool recent: false
    readonly property bool dragging: hit.pressed

    width: 12
    visible: total > view.height + 1
    Connections {
        target: bar.view
        function onContentYChanged() { bar.recent = true; hide.restart(); }
    }
    Timer { id: hide; interval: 800; onTriggered: bar.recent = false }

    Rectangle {
        visible: bar.recent || hit.containsMouse || hit.pressed
        x: parent.width - width - 2
        y: bar.thumbY
        width: hit.containsMouse || hit.pressed ? 7 : 4
        height: bar.thumbH
        radius: width / 2
        color: FiliTheme.alpha(FiliTheme.brume, hit.pressed ? 0.55 : 0.35)
    }
    MouseArea {
        id: hit
        anchors.fill: parent
        hoverEnabled: true
        property real grab: 0   // gap between the click and the top of the handle
        function moveTo(y) {
            const top = Math.max(0, Math.min(bar.height - bar.thumbH, y - grab));
            const f = bar.height > bar.thumbH ? top / (bar.height - bar.thumbH) : 0;
            bar.view.cancelFlick();
            bar.view.contentY = bar.view.originY + f * bar.range;
        }
        onPressed: e => {
            const onThumb = e.y >= bar.thumbY && e.y <= bar.thumbY + bar.thumbH;
            grab = onThumb ? e.y - bar.thumbY : bar.thumbH / 2;
            moveTo(e.y);
        }
        onPositionChanged: e => { if (pressed) moveTo(e.y); }
        onReleased: bar.released()
    }
}
