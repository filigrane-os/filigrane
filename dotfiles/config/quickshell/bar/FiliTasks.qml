// fili-tasks: the tasks bar, one per screen (bottom edge by default, TasksLayout): every window of the screen, grouped by
// workspace in the order niri lays them out (columns left to right), so that one glance tells what runs where and one click
// goes there, whatever the workspace. Click: focus the window; middle click: close it. A merged icon (several windows of one
// application) and a folded workspace open the list of their windows. Hover: fili-tooltip.
// Like the fili-bar it squeezes itself, per screen, one level at a time while its row does not fit (TasksLayout.groups for
// the levels), and goes back as soon as there is room again.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import qs

PanelWindow {
    id: win
    required property var modelData
    screen: modelData
    readonly property string edge: TasksLayout.edge
    anchors {
        top: edge === "top"
        bottom: edge === "bottom"
        left: true
        right: true
    }
    implicitHeight: FiliTheme.tasksHeight
    color: FiliTheme.nuit
    visible: !FiliTheme.testing
    WlrLayershell.namespace: "fili-tasks"
    // Hint mode: the bar of the display that has the focus takes the keyboard until the digits are given
    readonly property bool hinting: TasksHint.active && TasksHint.output === modelData.name
    WlrLayershell.keyboardFocus: hinting ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    onHintingChanged: if (hinting) keys.forceActiveFocus()
    Item {
        id: keys
        objectName: "tasks-keys"
        focus: true
        Keys.onPressed: e => {
            if (!TasksHint.active)
                return;
            if (e.key === Qt.Key_Escape)
                TasksHint.cancel();
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter)
                TasksHint.commit();
            else if (e.key === Qt.Key_Backspace)
                TasksHint.erase();
            else
                TasksHint.type(e.text);
            e.accepted = true;
        }
        // Releasing Mod or Alt (the keys held to start the mode) goes to the window
        Keys.onReleased: e => {
            if (TasksHint.active && [Qt.Key_Alt, Qt.Key_AltGr, Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R].indexOf(e.key) >= 0) {
                if (TasksHint.typed === "")
                    TasksHint.cancel();
                else
                    TasksHint.commit();
            }
            e.accepted = true;
        }
    }

    // Squeeze level and the width of the row measured at each level (tests drive the level by hand unless they ask for the measure)
    property int level: 0
    property var seen: []
    property bool measure: !FiliTheme.testing
    // Hint mode: one icon per window, no title, nothing merged or folded (the numbers name the windows)
    readonly property var groups: TasksLayout.groups(modelData.name, Niri.workspaces, Niri.windows, Niri.focusedId, TasksHint.active ? 1 : level)
    function fit() {
        if (!measure || width <= 0) {
            if (level !== 0)
                level = 0;
            return;
        }
        const row = rowItem.implicitWidth;
        const s = seen.slice();
        s[level] = row;
        seen = s;
        const next = TasksLayout.nextLevel(level, width - 2 * FiliTheme.space1, row, s);
        if (next !== level) {
            level = next;
            settle.restart();
        }
    }
    // Measured after the layout settled, not on every change of the windows
    Timer {
        id: settle
        interval: 150
        onTriggered: win.fit()
    }
    onWidthChanged: settle.restart()
    onGroupsChanged: settle.restart()

    // List of the windows of a merged icon or a folded workspace: opens above the item, closes on a choice, on a click
    // elsewhere in the shell and as soon as the focus changes
    property var listWins: []
    property Item listAnchor: null
    function openList(item, wins) {
        FiliTooltip.hide();
        FiliShell.popupOpened("tasks");
        listAnchor = item;
        listWins = wins;
    }
    function closeList() {
        listWins = [];
    }
    Connections {
        target: FiliShell
        function onPopupOpened(who) {
            if (who !== "tasks")
                win.closeList();
        }
    }
    Connections {
        target: Niri
        function onFocusedIdChanged() { win.closeList(); }
    }

    // Click on the background of the bar: closes the list and the panels
    MouseArea {
        anchors.fill: parent
        z: -1
        onPressed: {
            win.closeList();
            FiliShell.popupOpened("");
        }
    }
    // Thin line on the inner edge of the bar
    Rectangle {
        z: -1
        y: win.edge === "bottom" ? 0 : parent.height - 1
        width: parent.width
        height: 1
        color: FiliTheme.nuit3
    }

    Row {
        id: rowItem
        objectName: "tasks-row"
        anchors { left: parent.left; leftMargin: FiliTheme.space1; top: parent.top; bottom: parent.bottom }
        spacing: 0
        Repeater {
            model: win.groups
            Row {
                id: grp
                required property var modelData
                required property int index
                objectName: "tasks-group-" + modelData.id
                height: rowItem.height
                spacing: 0
                // A thin separator between two workspaces
                Rectangle {
                    visible: grp.index > 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1
                    height: 16
                    color: FiliTheme.nuit3
                }
                // Label of the workspace; folded: label and count in one cell that opens the list
                Item {
                    id: chip
                    objectName: "tasks-label-" + grp.modelData.id
                    property alias hover: chipHover
                    height: grp.height
                    implicitWidth: chipText.implicitWidth + 2 * FiliTheme.pad
                    width: implicitWidth
                    Rectangle {
                        anchors.fill: parent
                        color: grp.modelData.folded && chipHover.containsMouse ? FiliTheme.nuit3 : "transparent"
                    }
                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        text: grp.modelData.folded ? grp.modelData.label + " · " + grp.modelData.count : grp.modelData.label
                        color: TasksHint.active ? FiliTheme.voile : grp.modelData.urgent ? FiliTheme.sable : grp.modelData.active ? FiliTheme.brume : FiliTheme.ardoise
                        opacity: grp.modelData.wins.some(w => TasksHint.matches(TasksNumbers.numberOf(w.id))) || TasksHint.typed === "" ? 1 : 0.35
                        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall; weight: grp.modelData.active || TasksHint.active ? FiliTheme.weightAccent : Font.Normal }
                    }
                    BarHover {
                        id: chipHover
                        anchors.fill: parent
                        tipEdge: win.edge
                        tip: {
                            const g = grp.modelData;
                            return {
                                title: g.label === "•" ? FiliI18n.tr("Unnumbered workspace") : FiliI18n.tr("Workspace %1", g.label),
                                rows: g.wins.length ? g.wins.map(w => ["#" + TasksNumbers.numberOf(w.id) + " " + TasksLayout.appName(w.app_id), w.title ?? ""]) : [["", FiliI18n.tr("no window")]],
                                hint: g.folded ? FiliI18n.tr("click: list of the windows · wheel: previous / next") : FiliI18n.tr("click: go there · wheel: previous / next")
                            };
                        }
                        onLeftClicked: {
                            if (grp.modelData.folded)
                                win.openList(chip, grp.modelData.wins);
                            else
                                Niri.onOutput(win.modelData.name, "focus-workspace " + win.workspaceIdx(grp.modelData.id));
                        }
                        onWheelUp: Niri.onOutput(win.modelData.name, "focus-workspace-up")
                        onWheelDown: Niri.onOutput(win.modelData.name, "focus-workspace-down")
                    }
                }
                Repeater {
                    model: grp.modelData.folded ? [] : grp.modelData.entries
                    Item {
                        id: cell
                        required property var modelData
                        required property int index
                        objectName: "task-" + modelData.key
                        property alias hover: cellHover
                        readonly property bool merged: modelData.wins.length > 1
                        height: grp.height
                        opacity: cell.modelData.nums.some(n => TasksHint.matches(n)) ? 1 : 0.35
                        implicitWidth: FiliTheme.pad + 16 + FiliTheme.space1 + numText.implicitWidth + (title.visible ? FiliTheme.space1 + title.width : 0) + FiliTheme.pad
                        width: implicitWidth
                        Rectangle {
                            anchors.fill: parent
                            color: cell.modelData.focused || cellHover.containsMouse ? FiliTheme.nuit3 : "transparent"
                        }
                        // Mark of the focused window, on the inner edge of the bar (like the active workspace of the fili-bar)
                        Rectangle {
                            visible: cell.modelData.focused
                            anchors { left: parent.left; right: parent.right }
                            y: win.edge === "bottom" ? 0 : parent.height - height
                            height: 2
                            color: FiliTheme.voile
                        }
                        // Application icon, or its first letter when the theme has none
                        Item {
                            id: glyph
                            x: FiliTheme.pad
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16
                            height: 16
                            readonly property string source: TasksLayout.appIcon(cell.modelData.app_id)
                            IconImage {
                                anchors.fill: parent
                                visible: glyph.source !== ""
                                source: glyph.source
                                implicitSize: 16
                            }
                            Rectangle {
                                anchors.fill: parent
                                visible: glyph.source === ""
                                radius: FiliTheme.radiusMark
                                color: "transparent"
                                border { width: FiliTheme.borderWidth; color: FiliTheme.ardoise }
                                Text {
                                    anchors.centerIn: parent
                                    text: (TasksLayout.appName(cell.modelData.app_id) || "?").charAt(0).toUpperCase()
                                    color: FiliTheme.brume2
                                    font { family: FiliTheme.font; pixelSize: FiliTheme.sizeLabel; weight: FiliTheme.weightAccent }
                                }
                            }
                            // Urgent window: a dot on the icon, and the word in the card (colour is never the only signal)
                            Rectangle {
                                visible: cell.modelData.urgent
                                x: parent.width - 5
                                y: -2
                                width: 7
                                height: 7
                                radius: 4
                                color: FiliTheme.sable
                                border { width: 1; color: FiliTheme.nuit }
                            }
                        }
                        Text {
                            id: title
                            visible: cell.modelData.title !== "" && !TasksHint.active
                            x: FiliTheme.pad + 16 + FiliTheme.space1 + numText.implicitWidth + FiliTheme.space1
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, 180)
                            elide: Text.ElideRight
                            text: cell.modelData.title
                            color: cell.modelData.focused ? FiliTheme.brume : FiliTheme.brume2
                            font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList }
                        }
                        // Number of the window (TasksNumbers), always shown: the one to type in the hint mode. A merged icon shows the
                        // first number and how many windows come with it ("3+2").
                        Text {
                            id: numText
                            objectName: "task-num-" + cell.modelData.key
                            x: FiliTheme.pad + 16 + FiliTheme.space1
                            anchors.verticalCenter: parent.verticalCenter
                            text: cell.modelData.nums[0] + (cell.merged ? "+" + (cell.modelData.nums.length - 1) : "")
                            color: TasksHint.active ? FiliTheme.voile : FiliTheme.ardoise
                            font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall; weight: FiliTheme.weightAccent }
                        }
                        BarHover {
                            id: cellHover
                            anchors.fill: parent
                            tipEdge: win.edge
                            tip: {
                                const e = cell.modelData;
                                return {
                                    title: TasksLayout.appName(e.app_id),
                                    rows: e.wins.map(w => [(w.is_urgent ? FiliI18n.tr("URGENT") + " · " : "") + "#" + TasksNumbers.numberOf(w.id), w.title ?? ""]),
                                    hint: cell.merged ? FiliI18n.tr("click: list of the windows") : FiliI18n.tr("click: go there · middle click: close")
                                };
                            }
                            onLeftClicked: {
                                if (cell.merged)
                                    win.openList(cell, cell.modelData.wins);
                                else
                                    win.focusWindow(cell.modelData.wins[0].id);
                            }
                            onMiddleClicked: {
                                if (!cell.merged)
                                    Niri.action("close-window", "--id", String(cell.modelData.wins[0].id));
                            }
                        }
                    }
                }
            }
        }
    }

    function focusWindow(id) {
        closeList();
        Niri.action("focus-window", "--id", String(id));
    }
    // Index of a workspace on its display (focus-workspace N)
    function workspaceIdx(id) {
        return (Niri.workspaces.find(w => w.id === id) ?? { idx: 1 }).idx;
    }

    PopupWindow {
        id: list
        objectName: "tasks-list"
        visible: win.listWins.length > 0 && win.listAnchor !== null
        anchor.item: win.listAnchor
        anchor.edges: FiliTheme.popupEdgesFor(win.edge)
        anchor.gravity: FiliTheme.popupEdgesFor(win.edge)
        anchor.margins.top: win.edge === "top" ? 6 : 0
        anchor.margins.bottom: win.edge === "bottom" ? 6 : 0
        implicitWidth: Math.min(380, Math.max(180, col.implicitWidth + 2 * FiliTheme.space2))
        implicitHeight: col.implicitHeight + 2 * FiliTheme.space1
        color: "transparent"
        Rectangle {
            anchors.fill: parent
            color: FiliTheme.nuit
            border { color: FiliTheme.border; width: FiliTheme.borderWidth }
            radius: FiliTheme.radiusWindow
            Column {
                id: col
                anchors { fill: parent; margins: FiliTheme.space1 }
                Repeater {
                    model: win.listWins
                    Rectangle {
                        id: row
                        required property var modelData
                        objectName: "tasks-list-" + modelData.id
                        property alias hover: rowHover
                        width: col.width
                        height: 28
                        radius: FiliTheme.radiusControl
                        color: rowHover.containsMouse ? FiliTheme.nuit3 : "transparent"
                        Item {
                            id: rowGlyph
                            x: FiliTheme.space2
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16
                            height: 16
                            readonly property string source: TasksLayout.appIcon(row.modelData.app_id)
                            IconImage {
                                anchors.fill: parent
                                visible: rowGlyph.source !== ""
                                source: rowGlyph.source
                                implicitSize: 16
                            }
                        }
                        Text {
                            anchors { left: parent.left; leftMargin: FiliTheme.space2 + 16 + FiliTheme.space2; right: parent.right; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                            elide: Text.ElideRight
                            text: "#" + TasksNumbers.numberOf(row.modelData.id) + "  " + (row.modelData.is_urgent ? FiliI18n.tr("URGENT") + " · " : "") + (row.modelData.title || TasksLayout.appName(row.modelData.app_id))
                            color: row.modelData.id === Niri.focusedId ? FiliTheme.voile : FiliTheme.brume
                            font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList }
                        }
                        MouseArea {
                            id: rowHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            onClicked: m => {
                                if (m.button === Qt.MiddleButton)
                                    Niri.action("close-window", "--id", String(row.modelData.id));
                                else
                                    win.focusWindow(row.modelData.id);
                            }
                        }
                    }
                }
            }
        }
    }
}
