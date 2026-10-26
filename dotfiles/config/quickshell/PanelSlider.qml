// Curseur 0..1 des fili-panel (volume, luminosité): clic ou glisser; valeur affichée à droite
import QtQuick
import QtQuick.Layouts

RowLayout {
    id: s
    property real value: 0
    property string glyph
    property bool muted: false
    signal moved(real v)
    signal glyphClicked

    Layout.fillWidth: true
    spacing: 8
    Text {
        text: s.glyph
        color: s.muted ? FiliTheme.ardoise : FiliTheme.brume
        Layout.preferredWidth: 22
        horizontalAlignment: Text.AlignHCenter
        font { family: FiliTheme.font; pixelSize: 15 }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: s.glyphClicked() }
    }
    Item {
        Layout.fillWidth: true
        implicitHeight: 22
        Rectangle {
            id: track
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            height: 4
            radius: 2
            color: FiliTheme.nuit3
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, s.value))
                height: parent.height
                radius: 2
                color: s.muted ? FiliTheme.ardoise : FiliTheme.voile
            }
        }
        Rectangle {
            x: track.width * Math.max(0, Math.min(1, s.value)) - 6
            anchors.verticalCenter: parent.verticalCenter
            width: 12; height: 12; radius: 6
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
        font { family: FiliTheme.mono; pixelSize: 12 }
    }
}
