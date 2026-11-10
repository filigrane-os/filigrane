pragma Singleton
// Placement of the new windows of an application, the part niri's window rules cannot do: "left" and "right" (Settings >
// Workspaces, fili-app-output layout) open its new windows as the first or the last column of the workspace, tiled.
// When such a window opens and has the focus (niri focuses new windows), its column is moved there. The other
// placements (maximized, floating) are niri window rules written by fili-app-output.
// State: $XDG_STATE_HOME/filigrane/app-layouts, "APP_ID<TAB>MODE" per line, re-read when it changes.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: placement
    // app-id -> "left" | "right" (the other modes are left to niri)
    property var columns: ({})
    readonly property string file: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/filigrane/app-layouts"

    function parse(text) {
        const m = {};
        for (const l of text.split("\n")) {
            const [app, mode] = l.split("\t");
            if (app && (mode === "left" || mode === "right"))
                m[app] = mode;
        }
        return m;
    }
    // Called for every new window (also by the tests)
    function place(w) {
        const mode = columns[w.app_id ?? ""];
        if (!mode || w.is_floating || !w.is_focused)
            return;
        Niri.action(mode === "left" ? "move-column-to-first" : "move-column-to-last");
    }

    FileView {
        path: placement.file
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: placement.columns = placement.parse(text())
        onLoadFailed: placement.columns = {}
    }
    Connections {
        target: Niri
        function onWindowOpened(w) {
            placement.place(w);
        }
    }
}
