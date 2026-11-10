pragma Singleton
// fili-panel: the single action window under the clicked fili-bar item (network, sound, Bluetooth, power,
// monitor), inspired by the Omarchy panels. One view at a time, loaded on opening and freed on closing
// (nothing runs while the panel is closed). Closing: Escape, a click on a window (focus lost), a click on the bar or the
// same item clicked again.
// Usage: BarModule.togglePanel() (the module declares panel and panelSource); otherwise FiliPanel.toggle(item, name, barWindow)
// Keyboard: Mod+A (`fili-shell panel toggle`) opens the last panel or closes; ←/→ (Shift+←/→ on a slider, a row
// of choices or a field) goes to the neighbouring panel in bar order, fili-notification-center included (ring);
// ↑/↓ or Tab/Shift+Tab from item to item, Enter or Space to act, Escape to close.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.controls

Singleton {
    id: panel
    property string view: ""
    onViewChanged: FiliShell.panelOpen = view !== ""
    property real anchorX: 0
    // Along a column of the bar (left, right): the middle of the item
    property real anchorY: 0
    property var screen: null
    readonly property bool open: view !== ""
    // Loaded view (tests)
    property alias loaded: loader.item
    // Settings gear of the card (tests)
    property alias gearButton: gear
    // Panel views by name, registered by the bar modules (BarModule.panel / panelSource)
    property var sources: ({})

    // Last panel opened (Mod+A reopens it)
    property string last: "monitor"
    // Bar module of each panel, by screen: a panel opened from the keyboard sits under it
    property var modules: ({})
    function register(name, item, win, source) {
        const s = win?.screen?.name ?? "";
        modules[s] = modules[s] ?? {};
        modules[s][name] = { item: item, win: win };
        if (source)
            sources[name] = source;
    }
    function unregister(name, win) {
        const s = win?.screen?.name ?? "";
        if (modules[s])
            delete modules[s][name];
    }
    // Position of an item in the item tree: the child indices from the window root (the order of the modules in the
    // bar, whatever the layout state or the creation order)
    function treePath(item) {
        const path = [];
        for (let i = item; i && i.parent; i = i.parent)
            path.unshift(Array.from(i.parent.children).indexOf(i));
        return path;
    }
    function compareTree(a, b) {
        for (let i = 0; i < Math.min(a.length, b.length); i++)
            if (a[i] !== b[i])
                return a[i] - b[i];
        return a.length - b.length;
    }
    // Panels in keyboard order (←/→): the order of the modules in the bar (current screen, else the first);
    // "center" = fili-notification-center
    function ring() {
        const s = screen?.name ?? Quickshell.screens[0]?.name ?? "";
        const m = modules[s] ?? Object.values(modules)[0] ?? {};
        const path = {};
        for (const n in m)
            path[n] = treePath(m[n].item);
        // A panel whose item is hidden (the status icon with no active indicator) is not in the ring
        return Object.keys(m).filter(n => !m[n].item.panelNeedsVisible || m[n].item.visible).sort((a, b) => compareTree(path[a], path[b]));
    }

    function toggle(item, name, win) {
        FiliTooltip.hide();
        if (view === name) {
            close();
            return;
        }
        FiliShell.popupOpened("panel");
        anchorX = item.mapToItem(null, item.width / 2, 0).x;
        anchorY = item.mapToItem(null, 0, item.height / 2).y;
        screen = win?.screen ?? null;
        view = name;
        last = name;
    }
    // Right click on the bar background: the position of the bar and its settings, at the pointer (x, y in the bar window)
    function openBarMenu(win, x, y) {
        FiliTooltip.hide();
        if (view === "barmenu") {
            close();
            return;
        }
        FiliShell.popupOpened("panel");
        sources["barmenu"] = Qt.resolvedUrl("BarMenuPanel.qml");
        anchorX = x;
        anchorY = y;
        screen = win?.screen ?? null;
        view = "barmenu";
    }
    // Command `fili-shell panel NAME|toggle|close` (keyboard shortcuts): under the module of the panel
    function summon(name) {
        if (name === "toggle") {
            if (open || FiliNotification.centerOpen) {
                close();
                FiliNotification.centerOpen = false;
            } else {
                openKeyed(last);
            }
        } else if (name === "close" || view === name) {
            close();
        } else if (name in sources) {
            openKeyed(name);
        }
    }
    // Neighbouring panel (d = ±1) in bar order
    function step(d) {
        const r = ring();
        const i = r.indexOf(FiliNotification.centerOpen ? "center" : view);
        openKeyed(r[(i + d + r.length) % r.length]);
    }
    // Opening from the keyboard: under the bar module of the current screen (first screen by default), first item chosen
    function openKeyed(name) {
        FiliTooltip.hide();
        const s = screen?.name ?? Quickshell.screens[0]?.name ?? "";
        const m = (modules[s] ?? Object.values(modules)[0] ?? {})[name];
        if (name === "center") {
            close();
            FiliShell.keyNav = true;
            if (!FiliNotification.centerOpen)
                FiliNotification.toggleCenter();
            return;
        }
        FiliShell.popupOpened("panel");
        FiliShell.keyNav = true;
        anchorX = m ? m.item.mapToItem(null, m.item.width / 2, 0).x : 100000;
        anchorY = m ? m.item.mapToItem(null, 0, m.item.height / 2).y : 0;
        screen = m?.win?.screen ?? screen ?? Quickshell.screens[0] ?? null;
        view = name;
        last = name;
    }
    function close() {
        view = "";
    }
    // Next (or previous) item of the focus chain of a window, from the active item (from, read by the
    // caller: Window.activeFocusItem) or from scope
    function moveFocus(scope, from, forward) {
        FiliShell.keyNav = true;
        const next = (from ?? scope).nextItemInFocusChain(forward);
        if (next && next !== scope && next.activeFocusOnTab)
            next.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason);
    }
    // First item of the view, when opened from the keyboard
    function focusFirst(scope) {
        const first = scope.nextItemInFocusChain(true);
        if (first && first !== scope && first.activeFocusOnTab)
            first.forceActiveFocus(Qt.TabFocusReason);
    }

    Connections {
        target: FiliShell
        function onPopupOpened(who) {
            if (who !== "panel")
                panel.close();
        }
    }

    // Window the size of the card (no full-screen layer: 32 MB of image less while a panel is open).
    // Click elsewhere: niri gives the focus to another window, this one loses its own and the panel closes.
    PanelWindow {
        id: win
        visible: panel.open && !FiliTheme.testing
        screen: panel.screen
        // Beside the bar: under it (top), above it (bottom), or next to the clicked item (left, right)
        anchors {
            top: FiliTheme.barEdge !== "bottom"
            bottom: FiliTheme.barEdge === "bottom"
            left: FiliTheme.barEdge !== "right"
            right: FiliTheme.barEdge === "right"
        }
        margins.top: FiliTheme.barVertical ? Math.max(8, Math.min((panel.screen?.height ?? 0) - card.height - 8, panel.anchorY - card.height / 2)) : FiliTheme.barGap("top", FiliTheme.barHeight + 6)
        margins.bottom: FiliTheme.barGap("bottom", FiliTheme.barHeight + 6)
        margins.left: FiliTheme.barEdge === "left" ? FiliTheme.barWidth + 6 : FiliTheme.barVertical ? 0 : Math.max(8, Math.min((panel.screen?.width ?? 0) - card.width - 8, panel.anchorX - card.width / 2))
        margins.right: FiliTheme.barGap("right", FiliTheme.barWidth + 6)
        implicitWidth: card.width
        implicitHeight: card.height
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "fili-panel"
        // "Passive" view (keyboard viewer): no focus, the keystroke of wtype reaches the previous window
        WlrLayershell.keyboardFocus: panel.open && !(loader.item?.passive ?? false) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        FocusScope {
            id: scope
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: panel.close()
            Keys.onUpPressed: panel.moveFocus(scope, Window.activeFocusItem, false)
            Keys.onDownPressed: panel.moveFocus(scope, Window.activeFocusItem, true)
            Keys.onTabPressed: panel.moveFocus(scope, Window.activeFocusItem, true)
            Keys.onBacktabPressed: panel.moveFocus(scope, Window.activeFocusItem, false)
            Keys.onLeftPressed: panel.step(-1)
            Keys.onRightPressed: panel.step(1)
            // Focus received on opening then lost (click on a window): close
            property bool held: false
            Window.onActiveChanged: {
                if (Window.active)
                    held = true;
                else if (held)
                    panel.close();
            }
            Connections {
                target: panel
                function onOpenChanged() {
                    scope.held = false;
                }
            }
            Rectangle {
                id: card
                width: 340
                height: (loader.item ? loader.item.implicitHeight : 0) + 28
                color: FiliTheme.nuit
                border.color: FiliTheme.border
                border.width: FiliTheme.borderWidth
                radius: FiliTheme.radiusWindow
                Loader {
                    id: loader
                    objectName: "panel-view"
                    anchors { fill: parent; margins: FiliTheme.space5 }
                    source: panel.open ? (panel.sources[panel.view] ?? "") : ""
                    onLoaded: if (FiliShell.keyNav) Qt.callLater(() => panel.focusFirst(scope))
                }
                // Gear at the top right: opens the settings page of the view (the view declares settingsPage)
                Rectangle {
                    id: gear
                    objectName: "open-settings"
                    readonly property string page: loader.item?.settingsPage ?? ""
                    visible: page !== ""
                    anchors { top: parent.top; right: parent.right; topMargin: FiliTheme.space2; rightMargin: FiliTheme.space2 }
                    width: 24
                    height: 24
                    radius: FiliTheme.radiusControl
                    color: gearArea.containsMouse ? FiliTheme.nuit3 : "transparent"
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: FiliI18n.tr("Settings…")
                    function press(button) {
                        const p = page;
                        panel.close();
                        FiliSettings.show(p);
                    }
                    Keys.onReturnPressed: { FiliShell.keyNav = true; press(Qt.LeftButton); }
                    Keys.onEnterPressed: { FiliShell.keyNav = true; press(Qt.LeftButton); }
                    Keys.onSpacePressed: { FiliShell.keyNav = true; press(Qt.LeftButton); }
                    FocusRing {}
                    Text {
                        anchors.centerIn: parent
                        text: "\uf013"
                        color: gearArea.containsMouse ? FiliTheme.brume : FiliTheme.ardoise
                        font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                    }
                    MouseArea {
                        id: gearArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: gear.press(Qt.LeftButton)
                    }
                }
            }
        }
    }
}
