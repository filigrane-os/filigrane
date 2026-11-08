// fili-bar: top bar, one per screen: the layout only. Every element is a module (bar/modules/<name>/<Name>Module.qml,
// see BarModule) with its panel next to it. Click: main action; right/middle click and wheel: see each module. TUIs open
// through bar-tui. Hover: fili-tooltip (detailed state + reminder of the clicks); network, power and display are read
// on hover only (FiliInfo).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs

PanelWindow {
    id: barWin
    required property var modelData
    screen: modelData
    anchors { top: true; left: true; right: true }
    implicitHeight: FiliTheme.barHeight
    color: FiliTheme.nuit
    visible: !FiliTheme.testing
    WlrLayershell.namespace: "fili-bar"

    // Click on the bar background (outside the modules): closes fili-panel, the pinned calendar and the notification center
    MouseArea {
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.AllButtons
        onPressed: FiliShell.popupOpened("")
    }

    // Thin line under the bar
    Rectangle {
        z: -1
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1
        color: FiliTheme.nuit3
    }

    // ───────── Left: modules of BarLayout.left (logo, workspaces, application menu...) ─────────
    RowLayout {
        id: leftRow
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        spacing: 0
        Repeater {
            model: BarLayout.ready ? BarLayout.left : []
            BarSlot { bar: barWin; free: rightRow.x - leftRow.x }
        }
    }

    // ───────── Right: modules of BarLayout.right ─────────
    RowLayout {
        id: rightRow
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom; rightMargin: 6 }
        spacing: 0
        Repeater {
            model: BarLayout.ready ? BarLayout.right : []
            BarSlot { bar: barWin }
        }
    }
}
