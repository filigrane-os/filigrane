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
    // Edge of the screen (FiliTheme.barEdge): a row on the top or the bottom, a narrow column on the left or the right
    readonly property bool vertical: FiliTheme.barVertical
    anchors {
        top: FiliTheme.barEdge !== "bottom"
        bottom: FiliTheme.barEdge !== "top"
        left: FiliTheme.barEdge !== "right"
        right: FiliTheme.barEdge !== "left"
    }
    implicitHeight: vertical ? 0 : FiliTheme.barHeight
    implicitWidth: vertical ? FiliTheme.barWidth : 0
    color: FiliTheme.nuit
    visible: !FiliTheme.testing
    WlrLayershell.namespace: "fili-bar"

    // Click on the bar background (outside the modules): closes fili-panel, the pinned calendar and the notification center;
    // right click: the position of the bar and its settings
    MouseArea {
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.AllButtons
        onPressed: m => {
            if (m.button === Qt.RightButton)
                FiliPanel.openBarMenu(barWin, m.x, m.y);
            else
                FiliShell.popupOpened("");
        }
    }

    // Thin line on the inner edge of the bar
    Rectangle {
        z: -1
        x: FiliTheme.barEdge === "left" ? parent.width - 1 : 0
        y: FiliTheme.barEdge === "top" ? parent.height - 1 : 0
        width: barWin.vertical ? 1 : parent.width
        height: barWin.vertical ? parent.height : 1
        color: FiliTheme.nuit3
    }

    // Modules of BarLayout.left (logo, workspaces, application menu...) and BarLayout.right: a row, or a column on the
    // left and the right of the screen. Only the layout in use holds the modules (a module is created once).
    RowLayout {
        id: leftRow
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        spacing: 0
        Repeater {
            model: BarLayout.ready && !barWin.vertical ? BarLayout.left : []
            BarSlot { bar: barWin; free: rightRow.x - leftRow.x }
        }
    }
    RowLayout {
        id: rightRow
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom; rightMargin: 6 }
        spacing: 0
        Repeater {
            model: BarLayout.ready && !barWin.vertical ? BarLayout.right : []
            BarSlot { bar: barWin }
        }
    }
    // Column: the left modules on top, the right ones at the bottom
    ColumnLayout {
        id: topCol
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 0
        Repeater {
            model: BarLayout.ready && barWin.vertical ? BarLayout.left : []
            BarSlot { bar: barWin }
        }
    }
    ColumnLayout {
        id: bottomCol
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 6 }
        spacing: 0
        Repeater {
            model: BarLayout.ready && barWin.vertical ? BarLayout.right : []
            BarSlot { bar: barWin }
        }
    }
}
