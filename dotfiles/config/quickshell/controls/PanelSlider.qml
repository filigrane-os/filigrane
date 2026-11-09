// 0..1 slider of the fili-panel (volume, brightness): click or drag; value then icon (mute) on the right; label = short
// name on the left (an application of the mixer), empty for a lone slider
import QtQuick
import QtQuick.Layouts
import qs

RowLayout {
    id: s
    property real value: 0
    property string glyph
    property bool muted: false
    property string label
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
    function nudge(e, d) {
        if (e && e.modifiers & Qt.ShiftModifier) {
            e.accepted = false;
            return;
        }
        FiliShell.keyNav = true;
        s.moved(Math.max(0, Math.min(1, s.value + d)));
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
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            function at(x) { s.moved(Math.max(0, Math.min(1, x / width))); }
            onPressed: m => at(m.x)
            onPositionChanged: m => { if (pressed) at(m.x); }
            onWheel: w => s.moved(Math.max(0, Math.min(1, s.value + (w.angleDelta.y > 0 ? 0.05 : -0.05))))
        }
    }
    Text {
        text: Math.round(s.value * 100) + "%"
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
