pragma Singleton
// fili-chat: the Filigrane chat, a drawer on the right edge of the screen. Mod+Y (`fili-chat toggle`, or
// `fili-shell chat toggle`) shows or hides it; the conversation stays, since it lives in the fili-chat daemon
// (apps/fili-chat) which keeps the agent and the history of each session. The drawer only connects to the daemon
// while it is open or an agent is working (the daemon stops by itself without a client or an agent).
// Keyboard: Enter sends, Shift+Enter new line, Escape hides,
// The tabs show the 20 most recent sessions; the older ones are found with the list button in the footer.
// Archiving a session: confirmation (Enter archives, Escape cancels); it stays (with its history) in "All sessions",
// button at the bottom of the tabs, with "Settings" (fili-chat.toml in the default editor).
// Ctrl+N new session, Ctrl+L shows or hides the session tabs (left column, red dot = waiting for
// an answer, green = finished and unread), Ctrl+. interrupts the agent; permission asked by the agent:
// Ctrl+Enter allows, Ctrl+Backspace denies. Mod+Y notes the active application (context chip above
// the input, attached to the next message). AI dot of the fili-bar: ASK (permission), DONE (unread answer).
// Two layouts: "dock" (default: to the right of every window, the drawer reserves its place and niri shrinks the
// windows) or "float" (above the windows, without touching them). Chosen from the View menu (state ~/.local/state/filigrane/
// chat-view, "MODE WIDTH"), defaults in ~/.config/filigrane/fili-chat.toml (mode, width).
// fili-bar menu: dotfiles/config/filigrane/appmenu/fili-chat.json (AppMenu.qml shows it when the drawer has the keyboard
// focus); its commands are `fili-shell chat ACTION` (act() below), tests/fili-shell/check-fili-chat-menu.py
// keeps the menu and act() in agreement.
// Sessions and applications (follow setting of the toml: "app" by default, "window", "off"): on opening only, never
// while the drawer is open, the session linked to the active application (context chip) is resumed, otherwise the
// last one stays. The link is created by sending a message with the context chip, or by "New Session for This
// Application" (Ctrl+Shift+N); "Unlink" removes it. Link key: app_id ("window": app_id and title).
// Daemon protocol: see apps/fili-chat/src/main.rs.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.bar

Singleton {
    id: chat
    property bool open: false
    // Session tabs (left column), Ctrl+L shows or hides them
    property bool tabsOpen: true
    property var sessions: []
    // Tabs: the 20 most recent sessions (plus the current one if it is older); the others stay
    // in "All sessions"
    readonly property int maxTabs: 20
    readonly property var tabSessions: {
        const t = sessions.slice(0, maxTabs);
        const cur = sessions.find(x => x.id === current);
        if (cur && !t.includes(cur))
            t[t.length - 1] = cur;
        return t;
    }
    // All sessions, archived ones included (list in the footer of the tabs); `sessions` only keeps the live ones
    property var allSessions: []
    // Session whose deletion awaits a confirmation; full list open
    property string confirmId: ""
    property bool allOpen: false
    // Is the agent (Claude Code) installed? Otherwise a banner offers to install it (fili-ai install claude)
    property bool agentOk: true
    function installAgent() {
        if (!FiliTheme.testing)
            Quickshell.execDetached(["foot", "--hold", "-e", "fili-ai", "install", "claude"]);
    }
    Timer {
        interval: 2000
        repeat: true
        running: chat.open && !chat.agentOk && chat.linked
        onTriggered: chat.send_({ op: "agent" })
    }
    property string current: ""
    // Items of each open session (id -> [{kind: user|assistant|tool|error|note, text, name}]); replaced at every change
    property var items: ({})
    property var states: ({})
    // Agent text being written (current session)
    property string live: ""
    // Message typed before the session exists
    property string pending: ""
    readonly property var log: items[current] ?? []
    // Turn in progress (the agent works or waits for a permission)
    readonly property bool working: (states[current] ?? "idle") !== "idle"
    readonly property bool busy: Object.keys(states).some(k => states[k] !== "idle")
    // Sessions finished without the drawer having shown them (id -> true)
    property var unread: ({})
    // For the dot of the fili-bar: "waiting" (permission asked), "done" (unread answer) or ""
    readonly property string attention: Object.keys(states).some(k => states[k] === "waiting") ? "waiting" : Object.keys(unread).length ? "done" : ""
    // Active application noted by Mod+Y ({window: {app_id, title}, ...}) and attached to the next message if ctxOn
    property var ctx: null
    property bool ctxOn: false
    // Messages written during a turn, kept by the daemon and sent at the end of the turn: { id: [text] }
    property var queued: ({})
    readonly property var queuedNow: queued[current] ?? []
    // Files attached to the next message (absolute paths): dragged onto the drawer or pasted (Ctrl+V)
    property var attached: []
    function attach(paths) {
        const a = attached.slice();
        for (const p of paths)
            if (p && a.indexOf(p) < 0)
                a.push(p);
        attached = a;
        focusInput();
    }
    function attachUrls(urls) {
        attach(urls.map(u => decodeURIComponent(String(u).replace(/^file:\/\//, ""))).filter(p => p.startsWith("/")));
    }
    function detach(p) {
        attached = attached.filter(x => x !== p);
    }
    readonly property string ctxLabel: ctx ? [ctx.window?.app_id, ctx.window?.title].filter(x => x).join(" · ") : ""
    readonly property string ctxFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/filigrane/context.json"
    readonly property string title: sessions.find(s => s.id === current)?.title || FiliI18n.tr("New session")
    readonly property bool linked: link.connected
    readonly property string sock: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/fili-chat/sock"
    property int tries: 0
    // The drawer has the keyboard focus (sets FocusScope): AppMenu then shows its menu
    property bool focused: false
    // Layout: choice of the user (state), else setting (toml), else docked
    property string cfgMode: ""
    property int cfgWidth: 0
    property string cfgFollow: ""
    readonly property string follow: cfgFollow || "app"
    // Resuming the linked session: waits for the context (ctxRead) and the fresh session list, once per opening
    property bool followPending: false
    property bool ctxReady: false
    property bool sessionsFresh: false
    // Link key to set on the session about to be created
    property string pendingLink: ""
    property string stMode: ""
    property int stWidth: 0
    readonly property string mode: stMode || cfgMode || "dock"
    readonly property bool dock: mode === "dock"
    readonly property int viewWidth: stWidth || cfgWidth || 440
    readonly property string viewFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/filigrane/chat-view"
    readonly property string cfgFile: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/filigrane/fili-chat.toml"
    // Renaming of the current session in the header
    property bool renaming: false

    function show() {
        FiliShell.popupOpened("chat");
        FiliPanel.close();
        // Freshly opened: the session of the active application can be resumed (tryFollow)
        if (!open) {
            followPending = true;
            ctxReady = false;
            sessionsFresh = link.connected;
        }
        open = true;
        markRead();
        if (!FiliTheme.testing) {
            ctxRead.running = false;
            ctxRead.running = true;
        }
        focusInput();
    }
    // Key of the session <-> application link for a context ({window: {app_id, title}}); "" without an application.
    // force: even with follow = "off" (link requested by hand)
    function linkKey(c, force) {
        const id = c?.window?.app_id;
        if (!id || (follow === "off" && !force))
            return "";
        return follow === "window" ? id + "\n" + (c.window.title ?? "") : id;
    }
    function tryFollow() {
        if (!followPending || !ctxReady || !sessionsFresh)
            return;
        followPending = false;
        const key = linkKey(ctx);
        // A turn in progress (or a permission to give) stays in sight
        if (!key || working)
            return;
        const s = sessions.find(x => x.link === key);
        if (s && s.id !== current)
            openSession(s.id);
    }
    function markRead() {
        if (!unread[current])
            return;
        const u = Object.assign({}, unread);
        delete u[current];
        unread = u;
    }
    function hide() {
        open = false;
    }
    function toggle() {
        if (open)
            hide();
        else
            show();
    }
    signal focusInput

    // ───── layout ─────
    // Settings: "key = value" lines (# comments ignored), quoted values possible
    function parseKV(t) {
        const o = {};
        for (const l of t.split("\n")) {
            const m = l.match(/^\s*([A-Za-z_]+)\s*=\s*"?([^"#\n]*?)"?\s*(#.*)?$/);
            if (m)
                o[m[1]] = m[2];
        }
        return o;
    }
    FileView {
        path: chat.cfgFile
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const c = chat.parseKV(text());
            chat.cfgMode = c.mode === "dock" || c.mode === "float" ? c.mode : "";
            const w = parseInt(c.width) || 0;
            chat.cfgWidth = w ? Math.min(900, Math.max(300, w)) : 0;
            chat.cfgFollow = ["app", "window", "off"].includes(c.follow) ? c.follow : "";
        }
        onLoadFailed: { chat.cfgMode = ""; chat.cfgWidth = 0; chat.cfgFollow = ""; }
    }
    FileView {
        path: chat.viewFile
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const p = text().trim().split(" ");
            chat.stMode = p[0] === "dock" || p[0] === "float" ? p[0] : "";
            chat.stWidth = parseInt(p[1]) || 0;
        }
        onLoadFailed: { chat.stMode = ""; chat.stWidth = 0; }
    }
    function saveView() {
        if (FiliTheme.testing) {
            FiliTheme.ran = FiliTheme.ran.concat(["chat-view " + mode + " " + viewWidth]);
            return;
        }
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "${1%/*}" && printf "%s %s\\n" "$2" "$3" > "$1"', "sh", viewFile, mode, String(viewWidth)]);
    }
    function setMode(m) {
        stMode = m;
        stWidth = viewWidth;
        saveView();
    }
    function setWidth(w) {
        stMode = mode;
        stWidth = w;
        saveView();
    }
    function startRename() {
        if (!current)
            return;
        renaming = true;
    }
    function commitRename(t) {
        renaming = false;
        const title = t.trim();
        if (title && current && title !== (sessions.find(s => s.id === current)?.title ?? ""))
            send_({ op: "rename", id: current, title });
        focusInput();
    }

    // Commands of the fili-bar menu and of the `fili-shell chat ACTION` channel
    function act(a, args) {
        switch (a) {
        case "open": show(); if (args && args[0]) openSession(args[0]); break;
        case "toggle": toggle(); break;
        case "about": FiliChatAbout.show(); break;
        case "show": show(); break;
        case "close": hide(); break;
        case "new": show(); newSession(); break;
        case "new-here": show(); pendingLink = linkKey(ctx, true); newSession(); break;
        case "unlink": if (current) send_({ op: "link", id: current, key: "" }); break;
        case "sessions": show(); tabsOpen = !tabsOpen; break;
        case "rename": show(); startRename(); break;
        case "stop": stop(); break;
        case "archive": show(); askArchive(current); break;
        case "allow": answerFirst(true); break;
        case "deny": answerFirst(false); break;
        case "drop-context": ctxOn = false; break;
        case "float": setMode("float"); break;
        case "dock": setMode("dock"); break;
        case "width-narrow": setWidth(360); break;
        case "width-medium": setWidth(440); break;
        case "width-wide": setWidth(560); break;
        }
    }
    onWorkingChanged: if (!working) focusInput()

    // ───── daemon ─────
    function ensure() {
        if (FiliTheme.testing || link.connected)
            return;
        // The binary is shipped by the fili-apps package (/usr/bin); FiliTheme.bin first (tests, local builds)
        Quickshell.execDetached(["sh", "-c", 'for d in "$1" /usr/bin; do [ -x "$d/fili-chat" ] && exec "$d/fili-chat" daemon; done', "sh", FiliTheme.bin]);
        tries = 0;
        retry.start();
    }
    readonly property bool wantLink: open || busy
    onWantLinkChanged: {
        if (wantLink) {
            ensure();
        } else {
            retry.stop();
            link.connected = false;
        }
    }
    Timer {
        id: retry
        interval: 250
        repeat: true
        onTriggered: {
            if (link.connected || !chat.wantLink || ++chat.tries > 20) {
                stop();
                return;
            }
            link.connected = false;
            link.connected = true;
        }
    }
    // Ctrl+V: files (text/uri-list) attached; an image (screenshot, "copy image") is saved in
    // ~/.local/state/filigrane/chat/images then attached; the agent reads it like a file. Text is pasted normally
    Process {
        id: pasteFiles
        command: ["sh", "-c", 't="$(wl-paste -l 2>/dev/null)"; if printf "%s\\n" "$t" | grep -qx text/uri-list; then wl-paste -t text/uri-list 2>/dev/null; elif m="$(printf "%s\\n" "$t" | grep -x -m1 image/png || printf "%s\\n" "$t" | grep -m1 "^image/[a-z]*$")" && [ -n "$m" ]; then d="${XDG_STATE_HOME:-$HOME/.local/state}/filigrane/chat/images"; mkdir -p "$d"; f="$d/image-$(date +%Y%m%d-%H%M%S).${m#image/}"; wl-paste -t "$m" > "$f" 2>/dev/null && [ -s "$f" ] && echo "file://$f"; fi']
        stdout: StdioCollector {
            onStreamFinished: chat.attachUrls(text.split("\n").map(l => l.trim()).filter(l => l.startsWith("file://")))
        }
    }
    // Context noted by `fili-chat toggle` just before opening
    Process {
        id: ctxRead
        command: ["cat", chat.ctxFile]
        stdout: StdioCollector {
            onStreamFinished: {
                let c = null;
                try {
                    c = JSON.parse(text);
                } catch (e) {}
                chat.ctx = c && c.window && c.window.app_id ? c : null;
                chat.ctxOn = chat.ctx !== null;
                chat.ctxReady = true;
                chat.tryFollow();
            }
        }
    }
    Socket {
        id: link
        path: chat.sock
        onConnectedChanged: {
            if (connected) {
                retry.stop();
                if (chat.current)
                    chat.send_({ op: "open", id: chat.current });
            } else if (chat.wantLink) {
                // Daemon stopped while it is awaited: restarted
                chat.ensure();
            }
        }
        parser: SplitParser {
            onRead: line => {
                try {
                    chat.receive(JSON.parse(line));
                } catch (e) {}
            }
        }
    }
    function send_(obj) {
        if (FiliTheme.testing) {
            FiliTheme.ran = FiliTheme.ran.concat(["chat " + JSON.stringify(obj)]);
            return;
        }
        if (!link.connected)
            return;
        link.write(JSON.stringify(obj) + "\n");
        link.flush();
    }

    // ───── actions ─────
    function newSession() {
        followPending = false;
        send_({ op: "new" });
    }
    function openSession(id) {
        followPending = false;
        if (id === current)
            return;
        current = id;
        live = "";
        markRead();
        send_({ op: "open", id });
        focusInput();
    }
    function archiveSession(id) {
        send_({ op: "archive", id });
    }
    // Deletion: asks for confirmation first (the session and its history stay in "All sessions")
    function askArchive(id) {
        if (!id || !sessions.some(s => s.id === id))
            return;
        allOpen = false;
        confirmId = id;
    }
    function confirmArchive(yes) {
        const id = confirmId;
        confirmId = "";
        if (yes && id)
            archiveSession(id);
        focusInput();
    }
    // Full list: an archived session is restored then opened
    function pickSession(id) {
        allOpen = false;
        if (allSessions.find(s => s.id === id)?.archived)
            send_({ op: "restore", id });
        openSession(id);
    }
    // Settings: the configuration file in the default editor
    function openSettings() {
        if (!FiliTheme.testing)
            Quickshell.execDetached(["xdg-open", Quickshell.env("HOME") + "/.config/filigrane/fili-chat.toml"]);
    }
    function send(text) {
        let t = text.trim();
        if (!t && !attached.length)
            return;
        if (attached.length) {
            t = (t || FiliI18n.tr("Here are some files.")) + "\n\n" + FiliI18n.tr("Attached files:") + "\n" + attached.join("\n");
            attached = [];
        }
        followPending = false;
        if (!current) {
            pending = t;
            if (ctxOn && !pendingLink)
                pendingLink = linkKey(ctx);
            send_({ op: "new" });
            return;
        }
        // First conversation with an application: the session links to it
        const cur = sessions.find(x => x.id === current);
        if (ctxOn && cur && !cur.link && linkKey(ctx))
            send_({ op: "link", id: current, key: linkKey(ctx) });
        const req = { op: "send", id: current, text: t };
        if (ctxOn)
            req.context = true;
        ctxOn = false;
        send_(req);
    }
    // Answer to the first pending permission of the current session
    function answer(rid, allow) {
        send_({ op: "answer", rid, allow });
    }
    function answerFirst(allow) {
        const a = log.find(i => i.kind === "ask" && i.status === "pending");
        if (a)
            answer(a.rid, allow);
    }
    function stop() {
        if (current)
            send_({ op: "stop", id: current });
    }

    // ───── daemon events ─────
    function append(id, item) {
        if (items[id] === undefined)
            return;
        const m = Object.assign({}, items);
        m[id] = items[id].concat([item]);
        items = m;
    }
    function setState(id, st) {
        const was = states[id] ?? "idle";
        const m = Object.assign({}, states);
        m[id] = st;
        states = m;
        if (st === "idle" && id === current)
            live = "";
        // Turn finished out of sight of the drawer: to read
        if (st === "idle" && was !== "idle" && !(open && id === current)) {
            const u = Object.assign({}, unread);
            u[id] = true;
            unread = u;
            notify(id, FiliI18n.tr("Rob has finished"), "normal");
        } else if (st === "waiting" && was !== "waiting" && !(open && id === current)) {
            notify(id, FiliI18n.tr("Rob needs you"), "critical");
        }
    }
    // Notification of a session out of sight of the drawer; its "Open" button (or a click) shows the drawer on it
    function notify(id, summary, urgency) {
        if (FiliTheme.testing) {
            FiliTheme.ran = FiliTheme.ran.concat(["notify " + id + " " + summary]);
            return;
        }
        const title = sessions.find(s => s.id === id)?.title || "Rob";
        Quickshell.execDetached(["setsid", "-f", "sh", "-c",
            'r="$(notify-send -a fili-chat -i fili-chat -u "$2" -A default="$5" "$3" "$4")" && [ "$r" = default ] && exec "$0" chat open "$1"',
            FiliTheme.bin + "/fili-shell", id, urgency, summary, title, FiliI18n.tr("Open")]);
    }
    function askItem(ev) {
        return { kind: "ask", rid: ev.rid, name: ev.tool, text: ev.summary, status: ev.status };
    }
    function item(ev) {
        if (ev.ev === "ask")
            return askItem(ev);
        const text = ev.ev === "tool" ? ev.summary : ev.role === "error" ? FiliI18n.tr(ev.text) : ev.text;
        return { kind: ev.ev === "tool" ? "tool" : ev.role, text, name: ev.name ?? "" };
    }
    function receive(ev) {
        if (ev.ev === "agent") {
            agentOk = ev.ok === true;
        } else if (ev.ev === "sessions") {
            allSessions = ev.sessions;
            sessions = ev.sessions.filter(s => !s.archived);
            if (confirmId && !sessions.some(s => s.id === confirmId))
                confirmId = "";
            sessionsFresh = true;
            const m = Object.assign({}, states);
            for (const s of sessions)
                m[s.id] = s.state;
            states = m;
            if (!sessions.some(s => s.id === current)) {
                current = pending ? current : (sessions[0]?.id ?? "");
                if (current && items[current] === undefined)
                    send_({ op: "open", id: current });
            }
            tryFollow();
        } else if (ev.ev === "created") {
            const m = Object.assign({}, items);
            m[ev.id] = [];
            items = m;
            current = ev.id;
            live = "";
            if (pendingLink) {
                send_({ op: "link", id: ev.id, key: pendingLink });
                pendingLink = "";
            }
            if (pending) {
                const t = pending;
                pending = "";
                const req = { op: "send", id: ev.id, text: t };
                if (ctxOn)
                    req.context = true;
                ctxOn = false;
                send_(req);
            }
        } else if (ev.ev === "queue") {
            const q = Object.assign({}, queued);
            q[ev.id] = ev.items;
            queued = q;
        } else if (ev.ev === "history") {
            const m = Object.assign({}, items);
            m[ev.id] = ev.items.map(item);
            items = m;
        } else if (ev.ev === "msg" || ev.ev === "tool") {
            append(ev.id, item(ev));
            if (ev.role === "assistant" && ev.id === current)
                live = "";
        } else if (ev.ev === "ask") {
            // Permission request: the same request is updated when it is settled
            if (items[ev.id] === undefined)
                return;
            const a = items[ev.id].slice();
            const i = a.findIndex(x => x.kind === "ask" && x.rid === ev.rid);
            if (i >= 0)
                a[i] = askItem(ev);
            else
                a.push(askItem(ev));
            const m = Object.assign({}, items);
            m[ev.id] = a;
            items = m;
        } else if (ev.ev === "delta") {
            if (ev.id === current)
                live += ev.text;
        } else if (ev.ev === "state") {
            setState(ev.id, ev.state);
        } else if (ev.ev === "note") {
            append(ev.id, { kind: "note", text: FiliI18n.tr(ev.code === "interrupted" ? "Interrupted" : ev.code), name: "" });
        }
    }

    Connections {
        target: FiliShell
        function onPopupOpened(who) {
            // Docked, the drawer stays (like a sidebar); floating, it makes way for the bar panels
            if (who !== "chat" && who !== "chat-about" && who !== "" && !chat.dock)
                chat.hide();
        }
    }

    PanelWindow {
        id: win
        visible: chat.open && !FiliTheme.testing
        anchors { top: true; bottom: true; right: true }
        margins.top: FiliTheme.barHeight
        implicitWidth: chat.viewWidth
        // Docked: the place is reserved (windows shrink); floating: above, without reserving
        exclusionMode: chat.dock ? ExclusionMode.Normal : ExclusionMode.Ignore
        exclusiveZone: chat.dock ? chat.viewWidth : 0
        WlrLayershell.layer: chat.dock ? WlrLayer.Top : WlrLayer.Overlay
        WlrLayershell.namespace: "fili-chat"
        WlrLayershell.keyboardFocus: chat.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        FocusScope {
            anchors.fill: parent
            focus: true
            onActiveFocusChanged: chat.focused = activeFocus
            Keys.onEscapePressed: chat.confirmId ? chat.confirmArchive(false) : chat.allOpen ? chat.allOpen = false : chat.hide()
            Keys.onPressed: e => {
                if (e.key === Qt.Key_F2) {
                    chat.startRename();
                    e.accepted = true;
                } else if (e.modifiers & Qt.ControlModifier) {
                    if (e.key === Qt.Key_N && (e.modifiers & Qt.ShiftModifier))
                        chat.act("new-here");
                    else if (e.key === Qt.Key_N)
                        chat.newSession();
                    else if (e.key === Qt.Key_L)
                        chat.tabsOpen = !chat.tabsOpen;
                    else if (e.key === Qt.Key_Period)
                        chat.stop();
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter)
                        chat.answerFirst(true);
                    else if (e.key === Qt.Key_Backspace)
                        chat.answerFirst(false);
                    else
                        return;
                    e.accepted = true;
                }
            }

            Rectangle {
                id: drawer
                anchors.fill: parent
                anchors.margins: FiliTheme.space1
                color: FiliTheme.nuit
                border { color: FiliTheme.border; width: FiliTheme.borderWidth }
                radius: FiliTheme.radiusWindow
                clip: true
                // Tooltip of a session tab (full title and linked application)
                property string tipId: ""
                property string tipText: ""
                property real tipY: 0

                // Files dragged from an application: attached to the next message
                DropArea {
                    anchors.fill: parent
                    keys: ["text/uri-list"]
                    onDropped: d => {
                        if (d.hasUrls)
                            chat.attachUrls(d.urls);
                    }
                }

                // Vertical session tabs: red dot (cendre) = the agent waits for an answer, green (sauge) =
                // finished, to read, voile = working
                Rectangle {
                    id: rail
                    visible: chat.tabsOpen
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 1 }
                    width: visible ? 52 : 0
                    color: FiliTheme.nuit2
                    // Left corners rounded like those of the drawer (the right edge stays straight)
                    radius: FiliTheme.radiusWindow - 1
                    Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: parent.radius; color: parent.color }
                    Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: 1; color: FiliTheme.nuit4 }
                    ListView {
                        id: list
                        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: foot.top; rightMargin: 1 }
                        topMargin: FiliTheme.space2
                        model: chat.tabSessions
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true
                        delegate: Rectangle {
                            id: srow
                            required property var modelData
                            readonly property string st: chat.states[modelData.id] ?? modelData.state ?? "idle"
                            width: list.width
                            height: 48
                            color: modelData.id === chat.current ? FiliTheme.nuit3 : (rowHit.containsMouse ? FiliTheme.nuit3 : "transparent")
                            // Icon of the application linked to the session; without a link (or without an icon): speech bubble
                            readonly property string appKey: (modelData.link ?? "").split("\n")[0]
                            readonly property string appIcon: appKey === "" ? "" : (Quickshell.iconPath(appKey, true) || Quickshell.iconPath(appKey.toLowerCase(), true))
                            readonly property int topic: modelData.icon ?? 0
                            Image {
                                id: appImg
                                anchors.centerIn: parent
                                width: 28
                                height: 28
                                visible: srow.topic === 0 && srow.appIcon !== ""
                                source: srow.appIcon
                                sourceSize: Qt.size(56, 56)
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: srow.topic !== 0 || srow.appIcon === ""
                                text: String.fromCodePoint(srow.topic !== 0 ? srow.topic : 0xF05A3)
                                color: modelData.id === chat.current ? FiliTheme.brume : FiliTheme.brume2
                                font { family: "Fili Icons"; pixelSize: 24 }
                            }
                            // Status dot at the corner: red = waiting, voile = working, green = finished unread
                            Rectangle {
                                id: dot
                                anchors { right: parent.right; rightMargin: FiliTheme.space2; top: parent.top; topMargin: FiliTheme.space2 }
                                width: 10
                                height: 10
                                radius: 5
                                visible: color.a > 0
                                color: srow.st === "waiting" ? FiliTheme.cendre : srow.st !== "idle" ? FiliTheme.voile : chat.unread[modelData.id] ? FiliTheme.sauge : "transparent"
                                border { width: 2; color: FiliTheme.nuit2 }
                            }
                            MouseArea {
                                id: rowHit
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: chat.openSession(srow.modelData.id)
                                onContainsMouseChanged: {
                                    if (containsMouse)
                                        tipDelay.restart();
                                    else {
                                        tipDelay.stop();
                                        if (drawer.tipId === srow.modelData.id)
                                            drawer.tipId = "";
                                    }
                                }
                            }
                            Timer {
                                id: tipDelay
                                interval: 350
                                onTriggered: {
                                    drawer.tipText = (srow.modelData.title || FiliI18n.tr("New session")) + ((srow.modelData.link ?? "") !== "" ? "\n" + srow.modelData.link.split("\n")[0] : "");
                                    drawer.tipY = srow.mapToItem(drawer, 0, 0).y;
                                    drawer.tipId = srow.modelData.id;
                                }
                            }
                            Text {
                                anchors { left: parent.left; leftMargin: FiliTheme.space1 + 2; top: parent.top; topMargin: 0 }
                                visible: rowHit.containsMouse || delHit.containsMouse
                                text: "×"
                                color: delHit.containsMouse ? FiliTheme.cendre : FiliTheme.ardoise
                                font { family: FiliTheme.font; pixelSize: 16 }
                                MouseArea {
                                    id: delHit
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: chat.askArchive(srow.modelData.id)
                                }
                            }
                        }
                    }
                    // Footer of the tabs: all sessions (archived included) and settings
                    Column {
                        id: foot
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; rightMargin: 1 }
                        Rectangle { width: parent.width; height: 1; color: FiliTheme.nuit4 }
                        Repeater {
                            model: [
                                { glyph: 0xF2F00, tip: "All sessions", act: "all" },
                                { glyph: 0xF2F01, tip: "Settings…", act: "settings" }
                            ]
                            delegate: Rectangle {
                                id: fbtn
                                required property var modelData
                                width: foot.width
                                height: 40
                                color: fHit.containsMouse || (modelData.act === "all" && chat.allOpen) ? FiliTheme.nuit3 : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: String.fromCodePoint(fbtn.modelData.glyph)
                                    color: FiliTheme.brume2
                                    font { family: "Fili Icons"; pixelSize: 22 }
                                }
                                MouseArea {
                                    id: fHit
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (fbtn.modelData.act === "all") {
                                            chat.confirmId = "";
                                            chat.allOpen = !chat.allOpen;
                                        } else
                                            chat.openSettings();
                                    }
                                    onContainsMouseChanged: {
                                        if (containsMouse) {
                                            drawer.tipText = FiliI18n.tr(fbtn.modelData.tip);
                                            drawer.tipY = fbtn.mapToItem(drawer, 0, 0).y;
                                            drawer.tipId = "foot" + fbtn.modelData.act;
                                        } else if (drawer.tipId === "foot" + fbtn.modelData.act)
                                            drawer.tipId = "";
                                    }
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    anchors { left: rail.right; right: parent.right; top: parent.top; bottom: parent.bottom }
                    spacing: 0

                    // Header: current session (list), new session, hide
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        Layout.leftMargin: FiliTheme.space3
                        Layout.rightMargin: FiliTheme.space2
                        spacing: FiliTheme.space2
                        Rectangle {
                            Layout.preferredWidth: 8
                            Layout.preferredHeight: 8
                            radius: 4
                            color: chat.working ? FiliTheme.voile : FiliTheme.ardoise
                        }
                        // Session title: click or F2 = rename (double click)
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 24
                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: !chat.renaming
                                text: chat.title
                                elide: Text.ElideRight
                                color: FiliTheme.brume
                                font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: chat.tabsOpen = !chat.tabsOpen
                                    onDoubleClicked: chat.startRename()
                                }
                            }
                            TextInput {
                                id: renameInput
                                anchors.fill: parent
                                verticalAlignment: TextInput.AlignVCenter
                                visible: chat.renaming
                                clip: true
                                color: FiliTheme.brume
                                selectionColor: FiliTheme.voile
                                selectedTextColor: FiliTheme.nuit
                                font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
                                onVisibleChanged: if (visible) {
                                    text = chat.sessions.find(s => s.id === chat.current)?.title ?? "";
                                    forceActiveFocus();
                                    selectAll();
                                }
                                onAccepted: chat.commitRename(text)
                                Keys.onEscapePressed: { chat.renaming = false; chat.focusInput(); }
                                onActiveFocusChanged: if (!activeFocus && chat.renaming) chat.renaming = false
                            }
                        }
                        Repeater {
                            model: [{ t: "+", tip: "New session", act: 0 }, { t: "×", tip: "Hide", act: 1 }]
                            Text {
                                required property var modelData
                                Layout.preferredWidth: 28
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.t
                                color: hit.containsMouse ? FiliTheme.brume : FiliTheme.brume2
                                font { family: FiliTheme.font; pixelSize: 20 }
                                MouseArea {
                                    id: hit
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: modelData.act === 0 ? chat.newSession() : chat.hide()
                                }
                            }
                        }
                    }
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: FiliTheme.nuit4 }

                    // Fil de la conversation
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ListView {
                            id: thread
                            anchors.fill: parent
                            model: chat.log
                            spacing: FiliTheme.space3
                            topMargin: FiliTheme.space3
                            bottomMargin: FiliTheme.space3
                            boundsBehavior: Flickable.StopAtBounds
                            clip: true
                            // The thread follows the end as long as one has not scrolled up to read
                            property bool follow: true
                            onMovementEnded: follow = atYEnd
                            onCountChanged: if (follow) Qt.callLater(positionViewAtEnd)
                            KineticScroll {}
                            Connections {
                                target: chat
                                function onLiveChanged() { if (thread.follow) Qt.callLater(thread.positionViewAtEnd); }
                                function onCurrentChanged() { thread.follow = true; Qt.callLater(thread.positionViewAtEnd); }
                            }
                            delegate: Item {
                                id: row
                                required property var modelData
                                width: thread.width
                                implicitHeight: isAsk ? askCard.height : body.implicitHeight + (isUser ? 16 : 0)
                                readonly property bool isAsk: modelData.kind === "ask"
                                readonly property bool isUser: modelData.kind === "user"
                                readonly property bool isTool: modelData.kind === "tool"
                                Rectangle {
                                    visible: row.isUser
                                    anchors { right: parent.right; rightMargin: FiliTheme.space3 }
                                    width: Math.min(parent.width * 0.85, body.implicitWidth + 20)
                                    height: parent.height
                                    radius: FiliTheme.radiusControl
                                    color: FiliTheme.nuit3
                                }
                                // Permission asked by the agent
                                Rectangle {
                                    id: askCard
                                    visible: row.isAsk
                                    x: FiliTheme.space3
                                    width: parent.width - 2 * FiliTheme.space3
                                    height: askCol.implicitHeight + 2 * FiliTheme.space2
                                    radius: FiliTheme.radiusControl
                                    color: FiliTheme.nuit2
                                    border { width: 1; color: row.modelData.status === "pending" ? FiliTheme.sable : FiliTheme.nuit4 }
                                    ColumnLayout {
                                        id: askCol
                                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: FiliTheme.space2 }
                                        spacing: FiliTheme.space2
                                        Text {
                                            Layout.fillWidth: true
                                            text: ({ pending: FiliI18n.tr("Allow %1?", row.modelData.name), allowed: FiliI18n.tr("%1 allowed", row.modelData.name), denied: FiliI18n.tr("%1 denied", row.modelData.name) })[row.modelData.status] ?? FiliI18n.tr("%1 cancelled", row.modelData.name)
                                            color: row.modelData.status === "pending" ? FiliTheme.sable : row.modelData.status === "denied" ? FiliTheme.cendre : FiliTheme.brume2
                                            font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            visible: text !== ""
                                            text: row.modelData.text
                                            wrapMode: Text.WrapAnywhere
                                            maximumLineCount: 6
                                            elide: Text.ElideRight
                                            color: FiliTheme.brume
                                            font { family: FiliTheme.mono; pixelSize: FiliTheme.sizeSmall }
                                        }
                                        RowLayout {
                                            visible: row.modelData.status === "pending"
                                            spacing: FiliTheme.space2
                                            Repeater {
                                                model: [{ label: "Allow", allow: true }, { label: "Deny", allow: false }]
                                                Rectangle {
                                                    required property var modelData
                                                    Layout.preferredWidth: 84
                                                    Layout.preferredHeight: 26
                                                    radius: FiliTheme.radiusControl
                                                    color: modelData.allow ? FiliTheme.voile : FiliTheme.nuit3
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: FiliI18n.tr(parent.modelData.label)
                                                        color: parent.modelData.allow ? FiliTheme.nuit : FiliTheme.brume
                                                        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: chat.answer(row.modelData.rid, parent.modelData.allow)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                TextEdit {
                                    id: body
                                    visible: !row.isAsk
                                    x: row.isUser ? parent.width - width - FiliTheme.space3 - 10 : FiliTheme.space3
                                    y: row.isUser ? 8 : 0
                                    width: row.isUser ? Math.min(parent.width * 0.85 - 20, implicitWidth) : parent.width - 2 * FiliTheme.space3
                                    readOnly: true
                                    selectByMouse: true
                                    wrapMode: TextEdit.Wrap
                                    textFormat: row.isTool || row.isUser || modelData.kind !== "assistant" ? TextEdit.PlainText : TextEdit.MarkdownText
                                    text: row.isTool ? "▸ " + modelData.name + "  " + modelData.text : modelData.text
                                    color: modelData.kind === "error" ? FiliTheme.cendre : (row.isTool || modelData.kind === "note") ? FiliTheme.ardoise : FiliTheme.brume
                                    selectionColor: FiliTheme.voile
                                    selectedTextColor: FiliTheme.nuit
                                    font {
                                        family: row.isTool ? FiliTheme.mono : FiliTheme.font
                                        pixelSize: row.isTool ? FiliTheme.sizeSmall : FiliTheme.size
                                        italic: modelData.kind === "note"
                                    }
                                    onLinkActivated: link => Qt.openUrlExternally(link)
                                }
                            }
                            footer: Item {
                                width: thread.width
                                implicitHeight: (chat.live || chat.working ? liveText.implicitHeight + FiliTheme.space3 : 0) + (chat.working ? 24 : 0)
                                visible: chat.live !== "" || chat.working
                                TextEdit {
                                    id: liveText
                                    x: FiliTheme.space3
                                    y: FiliTheme.space3
                                    width: parent.width - 2 * FiliTheme.space3
                                    height: chat.live ? implicitHeight : 0
                                    readOnly: true
                                    wrapMode: TextEdit.Wrap
                                    textFormat: TextEdit.PlainText
                                    text: chat.live
                                    color: FiliTheme.brume
                                    font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                                }
                                Text {
                                    visible: chat.working
                                    anchors { left: parent.left; leftMargin: FiliTheme.space3; bottom: parent.bottom }
                                    text: FiliI18n.tr((chat.states[chat.current] ?? "") === "waiting" ? "Waiting for your answer…" : "Working…") + "  "
                                    color: FiliTheme.ardoise
                                    font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                                    Text {
                                        anchors { left: parent.right; baseline: parent.baseline }
                                        text: FiliI18n.tr("Stop")
                                        color: FiliTheme.voile
                                        font: parent.font
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: chat.stop()
                                        }
                                    }
                                }
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: chat.log.length === 0 && !chat.working
                                text: FiliI18n.tr("Ask anything about this machine or Filigrane.")
                                color: FiliTheme.ardoise
                                font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                            }
                        }
                        FiliScrollBar {
                            view: thread
                            anchors { right: thread.right; top: thread.top; bottom: thread.bottom }
                            onReleased: thread.follow = thread.atYEnd
                        }
                        // Scroll back down to the bottom of the discussion (visible only when scrolled up)
                        Rectangle {
                            id: toEnd
                            objectName: "chat-to-end"
                            visible: chat.log.length > 0 && (!thread.atYEnd || !thread.follow)
                            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: FiliTheme.space3 }
                            width: 28
                            height: 28
                            radius: 14
                            color: toEndHit.containsMouse ? FiliTheme.nuit4 : FiliTheme.nuit3
                            border { width: 1; color: FiliTheme.nuit4 }
                            Text {
                                anchors.centerIn: parent
                                text: "↓"
                                color: FiliTheme.voile
                                font { family: FiliTheme.font; pixelSize: 16; weight: FiliTheme.weightAccent }
                            }
                            MouseArea {
                                id: toEndHit
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    thread.follow = true;
                                    thread.positionViewAtEnd();
                                }
                            }
                        }
                    }

                    // Input, with the context chip (active application at opening)
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: FiliTheme.nuit4 }
                    // No AI agent: says why the chat does not answer and offers to install it
                    Rectangle {
                        visible: !chat.agentOk
                        Layout.fillWidth: true
                        Layout.margins: FiliTheme.space3
                        Layout.preferredHeight: noAi.implicitHeight + 2 * FiliTheme.space3
                        radius: FiliTheme.radiusControl
                        color: FiliTheme.nuit2
                        border { color: FiliTheme.cendre; width: 1 }
                        ColumnLayout {
                            id: noAi
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: FiliTheme.space3 }
                            spacing: FiliTheme.space2
                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: FiliI18n.tr("No AI agent installed. Rob needs Claude Code to answer.")
                                color: FiliTheme.brume
                                font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                            }
                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: FiliI18n.tr("Install it in a terminal, then type /login in claude to sign in.")
                                color: FiliTheme.brume2
                                font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                            }
                            Rectangle {
                                Layout.preferredWidth: instLabel.implicitWidth + 2 * FiliTheme.space3
                                Layout.preferredHeight: 28
                                radius: FiliTheme.radiusControl
                                color: instHit.containsMouse ? FiliTheme.nuit4 : FiliTheme.nuit3
                                border { color: FiliTheme.border; width: FiliTheme.borderWidth }
                                Text {
                                    id: instLabel
                                    anchors.centerIn: parent
                                    text: FiliI18n.tr("Install Claude Code")
                                    color: FiliTheme.brume
                                    font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                                }
                                MouseArea {
                                    id: instHit
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: chat.installAgent()
                                }
                            }
                        }
                    }
                    Rectangle {
                        visible: chat.ctxOn && chat.ctxLabel !== ""
                        Layout.fillWidth: true
                        Layout.leftMargin: FiliTheme.space3
                        Layout.rightMargin: FiliTheme.space3
                        Layout.topMargin: FiliTheme.space2
                        Layout.preferredHeight: 22
                        radius: FiliTheme.radiusControl
                        color: FiliTheme.nuit2
                        Text {
                            anchors { left: parent.left; leftMargin: FiliTheme.space2; right: chipX.left; verticalCenter: parent.verticalCenter }
                            text: FiliI18n.tr("Context") + ": " + chat.ctxLabel
                            elide: Text.ElideRight
                            color: FiliTheme.brume2
                            font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                        }
                        Text {
                            id: chipX
                            anchors { right: parent.right; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                            text: "×"
                            color: FiliTheme.ardoise
                            font { family: FiliTheme.font; pixelSize: 16 }
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: chat.ctxOn = false
                            }
                        }
                    }
                    Repeater {
                        model: chat.queuedNow
                        delegate: Text {
                            required property string modelData
                            Layout.fillWidth: true
                            Layout.leftMargin: FiliTheme.space3
                            Layout.rightMargin: FiliTheme.space3
                            Layout.topMargin: FiliTheme.space1
                            text: FiliI18n.tr("Queued") + ": " + modelData.split("\n")[0]
                            elide: Text.ElideRight
                            color: FiliTheme.ardoise
                            font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                        }
                    }
                    Flow {
                        visible: chat.attached.length > 0
                        Layout.fillWidth: true
                        Layout.leftMargin: FiliTheme.space3
                        Layout.rightMargin: FiliTheme.space3
                        Layout.topMargin: FiliTheme.space2
                        spacing: FiliTheme.space1
                        Repeater {
                            model: chat.attached
                            delegate: Rectangle {
                                id: chip
                                required property string modelData
                                height: 22
                                readonly property bool isImage: /\.(png|jpe?g|gif|webp|bmp)$/i.test(modelData)
                                width: Math.min(chipName.implicitWidth + chipClose.width + 3 * FiliTheme.space2 + (isImage ? 20 : 0), parent.width)
                                radius: FiliTheme.radiusControl
                                color: FiliTheme.nuit2
                                Image {
                                    id: chipThumb
                                    visible: chip.isImage
                                    anchors { left: parent.left; leftMargin: 3; verticalCenter: parent.verticalCenter }
                                    width: 16
                                    height: 16
                                    sourceSize: Qt.size(32, 32)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    source: chip.isImage ? "file://" + chip.modelData : ""
                                }
                                Text {
                                    id: chipName
                                    anchors { left: chip.isImage ? chipThumb.right : parent.left; leftMargin: FiliTheme.space2; right: chipClose.left; verticalCenter: parent.verticalCenter }
                                    text: chip.modelData.split("/").pop()
                                    elide: Text.ElideMiddle
                                    color: FiliTheme.brume2
                                    font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                                }
                                Text {
                                    id: chipClose
                                    anchors { right: parent.right; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                                    text: "×"
                                    color: FiliTheme.ardoise
                                    font { family: FiliTheme.font; pixelSize: 16 }
                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -4
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: chat.detach(chip.modelData)
                                    }
                                }
                            }
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(140, Math.max(44, input.implicitHeight + 2 * FiliTheme.space3))
                        TextEdit {
                            id: input
                            anchors { fill: parent; margins: FiliTheme.space3; rightMargin: FiliTheme.space3 + 32 }
                            wrapMode: TextEdit.Wrap
                            color: FiliTheme.brume
                            selectionColor: FiliTheme.voile
                            selectedTextColor: FiliTheme.nuit
                            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                            focus: true
                            Keys.onPressed: e => {
                                if (e.key === Qt.Key_V && (e.modifiers & Qt.ControlModifier) && !FiliTheme.testing)
                                    pasteFiles.running = true;
                                if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) {
                                    chat.send(text);
                                    text = "";
                                    e.accepted = true;
                                }
                            }
                            Connections {
                                target: chat
                                function onFocusInput() { input.forceActiveFocus(); }
                            }
                            Text {
                                visible: !input.text
                                text: chat.working ? FiliI18n.tr("Write now, Rob reads it when done…") : FiliI18n.tr("Message Rob…")
                                color: FiliTheme.ardoise
                                font: input.font
                            }
                        }
                        // Send (like Enter); greyed out while there is nothing to send
                        Rectangle {
                            id: sendBtn
                            readonly property bool ready: input.text.trim() !== "" || chat.attached.length > 0
                            anchors { right: parent.right; rightMargin: FiliTheme.space3; bottom: parent.bottom; bottomMargin: FiliTheme.space3 }
                            width: 26
                            height: 26
                            radius: 13
                            color: ready ? (sendHit.containsMouse ? FiliTheme.brume : FiliTheme.voile) : FiliTheme.nuit3
                            Text {
                                anchors.centerIn: parent
                                text: String.fromCodePoint(0xF06A9)
                                color: sendBtn.ready ? FiliTheme.nuit : FiliTheme.ardoise
                                font { family: "Fili Icons"; pixelSize: 18 }
                            }
                            MouseArea {
                                id: sendHit
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: sendBtn.ready
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    chat.send(input.text);
                                    input.text = "";
                                    input.forceActiveFocus();
                                }
                            }
                        }
                    }
                }

                // All sessions, archived ones included (click = open; an archived one is restored)
                Rectangle {
                    visible: chat.allOpen
                    anchors { left: rail.right; right: parent.right; top: parent.top; bottom: parent.bottom }
                    color: FiliTheme.nuit
                    Text {
                        id: allTitle
                        anchors { left: parent.left; leftMargin: FiliTheme.space3; top: parent.top; topMargin: FiliTheme.space3 }
                        text: FiliI18n.tr("All sessions")
                        color: FiliTheme.brume
                        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
                    }
                    ListView {
                        id: allList
                        anchors { left: parent.left; right: parent.right; top: allTitle.bottom; bottom: parent.bottom; topMargin: FiliTheme.space2 }
                        model: chat.allSessions
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        KineticScroll {}
                        delegate: Rectangle {
                            id: arow
                            required property var modelData
                            width: allList.width
                            height: 36
                            color: aHit.containsMouse ? FiliTheme.nuit3 : "transparent"
                            Text {
                                id: aState
                                anchors { right: parent.right; rightMargin: FiliTheme.space3; verticalCenter: parent.verticalCenter }
                                text: arow.modelData.archived ? FiliI18n.tr("archived") : ""
                                color: FiliTheme.ardoise
                                font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                            }
                            Text {
                                anchors { left: parent.left; leftMargin: FiliTheme.space3; right: aState.left; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                                text: arow.modelData.title || FiliI18n.tr("New session")
                                elide: Text.ElideRight
                                color: arow.modelData.archived ? FiliTheme.ardoise : FiliTheme.brume
                                font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                            }
                            MouseArea {
                                id: aHit
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: chat.pickSession(arow.modelData.id)
                            }
                        }
                    }
                }

                // Archiving confirmation: Enter archives, Escape cancels
                Rectangle {
                    id: confirm
                    visible: chat.confirmId !== ""
                    anchors { left: rail.right; right: parent.right; top: parent.top; bottom: parent.bottom }
                    color: FiliTheme.alpha(FiliTheme.nuit, 0.85)
                    onVisibleChanged: if (visible) confirmBox.forceActiveFocus()
                    MouseArea { anchors.fill: parent }
                    FocusScope {
                        id: confirmBox
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 2 * FiliTheme.space4, 300)
                        height: cCol.implicitHeight + 2 * FiliTheme.space3
                        Keys.onPressed: e => {
                            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter)
                                chat.confirmArchive(true);
                            else if (e.key === Qt.Key_Escape)
                                chat.confirmArchive(false);
                            else
                                return;
                            e.accepted = true;
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: FiliTheme.radiusWindow
                            color: FiliTheme.nuit2
                            border { color: FiliTheme.border; width: FiliTheme.borderWidth }
                        }
                        Column {
                            id: cCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: FiliTheme.space3 }
                            spacing: FiliTheme.space2
                            Text {
                                width: parent.width
                                wrapMode: Text.Wrap
                                text: FiliI18n.tr("Archive this session?")
                                color: FiliTheme.brume
                                font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
                            }
                            Text {
                                width: parent.width
                                wrapMode: Text.Wrap
                                text: (chat.sessions.find(x => x.id === chat.confirmId)?.title || FiliI18n.tr("New session")) + "\n" + FiliI18n.tr("It stays in All sessions and can be restored.")
                                color: FiliTheme.brume2
                                font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                            }
                            Row {
                                spacing: FiliTheme.space2
                                layoutDirection: Qt.RightToLeft
                                width: parent.width
                                Repeater {
                                    model: [{ label: "Archive", yes: true }, { label: "Cancel", yes: false }]
                                    delegate: Rectangle {
                                        id: cb
                                        required property var modelData
                                        width: 90
                                        height: 28
                                        radius: FiliTheme.radiusControl
                                        color: cbHit.containsMouse ? FiliTheme.nuit4 : FiliTheme.nuit3
                                        border { color: modelData.yes ? FiliTheme.cendre : FiliTheme.nuit4; width: 1 }
                                        Text {
                                            anchors.centerIn: parent
                                            text: FiliI18n.tr(cb.modelData.label)
                                            color: cb.modelData.yes ? FiliTheme.cendre : FiliTheme.brume
                                            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                                        }
                                        MouseArea {
                                            id: cbHit
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: chat.confirmArchive(cb.modelData.yes)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    visible: drawer.tipId !== "" && chat.tabsOpen
                    x: rail.width + FiliTheme.space1
                    y: Math.max(FiliTheme.space1, Math.min(drawer.height - height - FiliTheme.space1, drawer.tipY))
                    width: Math.min(tipLabel.implicitWidth + 2 * FiliTheme.space2, drawer.width - rail.width - 2 * FiliTheme.space1)
                    height: tipLabel.implicitHeight + 2 * FiliTheme.space1
                    radius: FiliTheme.radiusControl
                    color: FiliTheme.nuit3
                    border { color: FiliTheme.border; width: FiliTheme.borderWidth }
                    Text {
                        id: tipLabel
                        anchors { fill: parent; margins: FiliTheme.space1; leftMargin: FiliTheme.space2; rightMargin: FiliTheme.space2 }
                        text: drawer.tipText
                        wrapMode: Text.Wrap
                        color: FiliTheme.brume
                        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList }
                    }
                }
            }
        }
    }
}
