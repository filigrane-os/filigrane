pragma Singleton
// Number of every window, shown in the taskbar and typed in its hint mode (TaskbarHint): a window gets the lowest free
// number (1, 2, 3...) when it opens, across all the screens, keeps it as long as it lives, and gives it back when it
// closes (so the numbers stay small and a number can be learned). The numbers are kept in
// ~/.local/state/filigrane/window-numbers.json, so that a reload of the shell does not renumber the windows.
import QtQuick
import Quickshell
import Quickshell.Io
import qs

Singleton {
    id: nums
    // niri window id -> number
    property var map: ({})
    // The saved numbers are read (or there are none): before that nothing is assigned, so they are not overwritten
    property bool ready: FiliTheme.testing

    function numberOf(id) {
        return map[id] ?? 0;
    }
    // Window of a number (its niri id), or null
    function windowOf(n) {
        for (const id in map)
            if (map[id] === n)
                return Number(id);
        return null;
    }
    // Keep the numbers of the windows that are still there, give the new ones the lowest free number
    function sync(windows) {
        if (!ready)
            return;
        const ids = Object.keys(windows).map(Number).sort((a, b) => a - b);
        // Before the first list of windows (empty) the saved numbers are left alone
        if (ids.length === 0 && !Niri.seeded)
            return;
        const next = {}, used = new Set();
        for (const id of ids) {
            const n = map[id];
            if (n && !used.has(n)) {
                next[id] = n;
                used.add(n);
            }
        }
        for (const id of ids) {
            if (next[id])
                continue;
            let n = 1;
            while (used.has(n))
                n++;
            next[id] = n;
            used.add(n);
        }
        if (JSON.stringify(next) !== JSON.stringify(map)) {
            map = next;
            if (!FiliTheme.testing)
                store.setText(JSON.stringify(next));
        }
    }

    Connections {
        target: Niri
        function onWindowsChanged() { nums.sync(Niri.windows); }
    }
    FileView {
        id: store
        path: FiliTheme.testing ? "" : (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/filigrane/window-numbers.json"
        printErrors: false
        onLoaded: {
            try {
                nums.map = JSON.parse(text());
            } catch (e) {
                nums.map = ({});
            }
            nums.ready = true;
            nums.sync(Niri.windows);
        }
        onLoadFailed: {
            nums.ready = true;
            nums.sync(Niri.windows);
        }
    }
}
