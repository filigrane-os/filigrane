pragma Singleton
// fili-bar states read from their files, without running a script: FileView re-reads a file as soon as it changes
// (inotify), even if it is absent at the start. Each state is a {text, class, tooltip} object, like a line of JSON from
// a script (BarScript.value), shared by the bars of all screens.
//   drawer    $XDG_RUNTIME_DIR/bar-tray-open          present = open (bar-tray toggle)
//   timer     $XDG_RUNTIME_DIR/bar-timer              "T <end>" | "S <start>" | "done" (bar-timer click/add/expire)
//   backup                                             bar-stats backup stat, kept visible 10 s after the end
//   AI agent  $XDG_RUNTIME_DIR/fili-ai/state.json     Claude Code sessions and plan limits (fili-ai-session)
//   agenda    ~/.local/state/agenda                    next events (clock card)
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
    // Next events of the agenda (cal-notify, user layer): null without the file
    BarWatched { id: agendaF; path: Quickshell.env("HOME") + "/.local/state/agenda" }
    readonly property var agenda: agendaF.exists ? rows(agendaF.content).filter(r => Number(r[0]) > minute - 60).slice(0, 5).map(r => ({ start: Number(r[0]), title: r[1] ?? "", place: r[2] ?? "" })) : null

    // Instant (s) that expires the agenda events, advanced every minute while there are some
    property real minute: Date.now() / 1000
    Timer {
        interval: 60000
        repeat: true
        running: agendaF.content !== ""
        onTriggered: st.minute = Date.now() / 1000
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

    // ───── AI agent ─────
    // Sessions written by fili-ai-session (Claude Code hooks and status line): state, niri window, context, cost;
    // plan limits kept after the last session. Window of a waiting session looked at: no more highlight
    // (fili-ai-session seen)
    BarWatched { id: aiF; path: st.run + "/fili-ai/state.json" }
    property var aiData: ({ sessions: [], limits: null })
    readonly property string aiText: aiF.content
    onAiTextChanged: {
        try {
            aiData = aiText.trim() ? JSON.parse(aiText) : { sessions: [], limits: null };
        } catch (e) {
            // File being written: the previous state stays
        }
        aiSeen();
    }
    // The chat (FiliChat) joins the terminal sessions: permission asked = ASK, unread answer = DONE
    readonly property var ai: aiChat(aiFor(aiData, Niri.focusedId, Niri.windows), FiliChat.attention, FiliChat.busy)
    function aiChat(base, attention, busy) {
        const icon = String.fromCodePoint(0xf06a9);
        const rows = base.tooltip.rows.filter(r => r[0] !== FiliI18n.tr("Sessions") || r[1] !== FiliI18n.tr("none"));
        const chat = attention === "waiting" ? FiliI18n.tr("waiting for you") : busy ? FiliI18n.tr("working") : attention === "done" ? FiliI18n.tr("finished") : "";
        if (chat)
            rows.unshift([FiliI18n.tr("Chat"), chat]);
        const card = Object.assign({}, base.tooltip, { rows: rows });
        if (attention === "waiting")
            return { text: icon + " ASK", class: "waiting", tooltip: card };
        if (base.class === "waiting")
            return Object.assign({}, base, { tooltip: card });
        if (attention === "done")
            return { text: icon + " DONE", class: "done", tooltip: card };
        if (busy && (base.class === "off" || base.class === "idle"))
            return { text: base.text, class: "working", tooltip: card };
        return Object.assign({}, base, { tooltip: card });
    }
    // Go to what is asking: the chat when it waits for an answer, else the terminal session that waits (or the next one)
    function aiAsk() {
        if (FiliChat.attention === "waiting")
            FiliChat.show();
        else
            FiliTheme.run(FiliTheme.bin + "/fili-ai-session focus");
    }
    Connections {
        target: Niri
        function onFocusedIdChanged() {
            st.aiSeen();
        }
    }
    function aiSeen() {
        for (const s of aiData.sessions ?? [])
            if (s.attention && s.window !== undefined && s.window === Niri.focusedId)
                FiliTheme.run(FiliTheme.bin + "/fili-ai-session seen " + s.id);
    }
    // Name of a session: title of its window (subject given by Claude Code, without its activity indicator ✳ ◐ ⠋...), else its folder
    function aiName(s, windows) {
        const title = (windows?.[s.window]?.title ?? "").replace(/^[\u2000-\u2bff\s]+/, "");
        return title || (s.cwd ?? "").split("/").filter(x => x).pop() || "~";
    }
    // Plan limit line: usage, reset, gauge and steady-pace mark (elapsed part of the window: 5 h or 7 days),
    // like the "pace" of the agents panel of Omarchy
    function aiLimit(label, l, span, fmt, now) {
        if (!l || l.used_percentage === undefined)
            return null;
        const reset = l.resets_at ? " · " + FiliI18n.tr("resets %1", FiliI18n.locale.toString(new Date(l.resets_at * 1000), fmt)) : "";
        const mark = l.resets_at ? 1 - (l.resets_at - now) / span : -1;
        return [label, Math.round(l.used_percentage) + " %" + reset, { value: l.used_percentage / 100, mark: mark }];
    }
    // now: instant (s), the current time by default (fixed by the tests)
    function aiFor(data, focused, windows, now) {
        const icon = String.fromCodePoint(0xf06a9);
        const sessions = data?.sessions ?? [];
        // A session being looked at no longer calls for attention
        const calls = sessions.filter(s => s.attention && s.window !== focused);
        const rows = sessions.slice(0, 6).map(s => {
            const state = { working: FiliI18n.tr("working"), waiting: FiliI18n.tr("waiting for you"), done: FiliI18n.tr("finished") }[s.state] ?? FiliI18n.tr("ready");
            const parts = [state];
            if (s.ctx !== undefined && s.ctx !== null)
                parts.push(FiliI18n.tr("context %1 %", Math.round(s.ctx)));
            if (s.cost)
                parts.push(FiliI18n.num(s.cost, 2) + " $");
            if (s.model)
                parts.push(s.model);
            return [aiName(s, windows), parts.join(" · ")];
        });
        const waitMsg = sessions.find(s => s.state === "waiting" && s.message)?.message;
        if (waitMsg)
            rows.push(["", waitMsg]);
        if (sessions.length === 0)
            rows.push([FiliI18n.tr("Sessions"), FiliI18n.tr("none")]);
        const lim = data?.limits;
        now = now ?? Date.now() / 1000;
        const five = aiLimit(FiliI18n.tr("5-hour limit"), lim?.five_hour, 5 * 3600, "HH:mm", now);
        const week = aiLimit(FiliI18n.tr("Weekly limit"), lim?.seven_day, 7 * 86400, "ddd HH:mm", now);
        if (five)
            rows.push(five);
        if (week)
            rows.push(week);
        if ((five || week) && lim.seen && now - lim.seen > 900)
            rows.push(["", FiliI18n.tr("as of %1", FiliI18n.locale.toString(new Date(lim.seen * 1000), "ddd HH:mm"))]);
        const card = {
            title: sessions.length ? "Claude Code" : FiliI18n.tr("AI agent"),
            rows: rows,
            hint: FiliI18n.tr("click: agent panel · Super+click or middle click: go to what is asking · right click: choose the agent")
        };
        if (calls.some(s => s.state === "waiting"))
            return { text: icon + " ASK", class: "waiting", tooltip: card };
        if (calls.length)
            return { text: icon + " DONE", class: "done", tooltip: card };
        const working = sessions.filter(s => s.state === "working").length;
        if (sessions.length)
            return { text: icon + (sessions.length > 1 ? " " + sessions.length : ""), class: working ? "working" : "idle", tooltip: card };
        return { text: icon, class: "off", tooltip: card };
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
