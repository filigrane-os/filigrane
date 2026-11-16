// Filter field at the top of a list: lens, placeholder, a × that clears it (Esc too).
import QtQuick
import Fili.Baladeur

Rectangle {
    id: bar
    property string placeholder
    property alias text: input.text
    property alias input: input
    height: 36
    color: FiliTheme.background
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: FiliTheme.borderWidth
        color: FiliTheme.border
    }
    Text {
        id: lens
        x: FiliTheme.margin
        anchors.verticalCenter: parent.verticalCenter
        text: ""
        font.family: FiliTheme.icons
        font.pixelSize: 13
        color: FiliTheme.muted
    }
    Text {
        anchors { left: lens.right; leftMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
        visible: input.text === ""
        text: bar.placeholder
        font.family: FiliTheme.font
        font.pixelSize: FiliTheme.size
        color: FiliTheme.muted
    }
    TextInput {
        id: input
        anchors { left: lens.right; leftMargin: FiliTheme.space2; right: clear.left; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
        clip: true
        font.family: FiliTheme.font
        font.pixelSize: FiliTheme.size
        color: FiliTheme.text
        selectionColor: FiliTheme.surfaceActive
        selectedTextColor: FiliTheme.text
        Keys.onEscapePressed: text = ""
        Accessible.name: bar.placeholder
    }
    Text {
        id: clear
        anchors { right: parent.right; rightMargin: FiliTheme.margin; verticalCenter: parent.verticalCenter }
        visible: input.text !== ""
        text: "×"
        font.family: FiliTheme.font
        font.pixelSize: 16
        color: FiliTheme.muted
        MouseArea { anchors { fill: parent; margins: -6 } onClicked: input.text = "" }
        Accessible.role: Accessible.Button
        Accessible.name: Fili.tr("Clear")
    }
}
