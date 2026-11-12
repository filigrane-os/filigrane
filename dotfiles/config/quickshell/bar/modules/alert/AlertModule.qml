// Alert indicator of one kind: ~/.local/state/alerts/<kind> (one line "field<TAB>field" per item, added by `bar-alert push`)
// and, optionally, <kind>.count (the real number of unread items, which takes priority). Shown in the bar while there is
// something; at rest it only shows in the open drawer (bar-tray toggle). Click = `bar-alert open <kind>` (opens the web
// app and clears the alert). The plugins (mail, chat, calendar...) are an AlertModule with their
// kind, title, glyph and colour; `render` gives a kind its own format and expiry.
import QtQuick
import qs
import qs.bar

BarScript {
    id: alert
    objectName: kind
    // File name under ~/.local/state/alerts
    property string kind
    // Name in the tooltip
    property string title: kind
    property string glyph: ""
    // Icon in the open drawer when there is no alert
    property string idleGlyph: glyph
    // Colour of the alert (at rest: slate)
    property color accent: FiliTheme.barText
    property string openHint: FiliI18n.tr("click: open %1", title)
    // Web app opened by a click (bar-alert open KIND URL); empty: the web app of the list named like the kind
    property string url: ""
    // Optional (rows, now) => { text, rows } or null when nothing is left: for a kind with its own format and expiry
    // (text follows the glyph, rows are the tooltip lines). A null result also empties the file.
    property var render: null
    // Seconds since the epoch, advanced every minute while the file has content (expiry)
    property real now: Date.now() / 1000

    readonly property string dir: BarState.alerts
    BarWatched { id: file; path: alert.dir + "/" + alert.kind }
    BarWatched { id: counter; path: alert.dir + "/" + alert.kind + ".count" }
    Timer {
        interval: 60000
        repeat: true
        running: file.content !== ""
        onTriggered: {
            alert.now = Date.now() / 1000;
            // Nothing left to come: the file is emptied (as bar-alert open does)
            if (alert.render && alert.shown.text === "" && !counter.exists)
                file.setText("");
        }
    }

    readonly property var shown: build(file.content, counter.exists ? counter.content : null, now)
    value: shown.text !== "" ? shown : (BarState.trayOpen ? ({ text: idleGlyph, "class": "idle", tooltip: { title: title, hint: FiliI18n.tr("click: open") } }) : BarState.empty)
    colors: ({ active: accent, idle: FiliTheme.barMuted })
    click: FiliTheme.bin + "/bar-alert open " + kind + (url ? " '" + url + "'" : "")

    // State from the file content, the content of <kind>.count (null if it does not exist) and the time
    function build(text, count, now) {
        const r = BarState.rows(text);
        // Tooltip in the fili-tooltip standard: title on the left, sender / subject lines on the right
        const lines = r.slice(-8).map(x => [x[0], x[1] ?? ""]);
        if (count !== null) {
            const n = parseInt(count);
            if (!(n > 0))
                return BarState.empty;
            return { text: glyph + " " + n, "class": "active", tooltip: { title: title, rows: [[FiliI18n.tr("Unread"), String(n)]].concat(lines), hint: openHint } };
        }
        if (r.length === 0)
            return BarState.empty;
        if (render) {
            const x = render(r, now);
            return x ? { text: glyph + " " + x.text, "class": "active", tooltip: { title: title, rows: x.rows, hint: openHint } } : BarState.empty;
        }
        return { text: glyph + " " + r.length, "class": "active", tooltip: { title: title, rows: lines, hint: openHint } };
    }
}
