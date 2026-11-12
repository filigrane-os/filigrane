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
    // On the left or the right: a narrow column (one icon over its number per window); the corner shared with the fili-bar is
    // left to it (margins), so the two bars never overlap
    readonly property bool vertical: TaskbarLayout.vertical
    anchors {
        top: edge === "top" || vertical
        bottom: edge === "bottom" || vertical
        left: edge === "left" || !vertical
        right: edge === "right" || !vertical
    }
    margins {
        top: vertical && FiliTheme.barEdge === "top" ? FiliTheme.barThickness : 0
        bottom: vertical && FiliTheme.barEdge === "bottom" ? FiliTheme.barThickness : 0
        left: !vertical && FiliTheme.barEdge === "left" ? FiliTheme.barThickness : 0
        right: !vertical && FiliTheme.barEdge === "right" ? FiliTheme.barThickness : 0
    }
    // Automatic hiding ([taskbar] autohide): a thin strip on the edge that takes no room; the pointer on it, the hint mode, a
    // list or a menu open, or the moment after the pointer left (the timer) show the bar
    readonly property bool autohide: TaskbarLayout.autohide
    readonly property bool shown: !autohide || hinting || hov.hovered || leave.running || listWins.length > 0 || menuItems.length > 0 || (FiliPanel.open && FiliPanel.hang !== "")
    HoverHandler {
        id: hov
        onHoveredChanged: if (!hovered) leave.restart()
    }
    Timer {
        id: leave
        interval: 600
    }
    implicitHeight: vertical ? 0 : shown ? FiliTheme.taskbarHeight : 2
    implicitWidth: vertical ? (shown ? FiliTheme.taskbarWidth : 2) : 0
    exclusionMode: autohide ? ExclusionMode.Ignore : ExclusionMode.Auto
    // Transparent window, background drawn by a rectangle: the surface needs its alpha channel from the start
    color: "transparent"
    Rectangle {
        objectName: "taskbar-fill"
        z: -3
        anchors.fill: parent
        color: win.shown ? Qt.alpha(FiliTheme.nuit, TaskbarLayout.alpha) : FiliTheme.toned(FiliTheme.taskbarTone, "hover")
    }
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
    // Width the titles may take at level 0: they shrink to share the room before any title is dropped (level 1), and grow back
    // up to titleMax when there is room again
    readonly property int titleMax: 180
    readonly property int titleMin: 64
    property int titleCap: titleMax
    // Natural widths of the titles shown in the row
    function titleWidths(item, out) {
        for (const c of item.children) {
            if (c.titleShown === true)
                out.push(c.titleNatural);
            else if (c.children && c.children.length > 0)
                titleWidths(c, out);
        }
        return out;
    }
    // Largest cap (titleMin..titleMax) with which the titles fit in the budget
    function capFor(nat, budget) {
        const total = cap => nat.reduce((t, w) => t + Math.min(w, cap), 0);
        if (total(titleMax) <= budget)
            return titleMax;
        let lo = titleMin, hi = titleMax;
        while (hi - lo > 1) {
            const mid = (lo + hi) >> 1;
            if (total(mid) <= budget)
                lo = mid;
            else
                hi = mid;
        }
        return lo;
    }
    function fit() {
        if (!measure || width <= 0 || height <= 0) {
            if (level !== 0)
                level = 0;
            if (titleCap !== titleMax)
                titleCap = titleMax;
            return;
        }
        const avail = (vertical ? height : width) - 2 * FiliTheme.space1;
        let row = vertical ? rowItem.implicitHeight : rowItem.implicitWidth;
        const s = seen.slice();
        s[level] = row;
        if (level === 0 && !vertical) {
            const nat = titleWidths(rowItem, []);
            const sum = cap => nat.reduce((t, w) => t + Math.min(w, cap), 0);
            const fixed = row - sum(titleCap);
            // The narrowest titles are what going back down from level 1 needs to know
            s[0] = fixed + sum(titleMin);
            const cap = capFor(nat, avail - fixed);
            if (cap !== titleCap) {
                titleCap = cap;
                settle.restart();
                seen = s;
                return;
            }
        }
        seen = s;
        const next = TaskbarLayout.nextLevel(level, avail, row, s);
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
    onHeightChanged: settle.restart()
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
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: m => {
            win.closeList();
            FiliShell.popupOpened("");
            if (m.button === Qt.RightButton)
                FiliPanel.openBarMenu(win, m.x, m.y, "taskbar");
        }
    }
    // Thin line on the inner edge of the bar (none when the background is transparent)
    Rectangle {
        z: -1
        visible: TaskbarLayout.background !== "transparent"
        x: win.edge === "right" ? 0 : win.edge === "left" ? parent.width - 1 : 0
        y: win.edge === "bottom" ? 0 : win.edge === "top" ? parent.height - 1 : 0
        width: win.vertical ? 1 : parent.width
        height: win.vertical ? parent.height : 1
        color: FiliTheme.toned(FiliTheme.taskbarTone, "hover")
    }

    Grid {
        id: rowItem
        objectName: "taskbar-row"
        visible: win.shown
        // One row of items, or one column of them when the Quai stands on the left or the right
        columns: win.vertical ? 1 : 1000
        anchors {
            left: parent.left
            leftMargin: win.vertical ? 0 : FiliTheme.space1
            top: parent.top
            topMargin: win.vertical ? FiliTheme.space1 : 0
            bottom: win.vertical ? undefined : parent.bottom
            right: win.vertical ? parent.right : undefined
        }
        spacing: 0
        // Workspaces of the screen (all of them, empty ones too): click goes there, wheel goes to the previous / next,
        // right click opens the menu of the workspace
        Grid {
            id: strip
            objectName: "taskbar-strip"
            columns: win.vertical ? 1 : 1000
            height: win.vertical ? implicitHeight : rowItem.height
            spacing: 0
            Repeater {
                model: Niri.workspaces.filter(w => w.output === win.modelData.name).sort(TaskbarLayout.wsOrder)
                Item {
                    id: btn
                    required property var modelData
                    objectName: "taskbar-ws-" + modelData.id
                    property alias hover: btnHover
                    readonly property string label: TaskbarLayout.label(modelData, Niri.workspaces.some(w => /^[0-9]+$/.test(w.name ?? "")))
                    height: win.vertical ? 24 : strip.height
                    width: win.vertical ? FiliTheme.taskbarWidth : btnText.implicitWidth + 2 * FiliTheme.pad
                    Rectangle {
                        anchors.fill: parent
                        color: btn.modelData.is_active || btnHover.containsMouse ? FiliTheme.toned(FiliTheme.taskbarTone, "hover") : "transparent"
                    }
                    Text {
                        id: btnText
                        anchors.centerIn: parent
                        text: btn.label
                        color: btn.modelData.is_active || btnHover.containsMouse ? FiliTheme.toned(FiliTheme.taskbarTone, "text") : FiliTheme.toned(FiliTheme.taskbarTone, "muted")
                        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall; weight: btn.modelData.is_active ? FiliTheme.weightAccent : Font.Normal }
                    }
                    Rectangle {
                        visible: btn.modelData.is_active
                        x: win.edge === "left" ? parent.width - width : 0
                        y: win.edge === "bottom" ? 0 : win.edge === "top" ? parent.height - height : 0
                        width: win.vertical ? 2 : parent.width
                        height: win.vertical ? parent.height : 2
                        color: FiliTheme.toned(FiliTheme.taskbarTone, "accent")
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
        Item {
            width: win.vertical ? FiliTheme.taskbarWidth : 1
            height: win.vertical ? 9 : rowItem.height
            Rectangle {
                anchors.centerIn: parent
                width: win.vertical ? 16 : 1
                height: win.vertical ? 1 : 16
                color: FiliTheme.toned(FiliTheme.taskbarTone, "hover")
            }
        }
        Repeater {
            model: win.groups
            Grid {
                id: grp
                required property var modelData
                required property int index
                objectName: "taskbar-group-" + modelData.id
                columns: win.vertical ? 1 : 1000
                height: win.vertical ? implicitHeight : rowItem.height
                spacing: 0
                // A thin separator between two workspaces
                Item {
                    visible: grp.index > 0
                    width: win.vertical ? FiliTheme.taskbarWidth : 1
                    height: win.vertical ? 9 : grp.height
                    Rectangle {
                        anchors.centerIn: parent
                        width: win.vertical ? 16 : 1
                        height: win.vertical ? 1 : 16
                        color: FiliTheme.toned(FiliTheme.taskbarTone, "hover")
                    }
                }
                // Label of the workspace; folded: label and count in one cell that opens the list
                Item {
                    id: chip
                    objectName: "taskbar-label-" + grp.modelData.id
                    property alias hover: chipHover
                    height: win.vertical ? 22 : grp.height
                    implicitWidth: win.vertical ? FiliTheme.taskbarWidth : chipText.implicitWidth + 2 * FiliTheme.pad
                    width: implicitWidth
                    Rectangle {
                        anchors.fill: parent
                        color: grp.modelData.folded && chipHover.containsMouse ? FiliTheme.toned(FiliTheme.taskbarTone, "hover") : "transparent"
                    }
                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        text: grp.modelData.folded ? grp.modelData.label + " · " + grp.modelData.count : grp.modelData.label
                        color: TaskbarHint.active ? FiliTheme.toned(FiliTheme.taskbarTone, "accent") : grp.modelData.urgent ? FiliTheme.toned(FiliTheme.taskbarTone, "warn") : grp.modelData.active ? FiliTheme.toned(FiliTheme.taskbarTone, "text") : FiliTheme.toned(FiliTheme.taskbarTone, "muted")
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
                        // Read by the squeeze (FiliTaskbar.titleWidths)
                        readonly property bool titleShown: title.visible
                        readonly property real titleNatural: title.implicitWidth
                        height: win.vertical ? 44 : grp.height
                        opacity: cell.modelData.nums.some(n => TaskbarHint.matches(n)) ? 1 : 0.35
                        implicitWidth: win.vertical ? FiliTheme.taskbarWidth : FiliTheme.pad + 16 + FiliTheme.space1 + numText.implicitWidth + (title.visible ? FiliTheme.space1 + title.width : 0) + FiliTheme.pad
                        width: implicitWidth
                        Rectangle {
                            anchors.fill: parent
                            color: cell.modelData.focused || cellHover.containsMouse ? FiliTheme.toned(FiliTheme.taskbarTone, "hover") : "transparent"
                        }
                        // Mark of the focused window, on the inner edge of the bar (like the active workspace of the fili-bar)
                        Rectangle {
                            visible: cell.modelData.focused
                            x: win.edge === "left" ? parent.width - width : 0
                            y: win.edge === "bottom" ? 0 : win.edge === "top" ? parent.height - height : 0
                            width: win.vertical ? 2 : parent.width
                            height: win.vertical ? parent.height : 2
                            color: FiliTheme.toned(FiliTheme.taskbarTone, "accent")
                        }
                        // Application icon, or its first letter when the theme has none
                        Item {
                            id: glyph
                            x: win.vertical ? (parent.width - width) / 2 : FiliTheme.pad
                            y: win.vertical ? 6 : (parent.height - height) / 2
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
                                border { width: FiliTheme.borderWidth; color: FiliTheme.toned(FiliTheme.taskbarTone, "muted") }
                                Text {
                                    anchors.centerIn: parent
                                    text: (TaskbarLayout.appName(cell.modelData.app_id) || "?").charAt(0).toUpperCase()
                                    color: FiliTheme.toned(FiliTheme.taskbarTone, "text2")
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
                                color: FiliTheme.toned(FiliTheme.taskbarTone, "warn")
                                border { width: 1; color: FiliTheme.nuit }
                            }
                        }
                        Text {
                            id: title
                            visible: cell.modelData.title !== "" && !TaskbarHint.active && !win.vertical
                            x: FiliTheme.pad + 16 + FiliTheme.space1 + numText.implicitWidth + FiliTheme.space1
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, win.level === 0 ? win.titleCap : win.titleMax)
                            elide: Text.ElideRight
                            text: cell.modelData.title
                            color: cell.modelData.focused ? FiliTheme.toned(FiliTheme.taskbarTone, "text") : FiliTheme.toned(FiliTheme.taskbarTone, "text2")
                            font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList }
                        }
                        // Number of the window (TaskbarNumbers), always shown: the one to type in the hint mode. A merged icon shows the
                        // first number and how many windows come with it ("3+2").
                        Text {
                            id: numText
                            objectName: "task-num-" + cell.modelData.key
                            x: win.vertical ? (parent.width - width) / 2 : FiliTheme.pad + 16 + FiliTheme.space1
                            y: win.vertical ? 26 : (parent.height - height) / 2
                            text: cell.modelData.nums[0] + (cell.merged ? "+" + (cell.modelData.nums.length - 1) : "")
                            color: TaskbarHint.active ? FiliTheme.toned(FiliTheme.taskbarTone, "accent") : FiliTheme.toned(FiliTheme.taskbarTone, "muted")
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
        anchor.margins.left: win.edge === "left" ? 6 : 0
        anchor.margins.right: win.edge === "right" ? 6 : 0
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
        anchor.margins.left: win.edge === "left" ? 6 : 0
        anchor.margins.right: win.edge === "right" ? 6 : 0
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
