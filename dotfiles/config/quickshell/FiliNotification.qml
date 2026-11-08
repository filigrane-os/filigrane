pragma Singleton
// fili-notification: notification server (replaces mako), bubbles at the top right under the fili-bar, 4 at most,
// duration by urgency (the one requested by the app is ignored), Do Not Disturb (bubbles hidden).
// fili-notification-center: history of the last 30 (click on the bell of the fili-bar, `fili-shell notification center`).
// Left click on a bubble: default action then focus on the window of the app (notif-focus); cross or right click: close.
// The other actions of the notification (notify-send -A id=Text) are buttons under the text, three at most, the
// first highlighted (fili-ai-ask: Allow / Deny, or the options of a question); a bubble with buttons stays 60 s, or the requested delay (notify-send -t), to leave time to answer.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.bar
import qs.controls

Singleton {
    id: notifs
    property bool dnd: false
    // Bubbles displayed: { n: Notification, key }
    property var popups: []
    // History (copies, most recent first): { app, icon, summary, body, time }
    property var history: []
    property bool centerOpen: false
    onCenterOpenChanged: FiliShell.centerOpen = centerOpen
    property int serial: 0
    // Sender stacks: app name -> true when its stack is spread out
    property var expanded: ({})

    // Popups grouped by sender, newest group first, newest popup first: { app, items: [popup] }
    function groups() {
        const out = [], idx = {};
        for (const p of popups.slice().reverse()) {
            const a = p.n.appName;
            if (idx[a] === undefined) {
                idx[a] = out.length;
                out.push({ app: a, items: [] });
            }
            out[idx[a]].items.push(p);
        }
        return out;
    }
    function toggleStack(app) {
        const e = Object.assign({}, expanded);
        if (e[app])
            delete e[app];
        else
            e[app] = true;
        expanded = e;
    }
    function closeGroup(app, how) {
        for (const p of popups.filter(p => p.n.appName === app))
            close(p.n, how);
    }

    // Actions offered as buttons (apart from "default", the click on the bubble)
    function buttons(n) {
        return n.actions.filter(a => a.identifier !== "default").slice(0, 3);
    }
    // Answer to an action: the app is told (ActionInvoked), the bubble closes
    function answer(n, identifier) {
        const a = n.actions.find(x => x.identifier === identifier);
        if (a)
            a.invoke();
        close(n, "dismiss");
    }
    // Low-battery alert (bar-status batwatch): stays until the user closes it
    function sticky(n) {
        return n.appName === "fili-battery";
    }
    function timeout(n) {
        if (buttons(n).length > 0)
            return n.expireTimeout > 0 ? n.expireTimeout : 60000;
        return n.urgency === NotificationUrgency.Critical ? 10000 : n.urgency === NotificationUrgency.Low ? 3000 : 5000;
    }
    // Notifications from AI agents (fili-ai-ask, fili-ai-session, Codex, opencode): drawn as a badge, not a theme icon
    function isAi(app) {
        return /^(claude code|fili-ai|codex|opencode)$/i.test(app || "");
    }
    function icon(n) {
        if (isAi(n.appName) && !n.image)
            return "";
        const i = n.image || n.appIcon;
        if (!i)
            return "";
        // Icon name already turned into image://icon/NAME: absent from the theme, it would give the Qt magenta checkerboard (nothing to show)
        if (i.startsWith("image://icon/") && !i.startsWith("image://icon//"))
            return Quickshell.iconPath(i.slice(13), true);
        return i.startsWith("/") ? "file://" + i : i.indexOf("://") > 0 || i.startsWith("image:") ? i : Quickshell.iconPath(i, true);
    }
    // Close a bubble; it goes into the history (except niri screenshots: full-screen image, as with the old mako)
    function close(n, how) {
        if (!n)
            return;
        popups = popups.filter(p => p.n !== n);
        if (expanded[n.appName] && !popups.some(p => p.n.appName === n.appName))
            toggleStack(n.appName);
        if (n.appName !== "niri")
            history = [{ app: n.appName, ai: isAi(n.appName) && !n.image, icon: icon(n), summary: n.summary, body: n.body, time: new Date() }].concat(history).slice(0, 30);
        if (how === "expire")
            n.expire();
        else
            n.dismiss();
    }
    function dismissAll() {
        for (const p of popups.slice())
            close(p.n, "dismiss");
    }
    // Copy the text of a history notification and close the center
    function copy(h) {
        if (FiliTheme.testing)
            FiliTheme.ran = FiliTheme.ran.concat(["wl-copy " + h.summary]);
        else
            Quickshell.execDetached(["wl-copy", h.summary + (h.body ? "\n" + h.body.replace(/<[^>]*>/g, "") : "")]);
        centerOpen = false;
    }
    function toggleCenter() {
        centerOpen = !centerOpen;
        if (centerOpen)
            FiliShell.popupOpened("center");
    }
    function activate(n) {
        const def = n.actions.find(a => a.identifier === "default");
        const app = n.appName, entry = n.desktopEntry;
        if (def)
            def.invoke();
        Quickshell.execDetached([FiliTheme.bin + "/notif-focus", app, entry]);
        close(n, "dismiss");
    }

    NotificationServer {
        keepOnReload: true
        actionsSupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        imageSupported: true
        persistenceSupported: true
        onNotification: n => {
            n.tracked = true;
            if (notifs.dnd) {
                notifs.close(n, "expire");
                return;
            }
            if (n.urgency !== NotificationUrgency.Low)
                FiliSound.notified(n.appName);
            // Identical repeat (same sender, summary and body): replaces the older one and counts up
            const old = notifs.popups.find(p => p.n.appName === n.appName && p.n.summary === n.summary && p.n.body === n.body);
            let count = 1;
            if (old) {
                count = old.count + 1;
                notifs.popups = notifs.popups.filter(p => p !== old);
                old.n.dismiss();
            }
            notifs.popups = notifs.popups.concat([{ n: n, key: ++notifs.serial, count: count }]);
            n.closed.connect(() => notifs.popups = notifs.popups.filter(p => p.n !== n));
        }
    }

    Connections {
        target: FiliShell
        function onPopupOpened(who) {
            if (who !== "center")
                notifs.centerOpen = false;
        }
    }
    Connections {
        target: FiliShell
        function onCommand(target, name, args) {
            if (target !== "notification")
                return;
            if (name === "dnd")
                notifs.dnd = args[0] === "on" ? true : args[0] === "off" ? false : !notifs.dnd;
            else if (name === "dismiss-all")
                notifs.dismissAll();
            else if (name === "dismiss") {
                const s = args.join(" ");
                const p = notifs.popups.find(p => p.n.summary === s);
                if (p)
                    notifs.close(p.n, "dismiss");
            } else if (name === "center")
                notifs.toggleCenter();
            else if (name === "history")
                FiliShell.reply(args[0], JSON.stringify(notifs.history.map(h => ({ app_name: h.app, app_icon: h.icon, summary: h.summary, body: h.body }))));
        }
    }

    // fili-notification: bulles
    PanelWindow {
        visible: !notifs.dnd && notifs.popups.length > 0 && !FiliTheme.testing
        anchors { top: true; right: true }
        margins { top: 12; right: 12 }
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "fili-notification"
        implicitWidth: 360
        implicitHeight: Math.max(1, stack.implicitHeight)
        color: "transparent"

        ColumnLayout {
            id: stack
            width: 360
            spacing: FiliTheme.space2
            Repeater {
                model: notifs.groups().slice(0, 4)
                Stack {
                    required property var modelData
                    g: modelData
                    Layout.fillWidth: true
                }
            }
        }
    }

    // One sender: its newest popup with two edges behind it when several are stacked; the "+N" pill spreads them out
    component Stack: Item {
        id: stack
        property var g
        readonly property bool open: notifs.expanded[g.app] === true
        readonly property bool stacked: g.items.length > 1 && !open
        // Each edge peeks out 8 px below the one in front, like a pile of cards
        readonly property int edges: stacked ? Math.min(2, g.items.length - 1) : 0
        implicitHeight: cards.implicitHeight + 8 * edges
        Repeater {
            model: stack.edges
            Rectangle {
                required property int index
                z: -1 - index
                anchors { left: parent.left; right: parent.right; leftMargin: 12 * (index + 1); rightMargin: 12 * (index + 1) }
                y: cards.implicitHeight - 30 + 8 * (index + 1)
                height: 30
                radius: FiliTheme.radiusWindow
                color: FiliTheme.nuit
                border { width: FiliTheme.borderWidth; color: FiliTheme.border }
                opacity: 1 - 0.25 * index
            }
        }
        ColumnLayout {
            id: cards
            width: parent.width
            spacing: FiliTheme.space2
            Repeater {
                model: stack.stacked ? [stack.g.items[0]] : stack.g.items.slice(0, 5)
                Card {
                    required property var modelData
                    required property int index
                    n: modelData.n
                    count: modelData.count
                    groupSize: stack.g.items.length
                    stacked: stack.stacked
                    first: index === 0
                    Layout.fillWidth: true
                }
            }
        }
    }

    component Card: Rectangle {
        id: card
        property var n
        property int count: 1
        property int groupSize: 1
        property bool stacked: false
        property bool first: true
        readonly property bool low: n.urgency === NotificationUrgency.Low
        readonly property bool critical: n.urgency === NotificationUrgency.Critical
        readonly property string img: notifs.icon(n)
        readonly property var btns: notifs.buttons(n)
        implicitHeight: Math.min(140, Math.max(row.implicitHeight + 28, 56)) + (btns.length > 0 ? 40 : 0)
        color: FiliTheme.nuit
        radius: FiliTheme.radiusWindow
        border.width: FiliTheme.borderWidth
        border.color: critical ? FiliTheme.cendre : low ? FiliTheme.nuit3 : FiliTheme.border
        clip: true

        Timer {
            running: !area.containsMouse && !closeBtn.hovered && !pill.hovered && !notifs.sticky(card.n)
            interval: notifs.timeout(card.n)
            onTriggered: card.stacked ? notifs.closeGroup(card.n.appName, "expire") : notifs.close(card.n, "expire")
        }
        RowLayout {
            id: row
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: FiliTheme.space3; rightMargin: pill.visible ? 34 + pill.width + FiliTheme.space2 : 34 }
            height: Math.min(140, Math.max(row.implicitHeight + 28, 56)) - 2 * FiliTheme.space3
            spacing: FiliTheme.space3
            IconImage {
                visible: card.img !== ""
                source: card.img
                implicitSize: 40
                Layout.alignment: Qt.AlignTop
            }
            AiBadge {
                visible: card.img === "" && notifs.isAi(card.n.appName)
                size: 40
                Layout.alignment: Qt.AlignTop
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    text: card.n.summary + (card.count > 1 ? "  \u00d7" + card.count : "")
                    elide: Text.ElideRight
                    color: card.low ? FiliTheme.brume2 : FiliTheme.brume
                    font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: card.n.body
                    textFormat: Text.StyledText
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    color: card.low ? FiliTheme.brume2 : FiliTheme.brume
                    linkColor: FiliTheme.voile
                    font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                    onLinkActivated: l => Qt.openUrlExternally(l)
                }
                // Barre de progression (indice "value")
                Rectangle {
                    visible: card.n.hints.value !== undefined
                    Layout.fillWidth: true
                    Layout.topMargin: FiliTheme.space1
                    implicitHeight: 4
                    radius: FiliTheme.radiusMark
                    color: FiliTheme.nuit3
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(100, card.n.hints.value ?? 0)) / 100
                        height: parent.height
                        radius: FiliTheme.radiusMark
                        color: FiliTheme.voile
                    }
                }
            }
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: m => m.button === Qt.LeftButton ? notifs.activate(card.n) : notifs.close(card.n, "dismiss")
        }
        // Action buttons (above the click area of the bubble)
        Row {
            z: 2
            visible: card.btns.length > 0
            anchors { right: parent.right; bottom: parent.bottom; margins: FiliTheme.space3 }
            spacing: FiliTheme.space2
            Repeater {
                model: card.btns
                Rectangle {
                    id: btn
                    required property var modelData
                    required property int index
                    objectName: "notif-action-" + modelData.identifier
                    height: 24
                    width: label.implicitWidth + 2 * FiliTheme.space3
                    radius: FiliTheme.radiusControl
                    color: index === 0 ? (btnArea.containsMouse ? FiliTheme.voileVif : FiliTheme.voile) : btnArea.containsMouse ? FiliTheme.nuit4 : FiliTheme.nuit3
                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: btn.modelData.text
                        color: btn.index === 0 ? FiliTheme.nuit : FiliTheme.brume
                        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList; weight: FiliTheme.weightAccent }
                    }
                    MouseArea {
                        id: btnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: notifs.answer(card.n, btn.modelData.identifier)
                    }
                }
            }
        }
        // Stack button: "N more" spreads the sender's notifications out, the arrow folds them back
        Rectangle {
            id: pill
            z: 2
            visible: card.first && card.groupSize > 1
            readonly property bool hovered: pillArea.containsMouse
            objectName: "notif-stack-" + card.n.appName
            anchors { top: parent.top; right: closeBtn.left; margins: FiliTheme.space2 }
            height: 22
            width: pillLabel.implicitWidth + 2 * FiliTheme.space2
            radius: FiliTheme.radiusControl
            color: hovered ? FiliTheme.nuit4 : FiliTheme.nuit3
            Text {
                id: pillLabel
                anchors.centerIn: parent
                text: card.stacked ? "\u25be " + FiliI18n.tr("%1 more", card.groupSize - 1) : "\u25b4 " + FiliI18n.tr("Collapse")
                color: FiliTheme.brume
                font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList; weight: FiliTheme.weightAccent }
            }
            MouseArea {
                id: pillArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: notifs.toggleStack(card.n.appName)
            }
        }
        CloseCross {
            id: closeBtn
            anchors { top: parent.top; right: parent.right; margins: FiliTheme.space2 }
            onClicked: card.stacked ? notifs.closeGroup(card.n.appName, "dismiss") : notifs.close(card.n, "dismiss")
        }
    }

    // AI agent badge: Filigrane tile with a robot glyph, shown when the notification has no image
    component AiBadge: Rectangle {
        property int size: 32
        implicitWidth: size
        implicitHeight: size
        radius: size * 0.225
        color: FiliTheme.voile
        Text {
            anchors.centerIn: parent
            text: String.fromCodePoint(0xF06A9)  // nf-md-robot
            color: FiliTheme.nuit
            font { family: FiliTheme.font; pixelSize: parent.size * 0.6 }
        }
    }

    // Close cross (bubbles and fili-notification-center): discreet, lighter on hover
    component CloseCross: Rectangle {
        id: cross
        signal clicked
        readonly property bool hovered: crossArea.containsMouse
        width: 22
        height: 22
        radius: FiliTheme.radiusControl
        color: hovered ? FiliTheme.nuit3 : "transparent"
        Text {
            anchors.centerIn: parent
            text: "\u2715"
            color: cross.hovered ? FiliTheme.brume : FiliTheme.ardoise
            font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList }
        }
        MouseArea {
            id: crossArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: cross.clicked()
        }
    }

    // fili-notification-center: click = copy the text, cross or right click = remove, Escape or click on a window = close.
    // Keyboard (like the fili-panel): ↑/↓ or Tab from item to item, Enter = copy, Delete = remove, ←/→ = neighbouring panel.
    // Window the size of the panel (no full-screen layer); click elsewhere: the focus leaves, the center closes.
    PanelWindow {
        id: centerWin
        visible: notifs.centerOpen && !FiliTheme.testing
        anchors { top: true; right: true }
        margins { top: 12; right: 12 }
        implicitWidth: centerCard.width
        implicitHeight: centerCard.height
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "fili-notification-center"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        color: "transparent"

        Rectangle {
            id: centerCard
            width: 380
            height: Math.min((centerWin.screen?.height ?? 800) - FiliTheme.barHeight - 24, col.implicitHeight + 28)
            color: FiliTheme.nuit
            radius: FiliTheme.radiusWindow
            border { width: 1; color: FiliTheme.nuit4 }
            focus: true
            Keys.onEscapePressed: notifs.centerOpen = false
            Keys.onUpPressed: FiliPanel.moveFocus(centerCard, Window.activeFocusItem, false)
            Keys.onDownPressed: FiliPanel.moveFocus(centerCard, Window.activeFocusItem, true)
            Keys.onTabPressed: FiliPanel.moveFocus(centerCard, Window.activeFocusItem, true)
            Keys.onBacktabPressed: FiliPanel.moveFocus(centerCard, Window.activeFocusItem, false)
            Keys.onLeftPressed: FiliPanel.step(-1)
            Keys.onRightPressed: FiliPanel.step(1)
            // Focus received on opening then lost (click on a window): close
            property bool held: false
            Window.onActiveChanged: {
                if (Window.active)
                    held = true;
                else if (held)
                    notifs.centerOpen = false;
            }
            Connections {
                target: notifs
                function onCenterOpenChanged() {
                    centerCard.held = false;
                    if (notifs.centerOpen && FiliShell.keyNav)
                        Qt.callLater(() => FiliPanel.focusFirst(centerCard));
                }
            }

            ColumnLayout {
                id: col
                anchors { fill: parent; margins: FiliTheme.space5 }
                spacing: FiliTheme.space2
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: FiliI18n.tr("Notifications") + (notifs.dnd ? "  ·  " + FiliI18n.tr("do not disturb") : "")
                        color: FiliTheme.voile
                        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
                    }
                    Text {
                        text: notifs.dnd ? "" : ""
                        color: notifs.dnd ? FiliTheme.sable : FiliTheme.ardoise
                        font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                        MouseArea { anchors.fill: parent; onClicked: notifs.dnd = !notifs.dnd }
                        objectName: "center-dnd"
                        activeFocusOnTab: true
                        Keys.onReturnPressed: notifs.dnd = !notifs.dnd
                        Keys.onSpacePressed: notifs.dnd = !notifs.dnd
                        FocusRing { gap: 4 }
                    }
                    Text {
                        text: FiliI18n.tr("Clear")
                        visible: notifs.history.length > 0
                        color: FiliTheme.ardoise
                        font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                        MouseArea { anchors.fill: parent; onClicked: notifs.history = [] }
                        activeFocusOnTab: true
                        Keys.onReturnPressed: notifs.history = []
                        Keys.onSpacePressed: notifs.history = []
                        FocusRing { gap: 4 }
                    }
                }
                Text {
                    visible: notifs.history.length === 0
                    text: FiliI18n.tr("No notifications")
                    color: FiliTheme.ardoise
                    font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                }
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    implicitHeight: contentHeight
                    clip: true
                    spacing: FiliTheme.space2
                    boundsBehavior: Flickable.StopAtBounds
                    model: notifs.history
                    KineticScroll {}
                    delegate: Rectangle {
                        id: item
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        implicitHeight: Math.max(entry.implicitHeight, 32) + 16
                        radius: FiliTheme.radiusControl
                        color: hov.containsMouse ? FiliTheme.nuit3 : "transparent"
                        // Keyboard: Enter or Space = copy (like the click), Delete = remove; the list follows the focus
                        objectName: "center-item"
                        activeFocusOnTab: true
                        onActiveFocusChanged: if (activeFocus) ListView.view.positionViewAtIndex(index, ListView.Contain)
                        Keys.onReturnPressed: notifs.copy(modelData)
                        Keys.onSpacePressed: notifs.copy(modelData)
                        Keys.onDeletePressed: notifs.history = notifs.history.filter(x => x !== item.modelData)
                        FocusRing {}
                        RowLayout {
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: FiliTheme.space2; rightMargin: 32 }
                            spacing: FiliTheme.space2
                            // Icon of the app or image of the notification (empty: a discreet square keeps the alignment)
                            IconImage {
                                implicitSize: 32
                                Layout.alignment: Qt.AlignTop
                                source: item.modelData.icon
                                visible: item.modelData.icon !== ""
                            }
                            AiBadge {
                                visible: item.modelData.icon === "" && item.modelData.ai === true
                                Layout.alignment: Qt.AlignTop
                            }
                            Rectangle {
                                visible: item.modelData.icon === "" && item.modelData.ai !== true
                                implicitWidth: 32
                                implicitHeight: 32
                                Layout.alignment: Qt.AlignTop
                                radius: FiliTheme.radiusControl
                                color: FiliTheme.nuit3
                                Text {
                                    anchors.centerIn: parent
                                    text: ""
                                    color: FiliTheme.ardoise
                                    font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                                }
                            }
                            ColumnLayout {
                                id: entry
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    Layout.fillWidth: true
                                    text: item.modelData.app + "  ·  " + FiliI18n.locale.toString(item.modelData.time, "HH:mm")
                                    color: FiliTheme.ardoise
                                    font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: item.modelData.summary
                                    elide: Text.ElideRight
                                    color: FiliTheme.brume
                                    font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                    text: item.modelData.body.replace(/<[^>]*>/g, "")
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    color: FiliTheme.brume2
                                    font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                                }
                            }
                        }
                        MouseArea {
                            id: hov
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: m => {
                                const h = parent.modelData;
                                if (m.button === Qt.RightButton)
                                    notifs.history = notifs.history.filter(x => x !== h);
                                else
                                    notifs.copy(h);
                            }
                        }
                        CloseCross {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: FiliTheme.space2 }
                            visible: hov.containsMouse || hovered
                            onClicked: notifs.history = notifs.history.filter(x => x !== parent.modelData)
                        }
                    }
                }
                // Settings: under the notifications, separated by a line
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: FiliTheme.nuit4
                }
                // Sounds (FiliSound): new notification and charger plugged in
                Repeater {
                    model: [["notify", FiliI18n.tr("Notification sound")], ["plug", FiliI18n.tr("Charger plugged in sound")]]
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: parent.modelData[1]
                            color: FiliTheme.brume
                            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                        }
                        PanelSwitch {
                            objectName: "sound-" + parent.modelData[0]
                            checked: parent.modelData[0] === "notify" ? FiliSound.notify : FiliSound.plug
                            onToggled: FiliSound.set(parent.modelData[0], !checked)
                        }
                    }
                }
            }
        }
    }
}
