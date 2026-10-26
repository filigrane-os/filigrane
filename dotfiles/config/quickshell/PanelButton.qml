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
    property color tint: sel ? FiliTheme.voile : dim ? FiliTheme.ardoise : FiliTheme.brume
    signal clicked(int button)

    Layout.fillWidth: true
    implicitHeight: 30
    radius: 6
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
        Text {
            visible: btn.detail !== ""
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
