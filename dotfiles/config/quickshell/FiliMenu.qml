pragma Singleton
// fili-menu: sélecteur façon `fuzzel --dmenu` (remplace fuzzel et menu-backdrop), appelé par `fili-shell menu`
// (script ~/.local/bin/menu, minuteur, fili-ai): liste filtrée au clavier, icônes (protocole dmenu étendu
// "texte\0icon\037chemin"), invite seule pour une saisie libre. La fenêtre couvre l'écran (calque "fili-menu",
// flouté par niri): le voile reste 250 ms après un choix pour enchaîner les sous-menus sans clignoter.
// Entrée = choix (ou texte saisi sans correspondance), Échap = annuler (1), Maj+Retour arrière = revenir (10),
// clic hors de la boîte = annuler.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

Singleton {
    id: menu
    property var req: null      // options de la requête en cours (voir fili-shell)
    property string replyTo: ""
    property var entries: []    // { label, accept, icon }
    property var shown: []      // { e, score, hits }
    property int current: 0
    property bool open: false

    function finish(rc, text) {
        if (replyTo)
            FiliShell.reply(replyTo, rc + "\n" + (text ?? ""));
        replyTo = "";
        req = null;
        open = false;
        linger.restart();
    }

    function start(opts, reply) {
        if (replyTo)
            finish(1, "");
        linger.stop();
        req = opts;
        replyTo = reply;
        let raw = "";
        if (!opts.promptOnly) {
            inFile.path = opts.input;
            raw = inFile.text();
        }
        const list = [];
        for (const line of raw.split("\n")) {
            if (line === "")
                continue;
            const [text, extra] = line.split("\0");
            const icon = extra && extra.startsWith("icon\x1f") ? extra.slice(5) : "";
            const cols = text.split("\t");
            list.push({
                label: opts.withNth > 0 ? (cols[opts.withNth - 1] ?? text) : text,
                accept: opts.acceptNth > 0 ? (cols[opts.acceptNth - 1] ?? text) : text,
                icon: !icon ? "" : icon.startsWith("/") ? "file://" + icon : Quickshell.iconPath(icon, true)
            });
        }
        entries = list;
        input.text = "";
        filter();
        open = true;
        input.forceActiveFocus();
    }

    // Correspondance: chaque mot de la saisie doit apparaître (sous-chaîne, sinon lettres dans l'ordre);
    // score: début de libellé > début de mot > sous-chaîne > lettres dispersées. --no-sort garde l'ordre d'origine.
    function match(label, words) {
        const l = label.toLowerCase();
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
        const words = input.text.toLowerCase().split(/\s+/).filter(w => w);
        let out = [];
        for (const e of entries) {
            const m = words.length ? match(e.label, words) : { score: 0, hits: [] };
            if (m)
                out.push({ e: e, score: m.score, hits: m.hits });
        }
        if (words.length && !req?.noSort)
            out.sort((a, b) => b.score - a.score);
        shown = out;
        current = 0;
    }
    function rich(label, hits, sel) {
        // Espaces insécables: le texte riche fusionnerait les espaces d'alignement du menu principal
        const esc = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/ /g, "\u00a0");
        if (!hits.length)
            return esc(label);
        const set = new Set(hits);
        const col = sel ? "#b9d0e4" : FiliTheme.voile;
        let r = "";
        for (let i = 0; i < label.length; i++)
            r += set.has(i) ? '<font color="' + col + '">' + esc(label[i]) + "</font>" : esc(label[i]);
        return r;
    }
    function accept() {
        if (shown.length)
            finish(0, shown[current].e.accept);
        else if (input.text !== "")
            finish(0, input.text);
    }

    // Police de la requête ("Nom:size=N,..." comme fuzzel), sinon Jost 13 pt
    readonly property string fontFamily: req?.font ? req.font.split(",")[0].split(":")[0] : FiliTheme.font
    readonly property real fontPt: {
        const m = (req?.font ?? "").match(/size=(\d+)/);
        return m ? parseInt(m[1]) : 13;
    }

    // Fichiers uniques par requête (mktemp): le changement de chemin les lit, de façon bloquante
    FileView { id: optsFile; blockLoading: true; printErrors: false }
    FileView { id: inFile; blockLoading: true; printErrors: false }

    Timer {
        id: linger
        interval: 250
    }

    Connections {
        target: FiliShell
        function onCommand(target, action, args) {
            if (target !== "menu")
                return;
            if (action === "open") {
                // Options en JSON dans un fichier écrit par fili-shell (texte libre, accents compris)
                let opts;
                try {
                    optsFile.path = args[0];
                    opts = JSON.parse(optsFile.text());
                } catch (e) {
                    FiliShell.reply(args[1], "1\n");
                    return;
                }
                menu.start(opts, args[1]);
            } else if (action === "close") {
                const was = menu.open;
                if (was)
                    menu.finish(1, "");
                FiliShell.reply(args[0], was ? "1" : "0");
            }
        }
    }

    PanelWindow {
        visible: menu.open || linger.running
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "fili-menu"
        WlrLayershell.keyboardFocus: menu.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        // rgba(24, 29, 37, 0.35): nuit profond, flouté par niri (layer-rule fili-menu)
        color: Qt.rgba(24 / 255, 29 / 255, 37 / 255, 0.35)

        MouseArea {
            anchors.fill: parent
            onClicked: menu.finish(1, "")
        }

        FontMetrics {
            id: fm
            font.family: menu.fontFamily
            font.pointSize: menu.fontPt
        }

        Rectangle {
            id: box
            visible: menu.open
            anchors.centerIn: parent
            readonly property int lineH: 32
            readonly property int rows: menu.req?.promptOnly ? 0 : Math.min(menu.req?.lines ?? 12, menu.shown.length)
            width: (menu.req?.width || 36) * fm.averageCharacterWidth + 32
            height: 14 * 2 + lineH + (rows > 0 ? 10 + rows * lineH : 0)
            color: Qt.rgba(28 / 255, 34 / 255, 43 / 255, 0.98)
            radius: 14
            border { width: 1; color: FiliTheme.nuit4 }
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                anchors { fill: parent; topMargin: 14; bottomMargin: 14; leftMargin: 16; rightMargin: 16 }
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: box.lineH
                    spacing: 0
                    Text {
                        text: menu.req?.prompt ?? ""
                        color: FiliTheme.brume
                        font { family: menu.fontFamily; pointSize: menu.fontPt }
                    }
                    TextInput {
                        id: input
                        Layout.fillWidth: true
                        color: FiliTheme.brume
                        selectionColor: FiliTheme.nuit3
                        font { family: menu.fontFamily; pointSize: menu.fontPt }
                        clip: true
                        onTextChanged: menu.filter()
                        Text {
                            visible: !input.text && !menu.req?.promptOnly
                            text: "Search..."
                            color: FiliTheme.ardoise
                            font: input.font
                        }
                        Keys.onPressed: k => {
                            const n = menu.shown.length;
                            const ctrl = k.modifiers & Qt.ControlModifier;
                            if (k.key === Qt.Key_Escape) {
                                menu.finish(1, "");
                            } else if (k.key === Qt.Key_Backspace && (k.modifiers & Qt.ShiftModifier)) {
                                menu.finish(10, "");
                            } else if (k.key === Qt.Key_Return || k.key === Qt.Key_Enter) {
                                menu.accept();
                            } else if (k.key === Qt.Key_Down || k.key === Qt.Key_Tab || (ctrl && k.key === Qt.Key_N)) {
                                menu.current = Math.min(n - 1, menu.current + 1);
                            } else if (k.key === Qt.Key_Up || k.key === Qt.Key_Backtab || (ctrl && k.key === Qt.Key_P)) {
                                menu.current = Math.max(0, menu.current - 1);
                            } else if (k.key === Qt.Key_PageDown) {
                                menu.current = Math.min(n - 1, menu.current + box.rows);
                            } else if (k.key === Qt.Key_PageUp) {
                                menu.current = Math.max(0, menu.current - box.rows);
                            } else {
                                return;
                            }
                            k.accepted = true;
                        }
                    }
                    Text {
                        visible: !menu.req?.promptOnly && input.text !== ""
                        text: menu.shown.length + "/" + menu.entries.length
                        color: FiliTheme.ardoise
                        font { family: menu.fontFamily; pointSize: menu.fontPt - 2 }
                    }
                }

                ListView {
                    id: list
                    visible: box.rows > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: menu.shown
                    currentIndex: menu.current
                    highlightMoveDuration: 0
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool sel: index === menu.current
                        width: list.width
                        height: box.lineH
                        radius: 9
                        color: sel ? FiliTheme.nuit3 : "transparent"
                        RowLayout {
                            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                            spacing: 10
                            IconImage {
                                visible: parent.parent.modelData.e.icon !== ""
                                source: parent.parent.modelData.e.icon
                                implicitSize: 22
                            }
                            Text {
                                Layout.fillWidth: true
                                text: menu.rich(parent.parent.modelData.e.label, parent.parent.modelData.hits, parent.parent.sel)
                                textFormat: Text.StyledText
                                elide: Text.ElideRight
                                color: FiliTheme.brume
                                font { family: menu.fontFamily; pointSize: menu.fontPt }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: menu.current = parent.index
                            onClicked: {
                                menu.current = parent.index;
                                menu.accept();
                            }
                        }
                    }
                }
            }
        }
    }
}
