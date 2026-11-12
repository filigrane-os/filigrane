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
    color: Qt.alpha(FiliTheme.nuit, BarLayout.alpha)
    visible: !FiliTheme.testing
    WlrLayershell.namespace: "fili-bar"

    // Squeeze level (BarLayout.nextLevel): raised one step at a time while the right row does not fit next to the left
    // row, lowered when it fits again. seen[l] = width of the right row measured at level l. A column never squeezes.
    property int level: 0
    property var seen: []
    // Tests drive the level by hand unless they ask for the measure
    property bool measure: !FiliTheme.testing
    // Width the left row keeps: its modules, the application menu at its minimum, the gaps
    function leftNeed() {
        let w = 0;
        for (let i = 0; i < leftRep.count; i++) {
            const slot = leftRep.itemAt(i);
            if (!slot || !slot.item)
                continue;
            w += slot.modelData === "appmenu" ? (slot.item.shown ? BarLayout.menuMin : 0) : slot.implicitWidth;
        }
        return w;
    }
    function fit() {
        if (!measure || vertical || width <= 0) {
            if (level !== 0)
                level = 0;
            return;
        }
        const right = rightRow.implicitWidth;
        const s = seen.slice();
        s[level] = right;
        seen = s;
        const avail = width - leftNeed() - rightRow.anchors.rightMargin - FiliTheme.space3;
        const next = BarLayout.nextLevel(level, avail, right, s);
        if (next !== level) {
            level = next;
            settle.restart();
        }
    }
    // Measured after the layout settled (a level change moves the widths), not on every width signal
    Timer {
        id: settle
        interval: 150
        onTriggered: barWin.fit()
    }
    onWidthChanged: settle.restart()
    onVerticalChanged: settle.restart()
    Connections {
        target: rightRow
        function onImplicitWidthChanged() { settle.restart(); }
    }
    Connections {
        target: leftRow
        function onImplicitWidthChanged() { settle.restart(); }
    }

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
            id: leftRep
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
