// fili-panel clavier: dispositions xkb de la session niri (Niri.layouts), choix direct ou retour à la précédente,
// visualiseur de clavier (clic = frappe via wtype) et sélecteur d'emoji (clic = copie dans le presse-papiers et frappe)
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ColumnLayout {
    id: view
    spacing: 4
    // "layouts" | "viewer" | "emoji"
    property string page: "layouts"
    // Le visualiseur ne prend pas le focus clavier: la frappe de wtype doit arriver dans la fenêtre d'avant (voir FiliPanel)
    readonly property bool passive: page === "viewer"
    readonly property bool hasPrevious: Niri.previousLayout >= 0 && Niri.previousLayout < Niri.layouts.length

    // Visualiseur: touches du groupe courant (fili-keymap), modificateurs à usage unique
    property var rows: []
    property bool shift: false
    property bool altgr: false
    readonly property int level: (shift ? 1 : 0) + (altgr ? 2 : 0)
    readonly property real unit: 312 / 14.5
    readonly property var offsets: [0, 0.5, 0.75, 1.25]

    // Emoji: liste de ~/.local/share/menu/emoji.txt (le même fichier que `menu emoji`), filtrée par la recherche
    property var emojis: []
    property string query: ""
    readonly property var found: {
        const words = query.toLowerCase().split(/\s+/).filter(w => w);
        const out = [];
        for (const e of emojis) {
            if (words.every(w => e.name.includes(w))) {
                out.push(e);
                if (out.length >= 48)
                    break;
            }
        }
        return out;
    }

    function typeKey(sym) {
        FiliTheme.run("wtype -k " + sym);
        shift = false;
        altgr = false;
    }
    function pickEmoji(char) {
        FiliPanel.close();
        // le panneau fermé, le focus revient à la fenêtre d'avant; la copie reste disponible si la frappe échoue
        FiliTheme.run("printf '%s' '" + char + "' | wl-copy; sleep 0.25; wtype '" + char + "'");
    }
    function loadKeys() {
        keymap.running = false;
        keymap.command = [FiliTheme.bin + "/fili-keymap", String(Math.max(0, Niri.layout))];
        keymap.running = true;
    }
    // Clavier: Retour arrière revient aux dispositions (hors du champ de recherche, qui le garde pour effacer)
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Backspace && page !== "layouts") {
            page = "layouts";
            e.accepted = true;
        }
    }
    onPageChanged: {
        if (page === "viewer")
            loadKeys();
        else if (page === "emoji") {
            if (emojis.length === 0)
                emojiFile.path = Quickshell.env("FILI_EMOJI") || Quickshell.env("HOME") + "/.local/share/menu/emoji.txt";
            search.forceActiveFocus();
        }
    }
    Connections {
        target: Niri
        function onLayoutChanged() {
            if (view.page === "viewer")
                view.loadKeys();
        }
    }

    Process {
        id: keymap
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    view.rows = JSON.parse(text).rows;
                } catch (e) {
                    view.rows = [];
                }
            }
        }
    }
    // Liste lue à la première ouverture de la page emoji (chemin posé à ce moment-là), sans processus
    FileView {
        id: emojiFile
        printErrors: false
        onLoaded: {
            // « 😀 grinning face (face-smiling) »: caractère, puis nom en anglais
            view.emojis = text().split("\n").filter(l => l).map(l => {
                const i = l.indexOf(" ");
                return { c: l.slice(0, i), name: l.slice(i + 1).toLowerCase() };
            });
        }
    }

    // ───── en-tête ─────
    RowLayout {
        Layout.fillWidth: true
        Text {
            visible: view.page !== "layouts"
            text: "‹"
            color: FiliTheme.brume2
            font { family: FiliTheme.font; pixelSize: 16 }
            MouseArea {
                objectName: "back"
                anchors { fill: parent; margins: -6 }
                cursorShape: Qt.PointingHandCursor
                onClicked: view.page = "layouts"
            }
        }
        Text {
            text: view.page === "viewer" ? FiliI18n.tr("Keyboard viewer") : view.page === "emoji" ? FiliI18n.tr("Emoji") : FiliI18n.tr("Keyboard")
            color: FiliTheme.voile
            font { family: FiliTheme.font; pixelSize: 14; weight: Font.Medium }
        }
    }

    // ───── dispositions ─────
    // Rétroéclairage du clavier (stat display de bar-stats, en %), -1: absent
    property real keys: (FiliShell.stats.display?.kbd ?? -1) < 0 ? -1 : FiliShell.stats.display.kbd / 100
    PanelSection { visible: view.page === "layouts" && Niri.layouts.length > 0; text: FiliI18n.tr("LAYOUTS") }
    Repeater {
        model: view.page === "layouts" ? Niri.layouts : []
        PanelButton {
            required property string modelData
            required property int index
            objectName: "layout"
            glyph: index === Niri.layout ? "●" : ""
            label: modelData
            sel: index === Niri.layout
            detail: Niri.shortName(modelData)
            onClicked: Niri.selectLayout(index)
        }
    }
    PanelButton {
        objectName: "previous"
        visible: view.page === "layouts" && view.hasPrevious
        glyph: "↺"
        label: FiliI18n.tr("Previous layout")
        detail: view.hasPrevious ? Niri.shortName(Niri.layouts[Niri.previousLayout]) : ""
        onClicked: Niri.selectLayout(Niri.previousLayout)
    }
    Text {
        visible: view.page === "layouts" && Niri.layouts.length === 0
        text: FiliI18n.tr("No layout found")
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: FiliTheme.size }
    }
    PanelSection { visible: view.page === "layouts"; text: FiliI18n.tr("TOOLS") }
    PanelButton {
        objectName: "open-viewer"
        visible: view.page === "layouts"
        glyph: ""
        label: FiliI18n.tr("Keyboard viewer")
        onClicked: view.page = "viewer"
    }
    PanelButton {
        objectName: "open-emoji"
        visible: view.page === "layouts"
        glyph: ""
        label: FiliI18n.tr("Emoji")
        onClicked: view.page = "emoji"
    }
    PanelButton {
        objectName: "open-hotkeys"
        visible: view.page === "layouts"
        glyph: "\uf11c"
        label: FiliI18n.tr("Keyboard shortcuts")
        detail: FiliI18n.tr("Super+Shift+/")
        onClicked: {
            FiliPanel.close();
            FiliHotkeys.show();
        }
    }
    Text {
        visible: view.page === "layouts" && Niri.layouts.length > 1
        Layout.topMargin: 4
        text: FiliI18n.tr("Layouts: XKB_LAYOUT in config.env")
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: 12 }
    }

    // ───── visualiseur ─────
    Repeater {
        model: view.page === "viewer" ? view.rows : []
        Item {
            required property var modelData
            required property int index
            Layout.preferredHeight: view.unit
            Layout.fillWidth: true
            Row {
                x: view.offsets[index] * view.unit
                spacing: 2
                Repeater {
                    model: modelData
                    Rectangle {
                        id: key
                        required property var modelData
                        readonly property var lv: modelData.l[view.level][0] !== "NoSymbol" ? modelData.l[view.level] : modelData.l[0]
                        objectName: "key"
                        width: view.unit - 2; height: view.unit - 2
                        radius: 4
                        color: keyArea.pressed ? FiliTheme.nuit4 : keyArea.containsMouse ? FiliTheme.nuit3 : "transparent"
                        border { color: FiliTheme.nuit4; width: 1 }
                        Text {
                            anchors.centerIn: parent
                            text: key.lv[1] || (key.lv[0] !== "NoSymbol" ? "◌" : "")
                            color: key.lv[1] ? FiliTheme.brume : FiliTheme.ardoise
                            font { family: FiliTheme.font; pixelSize: 12 }
                        }
                        MouseArea {
                            id: keyArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: key.lv[0] !== "NoSymbol"
                            onClicked: view.typeKey(key.lv[0])
                        }
                    }
                }
            }
        }
    }
    Row {
        visible: view.page === "viewer"
        spacing: 2
        Repeater {
            model: [
                { id: "shift", label: FiliI18n.tr("Shift"), w: 2 }, { id: "altgr", label: "AltGr", w: 2 },
                { id: "space", label: FiliI18n.tr("Space"), w: 5.5 }, { id: "BackSpace", label: "⌫", w: 1.5 }, { id: "Return", label: "⏎", w: 1.5 }
            ]
            Rectangle {
                required property var modelData
                objectName: "mod-" + modelData.id
                readonly property bool on: modelData.id === "shift" ? view.shift : modelData.id === "altgr" ? view.altgr : false
                width: modelData.w * view.unit - 2; height: view.unit - 2
                radius: 4
                color: on ? FiliTheme.voile : modAreaCol.containsMouse ? FiliTheme.nuit3 : "transparent"
                border { color: FiliTheme.nuit4; width: 1 }
                Text {
                    anchors.centerIn: parent
                    text: modelData.label
                    color: parent.on ? FiliTheme.nuit : FiliTheme.brume
                    font { family: FiliTheme.font; pixelSize: 12 }
                }
                MouseArea {
                    id: modAreaCol
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (modelData.id === "shift")
                            view.shift = !view.shift;
                        else if (modelData.id === "altgr")
                            view.altgr = !view.altgr;
                        else
                            view.typeKey(modelData.id);
                    }
                }
            }
        }
    }
    Text {
        visible: view.page === "viewer"
        Layout.topMargin: 4
        text: FiliI18n.tr("click: types the key in the active window · Shift / AltGr: next level")
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: 12 }
    }

    // ───── emoji ─────
    Rectangle {
        visible: view.page === "emoji"
        Layout.fillWidth: true
        implicitHeight: 28
        radius: 6
        color: FiliTheme.nuit3
        TextInput {
            id: search
            objectName: "search"
            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
            verticalAlignment: TextInput.AlignVCenter
            color: FiliTheme.brume
            selectionColor: FiliTheme.ardoise
            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
            clip: true
            onTextChanged: view.query = text
            activeFocusOnTab: true
            // Entrée: premier résultat
            Keys.onReturnPressed: if (view.found.length) view.pickEmoji(view.found[0].c)
            Text {
                visible: !search.text
                anchors.verticalCenter: parent.verticalCenter
                text: FiliI18n.tr("Search (smile, heart, thumbs…)")
                color: FiliTheme.ardoise
                font: search.font
            }
        }
    }
    Flow {
        visible: view.page === "emoji"
        Layout.fillWidth: true
        Repeater {
            model: view.page === "emoji" ? view.found : []
            Rectangle {
                required property var modelData
                id: cell
                objectName: "emoji"
                width: 39; height: 36
                radius: 6
                color: emojiArea.containsMouse ? FiliTheme.nuit3 : "transparent"
                // Clavier: ←/→ (comme ↑/↓) d'emoji en emoji, Entrée ou Espace = choisir
                activeFocusOnTab: true
                onActiveFocusChanged: if (activeFocus) view.hovered = modelData.name
                Keys.onLeftPressed: e => e.modifiers & Qt.ShiftModifier ? e.accepted = false : FiliPanel.moveFocus(cell, cell, false)
                Keys.onRightPressed: e => e.modifiers & Qt.ShiftModifier ? e.accepted = false : FiliPanel.moveFocus(cell, cell, true)
                Keys.onReturnPressed: view.pickEmoji(modelData.c)
                Keys.onSpacePressed: view.pickEmoji(modelData.c)
                FocusRing {}
                Text {
                    anchors.centerIn: parent
                    text: modelData.c
                    font { family: "Noto Color Emoji"; pixelSize: 22 }
                }
                MouseArea {
                    id: emojiArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: if (containsMouse) view.hovered = modelData.name
                    onClicked: view.pickEmoji(modelData.c)
                }
            }
        }
    }
    property string hovered: ""
    Text {
        visible: view.page === "emoji"
        text: view.hovered || (view.found.length === 0 ? FiliI18n.tr("No result") : FiliI18n.tr("click: copies and types in the active window"))
        elide: Text.ElideRight
        Layout.fillWidth: true
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: 12 }
    }

    // Rétroéclairage du clavier: tout en bas de la page des dispositions
    PanelSection { visible: view.page === "layouts" && view.keys >= 0; text: FiliI18n.tr("BACKLIGHT") }
    PanelSlider {
        objectName: "keys"
        visible: view.page === "layouts" && view.keys >= 0
        glyph: "\uf11c"
        value: Math.max(0, view.keys)
        onMoved: v => {
            view.keys = v;
            FiliTheme.run("brightnessctl -q -d '*kbd_backlight' set " + Math.round(v * 100) + "%; " + FiliTheme.bin + "/fili-shell bar refresh 23");
        }
    }
}
