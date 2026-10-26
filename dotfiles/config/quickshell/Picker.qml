// Sélecteur façon `fuzzel --dmenu` (remplace fuzzel et menu-backdrop), appelé par `fili-shell dmenu`:
// liste filtrée au clavier, icônes (protocole dmenu étendu "texte\0icon\037chemin"), invite seule pour une saisie libre.
// La fenêtre couvre l'écran (calque "menu-backdrop", flouté par niri): le voile reste 250 ms après un choix pour
// enchaîner les sous-menus sans clignoter. Entrée = choix (ou texte saisi sans correspondance), Échap = annuler (1),
// Maj+Retour arrière = revenir (10), clic hors de la boîte = annuler.
pragma Singleton
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

Singleton {
    id: picker
    property var req: null      // options de la requête en cours (voir fili-shell)
    property string replyTo: ""
    property var entries: []    // { label, accept, icon }
    property var shown: []      // { e, score, hits }
    property int current: 0
    property bool open: false

    function finish(rc, text) {
        if (replyTo)
            Control.reply(replyTo, rc + "\n" + (text ?? ""));
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
        const col = sel ? "#b9d0e4" : Theme.voile;
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
    readonly property string fontFamily: req?.font ? req.font.split(",")[0].split(":")[0] : Theme.font
    // Polices de repli (comme fuzzel): icônes en Symbols Nerd Font Mono, à chasse fixe pour aligner les libellés
    readonly property var fontFamilies: (req?.font ? req.font.split(",").map(f => f.split(":")[0]) : [Theme.font, "Symbols Nerd Font Mono"])
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
        target: Control
        function onCommand(name, args) {
            if (name === "dmenu") {
                // Options en JSON dans un fichier écrit par fili-shell (texte libre, accents compris)
                let opts;
                try {
                    optsFile.path = args[0];
                    opts = JSON.parse(optsFile.text());
                } catch (e) {
                    Control.reply(args[1], "1\n");
                    return;
                }
                picker.start(opts, args[1]);
            } else if (name === "picker-close") {
                const was = picker.open;
                if (was)
                    picker.finish(1, "");
                Control.reply(args[0], was ? "1" : "0");
            }
        }
    }

    PanelWindow {
        visible: picker.open || linger.running
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "menu-backdrop"
        WlrLayershell.keyboardFocus: picker.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        // rgba(24, 29, 37, 0.35): nuit profond, flouté par niri (layer-rule menu-backdrop)
        color: Qt.rgba(24 / 255, 29 / 255, 37 / 255, 0.35)

        MouseArea {
            anchors.fill: parent
            onClicked: picker.finish(1, "")
        }

        FontMetrics {
            id: fm
            font.family: picker.fontFamily
            font.pointSize: picker.fontPt
        }

        Rectangle {
            id: box
            visible: picker.open
            anchors.centerIn: parent
            readonly property int lineH: 32
            readonly property int rows: picker.req?.promptOnly ? 0 : Math.min(picker.req?.lines ?? 12, picker.shown.length)
            width: (picker.req?.width || 36) * fm.averageCharacterWidth + 32
            height: 14 * 2 + lineH + (rows > 0 ? 10 + rows * lineH : 0)
            color: Qt.rgba(28 / 255, 34 / 255, 43 / 255, 0.98)
            radius: 14
            border { width: 1; color: Theme.nuit4 }
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                anchors { fill: parent; topMargin: 14; bottomMargin: 14; leftMargin: 16; rightMargin: 16 }
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: box.lineH
                    spacing: 0
                    Text {
                        text: picker.req?.prompt ?? ""
                        color: Theme.brume
                        font { families: picker.fontFamilies; pointSize: picker.fontPt }
                    }
                    TextInput {
                        id: input
                        Layout.fillWidth: true
                        color: Theme.brume
                        selectionColor: Theme.nuit3
                        font { families: picker.fontFamilies; pointSize: picker.fontPt }
                        clip: true
                        onTextChanged: picker.filter()
                        Text {
                            visible: !input.text && !picker.req?.promptOnly
                            text: "Search..."
                            color: Theme.ardoise
                            font: input.font
                        }
                        Keys.onPressed: k => {
                            const n = picker.shown.length;
                            const ctrl = k.modifiers & Qt.ControlModifier;
                            if (k.key === Qt.Key_Escape) {
                                picker.finish(1, "");
                            } else if (k.key === Qt.Key_Backspace && (k.modifiers & Qt.ShiftModifier)) {
                                picker.finish(10, "");
                            } else if (k.key === Qt.Key_Return || k.key === Qt.Key_Enter) {
                                picker.accept();
                            } else if (k.key === Qt.Key_Down || k.key === Qt.Key_Tab || (ctrl && k.key === Qt.Key_N)) {
                                picker.current = Math.min(n - 1, picker.current + 1);
                            } else if (k.key === Qt.Key_Up || k.key === Qt.Key_Backtab || (ctrl && k.key === Qt.Key_P)) {
                                picker.current = Math.max(0, picker.current - 1);
                            } else if (k.key === Qt.Key_PageDown) {
                                picker.current = Math.min(n - 1, picker.current + box.rows);
                            } else if (k.key === Qt.Key_PageUp) {
                                picker.current = Math.max(0, picker.current - box.rows);
                            } else {
                                return;
                            }
                            k.accepted = true;
                        }
                    }
                    Text {
                        visible: !picker.req?.promptOnly && input.text !== ""
                        text: picker.shown.length + "/" + picker.entries.length
                        color: Theme.ardoise
                        font { families: picker.fontFamilies; pointSize: picker.fontPt - 2 }
                    }
                }

                ListView {
                    id: list
                    visible: box.rows > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: picker.shown
                    currentIndex: picker.current
                    highlightMoveDuration: 0
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool sel: index === picker.current
                        width: list.width
                        height: box.lineH
                        radius: 9
                        color: sel ? Theme.nuit3 : "transparent"
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
                                text: picker.rich(parent.parent.modelData.e.label, parent.parent.modelData.hits, parent.parent.sel)
                                textFormat: Text.StyledText
                                elide: Text.ElideRight
                                color: Theme.brume
                                font { families: picker.fontFamilies; pointSize: picker.fontPt }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: picker.current = parent.index
                            onClicked: {
                                picker.current = parent.index;
                                picker.accept();
                            }
                        }
                    }
                }
            }
        }
    }
}
