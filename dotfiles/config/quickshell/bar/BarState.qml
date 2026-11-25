pragma Singleton
// fili-bar states read from their files, without running a script: FileView re-reads a file as soon as it changes
// (inotify), even if it is absent at the start. Each state is a {text, class, tooltip} object, like a line of JSON from
// a script (BarScript.value), shared by the bars of all screens.
//   drawer    $XDG_RUNTIME_DIR/bar-tray-open          present = open (bar-tray toggle)
//   timer     $XDG_RUNTIME_DIR/bar-timer              "T <end>" | "S <start>" | "done" (bar-timer click/add/expire)
//   backup                                             bar-stats backup stat, kept visible 10 s after the end
//   agenda    ~/.local/state/filigrane/agenda   next events (clock card, written by fili-cal)
// The alerts (~/.local/state/alerts/<kind>) are read by AlertModule, one module per kind.
import QtQuick
import Quickshell
import Quickshell.Io
import qs

Singleton {
    id: st
    readonly property string run: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    // Alert files (AlertModule); the folder is created at the start since FileView does not see a file appear in a missing one
    readonly property string alerts: Quickshell.env("HOME") + "/.local/state/alerts"
    readonly property var empty: ({ text: "" })

    // ───── agenda ─────
    // Next events of the agenda: the file of fili-cal (the calendar of Filigrane, rewritten by `fili-cal tick`; one line per event:
    // epoch, title, place). null without the file.
    BarWatched { id: calF; path: Quickshell.env("HOME") + "/.local/state/filigrane/agenda" }
    readonly property var agenda: calF.exists
        ? rows(calF.content).filter(r => Number(r[0]) > minute - 60).sort((a, b) => Number(a[0]) - Number(b[0])).slice(0, 5).map(r => ({ start: Number(r[0]), title: r[1] ?? "", place: r[2] ?? "" }))
        : null

    // Instant (s) that expires the agenda events, advanced every minute; the same beat runs `fili-cal tick`, which shows
    // the alarms that are due (no daemon: the shell is the clock) and rewrites the agenda file
    property real minute: Date.now() / 1000
    Timer {
        interval: 60000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            st.minute = Date.now() / 1000;
            if (!FiliTheme.testing)
                calTick.running = true;
        }
    }
    Process {
        id: calTick
        command: [FiliTheme.tool("fili-cal"), "tick"]
    }

    // Lines "field<TAB>field..." of an alert or agenda file
    function rows(text) {
        return text.split("\n").filter(l => l !== "").map(l => l.split("\t"));
    }

    // ───── tiroir ─────
    BarWatched { id: trayF; path: st.run + "/bar-tray-open" }
    readonly property bool trayOpen: trayF.exists
    readonly property var trayHandle: trayOpen ? { text: "", class: "open", tooltip: { title: FiliI18n.tr("Drawer"), hint: FiliI18n.tr("click: fold") } } : { text: "", tooltip: { title: FiliI18n.tr("Drawer"), hint: FiliI18n.tr("click: show the backup") } }

    // ───── status indicators ─────
    // Rows of the status panel ({ key, glyph, title, detail, click }), published by the status module: the active
    // indicators (recording, SSH, airplane mode, VPN, updates) merged into one bar icon
    property var statusRows: []

    // ───── backup ─────
    // Folded, visible only while running or on failure; back at rest, it stays 10 s (to be able to run it again
    // after a click by mistake)
    property var backupRaw: empty
    property bool backupLinger: false
    readonly property var backup: trayOpen || backupLinger || backupRaw["class"] !== "idle" ? backupRaw : empty
    function setBackup(j) {
        if (j["class"] === "idle" && (backupRaw["class"] ?? "idle") !== "idle") {
            backupLinger = true;
            linger.restart();
        }
        backupRaw = j;
    }
    Timer {
        id: linger
        interval: 10000
        onTriggered: st.backupLinger = false
    }
    Connections {
        target: FiliShell
        function onStat(name, data) {
            if (name === "backup")
                st.setBackup(data);
        }
    }
    Component.onCompleted: {
        if (FiliShell.stats.backup)
            backupRaw = FiliShell.stats.backup;
        if (!FiliTheme.testing)
            Quickshell.execDetached(["mkdir", "-p", alerts]);
    }

    // ───── timer / stopwatch ─────
    BarWatched { id: timerF; path: st.run + "/bar-timer" }
    readonly property var timerFile: {
        const p = timerF.content.trim().split(" ");
        return { kind: p[0] ?? "", val: Number(p[1] ?? 0) };
    }
    // Current second, advanced only while a timer or a stopwatch runs
    property real second: Date.now() / 1000
    readonly property var timer: timerFor(timerFile.kind, timerFile.val, second)
    // Timer elapsed: bar-timer expire (state "done" and notification), once per timer
    property real expired: 0
    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: st.timerFile.kind === "S" || st.timerFile.kind === "T"
        onTriggered: {
            st.second = Date.now() / 1000;
            if (st.timerFile.kind === "T" && st.timerFile.val <= st.second && st.expired !== st.timerFile.val) {
                st.expired = st.timerFile.val;
                FiliTheme.run(FiliTheme.bin + "/bar-timer expire");
            }
        }
    }
    // secondes -> [H:]MM:SS
    function fmt(s) {
        const p = n => String(n).padStart(2, "0");
        return s >= 3600 ? Math.floor(s / 3600) + ":" + p(Math.floor(s % 3600 / 60)) + ":" + p(s % 60) : p(Math.floor(s / 60)) + ":" + p(s % 60);
    }
    function timerFor(kind, val, now) {
        const icon = "";
        now = Math.floor(now);
        if (kind === "")
            return { text: icon, class: "idle", tooltip: FiliI18n.tr("Timer / stopwatch (click: choose)") };
        if (kind === "S")
            return { text: icon + " " + fmt(Math.max(0, now - val)), class: "stopwatch", tooltip: FiliI18n.tr("Stopwatch (click: stop)") };
        if (kind === "T" && val - now > 0)
            return { text: icon + " " + fmt(val - now), class: "active", tooltip: FiliI18n.tr("Timer (click: cancel, right click: +5 min)") };
        return { text: icon + " 00:00", class: "done", tooltip: FiliI18n.tr("Done (click: dismiss)") };
    }
}
