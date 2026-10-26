// Ligne cliquable des fili-panel: glyphe, libellé, détail à droite; survol = fond nuit3, sel = voile
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: btn
    property string glyph
    property string label
    property string detail
    property bool sel: false
    property bool dim: false
    // Interrupteur à droite (activer / désactiver): switchable = false le grise (rien à activer)
    property bool toggle: false
    property bool switchable: true
    property color tint: sel ? FiliTheme.voile : dim ? FiliTheme.ardoise : FiliTheme.brume
    signal clicked(int button)

    Layout.fillWidth: true
    implicitHeight: 30
    radius: 6
    enabled: !toggle || switchable
    color: area.containsMouse ? FiliTheme.nuit3 : "transparent"

    RowLayout {
        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
        spacing: 8
        Text {
            visible: btn.glyph !== ""
            text: btn.glyph
            color: btn.tint
            Layout.preferredWidth: 18
            horizontalAlignment: Text.AlignHCenter
            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
        }
        Text {
            text: btn.label
            color: btn.tint
            Layout.fillWidth: true
            elide: Text.ElideRight
            font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: btn.sel ? Font.Medium : Font.Normal }
        }
        Rectangle {
            visible: btn.toggle
            implicitWidth: 34
            implicitHeight: 18
            radius: 9
            opacity: btn.switchable ? 1 : 0.4
            color: btn.sel ? FiliTheme.voile : FiliTheme.nuit4
            Rectangle {
                x: btn.sel ? parent.width - width - 2 : 2
                anchors.verticalCenter: parent.verticalCenter
                width: 14; height: 14; radius: 7
                color: btn.sel ? FiliTheme.nuit : FiliTheme.brume2
            }
        }
        Text {
            visible: btn.detail !== "" && !btn.toggle
            text: btn.detail
            color: FiliTheme.ardoise
            font { family: FiliTheme.font; pixelSize: 12 }
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: m => btn.press(m.button)
    }
    // Clic (appelé aussi par les tests)
    function press(button) {
        btn.clicked(button);
    }
}
