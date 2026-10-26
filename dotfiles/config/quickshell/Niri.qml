// État de niri (espaces de travail, fenêtres, disposition clavier) depuis `niri msg -j event-stream`:
// Quickshell n'a pas de module niri, le flux d'événements donne tout sans interroger.
pragma Singleton
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

    readonly property var focused: focusedId !== null ? windows[focusedId] ?? null : null

    function action(...args) {
        Quickshell.execDetached(["niri", "msg", "action", ...args]);
    }

    function setWindows(m) {
        windows = m;
    }

    Process {
        id: stream
        running: true
        command: ["niri", "msg", "-j", "event-stream"]
        stdout: SplitParser {
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
                } else if (ev.WindowOpenedOrChanged) {
                    const w = ev.WindowOpenedOrChanged.window;
                    const m = Object.assign({}, niri.windows);
                    m[w.id] = w;
                    niri.setWindows(m);
                    if (w.is_focused)
                        niri.focusedId = w.id;
                } else if (ev.WindowClosed) {
                    const m = Object.assign({}, niri.windows);
                    delete m[ev.WindowClosed.id];
                    niri.setWindows(m);
                } else if (ev.WindowFocusChanged) {
                    niri.focusedId = ev.WindowFocusChanged.id;
                } else if (ev.KeyboardLayoutsChanged) {
                    niri.layouts = ev.KeyboardLayoutsChanged.keyboard_layouts.names;
                    niri.layout = ev.KeyboardLayoutsChanged.keyboard_layouts.current_idx;
                } else if (ev.KeyboardLayoutSwitched) {
                    niri.layout = ev.KeyboardLayoutSwitched.idx;
                }
            }
        }
        // niri relancé ou flux coupé: on se reconnecte
        onExited: restart.start()
    }
    Timer {
        id: restart
        interval: 1000
        onTriggered: stream.running = true
    }
}
