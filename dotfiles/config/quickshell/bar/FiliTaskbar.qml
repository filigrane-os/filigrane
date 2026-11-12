// fili-taskbar: the taskbar, one per screen (bottom edge by default, TaskbarLayout): every window of the screen, grouped by
// workspace in the order niri lays them out (columns left to right), so that one glance tells what runs where and one click
// goes there, whatever the workspace. Click: focus the window; middle click: close it. A merged icon (several windows of one
// application) and a folded workspace open the list of their windows. Hover: fili-tooltip.
// Like the fili-bar it squeezes itself, per screen, one level at a time while its row does not fit (TaskbarLayout.groups for
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
    readonly property string edge: TaskbarLayout.edge
    anchors {
        top: edge === "top"
        bottom: edge === "bottom"
        left: true
        right: true
    }
    // Automatic hiding ([taskbar] autohide): a thin strip on the edge that takes no room; the pointer on it, the hint mode, a
    // list or a menu open, or the moment after the pointer left (the timer) show the bar
    readonly property bool autohide: TaskbarLayout.autohide
    readonly property bool shown: !autohide || hinting || hov.hovered || leave.running || listWins.length > 0 || menuItems.length > 0
    HoverHandler {
        id: hov
        onHoveredChanged: if (!hovered) leave.restart()
    }
    Timer {
        id: leave
        interval: 600
    }
    implicitHeight: shown ? FiliTheme.taskbarHeight : 2
    exclusionMode: autohide ? ExclusionMode.Ignore : ExclusionMode.Auto
    color: shown ? Qt.alpha(FiliTheme.nuit, TaskbarLayout.alpha) : FiliTheme.nuit3
    visible: !FiliTheme.testing
    WlrLayershell.namespace: "fili-taskbar"
    // Hint mode: the bar of the display that has the focus takes the keyboard until the digits are given
    readonly property bool hinting: TaskbarHint.active && TaskbarHint.output === modelData.name
    WlrLayershell.keyboardFocus: hinting ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    onHintingChanged: if (hinting) keys.forceActiveFocus()
    Item {
        id: keys
        objectName: "taskbar-keys"
        focus: true
        Keys.onPressed: e => {
            if (!TaskbarHint.active)
                return;
            if (e.key === Qt.Key_Escape)
                TaskbarHint.cancel();
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter)
                TaskbarHint.commit();
            else if (e.key === Qt.Key_Backspace)
                TaskbarHint.erase();
            else
                TaskbarHint.type(e.text);
            e.accepted = true;
        }
        // Releasing Mod or Alt (the keys held to start the mode) goes to the window
        Keys.onReleased: e => {
            if (TaskbarHint.active && [Qt.Key_Alt, Qt.Key_AltGr, Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R].indexOf(e.key) >= 0) {
                if (TaskbarHint.typed === "")
                    TaskbarHint.cancel();
                else
                    TaskbarHint.commit();
            }
            e.accepted = true;
        }
    }

    // Squeeze level and the width of the row measured at each level (tests drive the level by hand unless they ask for the measure)
    property int level: 0
    property var seen: []
    property bool measure: !FiliTheme.testing
    // Hint mode: one icon per window, no title, nothing merged or folded (the numbers name the windows)
    readonly property var groups: TaskbarLayout.groups(modelData.name, Niri.workspaces, Niri.windows, Niri.focusedId, TaskbarHint.active ? 1 : level)
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
        const next = TaskbarLayout.nextLevel(level, width - 2 * FiliTheme.space1, row, s);
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
        FiliShell.popupOpened("taskbar");
        listAnchor = item;
        listWins = wins;
    }
    function closeList() {
        listWins = [];
        menuItems = [];
    }
    // Menu of a workspace (right click on its label or its button of the strip): [{ text, cmd }], cmd = niri action(s)
    // run on the display of the workspace once it has the focus (move-workspace-up/down act on the focused workspace)
    property var menuItems: []
    property Item menuAnchor: null
    function openMenu(item, ws) {
        FiliTooltip.hide();
        FiliShell.popupOpened("taskbar");
        const at = "focus-workspace " + ws.idx;
        const items = [{ text: FiliI18n.tr("Go to the workspace"), cmd: at }];
        if (Niri.focusedId !== null && Niri.focused?.workspace_id !== ws.id)
            items.push({ text: FiliI18n.tr("Move the focused window here"), cmd: "move-window-to-workspace --window-id " + Niri.focusedId + " " + ws.idx });
        items.push({ text: FiliI18n.tr("Move up"), cmd: at + " && niri msg action move-workspace-up" });
        items.push({ text: FiliI18n.tr("Move down"), cmd: at + " && niri msg action move-workspace-down" });
        for (const s of Quickshell.screens)
            if (s.name !== ws.output)
                items.push({ text: FiliI18n.tr("Send to %1").replace("%1", s.name), cmd: at + " && niri msg action move-workspace-to-monitor " + s.name });
        listWins = [];
        menuAnchor = item;
        menuItems = items.map(i => Object.assign(i, { output: ws.output }));
    }
    Connections {
        target: FiliShell
        function onPopupOpened(who) {
            if (who !== "taskbar")
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
        objectName: "taskbar-row"
        visible: win.shown
        anchors { left: parent.left; leftMargin: FiliTheme.space1; top: parent.top; bottom: parent.bottom }
        spacing: 0
        // Workspaces of the screen (all of them, empty ones too): click goes there, wheel goes to the previous / next,
        // right click opens the menu of the workspace
        Row {
            id: strip
            objectName: "taskbar-strip"
            height: rowItem.height
            spacing: 0
            Repeater {
                model: Niri.workspaces.filter(w => w.output === win.modelData.name).sort((a, b) => a.idx - b.idx)
                Item {
                    id: btn
                    required property var modelData
                    objectName: "taskbar-ws-" + modelData.id
                    property alias hover: btnHover
                    readonly property string label: TaskbarLayout.label(modelData, Niri.workspaces.some(w => /^[0-9]+$/.test(w.name ?? "")))
                    height: strip.height
                    width: btnText.implicitWidth + 2 * FiliTheme.pad
                    Rectangle {
                        anchors.fill: parent
                        color: btn.modelData.is_active || btnHover.containsMouse ? FiliTheme.nuit3 : "transparent"
                    }
                    Text {
                        id: btnText
                        anchors.centerIn: parent
                        text: btn.label
                        color: btn.modelData.is_active || btnHover.containsMouse ? FiliTheme.brume : FiliTheme.ardoise
                        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall; weight: btn.modelData.is_active ? FiliTheme.weightAccent : Font.Normal }
                    }
                    Rectangle {
                        visible: btn.modelData.is_active
                        anchors { left: parent.left; right: parent.right; top: win.edge === "bottom" ? parent.top : undefined; bottom: win.edge === "bottom" ? undefined : parent.bottom }
                        height: 2
                        color: FiliTheme.voile
                    }
                    BarHover {
                        id: btnHover
                        anchors.fill: parent
                        tipEdge: win.edge
                        tip: {
                            const id = btn.modelData.id;
                            const wins = Object.values(Niri.windows).filter(w => w.workspace_id === id);
                            return {
                                title: btn.label === "\u2022" ? FiliI18n.tr("Unnumbered workspace") : FiliI18n.tr("Workspace %1", btn.label),
                                rows: wins.length ? wins.map(w => ["#" + TaskbarNumbers.numberOf(w.id) + " " + TaskbarLayout.appName(w.app_id), w.title ?? ""]) : [["", FiliI18n.tr("no window")]],
                                hint: FiliI18n.tr("click: go there · wheel: previous / next") + " · " + FiliI18n.tr("right click: menu")
                            };
                        }
                        onLeftClicked: Niri.onOutput(win.modelData.name, "focus-workspace " + btn.modelData.idx)
                        onRightClicked: win.openMenu(btn, btn.modelData)
                        onWheelUp: Niri.onOutput(win.modelData.name, "focus-workspace-up")
                        onWheelDown: Niri.onOutput(win.modelData.name, "focus-workspace-down")
                    }
                }
            }
        }
        // Separator between the strip and the windows
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: 16
            color: FiliTheme.nuit3
        }
        Repeater {
            model: win.groups
            Row {
                id: grp
                required property var modelData
                required property int index
                objectName: "taskbar-group-" + modelData.id
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
                    objectName: "taskbar-label-" + grp.modelData.id
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
                        color: TaskbarHint.active ? FiliTheme.voile : grp.modelData.urgent ? FiliTheme.sable : grp.modelData.active ? FiliTheme.brume : FiliTheme.ardoise
                        opacity: grp.modelData.wins.some(w => TaskbarHint.matches(TaskbarNumbers.numberOf(w.id))) || TaskbarHint.typed === "" ? 1 : 0.35
                        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall; weight: grp.modelData.active || TaskbarHint.active ? FiliTheme.weightAccent : Font.Normal }
                    }
                    BarHover {
                        id: chipHover
                        anchors.fill: parent
                        tipEdge: win.edge
                        tip: {
                            const g = grp.modelData;
                            return {
                                title: g.label === "•" ? FiliI18n.tr("Unnumbered workspace") : FiliI18n.tr("Workspace %1", g.label),
                                rows: g.wins.length ? g.wins.map(w => ["#" + TaskbarNumbers.numberOf(w.id) + " " + TaskbarLayout.appName(w.app_id), w.title ?? ""]) : [["", FiliI18n.tr("no window")]],
                                hint: g.folded ? FiliI18n.tr("click: list of the windows · wheel: previous / next") : FiliI18n.tr("click: go there · wheel: previous / next")
                            };
                        }
                        onLeftClicked: {
                            if (grp.modelData.folded)
                                win.openList(chip, grp.modelData.wins);
                            else
                                Niri.onOutput(win.modelData.name, "focus-workspace " + win.workspaceIdx(grp.modelData.id));
                        }
                        onRightClicked: win.openMenu(chip, Niri.workspaces.find(w => w.id === grp.modelData.id))
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
                        opacity: cell.modelData.nums.some(n => TaskbarHint.matches(n)) ? 1 : 0.35
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
                            readonly property string source: TaskbarLayout.appIcon(cell.modelData.app_id)
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
                                    text: (TaskbarLayout.appName(cell.modelData.app_id) || "?").charAt(0).toUpperCase()
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
                            visible: cell.modelData.title !== "" && !TaskbarHint.active
                            x: FiliTheme.pad + 16 + FiliTheme.space1 + numText.implicitWidth + FiliTheme.space1
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, 180)
                            elide: Text.ElideRight
                            text: cell.modelData.title
                            color: cell.modelData.focused ? FiliTheme.brume : FiliTheme.brume2
                            font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList }
                        }
                        // Number of the window (TaskbarNumbers), always shown: the one to type in the hint mode. A merged icon shows the
                        // first number and how many windows come with it ("3+2").
                        Text {
                            id: numText
                            objectName: "task-num-" + cell.modelData.key
                            x: FiliTheme.pad + 16 + FiliTheme.space1
                            anchors.verticalCenter: parent.verticalCenter
                            text: cell.modelData.nums[0] + (cell.merged ? "+" + (cell.modelData.nums.length - 1) : "")
                            color: TaskbarHint.active ? FiliTheme.voile : FiliTheme.ardoise
                            font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall; weight: FiliTheme.weightAccent }
                        }
                        BarHover {
                            id: cellHover
                            anchors.fill: parent
                            tipEdge: win.edge
                            tip: {
                                const e = cell.modelData;
                                return {
                                    title: TaskbarLayout.appName(e.app_id),
                                    rows: e.wins.map(w => [(w.is_urgent ? FiliI18n.tr("URGENT") + " · " : "") + "#" + TaskbarNumbers.numberOf(w.id), w.title ?? ""]),
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
        id: menu
        objectName: "taskbar-menu"
        visible: win.menuItems.length > 0 && win.menuAnchor !== null
        anchor.item: win.menuAnchor
        anchor.edges: FiliTheme.popupEdgesFor(win.edge)
        anchor.gravity: FiliTheme.popupEdgesFor(win.edge)
        anchor.margins.top: win.edge === "top" ? 6 : 0
        anchor.margins.bottom: win.edge === "bottom" ? 6 : 0
        implicitWidth: Math.min(380, Math.max(180, mcol.implicitWidth + 2 * FiliTheme.space2))
        implicitHeight: mcol.implicitHeight + 2 * FiliTheme.space1
        color: "transparent"
        Rectangle {
            anchors.fill: parent
            color: FiliTheme.nuit
            border { color: FiliTheme.border; width: FiliTheme.borderWidth }
            radius: FiliTheme.radiusWindow
            Column {
                id: mcol
                anchors { fill: parent; margins: FiliTheme.space1 }
                Repeater {
                    model: win.menuItems
                    Rectangle {
                        id: mrow
                        required property var modelData
                        objectName: "taskbar-menu-" + index
                        required property int index
                        property alias hover: mHover
                        width: mcol.width
                        height: 28
                        radius: FiliTheme.radiusControl
                        color: mHover.containsMouse ? FiliTheme.nuit3 : "transparent"
                        Text {
                            anchors { left: parent.left; leftMargin: FiliTheme.space2; right: parent.right; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                            elide: Text.ElideRight
                            text: mrow.modelData.text
                            color: FiliTheme.brume
                            font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList }
                        }
                        MouseArea {
                            id: mHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const it = mrow.modelData;
                                win.closeList();
                                Niri.onOutput(it.output, it.cmd);
                            }
                        }
                    }
                }
            }
        }
    }

    PopupWindow {
        id: list
        objectName: "taskbar-list"
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
                        objectName: "taskbar-list-" + modelData.id
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
                            readonly property string source: TaskbarLayout.appIcon(row.modelData.app_id)
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
                            text: "#" + TaskbarNumbers.numberOf(row.modelData.id) + "  " + (row.modelData.is_urgent ? FiliI18n.tr("URGENT") + " · " : "") + (row.modelData.title || TaskbarLayout.appName(row.modelData.app_id))
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
