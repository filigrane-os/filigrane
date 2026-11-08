pragma Singleton
// fili-appmenu: menu of the application that has the focus, in the fili-bar (global menu, like Mac OS X).
//
// Source of the menus, in order:
// 1. the menu bar of the application, read through AT-SPI with ~/.local/bin/fili-appmenu (apps/fili-appmenu): GTK3,
// Qt, Firefox... Only the applications that export their accessibility have one; each GTK3 menu is only filled in
// when it opens (`expand`);
// 2. else a fallback menu, written by hand: ~/.config/filigrane/appmenu/APP_ID.json (dotfiles/config/filigrane/appmenu/,
// user layer included), which completes _default.json.
// In both cases: application menu (name in bold, "Quit"), own menus, Window menu (niri). They replace
// the window title in the fili-bar (AppmenuModule): all shown, or only the application name when they do not
// fit (the rest goes into a "…" title). Mouse, or keyboard: `fili-shell appmenu` (Mod+F10).
//
// Fallback file: { "name": "Chrome", "app": [ENTRY], "menus": [ { "label": "File", "children": [ENTRY] } ] }
// ENTRY = { "label", "exec": "shell command" } or { "label", "niri": ["action", "argument"] } or { "sep": true }
// or { "label", "children": [ENTRY] } (submenu). Texts in English, translated by FiliI18n; %1 = application name.
// No process stays: fili-appmenu is started when the active window changes, once per application
// without a menu (the "nothing" answer is remembered for a minute).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.bar
import qs

Singleton {
    id: am

    // Window whose menu is shown: the active window of niri, kept while the menu is open. A menu taken from the
    // keyboard receives the focus and niri then announces no active window (null): this is not a change of application.
    readonly property var niriWin: Niri.focused
    property var win: null
    onNiriWinChanged: {
        if (niriWin || !open)
            win = niriWin;
    }
    Component.onCompleted: win = niriWin
    // The fili-chat drawer has the keyboard focus: its menu (appmenu/fili-chat.json) replaces the one of the window. Kept as long as
    // a menu is open (a menu taken from the keyboard receives the focus in its place) and during a press on a title of the
    // bar: the bar does not take the keyboard, niri then gives the focus back to the previous window, and the menu would change
    // under the mouse before the click ends
    property bool chatFocus: false
    property bool holdChat: false
    readonly property bool chatNow: FiliChat.focused
    onChatNowChanged: {
        if (chatNow || !(open || holdChat))
            chatFocus = chatNow;
    }
    onOpenChanged: {
        if (!open && !holdChat && !chatNow)
            chatFocus = false;
    }
    function pressTitle() {
        if (chatFocus) {
            holdChat = true;
            holdTimer.restart();
        }
    }
    Timer {
        id: holdTimer
        interval: 1500
        onTriggered: {
            am.holdChat = false;
            if (!am.open && !am.chatNow)
                am.chatFocus = false;
        }
    }
    readonly property var winId: chatFocus ? "fili-chat" : (win ? win.id : null)
    readonly property string appId: chatFocus ? "fili-chat" : (win?.app_id ?? "")
    readonly property string dir: Quickshell.env("FILI_APPMENU_DIR") || Quickshell.env("HOME") + "/.config/filigrane/appmenu"
    readonly property string key: appId.replace(/[^A-Za-z0-9._-]/g, "_")

    // Menus shown in the bar (normalized ENTRY, see norm) and their origin: "atspi", "fallback" or ""
    property var menus: []
    property string source: ""
    // Answer of fili-appmenu awaited: nothing shown meanwhile
    property bool pending: false
    property var appMenus: []
    property var spec: ({})
    property var generic: ({})
    property var noMenu: ({})
    property int gen: 0
    readonly property string appName: spec.name ?? prettyName(appId)

    // Open menu (index in menus, -1 = closed), open menu columns, chosen entry and y of the top of
    // each column
    property int openIndex: -1
    property var levels: []
    property var sel: []
    property var levelY: []
    property real anchorX: 0
    property real anchorY: 0
    property var screen: null
    readonly property bool open: openIndex >= 0
    // Menu opened from the keyboard (fili-shell appmenu): it takes the keyboard focus, otherwise the application keeps its own
    property bool keyboard: false
    // Menu opened from "…" (the menus that no longer fit in the bar): the first column lists them
    property bool more: false
    // One AppmenuModule widget per bar (screen): titles shown (fit), "…" title (overflow)
    property var hosts: ({})
    function register(host) {
        hosts[host.bar?.screen?.name ?? ""] = host;
    }

    function prettyName(id) {
        if (!id)
            return "";
        const n = id.split(".").pop().replace(/^chrome-/, "").replace(/__.*$/, "");
        return n.charAt(0).toUpperCase() + n.slice(1);
    }

    function parse(text) {
        try {
            return JSON.parse(text) ?? {};
        } catch (e) {
            return {};
        }
    }

    // Shortcuts of the niri binds (config.kdl, then local.kdl which completes or replaces): a fallback entry that runs
    // the same command or the same action as a bind shows its key, without copying it (so it cannot drift).
    // Key: "niri:ACTION ARGS" or "exec:COMMAND" (spawn and spawn-sh, without $HOME/.local/bin/ or /usr/bin/); value: "Super+Q".
    readonly property string niriDir: Quickshell.env("FILI_NIRI_DIR") || (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/niri"
    property var bindsMain: ({})
    property var bindsLocal: ({})
    readonly property var binds: Object.assign({}, bindsMain, bindsLocal)
    onBindsChanged: rebuild()
    function parseBinds(text) {
        const out = {};
        let inBinds = false;
        for (const line of text.split("\n")) {
            if (/^binds\s*\{/.test(line)) {
                inBinds = true;
                continue;
            }
            if (inBinds && /^\}/.test(line)) {
                inBinds = false;
                continue;
            }
            if (!inBinds || /^\s*\/\//.test(line))
                continue;
            const m = /^\s*([A-Za-z0-9_+]+)\s[^{]*\{\s*([a-z0-9-]+)((?:\s+(?:"[^"]*"|[^\s";}]+))*)\s*;/.exec(line);
            if (!m)
                continue;
            const args = (m[3].match(/"[^"]*"|[^\s"]+/g) ?? []).map(a => a.replace(/^"|"$/g, ""));
            let id;
            if (m[2] === "spawn")
                id = "exec:" + args.join(" ");
            else if (m[2] === "spawn-sh")
                id = "exec:" + (args[0] ?? "").replace("$HOME/.local/bin/", "").replace(/^\/usr\/bin\//, "");
            else
                id = "niri:" + [m[2]].concat(args).join(" ");
            if (!(id in out))
                out[id] = m[1].replace(/^Mod\+/, "Super+").replace(/\+Mod\+/g, "+Super+");
        }
        return out;
    }
    FileView {
        path: am.niriDir + "/config.kdl"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: am.bindsMain = am.parseBinds(text())
        onLoadFailed: am.bindsMain = ({})
    }
    FileView {
        path: am.niriDir + "/local.kdl"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: am.bindsLocal = am.parseBinds(text())
        onLoadFailed: am.bindsLocal = ({})
    }
    // Key of a fallback entry ("keys" field of the file, else the niri bind of the same action or command)
    function bindKey(e) {
        if (e.niri)
            return binds["niri:" + e.niri.join(" ")] ?? "";
        if (e.exec)
            return binds["exec:" + e.exec] ?? "";
        return "";
    }

    // Commands of the application that are impossible now: "disabled" field of its context file
    // ($XDG_RUNTIME_DIR/fili/context/PID.json, see the filigrane-ui skill), re-read when the menu opens. A fallback entry
    // "... ctl --pid %pid action NAME" is greyed out when NAME is in it.
    property var disabled: []
    onDisabledChanged: rebuild()
    function cmdDisabled(exec) {
        const m = /\bctl\b.*\baction ([a-z-]+)/.exec(exec ?? "");
        return m !== null && disabled.indexOf(m[1]) >= 0;
    }
    function onState(text) {
        let list = [];
        try {
            list = JSON.parse(text).disabled ?? [];
        } catch (e) {
            list = [];
        }
        // Nothing changes when the list is the same (avoids rebuilding the menus at every opening)
        if (list.join(",") !== disabled.join(","))
            disabled = list;
    }
    function readState() {
        if (!win || !win.pid || source !== "fallback" || JSON.stringify(spec).indexOf("%pid") < 0) {
            if (disabled.length > 0)
                disabled = [];
            return;
        }
        stateReader.command = ["cat", (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/fili/context/" + win.pid + ".json"];
        stateReader.running = false;
        stateReader.running = true;
    }
    Process {
        id: stateReader
        stdout: StdioCollector {
            onStreamFinished: am.onState(text)
        }
    }

    // Normalized entry, whether it comes from AT-SPI or from a fallback file
    function norm(e) {
        if (e.sep || e.kind === "sep")
            return { label: "", kind: "sep", enabled: false, check: 0, keys: "", svc: "", path: "", exec: "", niri: null, children: [] };
        const kids = (e.children ?? []).map(c => norm(c)).filter(c => c.kind === "sep" || c.label !== "");
        return {
            label: e.label ?? "",
            kind: e.kind ?? (kids.length > 0 ? "sub" : "item"),
            enabled: e.enabled ?? !cmdDisabled(e.exec),
            check: e.check ?? 0,
            keys: e.keys ?? bindKey(e),
            svc: e.svc ?? "",
            path: e.path ?? "",
            exec: e.exec ?? "",
            niri: e.niri ?? null,
            children: kids
        };
    }

    // Menus of the bar: application menu, own menus (AT-SPI or fallback), Window menu
    function rebuild() {
        if ((!win && !chatFocus) || pending) {
            menus = [];
            return;
        }
        const own = source === "atspi" ? appMenus : (spec.menus ?? []).map(m => norm(m));
        // Name recomputed here: appName (binding) is not up to date yet when spec has just changed
        // The common menus (Quit, Window) act on the active window of niri: not for the drawer
        const app = norm({ label: spec.name ?? prettyName(appId), kind: "sub", children: [].concat(spec.app ?? [], chatFocus ? [] : generic.app ?? []) });
        // Common Window menu, followed by the entries of the application ("window" key of its menu file)
        const own_w = spec.window ?? [];
        const w = generic.window && !chatFocus ? [norm({ label: "Window", children: [].concat(generic.window, own_w.length > 0 ? [{ sep: true }] : [], own_w) })] : [];
        menus = [].concat(app.children.length > 0 ? [app] : [], own, w);
    }
    onSpecChanged: rebuild()
    onGenericChanged: rebuild()

    // Active window changed: menu closed, menus re-read (once the burst of niri events has passed)
    onWinIdChanged: debounce.restart()
    Timer {
        id: debounce
        interval: 100
        onTriggered: am.refresh()
    }
    function refresh() {
        gen++;
        query.running = false;
        expander.running = false;
        close();
        appMenus = [];
        source = "";
        pending = false;
        disabled = [];
        const w = chatFocus ? null : win;
        // A fallback file of the application is a deliberate choice: it takes precedence over AT-SPI (the Qt Quick
        // Controls MenuBar is there without any entry, its menus are not exported)
        if (w && w.pid && (spec.menus ?? []).length === 0 && Date.now() - (noMenu[w.app_id] ?? 0) > 60000) {
            pending = true;
            query.queryGen = gen;
            query.command = [FiliTheme.bin + "/fili-appmenu", "menu", String(w.pid), w.title ?? ""];
            query.running = true;
        } else {
            source = "fallback";
        }
        rebuild();
    }
    Process {
        id: query
        property int queryGen: -1
        stdout: StdioCollector {
            onStreamFinished: am.onMenu(query.queryGen, text)
        }
    }
    function onMenu(g, text) {
        if (g !== gen)
            return;
        const d = parse(text);
        pending = false;
        if (d.items && d.items.length > 0) {
            appMenus = d.items.map(i => norm(i)).filter(i => i.label !== "");
            source = "atspi";
        } else {
            noMenu[appId] = Date.now();
            source = "fallback";
        }
        rebuild();
    }

    // Fallback menus of the application and common menus, re-read when the file changes
    FileView {
        path: am.key !== "" ? am.dir + "/" + am.key + ".json" : ""
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: am.spec = am.parse(text())
        onLoadFailed: am.spec = ({})
    }
    FileView {
        path: am.dir + "/_default.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: am.generic = am.parse(text())
        onLoadFailed: am.generic = ({})
    }

    // ───────── Opening, navigation, action ─────────
    // Click on a title (host: the AppmenuModule of the bar). The title of index host.fit is "…" when menus overflow
    function toggle(index, item, bar, host) {
        if (openIndex === index)
            close();
        else
            openAt(index, item, bar, host);
    }
    // Menu opened with the mouse: moving over another title opens it in turn
    function hoverTitle(index, item, bar, host) {
        if (open && !keyboard && openIndex !== index)
            openAt(index, item, bar, host);
    }
    function openAt(index, item, bar, host) {
        const m = menus[index];
        if (!m)
            return;
        FiliTooltip.hide();
        FiliShell.popupOpened("appmenu");
        readState();
        anchorX = item.mapToItem(null, 0, 0).x;
        anchorY = item.mapToItem(null, 0, 0).y;
        screen = bar?.screen ?? null;
        more = host ? host.overflow && index === host.fit : false;
        openIndex = index;
        // "…": the first column is the list of the remaining menus, each opens its column
        levels = [more ? menus.slice(host.fit) : m.children];
        sel = [-1];
        levelY = [0];
        if (!more)
            fillIfLazy(0, m);
    }
    function close() {
        openIndex = -1;
        levels = [];
        sel = [];
        levelY = [];
        keyboard = false;
        more = false;
    }

    // ───────── Keyboard (fili-shell appmenu, Mod+F10): ↑/↓ entry, → submenu or next menu, ← back or previous menu,
    // Enter or Space act, Escape close ─────────
    // Command `fili-shell appmenu [toggle|close]`: opens the first menu of the bar of the current screen, from the keyboard
    function summon(action) {
        if (action === "close" || open) {
            close();
            return;
        }
        const host = hosts[Quickshell.screens[0]?.name ?? ""] ?? Object.values(hosts)[0];
        if (!host || menus.length === 0)
            return;
        const first = host.titleAt(0);
        if (!first)
            return;
        openAt(0, first, host.bar, host);
        keyboard = true;
        selectFirst(0);
    }
    // First selectable item of a column (neither separator nor greyed out), -1 if there is none
    function firstEnabled(entries) {
        return entries.findIndex(e => e.kind !== "sep" && e.enabled);
    }
    function selectFirst(level) {
        sel = sel.slice(0, level).concat([firstEnabled(levels[level] ?? [])]);
    }
    // Next (d = 1) or previous (-1) entry of the last column, wrapping around
    function keyMove(d) {
        const level = levels.length - 1;
        const es = levels[level] ?? [];
        let i = sel[level] ?? -1;
        if (i < 0)
            i = d > 0 ? -1 : 0;
        for (let n = 0; n < es.length; n++) {
            i = (i + d + es.length) % es.length;
            if (es[i].kind !== "sep" && es[i].enabled) {
                sel = sel.slice(0, level).concat([i]);
                return;
            }
        }
    }
    // y of row i of column level (the column computes it: scrolling included)
    function rowY(level, i) {
        return repeater.itemAt(level)?.rowY(i) ?? 0;
    }
    function keyRight() {
        const level = levels.length - 1;
        const e = (levels[level] ?? [])[sel[level]];
        if (e && e.kind === "sub" && e.enabled) {
            enter(level, e, sel[level], rowY(level, sel[level]));
            selectFirst(level + 1);
        } else {
            switchMenu(1);
        }
    }
    function keyLeft() {
        const level = levels.length - 1;
        if (level > 0) {
            levels = levels.slice(0, level);
            levelY = levelY.slice(0, level);
            sel = sel.slice(0, level);
        } else {
            switchMenu(-1);
        }
    }
    function keyActivate() {
        const level = levels.length - 1;
        const e = (levels[level] ?? [])[sel[level]];
        if (!e)
            return;
        if (e.kind === "sub")
            keyRight();
        else
            activate(e);
    }
    // Neighbouring title of the bar (d = ±1, "…" included, wrapping around)
    function switchMenu(d) {
        const host = hosts[screen?.name ?? ""] ?? Object.values(hosts)[0];
        const n = host ? host.fit + (host.overflow ? 1 : 0) : 0;
        if (n < 2)
            return;
        const index = (openIndex + d + n) % n;
        const title = host?.titleAt(index);
        if (!title)
            return;
        const kb = keyboard;
        openAt(index, title, host.bar, host);
        keyboard = kb;
        selectFirst(0);
    }
    // Hover or click on an entry: its submenu opens to the right, aligned with it, the following columns close
    function enter(level, entry, index, y) {
        sel = sel.slice(0, level).concat([index]);
        if (entry.kind === "sub") {
            levels = levels.slice(0, level + 1).concat([entry.children]);
            levelY = levelY.slice(0, level + 1).concat([y]);
            sel = sel.concat([-1]);
            fillIfLazy(level + 1, entry);
        } else {
            levels = levels.slice(0, level + 1);
            levelY = levelY.slice(0, level + 1);
        }
    }
    function activate(e) {
        if (!e.enabled || e.kind !== "item")
            return;
        close();
        if (e.exec) {
            // %pid: process of the window whose menu is shown (the application targeted by its control commands)
            FiliTheme.run(e.exec.replace(/%pid/g, win ? String(win.pid ?? "") : ""));
        } else if (e.niri) {
            Niri.action(...e.niri);
        } else if (e.svc) {
            const cmd = [FiliTheme.bin + "/fili-appmenu", "do", e.svc, e.path];
            if (FiliTheme.testing)
                FiliTheme.ran = FiliTheme.ran.concat([cmd.join(" ")]);
            else
                Quickshell.execDetached(cmd);
        }
    }

    // Empty AT-SPI submenu (GTK3, Firefox fill it when it opens): requested from fili-appmenu, column updated
    function fillIfLazy(depth, entry) {
        if (source !== "atspi" || entry.children.length > 0 || entry.svc === "")
            return;
        expander.running = false;
        expander.target = entry;
        expander.depth = depth;
        expander.expandGen = gen;
        expander.command = [FiliTheme.bin + "/fili-appmenu", "expand", entry.svc, entry.path];
        expander.running = true;
    }
    Process {
        id: expander
        property var target: null
        property int depth: 0
        property int expandGen: -1
        stdout: StdioCollector {
            onStreamFinished: {
                if (expander.expandGen !== am.gen || !expander.target)
                    return;
                const d = am.parse(text);
                const items = Array.isArray(d) ? d.map(i => am.norm(i)).filter(i => i.kind === "sep" || i.label !== "") : [];
                expander.target.children = items;
                // The column still waits for this submenu: it takes its content
                if (am.open && am.levels.length === expander.depth + 1) {
                    am.levels = am.levels.slice(0, expander.depth).concat([items]);
                    // Opened from the keyboard: the first item is chosen as soon as the menu is filled
                    if (am.keyboard && (am.sel[expander.depth] ?? -1) < 0)
                        am.selectFirst(expander.depth);
                }
            }
        }
    }

    Connections {
        target: FiliShell
        function onPopupOpened(who) {
            if (who !== "appmenu")
                am.close();
        }
    }

    // ───────── Windows: catch clicks next to the menu, then the menu columns ─────────
    // No keyboard focus: the application keeps its own (an action aimed at the active field, Paste for example, must
    // reach it). A click outside the menu closes it, the bar stays clickable (the catch window starts under it).
    PanelWindow {
        visible: am.open && !FiliTheme.testing
        screen: am.screen
        anchors { top: true; left: true; right: true; bottom: true }
        margins {
            top: FiliTheme.barMargin("top")
            bottom: FiliTheme.barMargin("bottom")
            left: FiliTheme.barMargin("left")
            right: FiliTheme.barMargin("right")
        }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "fili-appmenu-catcher"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: am.close()
        }
    }

    PanelWindow {
        id: menuWin
        visible: am.open && !FiliTheme.testing
        screen: am.screen
        // Beside the bar: under it (top), above it (bottom), or next to the clicked title (left, right)
        anchors {
            top: FiliTheme.barEdge !== "bottom"
            bottom: FiliTheme.barEdge === "bottom"
            left: FiliTheme.barEdge !== "right"
            right: FiliTheme.barEdge === "right"
        }
        margins.top: FiliTheme.barVertical ? Math.max(4, Math.min((am.screen?.height ?? 0) - implicitHeight - 4, am.anchorY)) : FiliTheme.barGap("top", FiliTheme.barHeight + 2)
        margins.bottom: FiliTheme.barGap("bottom", FiliTheme.barHeight + 2)
        margins.left: FiliTheme.barEdge === "left" ? FiliTheme.barWidth + 2 : FiliTheme.barVertical ? 0 : Math.max(4, Math.min((am.screen?.width ?? 0) - implicitWidth - 4, am.anchorX))
        margins.right: FiliTheme.barGap("right", FiliTheme.barWidth + 2)
        implicitWidth: Math.max(1, cards.width)
        implicitHeight: Math.max(1, cards.height)
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "fili-appmenu"
        // Opened with the mouse: no focus, the application keeps its own. From the keyboard: focus on demand
        WlrLayershell.keyboardFocus: am.open && am.keyboard ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        Item {
            id: cards
            focus: true
            Keys.onEscapePressed: am.close()
            Keys.onUpPressed: am.keyMove(-1)
            Keys.onDownPressed: am.keyMove(1)
            Keys.onLeftPressed: am.keyLeft()
            Keys.onRightPressed: am.keyRight()
            Keys.onReturnPressed: am.keyActivate()
            Keys.onEnterPressed: am.keyActivate()
            Keys.onSpacePressed: am.keyActivate()
            // Focus received on opening then lost (click on a window): close
            property bool held: false
            Window.onActiveChanged: {
                if (Window.active)
                    held = true;
                else if (held && am.keyboard)
                    am.close();
            }
            Connections {
                target: am
                function onOpenChanged() {
                    cards.held = false;
                }
            }
            readonly property int cardWidth: 290
            width: Math.max(0, am.levels.length - 1) * (cardWidth - 4) + cardWidth
            height: {
                let h = 0;
                for (let i = 0; i < repeater.count; i++) {
                    const c = repeater.itemAt(i);
                    if (c)
                        h = Math.max(h, c.y + c.height);
                }
                return h;
            }
            Repeater {
                id: repeater
                model: am.levels.length
                Rectangle {
                    id: card
                    required property int index
                    readonly property var entries: am.levels[index] ?? []
                    x: index * (cards.cardWidth - 4)
                    y: am.levelY[index] ?? 0
                    width: cards.cardWidth
                    height: Math.min(list.contentHeight, (am.screen?.height ?? 800) - (FiliTheme.barVertical ? 0 : FiliTheme.barHeight) - 40 - y) + 8
                    color: FiliTheme.nuit
                    border.color: FiliTheme.border
                    border.width: FiliTheme.borderWidth
                    radius: FiliTheme.radiusControl
                    // y (in the window) of row i: the submenu aligns on it
                    function rowY(i) {
                        const it = list.itemAtIndex(i);
                        return card.y + 4 + (it ? it.y - list.contentY : 0);
                    }
                    // Keyboard choice: the row stays visible in a long list
                    Connections {
                        target: am
                        function onSelChanged() {
                            const i = am.sel[card.index] ?? -1;
                            if (i >= 0 && am.keyboard)
                                list.positionViewAtIndex(i, ListView.Contain);
                        }
                    }
                    ListView {
                        id: list
                        anchors { fill: parent; margins: 4 }
                        model: card.entries
                        clip: true
                        interactive: contentHeight > height
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: Item {
                            id: row
                            required property var modelData
                            required property int index
                            readonly property bool sep: modelData.kind === "sep"
                            readonly property bool lit: !sep && modelData.enabled && (hover.hovered || am.sel[card.index] === index)
                            width: list.width
                            height: sep ? 9 : 22
                            Rectangle {
                                visible: row.sep
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 8; rightMargin: 8 }
                                height: 1
                                color: FiliTheme.nuit4
                            }
                            Rectangle {
                                visible: !row.sep
                                anchors.fill: parent
                                radius: FiliTheme.radiusMark
                                color: row.lit ? FiliTheme.nuit3 : "transparent"
                            }
                            Text {
                                visible: !row.sep && row.modelData.check === 2
                                x: 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: "✓"
                                color: FiliTheme.voile
                                font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList }
                            }
                            // Keyboard shortcut, right-aligned (an arrow replaces the key of a submenu)
                            Text {
                                id: keysText
                                visible: !row.sep && row.modelData.kind !== "sub" && row.modelData.keys !== ""
                                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                text: row.modelData.keys
                                color: FiliTheme.ardoise
                                font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList }
                            }
                            Text {
                                visible: !row.sep
                                x: 22
                                width: parent.width - 22 - (keysText.visible ? keysText.implicitWidth + 24 : 22)
                                anchors.verticalCenter: parent.verticalCenter
                                text: FiliI18n.tr(row.modelData.label, am.appName)
                                elide: Text.ElideRight
                                color: !row.modelData.enabled ? FiliTheme.ardoise : row.lit ? FiliTheme.voileVif : FiliTheme.brume
                                font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList }
                            }
                            Text {
                                visible: row.modelData.kind === "sub"
                                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                text: "›"
                                color: FiliTheme.ardoise
                                font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                            }
                            HoverHandler {
                                id: hover
                                enabled: !row.sep
                                onHoveredChanged: if (hovered) am.enter(card.index, row.modelData, row.index, card.y + 4 + row.y - list.contentY)
                            }
                            TapHandler {
                                enabled: !row.sep
                                onTapped: {
                                    if (row.modelData.kind === "sub")
                                        am.enter(card.index, row.modelData, row.index, card.y + 4 + row.y - list.contentY);
                                    else
                                        am.activate(row.modelData);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
