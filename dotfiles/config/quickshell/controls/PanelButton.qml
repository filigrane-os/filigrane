// Clickable row of the fili-panel: glyph, label, detail on the right; hover = nuit3 background, sel = voile
import QtQuick
import QtQuick.Layouts
import qs

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
    radius: FiliTheme.radiusControl
    color: area.containsMouse ? FiliTheme.nuit3 : "transparent"
    // Keyboard: Enter or Space = click, Shift+Enter = right click
    activeFocusOnTab: true
    Keys.onReturnPressed: e => btn.key(e)
    Keys.onEnterPressed: e => btn.key(e)
    Keys.onSpacePressed: e => btn.key(e)
    function key(e) {
        FiliShell.keyNav = true;
        press(e.modifiers & Qt.ShiftModifier ? Qt.RightButton : Qt.LeftButton);
    }
    FocusRing {}

    RowLayout {
        anchors { fill: parent; leftMargin: FiliTheme.space2; rightMargin: FiliTheme.space2 }
        spacing: FiliTheme.space2
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
            font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: btn.sel ? FiliTheme.weightAccent : Font.Normal }
        }
        Text {
            visible: btn.detail !== ""
            text: btn.detail
            color: FiliTheme.ardoise
            font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList }
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
    // Click (also called by the tests)
    function press(button) {
        btn.clicked(button);
    }
}
