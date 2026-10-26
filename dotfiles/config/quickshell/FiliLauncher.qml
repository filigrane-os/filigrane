pragma Singleton
// fili-launcher: lanceur et sélecteur façon `fuzzel --dmenu` (menu ~/.local/bin/menu, applications, minuteur, fili-ai),
// appelé par `fili-shell launcher`. Liste filtrée au clavier, icônes (protocole dmenu étendu "texte\0icon\037chemin"),
// invite seule pour une saisie libre. La fenêtre couvre l'écran (calque "fili-launcher", flouté par niri) et la boîte
// est un voile à peine translucide au tiers haut (elle ne saute pas pendant le filtrage); le voile reste 250 ms après
// un choix pour enchaîner les sous-menus sans clignoter. Aucune animation (brand.md).
// Lignes du menu: "glyphe  Libellé ›  ‹Touche›" mis en page (colonne d'icône, chevron de sous-menu, touche en
// étiquette) plutôt qu'aligné par des espaces; la valeur rendue reste la ligne d'origine.
// Entrée = choix (ou texte saisi sans correspondance), Échap = annuler (1), Maj+Retour arrière = revenir (10),
// clic hors de la boîte = annuler.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

Singleton {
    id: launcher
    property var req: null      // options de la requête en cours (voir fili-shell)
    property string replyTo: ""
    property var entries: []    // { accept, glyph, text, sub, key, icon, thumb }
    property var shown: []      // { e, score, hits }
    property int current: 0
    property bool open: false

    readonly property color nuit2: "#232b36"
    readonly property color selMatch: "#b9d0e4"

    function finish(rc, text) {
        if (replyTo)
            FiliShell.reply(replyTo, rc + "\n" + (text ?? ""));
        replyTo = "";
        req = null;
        open = false;
        linger.restart();
    }

    // Découpe une ligne affichée: glyphe Nerd Font en tête (zone d'usage privé), "‹Touche›" et chevron "›" en fin
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

    // Requête lue en deux temps (fichiers lus de façon asynchrone par FileView, voir onLoaded plus bas):
    // options, puis entrées, puis affichage
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
        linger.stop();
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
                accept: opts.acceptNth > 0 ? (cols[opts.acceptNth - 1] ?? text) : text,
                glyph: p.glyph, text: p.text, key: p.key, sub: p.sub,
                // Fichier image (miniature de fond d'écran, icône d'appli en chemin) ou nom d'icône du thème
                thumb: icon.startsWith("/") ? "file://" + icon : "",
                icon: icon && !icon.startsWith("/") ? Quickshell.iconPath(icon, true) : ""
            });
        }
        pending = null;
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
            const m = words.length ? match(e.text, words) : { score: 0, hits: [] };
            if (m)
                out.push({ e: e, score: m.score, hits: m.hits });
        }
        if (words.length && !req?.noSort)
            out.sort((a, b) => b.score - a.score);
        shown = out;
        current = 0;
    }
    // Lettres trouvées en voile (pas de gras, brand.md)
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

    // Invite fuzzel ("Style › ", "Minuteur: ", "› ") -> fil d'Ariane en capitales ("STYLE", "MENU")
    readonly property string crumb: {
        const p = (req?.prompt ?? "").replace(/[›:>\s]+$/, "").trim();
        return (p || "Menu").toUpperCase().replace(/\s*›\s*/g, "  ›  ");
    }

    // Fichiers uniques par requête (mktemp), lus à chaque changement de chemin
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
                // Options en JSON dans un fichier écrit par fili-shell (texte libre, accents compris)
                launcher.request(args[0], args[1]);
            } else if (action === "close") {
                const was = launcher.open;
                if (was)
                    launcher.finish(1, "");
                FiliShell.reply(args[0], was ? "1" : "0");
            }
        }
    }

    // Touche de clavier en étiquette (raccourcis du menu, aide en pied)
    component KeyCap: Rectangle {
        property alias text: capText.text
        implicitWidth: capText.implicitWidth + 12
        implicitHeight: 20
        radius: 5
        color: launcher.nuit2
        border { width: 1; color: FiliTheme.nuit4 }
        Text {
            id: capText
            anchors.centerIn: parent
            color: FiliTheme.brume2
            font { family: FiliTheme.mono; pixelSize: 11 }
        }
    }

    PanelWindow {
        id: win
        visible: launcher.open || linger.running
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "fili-launcher"
        WlrLayershell.keyboardFocus: launcher.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        // rgba(24, 29, 37, 0.35): nuit profond, flouté par niri (layer-rule fili-launcher)
        color: Qt.rgba(24 / 255, 29 / 255, 37 / 255, 0.35)

        MouseArea {
            anchors.fill: parent
            onClicked: launcher.finish(1, "")
        }

        Rectangle {
            id: box
            visible: launcher.open
            readonly property int rowH: 40
            readonly property int pad: 18
            readonly property bool listMode: !launcher.req?.promptOnly
            // Lignes: celles demandées, sans dépasser 70 % de la hauteur de l'écran
            readonly property int maxRows: Math.max(3, Math.floor((win.height * 0.7 - 150) / rowH))
            readonly property int rows: listMode ? Math.min(launcher.req?.lines ?? 12, maxRows, Math.max(1, launcher.shown.length)) : 0
            // Largeur: 560 px, ou la largeur demandée en caractères (fili-ai, historique), dans la limite de l'écran
            width: Math.min(win.width - 64, Math.max(560, (launcher.req?.width ?? 0) * 11))
            height: column.implicitHeight + 2 * pad
            x: (win.width - width) / 2
            y: Math.round(win.height * 0.2)
            // Voile à peine translucide: le flou du bureau transparaît (brand.md, transparence)
            color: Qt.rgba(28 / 255, 34 / 255, 43 / 255, 0.94)
            radius: 16
            border { width: 1; color: FiliTheme.nuit4 }
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: column
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: box.pad }
                spacing: 12

                // Fil d'Ariane: étiquette Jost 500 en capitales espacées
                Text {
                    text: launcher.crumb
                    color: FiliTheme.ardoise
                    font { family: FiliTheme.font; pixelSize: 11; weight: Font.Medium; letterSpacing: 1.6 }
                }

                // Champ de recherche
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: 10
                    color: launcher.nuit2
                    border { width: 1; color: input.activeFocus ? FiliTheme.nuit4 : "transparent" }
                    RowLayout {
                        anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                        spacing: 10
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
                            font { family: FiliTheme.font; pixelSize: 18; weight: Font.Light }
                            clip: true
                            onTextChanged: launcher.filter()
                            Text {
                                visible: !input.text
                                text: box.listMode ? "Rechercher…" : "Saisir…"
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
                            font { family: FiliTheme.mono; pixelSize: 11 }
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
                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            required property int index
                            readonly property var e: modelData.e
                            readonly property bool sel: index === launcher.current
                            width: list.width - (scroll.visible ? 8 : 0)
                            height: box.rowH
                            radius: 10
                            color: sel ? FiliTheme.nuit3 : "transparent"

                            // Liseré voile de la sélection (comme l'espace de travail actif de la fili-bar)
                            Rectangle {
                                visible: row.sel
                                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                width: 3
                                height: 18
                                radius: 2
                                color: FiliTheme.voile
                            }

                            RowLayout {
                                anchors { fill: parent; leftMargin: 14; rightMargin: 12 }
                                spacing: 12
                                // Colonne d'icône: glyphe du menu, icône du thème ou miniature
                                Item {
                                    visible: row.e.glyph !== "" || row.e.icon !== "" || row.e.thumb !== ""
                                    // Colonne de 24 px; 44 px pour une image large (miniature de fond d'écran)
                                    implicitWidth: thumb.visible && thumb.implicitWidth > thumb.implicitHeight * 1.2 ? 44 : 24
                                    implicitHeight: 28
                                    Text {
                                        visible: row.e.glyph !== ""
                                        anchors.centerIn: parent
                                        text: row.e.glyph
                                        color: row.sel ? FiliTheme.voile : FiliTheme.brume2
                                        font { family: "Fili Icons"; pixelSize: 18 }
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
                                    font { family: FiliTheme.font; pixelSize: 15 }
                                }
                                KeyCap {
                                    visible: row.e.key !== ""
                                    text: row.e.key
                                }
                                Text {
                                    visible: row.e.sub
                                    text: "›"
                                    color: row.sel ? FiliTheme.voile : FiliTheme.ardoise
                                    font { family: FiliTheme.font; pixelSize: 18 }
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

                    // Barre de défilement fine, seulement si la liste déborde
                    Rectangle {
                        id: scroll
                        visible: list.contentHeight > list.height + 1
                        anchors.right: parent.right
                        width: 3
                        radius: 2
                        color: FiliTheme.nuit4
                        y: list.visibleArea.yPosition * list.height
                        height: Math.max(24, list.visibleArea.heightRatio * list.height)
                    }

                    // Aucun résultat
                    Column {
                        visible: launcher.shown.length === 0
                        anchors.centerIn: parent
                        spacing: 4
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Aucun résultat"
                            color: FiliTheme.brume2
                            font { family: FiliTheme.font; pixelSize: 14 }
                        }
                        Text {
                            visible: input.text !== ""
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Entrée: utiliser « " + input.text + " »"
                            color: FiliTheme.ardoise
                            font { family: FiliTheme.font; pixelSize: 12 }
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
                    spacing: 16
                    Repeater {
                        model: box.listMode
                            ? [["↑ ↓", "naviguer"], ["⏎", "choisir"], ["⇧ ⌫", "retour"], ["Échap", "fermer"]]
                            : [["⏎", "valider"], ["⇧ ⌫", "retour"], ["Échap", "fermer"]]
                        RowLayout {
                            required property var modelData
                            spacing: 6
                            KeyCap { text: parent.modelData[0] }
                            Text {
                                text: parent.modelData[1]
                                color: FiliTheme.ardoise
                                font { family: FiliTheme.font; pixelSize: 12 }
                            }
                        }
                    }
                }
            }
        }
    }
}
