pragma Singleton
// State of niri (workspaces, windows, keyboard layout) from its event stream (socket $NIRI_SOCKET):
// Quickshell has no niri module, the event stream gives everything without querying.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: niri
    property var workspaces: []
    property var windows: ({})
    property var focusedId: null
    property var layouts: []
    property int layout: 0
    // Layout used before the current one ("previous" toggle, like Ctrl+Space of the Omarchy picker)
    property int previousLayout: -1

    readonly property var focused: focusedId !== null ? windows[focusedId] ?? null : null
    // A window opened after the start of the stream (not one of the windows already there)
    signal windowOpened(var window)
    property bool seeded: false

    function action(...args) {
        if (FiliTheme.testing)
            FiliTheme.ran = FiliTheme.ran.concat(["niri msg action " + args.join(" ")]);
        else
            Quickshell.execDetached(["niri", "msg", "action", ...args]);
    }

    // Niri action on a given display (connector): focus-monitor first, since focus-workspace N and
    // focus-workspace-up/down act on the display that has the focus
    function onOutput(output, act) {
        FiliTheme.run("niri msg action focus-monitor '" + String(output).replace(/'/g, "") + "' && niri msg action " + act);
    }

    // Window of an MPRIS player (niri id, or null): browsers publish "…instance<pid>" (the pid of the window),
    // the other players are found through their desktop entry (desktopEntry = app_id); if several windows remain
    // (tabs, PWAs), the one whose title contains the track; otherwise (the track plays in a background tab,
    // whose title does not appear) a browser window rather than a PWA (app_id "chrome-site__-Default")
    function playerWindow(wins, dbusName, desktopEntry, track) {
        const pid = /\.instance(\d+)$/.exec(dbusName ?? "");
        const entry = (desktopEntry ?? "").toLowerCase();
        let c = Object.values(wins).filter(w => pid ? w.pid === Number(pid[1]) : entry !== "" && (w.app_id ?? "").toLowerCase() === entry);
        if (c.length > 1 && track) {
            const t = c.filter(w => (w.title ?? "").indexOf(track) >= 0);
            const nonPwa = c.filter(w => (w.app_id ?? "").indexOf("__") < 0);
            c = t.length > 0 ? t : nonPwa.length > 0 ? nonPwa : c;
        }
        return c.length > 0 ? c[0].id : null;
    }

    // Short code of a layout for the bar: "French (BEPO, AFNOR)" -> fr, "English (Australia)" -> au
    function shortName(name) {
        const m = name.match(/\((Australian|Australia|US|UK)/);
        if (m)
            return { Australian: "au", Australia: "au", US: "us", UK: "gb" }[m[1]];
        return name.slice(0, 2).toLowerCase();
    }
    function setLayout(i) {
        if (i !== layout) {
            previousLayout = layout;
            layout = i;
        }
    }
    function selectLayout(i) {
        action("switch-layout", String(i));
    }

    function setWindows(m) {
        windows = m;
    }
    // Fields of a window read by the bar: niri sends the whole window at every move or resize
    // (layout), without changing anything that is displayed
    function same(a, b) {
        return a && a.title === b.title && a.app_id === b.app_id && a.workspace_id === b.workspace_id;
    }

    // Event stream read directly from the niri socket ("EventStream" request), without a `niri msg` process
    Socket {
        id: stream
        path: Quickshell.env("NIRI_SOCKET") ?? ""
        connected: path !== ""
        onConnectedChanged: {
            if (connected) {
                write('"EventStream"\n');
                flush();
            } else {
                // niri restarted or stream cut: reconnect
                restart.start();
            }
        }
        parser: SplitParser {
            onRead: line => {
                let ev;
                try {
                    ev = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (ev.WorkspacesChanged) {
                    niri.workspaces = ev.WorkspacesChanged.workspaces.slice().sort((a, b) => a.output === b.output ? a.idx - b.idx : a.output.localeCompare(b.output));
                } else if (ev.WorkspaceActivated) {
                    const id = ev.WorkspaceActivated.id;
                    const out = (niri.workspaces.find(w => w.id === id) || {}).output;
                    niri.workspaces = niri.workspaces.map(w => w.output === out ? Object.assign({}, w, { is_active: w.id === id }) : w);
                } else if (ev.WindowsChanged) {
                    const m = {};
                    for (const w of ev.WindowsChanged.windows) {
                        m[w.id] = w;
                        if (w.is_focused)
                            niri.focusedId = w.id;
                    }
                    niri.setWindows(m);
                    niri.seeded = true;
                } else if (ev.WindowOpenedOrChanged) {
                    const w = ev.WindowOpenedOrChanged.window;
                    const opened = niri.seeded && niri.windows[w.id] === undefined;
                    if (niri.same(niri.windows[w.id], w)) {
                        niri.windows[w.id] = w;
                    } else {
                        const m = Object.assign({}, niri.windows);
                        m[w.id] = w;
                        niri.setWindows(m);
                    }
                    if (w.is_focused)
                        niri.focusedId = w.id;
                    if (opened)
                        niri.windowOpened(w);
                } else if (ev.WindowClosed) {
                    const m = Object.assign({}, niri.windows);
                    delete m[ev.WindowClosed.id];
                    niri.setWindows(m);
                } else if (ev.WindowFocusChanged) {
                    niri.focusedId = ev.WindowFocusChanged.id;
                } else if (ev.KeyboardLayoutsChanged) {
                    niri.layouts = ev.KeyboardLayoutsChanged.keyboard_layouts.names;
                    niri.layout = ev.KeyboardLayoutsChanged.keyboard_layouts.current_idx;
                    niri.previousLayout = -1;
                } else if (ev.KeyboardLayoutSwitched) {
                    niri.setLayout(ev.KeyboardLayoutSwitched.idx);
                }
            }
        }
    }
    Timer {
        id: restart
        interval: 1000
        onTriggered: stream.connected = stream.path !== ""
    }

    // One-off request (e.g. "Outputs") on a second connection: callback with the reply (Ok field, or null on
    // error); requests go one by one, the connection closes when there are no more
    property var pending: []
    function request(name, done) {
        pending = pending.concat([{ name: name, done: done }]);
        if (!req.connected)
            req.connected = req.path !== "";
        else if (pending.length === 1)
            req.send();
    }
    Socket {
        id: req
        path: stream.path
        function send() {
            write(JSON.stringify(niri.pending[0].name) + "\n");
            flush();
        }
        onConnectedChanged: if (connected && niri.pending.length) send()
        parser: SplitParser {
            onRead: line => {
                const p = niri.pending[0];
                niri.pending = niri.pending.slice(1);
                let r = null;
                try {
                    r = JSON.parse(line).Ok ?? null;
                } catch (e) {}
                // A callback in error (requester destroyed in the meantime) does not block the queue
                try {
                    if (p)
                        p.done(r ? r[p.name] ?? r : null);
                } catch (e) {}
                if (niri.pending.length)
                    req.send();
                else
                    req.connected = false;
            }
        }
    }
}
