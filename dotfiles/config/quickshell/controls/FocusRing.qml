// Outline of the item chosen with the keyboard in the fili-panel and the fili-notification-center, visible only once the
// keyboard has been used (FiliShell.keyNav): nothing changes for the mouse. Child of the item (not in a Layout).
import QtQuick
import qs

Rectangle {
    property Item target: parent
    property bool shown: target.activeFocus
    property real gap: 2
    anchors { fill: target; margins: -gap }
    radius: (target.radius ?? FiliTheme.radiusControl) + gap
    color: "transparent"
    border.width: FiliTheme.borderWidth
    border.color: FiliTheme.voile
    visible: shown && FiliShell.keyNav
}
