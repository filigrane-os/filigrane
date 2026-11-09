// Switch of the fili-panel (right of the title): checked = on, switchable = false greys it out (nothing to turn on)
import QtQuick
import qs

Rectangle {
    id: sw
    property bool checked: false
    property bool switchable: true
    signal toggled

    implicitWidth: 34
    implicitHeight: 18
    radius: height / 2
    opacity: switchable ? 1 : 0.4
    // Keyboard: Enter or Space = toggle
    activeFocusOnTab: switchable
    Keys.onReturnPressed: key()
    Keys.onEnterPressed: key()
    Keys.onSpacePressed: key()
    function key() {
        FiliShell.keyNav = true;
        press();
    }
    FocusRing { gap: 3 }
    color: checked ? FiliTheme.voile : FiliTheme.nuit4
    Rectangle {
        x: sw.checked ? parent.width - width - 2 : 2
        anchors.verticalCenter: parent.verticalCenter
        width: 14; height: 14; radius: width / 2
        color: sw.checked ? FiliTheme.nuit : FiliTheme.brume2
    }
    MouseArea {
        anchors.fill: parent
        enabled: sw.switchable
        cursorShape: Qt.PointingHandCursor
        onClicked: sw.press()
    }
    // Click (also called by the tests)
    function press() {
        if (switchable)
            toggled();
    }
}
