// State of the AI agent of the bar: the sessions and plan limits written by fili-ai-session (Claude Code hooks and
// status line) in $XDG_RUNTIME_DIR/fili-ai/state.json, merged with the interface of the assistant (AiState). The module
// and its panel each create one; only the module sets `watching`, which marks a session looked at as seen
// (`fili-ai-session seen`).
import QtQuick
import qs
import qs.bar

Item {
    id: agent
    visible: false
    // Mark the sessions whose window has the focus as seen (the bar module only)
    property bool watching: false
    // Sessions written by fili-ai-session (Claude Code hooks and status line): state, niri window, context, cost;
    // plan limits kept after the last session. Window of a waiting session looked at: no more highlight
    // (fili-ai-session seen)
    BarWatched { id: aiF; path: BarState.run + "/fili-ai/state.json" }
    property var aiData: ({ sessions: [], limits: null })
    readonly property string aiText: aiF.content
    onAiTextChanged: {
        try {
            aiData = aiText.trim() ? JSON.parse(aiText) : { sessions: [], limits: null };
        } catch (e) {
            // File being written: the previous state stays
        }
        if (watching)
            aiSeen();
    }
    // The assistant's interface (AiState) joins the terminal sessions: permission asked = ASK, unread answer = DONE
    readonly property var ai: aiChat(aiFor(aiData, Niri.focusedId, Niri.windows), AiState.attention, AiState.busy)
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
        if (AiState.attention === "waiting")
            AiState.show();
        else
            FiliTheme.run(FiliTheme.tool("fili-ai-session") + " focus");
    }
    Connections {
        enabled: agent.watching
        target: Niri
        function onFocusedIdChanged() {
            agent.aiSeen();
        }
    }
    function aiSeen() {
        for (const s of aiData.sessions ?? [])
            if (s.attention && s.window !== undefined && s.window === Niri.focusedId)
                FiliTheme.run(FiliTheme.tool("fili-ai-session") + " seen " + s.id);
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
            hint: FiliI18n.tr("click: agent panel · Super+click or middle click: go to what is asking · right click: menu")
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
}
