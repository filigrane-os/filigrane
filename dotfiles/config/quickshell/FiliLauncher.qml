pragma Singleton
// fili-launcher: launcher and picker in the style of `fuzzel --dmenu` (menu ~/.local/bin/menu, applications, timer, fili-ai),
// called by `fili-shell launcher`. List filtered from the keyboard, icons (extended dmenu protocol "text\0icon\037path"),
// prompt alone for a free input. The window covers the screen ("fili-launcher" layer, blurred by niri) and the box
// is a barely translucent veil in the upper third (it does not jump while filtering); the veil stays 250 ms after
// a choice, with the box frozen, to chain submenus without flicker. No animation (brand.md),
// except the momentum of touchpad scrolling (KineticScroll).
// Menu rows: "glyph  Label ›  ‹Key›" laid out (icon column, submenu chevron, key as a
// label) rather than aligned with spaces; the returned value stays the original line.
// Enter = choose (or typed text without a match), Escape = cancel (1), Shift+Backspace = go back (10),
// click outside the box = cancel.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

Singleton {
    id: launcher
    property var req: null      // options of the current request (see fili-shell)
    property string replyTo: ""
    property var entries: []    // { accept, glyph, text, sub, key, icon, thumb }
    property var shown: []      // { e, score, hits }
    property int current: 0
    property bool open: false
    // Typed text (read and written by the tests)
    property alias query: input.text

    readonly property color nuit2: FiliTheme.nuit2
    readonly property color selMatch: FiliTheme.voileVif

    function finish(rc, text) {
        if (replyTo)
            FiliShell.reply(replyTo, rc + "\n" + (text ?? ""));
        // req and shown kept: the box stays frozen during the linger, replaced by the next request.
        // linger before open = false: the window never becomes invisible (destroyed surface = flicker)
        linger.restart();
        replyTo = "";
        open = false;
    }

    // Split a displayed line: Nerd Font glyph first (private-use area), "‹Key›" and chevron "›" at the end
    function parse(label) {
        let text = label, glyph = "", key = "", sub = false;
        const g = text.match(/^([-]|[\uDB80-\uDBFF][\uDC00-\uDFFF])\s+/);
        if (g) {
            glyph = g[1];
            text = text.slice(g[0].length);
        }
        const k = text.match(/\s*‹([^‹›]*)›\s*$/);
        if (k) {
            key = k[1];
            text = text.slice(0, k.index);
        }
        text = text.replace(/\s+$/, "");
        if (text.endsWith(" ›")) {
            sub = true;
            text = text.slice(0, -2);
        }
        return { glyph: glyph, text: text, key: key, sub: sub };
    }

    // Request read in two steps (files read asynchronously by FileView, see onLoaded below):
    // options, then entries, then display
    property var pending: null
    property string pendingReply: ""
    function request(optsPath, reply) {
        if (replyTo)
            finish(1, "");
        pendingReply = reply;
        optsFile.path = "";
        optsFile.path = optsPath;
    }
    function optsLoaded() {
        let opts;
        try {
            opts = JSON.parse(optsFile.text());
        } catch (e) {
            FiliShell.reply(pendingReply, "1\n");
            return;
        }
        pending = opts;
        if (opts.promptOnly) {
            start(opts, pendingReply, "");
        } else {
            inFile.path = "";
            inFile.path = opts.input;
        }
    }

    function start(opts, reply, raw) {
        req = opts;
        replyTo = reply;
        const list = [];
        for (const line of raw.split("\n")) {
            if (line === "")
                continue;
            const [text, extra] = line.split("\0");
            const icon = extra && extra.startsWith("icon\x1f") ? extra.slice(5) : "";
            const cols = text.split("\t");
            const label = opts.withNth > 0 ? (cols[opts.withNth - 1] ?? text) : text;
            const p = parse(label);
            list.push({
                // Keywords: column searched but never displayed (Keywords of the .desktop files)
                kw: opts.searchNth > 0 ? fold(cols[opts.searchNth - 1] ?? "") : "",
                accept: opts.acceptNth > 0 ? (cols[opts.acceptNth - 1] ?? text) : text,
                glyph: p.glyph, text: p.text, key: p.key, sub: p.sub,
                // Image file (wallpaper thumbnail, app icon as a path) or name of a theme icon
                thumb: icon.startsWith("/") ? "file://" + icon : "",
                icon: icon && !icon.startsWith("/") ? Quickshell.iconPath(icon, true) : ""
            });
        }
        pending = null;
        entries = list;
        input.text = "";
        filter();
        open = true;
        linger.stop();
        input.forceActiveFocus();
    }

    // Match: every word of the input must appear (substring, else letters in order);
    // score: start of label > start of word > substring > scattered letters. --no-sort keeps the original order.
    // Accents folded, one character for one (é -> e), so that the highlighted positions still fit the label:
    // "regl" finds "Réglages"
    function fold(s) {
        return s.toLowerCase().replace(/[\u00c0-\u017f]/g, c => c.normalize("NFD").charAt(0));
    }
    function match(label, words, kw) {
        const l = fold(label);
        let score = 0;
        const hits = [];
        for (const w of words) {
            const i = l.indexOf(w);
            if (i >= 0) {
                score += i === 0 ? 300 : /[\s\-_./›:]/.test(l[i - 1]) ? 200 : 100;
                for (let k = 0; k < w.length; k++)
                    hits.push(i + k);
                continue;
            }
            // Keyword: start of word in the keywords ("file" -> Casier), behind the matches of the label
            if (kw && (kw.startsWith(w) || kw.indexOf(" " + w) >= 0)) {
                score += 150;
                continue;
            }
            let p = 0;
            for (const c of w) {
                p = l.indexOf(c, p);
                if (p < 0)
                    return null;
                hits.push(p++);
            }
            score += 10;
        }
        return { score: score - label.length / 100, hits: hits };
    }
    function filter() {
        const words = fold(input.text).split(/\s+/).filter(w => w);
        let out = [];
        for (const e of entries) {
            const m = words.length ? match(e.text, words, e.kw) : { score: 0, hits: [] };
            if (m)
                out.push({ e: e, score: m.score, hits: m.hits });
        }
        if (words.length && !req?.noSort)
            out.sort((a, b) => b.score - a.score);
        shown = out;
        current = 0;
    }
    // Letters found in voile (no bold, brand.md)
    function rich(text, hits, sel) {
        const esc = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/ /g, " ");
        if (!hits.length)
            return esc(text);
        const set = new Set(hits);
        const col = sel ? launcher.selMatch : FiliTheme.voile;
        let r = "";
        for (let i = 0; i < text.length; i++)
            r += set.has(i) ? '<font color="' + col + '">' + esc(text[i]) + "</font>" : esc(text[i]);
        return r;
    }
    function accept() {
        if (shown.length)
            finish(0, shown[current].e.accept);
        else if (input.text !== "")
            finish(0, input.text);
    }
    function move(d) {
        current = Math.max(0, Math.min(shown.length - 1, current + d));
    }

    // fuzzel prompt ("Style › ", "Timer: ", "› ") -> breadcrumb in capitals ("STYLE", "MENU")
    readonly property string crumb: {
        const p = (req?.prompt ?? "").replace(/[›:>\s]+$/, "").trim();
        return (p || FiliI18n.tr("Menu")).toUpperCase().replace(/\s*›\s*/g, "  ›  ");
    }

    // Unique files per request (mktemp), read at every path change
    FileView {
        id: optsFile
        printErrors: false
        onLoaded: launcher.optsLoaded()
        onLoadFailed: if (path !== "") FiliShell.reply(launcher.pendingReply, "1\n")
    }
    FileView {
        id: inFile
        printErrors: false
        onLoaded: if (launcher.pending) launcher.start(launcher.pending, launcher.pendingReply, text())
        onLoadFailed: if (path !== "") FiliShell.reply(launcher.pendingReply, "1\n")
    }

    Timer {
        id: linger
        interval: 250
    }

    Connections {
        target: FiliShell
        function onCommand(target, action, args) {
            if (target !== "launcher")
                return;
            if (action === "open") {
                // Options as JSON in a file written by fili-shell (free text, accents included)
                launcher.request(args[0], args[1]);
            } else if (action === "close") {
                const was = launcher.open;
                if (was)
                    launcher.finish(1, "");
                FiliShell.reply(args[0], was ? "1" : "0");
            }
        }
    }

    // Keyboard key as a label (menu shortcuts, help in the footer)
    component KeyCap: Rectangle {
        property alias text: capText.text
        implicitWidth: capText.implicitWidth + 12
        implicitHeight: 20
        radius: FiliTheme.radiusControl
        color: launcher.nuit2
        border { width: 1; color: FiliTheme.nuit4 }
        Text {
            id: capText
            anchors.centerIn: parent
            color: FiliTheme.brume2
            font { family: FiliTheme.mono; pixelSize: FiliTheme.sizeSmall }
        }
    }

    PanelWindow {
        id: win
        visible: (launcher.open || linger.running) && !FiliTheme.testing
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "fili-launcher"
        WlrLayershell.keyboardFocus: launcher.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        // Deep night at 35 %, blurred by niri (layer-rule fili-launcher)
        color: FiliTheme.alpha(FiliTheme.nuitProfond, 0.35)

        MouseArea {
            anchors.fill: parent
            onClicked: if (launcher.open) launcher.finish(1, "")
        }

        Rectangle {
            id: box
            enabled: launcher.open
            readonly property int rowH: 40
            readonly property int pad: 18
            readonly property bool listMode: !launcher.req?.promptOnly
            // Rows: the requested ones, without exceeding 70 % of the screen height
            readonly property int maxRows: Math.max(3, Math.floor((win.height * 0.7 - 150) / rowH))
            readonly property int rows: listMode ? Math.min(launcher.req?.lines ?? 12, maxRows, Math.max(1, launcher.shown.length)) : 0
            // Width: 560 px, or the width requested in characters (fili-ai, history), within the screen
            width: Math.min(win.width - 64, Math.max(560, (launcher.req?.width ?? 0) * 11))
            height: column.implicitHeight + 2 * pad
            x: (win.width - width) / 2
            y: Math.round(win.height * 0.2)
            // Barely translucent veil: the blur of the desktop shows through (brand.md, transparency)
            color: FiliTheme.alpha(FiliTheme.nuit, 0.94)
            radius: FiliTheme.radiusWindow
            border { width: 1; color: FiliTheme.nuit4 }
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: column
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: box.pad }
                spacing: FiliTheme.space3

                // Breadcrumb: Jost 500 label in spaced capitals
                Text {
                    text: launcher.crumb
                    color: FiliTheme.ardoise
                    font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall; weight: FiliTheme.weightAccent; letterSpacing: 1.6 }
                }

                // Champ de recherche
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: FiliTheme.radiusWindow
                    color: launcher.nuit2
                    border { width: 1; color: input.activeFocus ? FiliTheme.nuit4 : "transparent" }
                    RowLayout {
                        anchors { fill: parent; leftMargin: FiliTheme.space3; rightMargin: FiliTheme.space3 }
                        spacing: FiliTheme.space2
                        Text {
                            text: box.listMode ? "" : ""
                            color: FiliTheme.ardoise
                            font { family: "Fili Icons"; pixelSize: 16 }
                        }
                        TextInput {
                            id: input
                            Layout.fillWidth: true
                            color: FiliTheme.brume
                            selectionColor: FiliTheme.nuit3
                            selectedTextColor: FiliTheme.brume
                            font { family: FiliTheme.font; pixelSize: FiliTheme.sizeTitle + 2; weight: Font.Light }
                            clip: true
                            onTextChanged: launcher.filter()
                            Text {
                                visible: !input.text
                                text: box.listMode ? FiliI18n.tr("Search…") : FiliI18n.tr("Type…")
                                color: FiliTheme.ardoise
                                font: input.font
                            }
                            Keys.onPressed: k => {
                                const ctrl = k.modifiers & Qt.ControlModifier;
                                if (k.key === Qt.Key_Escape)
                                    launcher.finish(1, "");
                                else if (k.key === Qt.Key_Backspace && (k.modifiers & Qt.ShiftModifier))
                                    launcher.finish(10, "");
                                else if (k.key === Qt.Key_Return || k.key === Qt.Key_Enter)
                                    launcher.accept();
                                else if (k.key === Qt.Key_Down || k.key === Qt.Key_Tab || (ctrl && k.key === Qt.Key_N))
                                    launcher.move(1);
                                else if (k.key === Qt.Key_Up || k.key === Qt.Key_Backtab || (ctrl && k.key === Qt.Key_P))
                                    launcher.move(-1);
                                else if (k.key === Qt.Key_PageDown)
                                    launcher.move(box.rows);
                                else if (k.key === Qt.Key_PageUp)
                                    launcher.move(-box.rows);
                                else if (k.key === Qt.Key_Home && ctrl)
                                    launcher.current = 0;
                                else if (k.key === Qt.Key_End && ctrl)
                                    launcher.current = Math.max(0, launcher.shown.length - 1);
                                else
                                    return;
                                k.accepted = true;
                            }
                        }
                        Text {
                            visible: box.listMode && input.text !== ""
                            text: launcher.shown.length + " / " + launcher.entries.length
                            color: FiliTheme.ardoise
                            font { family: FiliTheme.mono; pixelSize: FiliTheme.sizeSmall }
                        }
                    }
                }

                // Liste
                Item {
                    visible: box.listMode
                    Layout.fillWidth: true
                    implicitHeight: box.rows * box.rowH

                    ListView {
                        id: list
                        anchors.fill: parent
                        clip: true
                        model: launcher.shown
                        currentIndex: launcher.current
                        highlightMoveDuration: 0
                        boundsBehavior: Flickable.StopAtBounds
                        KineticScroll {}
                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            required property int index
                            readonly property var e: modelData.e
                            readonly property bool sel: index === launcher.current
                            width: list.width - (scroll.visible ? 8 : 0)
                            height: box.rowH
                            radius: FiliTheme.radiusWindow
                            color: sel ? FiliTheme.nuit3 : "transparent"

                            // Voile edge of the selection (like the active workspace of the fili-bar)
                            Rectangle {
                                visible: row.sel
                                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                width: 3
                                height: 18
                                radius: FiliTheme.radiusMark
                                color: FiliTheme.voile
                            }

                            RowLayout {
                                anchors { fill: parent; leftMargin: FiliTheme.space3; rightMargin: FiliTheme.space3 }
                                spacing: FiliTheme.space3
                                // Icon column: menu glyph, theme icon or thumbnail
                                Item {
                                    visible: row.e.glyph !== "" || row.e.icon !== "" || row.e.thumb !== ""
                                    // 24 px column; 44 px for a wide image (wallpaper thumbnail)
                                    implicitWidth: thumb.visible && thumb.implicitWidth > thumb.implicitHeight * 1.2 ? 44 : 24
                                    implicitHeight: 28
                                    Text {
                                        visible: row.e.glyph !== ""
                                        anchors.centerIn: parent
                                        text: row.e.glyph
                                        color: row.sel ? FiliTheme.voile : FiliTheme.brume2
                                        font { family: "Fili Icons"; pixelSize: FiliTheme.sizeTitle }
                                    }
                                    IconImage {
                                        visible: row.e.icon !== ""
                                        anchors.centerIn: parent
                                        source: row.e.icon
                                        implicitSize: 22
                                    }
                                    Image {
                                        id: thumb
                                        visible: row.e.thumb !== ""
                                        anchors.fill: parent
                                        source: row.e.thumb
                                        sourceSize { width: 88; height: 56 }
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: launcher.rich(row.e.text, row.modelData.hits, row.sel)
                                    textFormat: Text.StyledText
                                    elide: Text.ElideRight
                                    color: row.sel ? FiliTheme.brume : FiliTheme.brume2
                                    font { family: FiliTheme.font; pixelSize: FiliTheme.size + 1 }
                                }
                                KeyCap {
                                    visible: row.e.key !== ""
                                    text: row.e.key
                                }
                                Text {
                                    visible: row.e.sub
                                    text: "›"
                                    color: row.sel ? FiliTheme.voile : FiliTheme.ardoise
                                    font { family: FiliTheme.font; pixelSize: FiliTheme.sizeTitle }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: launcher.current = row.index
                                onClicked: {
                                    launcher.current = row.index;
                                    launcher.accept();
                                }
                            }
                        }
                    }

                    // Thin scroll bar, only if the list overflows
                    Rectangle {
                        id: scroll
                        visible: list.contentHeight > list.height + 1
                        anchors.right: parent.right
                        width: 3
                        radius: FiliTheme.radiusMark
                        color: FiliTheme.nuit4
                        y: list.visibleArea.yPosition * list.height
                        height: Math.max(24, list.visibleArea.heightRatio * list.height)
                    }

                    // No result
                    Column {
                        visible: launcher.shown.length === 0
                        anchors.centerIn: parent
                        spacing: FiliTheme.space1
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: FiliI18n.tr("No result")
                            color: FiliTheme.brume2
                            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                        }
                        Text {
                            visible: input.text !== ""
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: FiliI18n.tr("Enter: use “%1”", input.text)
                            color: FiliTheme.ardoise
                            font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList }
                        }
                    }
                }

                // Pied: rappel du clavier
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: FiliTheme.nuit3
                }
                RowLayout {
                    spacing: FiliTheme.space4
                    Repeater {
                        model: box.listMode
                            ? [["↑ ↓", FiliI18n.tr("navigate")], ["⏎", FiliI18n.tr("choose")], ["⇧ ⌫", FiliI18n.tr("back")], [FiliI18n.tr("Esc"), FiliI18n.tr("close")]]
                            : [["⏎", FiliI18n.tr("confirm")], ["⇧ ⌫", FiliI18n.tr("back")], [FiliI18n.tr("Esc"), FiliI18n.tr("close")]]
                        RowLayout {
                            required property var modelData
                            spacing: FiliTheme.space2
                            KeyCap { text: parent.modelData[0] }
                            Text {
                                text: parent.modelData[1]
                                color: FiliTheme.ardoise
                                font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList }
                            }
                        }
                    }
                }
            }
        }
    }
}
