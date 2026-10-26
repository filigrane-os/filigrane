// Interrupteur des fili-panel (à droite du titre): checked = allumé, switchable = false le grise (rien à activer)
import QtQuick

Rectangle {
    id: sw
    property bool checked: false
    property bool switchable: true
    signal toggled

    implicitWidth: 34
    implicitHeight: 18
    radius: 9
    opacity: switchable ? 1 : 0.4
    color: checked ? FiliTheme.voile : FiliTheme.nuit4
    Rectangle {
        x: sw.checked ? parent.width - width - 2 : 2
        anchors.verticalCenter: parent.verticalCenter
        width: 14; height: 14; radius: 7
        color: sw.checked ? FiliTheme.nuit : FiliTheme.brume2
    }
    MouseArea {
        anchors.fill: parent
        enabled: sw.switchable
        cursorShape: Qt.PointingHandCursor
        onClicked: sw.press()
    }
    // Clic (appelé aussi par les tests)
    function press() {
        if (switchable)
            toggled();
    }
}
