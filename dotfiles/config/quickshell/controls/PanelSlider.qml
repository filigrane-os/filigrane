// 0..1 slider of the fili-panel (volume, brightness): click or drag; value then icon (mute) on the right; label = short
// name on the left (an application of the mixer), empty for a lone slider
import QtQuick
import QtQuick.Layouts
import qs

RowLayout {
    id: s
    property real value: 0
    // Real range shown in the percentage on the right (0..1 by default: volume); `value` stays 0..1 along the track
    property real from: 0
    property real to: 1
    property string glyph
    property bool muted: false
    property string label
    // steps > 0: the value snaps to steps + 1 positions (0, 1/steps ... 1); `dragging` while the mouse button is down;
    // `released` when the drag ends (apply a heavy change there, not at each `moved`)
    property int steps: 0
    readonly property bool dragging: area.pressed
    signal released
    signal moved(real v)
    signal glyphClicked

    Layout.fillWidth: true
    spacing: FiliTheme.space2
    // Keyboard: ←/→ = ±5 % (Shift+←/→ stays with the fili-panel: neighbouring panel), Enter or Space = click on the icon (mute)
    activeFocusOnTab: true
    Keys.onLeftPressed: e => s.nudge(e, -0.05)
    Keys.onRightPressed: e => s.nudge(e, 0.05)
    Keys.onReturnPressed: s.activate()
    Keys.onEnterPressed: s.activate()
    Keys.onSpacePressed: s.activate()
    function snap(v) {
        v = Math.max(0, Math.min(1, v));
        return s.steps > 0 ? Math.round(v * s.steps) / s.steps : v;
    }
    function nudge(e, d) {
        if (e && e.modifiers & Qt.ShiftModifier) {
            e.accepted = false;
            return;
        }
        FiliShell.keyNav = true;
        s.moved(s.snap(s.value + (s.steps > 0 ? Math.sign(d) / s.steps : d)));
    }
    function activate() {
        FiliShell.keyNav = true;
        s.glyphClicked();
    }
    Text {
        visible: s.label !== ""
        text: s.label
        color: s.muted ? FiliTheme.ardoise : FiliTheme.brume2
        Layout.preferredWidth: 88
        elide: Text.ElideRight
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList }
    }
    Item {
        Layout.fillWidth: true
        implicitHeight: 22
        FocusRing { shown: s.activeFocus; gap: 4 }
        Rectangle {
            id: track
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            height: 4
            radius: FiliTheme.radiusMark
            color: FiliTheme.nuit3
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, s.value))
                height: parent.height
                radius: FiliTheme.radiusMark
                color: s.muted ? FiliTheme.ardoise : FiliTheme.voile
            }
        }
        Rectangle {
            x: track.width * Math.max(0, Math.min(1, s.value)) - 6
            anchors.verticalCenter: parent.verticalCenter
            width: 12; height: 12; radius: FiliTheme.radiusControl
            color: s.muted ? FiliTheme.ardoise : FiliTheme.brume
        }
        MouseArea {
            id: area
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            function at(x) { s.moved(s.snap(x / width)); }
            onPressed: m => at(m.x)
            onPositionChanged: m => { if (pressed) at(m.x); }
            onReleased: s.released()
            onWheel: w => s.moved(s.snap(s.value + (s.steps > 0 ? (w.angleDelta.y > 0 ? 1 : -1) / s.steps : (w.angleDelta.y > 0 ? 0.05 : -0.05))))
        }
    }
    Text {
        text: Math.round((s.from + s.value * (s.to - s.from)) * 100) + "%"
        color: FiliTheme.ardoise
        Layout.preferredWidth: 36
        horizontalAlignment: Text.AlignRight
        font { family: FiliTheme.mono; pixelSize: FiliTheme.sizeList }
    }
    Text {
        text: s.glyph
        color: s.muted ? FiliTheme.ardoise : FiliTheme.brume
        Layout.preferredWidth: 22
        horizontalAlignment: Text.AlignHCenter
        font { family: FiliTheme.font; pixelSize: FiliTheme.size }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: s.glyphClicked() }
    }
}
