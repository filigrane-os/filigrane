// fili-panel écrans (inspiré de omarchy-hyprmoncfg): les écrans en canvas (glisser pour les placer, aimantation aux
// bords), puis pour l'écran choisi allumage, définition, fréquence, échelle, rotation et VRR. Les changements passent
// par `niri msg output` (temporaires, appliqués tout de suite); définition, échelle, rotation et extinction sont à
// confirmer sous 15 s, sinon retour à l'état d'avant. « Enregistrer » écrit le profil kanshi (display-save),
// réappliqué à chaque branchement d'écran. En bas: luminosité de l'écran interne (lue par bar-stats, réglée par
// brightnessctl), apparence sombre/claire (fili-theme) et veilleuse.
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

ColumnLayout {
    id: view
    spacing: 4
    // Sorties triées par nom (niri msg -j outputs); logical = null pour une sortie éteinte
    property var outputs: []
    property string sel: ""
    readonly property var cur: outputs.find(o => o.name === sel) ?? null
    readonly property var active: outputs.filter(o => o.logical)
    // Glissement en cours: {name, x, y} en pixels logiques
    property var ghost: null
    // État d'avant le premier changement à confirmer, et secondes restantes
    property var snap: null
    property int secs: 0
    property real screen: -1
    readonly property int canvasH: 110
    readonly property real canvasW: 312

    function cmd(name, args) {
        return "niri msg output '" + name + "' " + args;
    }
    function transformName(t) {
        return String(t).replace(/^Flipped(\d+)$/, "flipped-$1").toLowerCase();
    }
    function modeArg(m) {
        return m.width + "x" + m.height + "@" + (m.refresh_rate / 1000).toFixed(3);
    }
    // Taille logique d'une sortie (celle de niri; en glissant, la même)
    function rect(o) {
        const g = ghost && ghost.name === o.name ? ghost : o.logical;
        return { x: g.x, y: g.y, w: o.logical.width, h: o.logical.height };
    }

    // Sorties demandées sur le socket de niri (requête Outputs), sans `niri msg`
    function read() {
        Niri.request("Outputs", o => {
            // Panneau fermé avant la réponse: plus rien à mettre à jour
            if (!o || !view)
                return;
            view.outputs = Object.values(o).sort((a, b) => a.name.localeCompare(b.name));
            if (!view.cur)
                view.sel = (view.active[0] ?? view.outputs[0] ?? { name: "" }).name;
        });
    }
    Component.onCompleted: {
        read();
        // Luminosité de l'écran interne (stat display de bar-stats, en %), -1: absente
        const b = FiliShell.stats.display?.screen ?? -1;
        screen = b < 0 ? -1 : b / 100;
        readNight.running = true;
    }
    Timer {
        id: reread
        interval: 500
        onTriggered: view.read()
    }
    // Veilleuse (wlsunset): allumée quand l'écran est réellement réchauffé (même critère que bar-status)
    property bool night: false
    Process {
        id: readNight
        command: ["sh", "-c", 'exec "$0" night | grep -q \'"class":"active"\'', FiliTheme.bin + "/bar-status"]
        onExited: code => view.night = code === 0
    }

    // Applique des arguments `niri msg output`; risky = à confirmer (retour à l'état d'avant au bout de 15 s)
    function apply(name, args, risky) {
        if (risky && !snap && cur) {
            snap = cur;
            secs = 15;
            confirm.restart();
        }
        FiliTheme.run(cmd(name, args));
        reread.restart();
    }
    function keep() {
        confirm.stop();
        snap = null;
    }
    function revert() {
        confirm.stop();
        const s = snap;
        snap = null;
        if (!s)
            return;
        let c = cmd(s.name, "on");
        if (!s.logical)
            c = cmd(s.name, "off");
        else {
            c += "; " + cmd(s.name, "mode " + modeArg(s.modes[s.current_mode]));
            c += "; " + cmd(s.name, "scale " + s.logical.scale);
            c += "; " + cmd(s.name, "transform " + transformName(s.logical.transform));
            c += "; " + cmd(s.name, "position set " + s.logical.x + " " + s.logical.y);
        }
        FiliTheme.run(c);
        reread.restart();
    }
    Timer {
        id: confirm
        interval: 1000
        repeat: true
        onTriggered: {
            view.secs -= 1;
            if (view.secs <= 0)
                view.revert();
        }
    }

    function setPower(o, on) {
        apply(o.name, on ? "on" : "off", !on);
    }
    // Définition: garde la fréquence actuelle si elle existe dans la nouvelle, sinon la plus haute
    function setResolution(o, r) {
        const cm = o.modes[o.current_mode];
        const same = o.modes.filter(m => m.width === r.w && m.height === r.h);
        if (!same.length)
            return;
        const m = same.find(x => x.refresh_rate === cm.refresh_rate) ?? same.reduce((a, b) => b.refresh_rate > a.refresh_rate ? b : a);
        apply(o.name, "mode " + modeArg(m), true);
    }
    function setRefresh(o, rate) {
        const cm = o.modes[o.current_mode];
        const m = o.modes.find(x => x.width === cm.width && x.height === cm.height && x.refresh_rate === rate);
        if (m)
            apply(o.name, "mode " + modeArg(m), true);
    }
    function setScale(o, s) {
        apply(o.name, "scale " + s, true);
        // les voisins se recalent: la taille logique change
    }
    function setTransform(o, t) {
        apply(o.name, "transform " + t, true);
    }

    // Aimantation: bords collés ou alignés aux autres sorties à moins de 40 px logiques
    function snapPos(o, x, y) {
        const r = rect(o);
        const T = 40;
        let bx = x, by = y, dx = T, dy = T;
        for (const p of active) {
            if (p.name === o.name)
                continue;
            const q = p.logical;
            for (const c of [q.x + q.width, q.x - r.w, q.x, q.x + q.width - r.w]) {
                if (Math.abs(c - x) < dx) { dx = Math.abs(c - x); bx = c; }
            }
            for (const c of [q.y + q.height, q.y - r.h, q.y, q.y + q.height - r.h]) {
                if (Math.abs(c - y) < dy) { dy = Math.abs(c - y); by = c; }
            }
        }
        return { x: Math.round(bx), y: Math.round(by) };
    }
    function move(o, x, y) {
        const p = snapPos(o, x, y);
        apply(o.name, "position set " + p.x + " " + p.y, false);
        return p;
    }

    // Choix de définition et de fréquence de la sortie choisie
    readonly property var resolutions: {
        if (!cur || !cur.logical)
            return [];
        const seen = {}, out = [];
        for (const m of cur.modes) {
            const k = m.width + "x" + m.height;
            if (!seen[k]) {
                seen[k] = true;
                out.push({ label: m.width + "×" + m.height, value: k, area: m.width * m.height, w: m.width, h: m.height });
            }
        }
        return out.sort((a, b) => b.area - a.area).slice(0, 8);
    }
    readonly property var curMode: cur && cur.logical ? cur.modes[cur.current_mode] : null
    readonly property var refreshes: {
        if (!curMode)
            return [];
        const seen = {}, out = [];
        for (const m of cur.modes) {
            if (m.width !== curMode.width || m.height !== curMode.height)
                continue;
            const hz = Math.round(m.refresh_rate / 1000);
            if (seen[hz] === undefined) {
                seen[hz] = out.length;
                out.push({ label: hz + " Hz", value: m.refresh_rate });
            } else if (m.refresh_rate > out[seen[hz]].value)
                out[seen[hz]].value = m.refresh_rate;
        }
        return out.sort((a, b) => b.value - a.value);
    }
    readonly property var scales: [1, 1.25, 1.5, 1.75, 2, 3].map(s => ({ label: String(s), value: s }))
    readonly property var transforms: [["normal", "0°"], ["90", "90°"], ["180", "180°"], ["270", "270°"]].map(t => ({ label: t[1], value: t[0] }))

    Text {
        text: "Écrans"
        color: FiliTheme.voile
        font { family: FiliTheme.font; pixelSize: 14; weight: Font.Medium }
    }

    // Canvas: sorties allumées à l'échelle, glisser pour déplacer
    Item {
        id: canvas
        objectName: "canvas"
        Layout.fillWidth: true
        implicitHeight: view.canvasH
        visible: view.active.length > 0
        // Zone logique couverte (avec de la marge pour pouvoir glisser vers l'extérieur) et facteur d'échelle
        readonly property var box: {
            let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
            for (const o of view.active) {
                x0 = Math.min(x0, o.logical.x); y0 = Math.min(y0, o.logical.y);
                x1 = Math.max(x1, o.logical.x + o.logical.width); y1 = Math.max(y1, o.logical.y + o.logical.height);
            }
            const pad = Math.max(x1 - x0, y1 - y0) * 0.3;
            return { x: x0 - pad, y: y0 - pad, w: x1 - x0 + 2 * pad, h: y1 - y0 + 2 * pad };
        }
        readonly property real k: view.active.length ? Math.min(width / box.w, height / box.h) : 1
        readonly property real offX: (width - box.w * k) / 2
        readonly property real offY: (height - box.h * k) / 2

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: FiliTheme.nuit3
            opacity: 0.4
        }
        Repeater {
            model: view.active
            Rectangle {
                id: tile
                required property var modelData
                readonly property var r: view.rect(modelData)
                readonly property bool picked: modelData.name === view.sel
                x: canvas.offX + (r.x - canvas.box.x) * canvas.k
                y: canvas.offY + (r.y - canvas.box.y) * canvas.k
                width: r.w * canvas.k
                height: r.h * canvas.k
                radius: 3
                color: picked ? FiliTheme.nuit4 : FiliTheme.nuit
                border.color: picked ? FiliTheme.voile : FiliTheme.ardoise
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    width: parent.width - 4
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: tile.modelData.name
                    color: tile.picked ? FiliTheme.voile : FiliTheme.brume2
                    font { family: FiliTheme.font; pixelSize: 11 }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SizeAllCursor
                    property point from
                    property var start
                    onPressed: m => {
                        view.sel = tile.modelData.name;
                        from = mapToItem(canvas, m.x, m.y);
                        start = Qt.point(tile.modelData.logical.x, tile.modelData.logical.y);
                    }
                    onPositionChanged: m => {
                        if (!pressed)
                            return;
                        const p = mapToItem(canvas, m.x, m.y);
                        const s = view.snapPos(tile.modelData, start.x + (p.x - from.x) / canvas.k, start.y + (p.y - from.y) / canvas.k);
                        view.ghost = { name: tile.modelData.name, x: s.x, y: s.y };
                    }
                    onReleased: {
                        const g = view.ghost;
                        if (g && (g.x !== start.x || g.y !== start.y))
                            view.move(tile.modelData, g.x, g.y);
                        view.ghost = null;
                    }
                }
            }
        }
    }
    Text {
        visible: view.outputs.length === 0
        text: "Aucun écran détecté"
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: FiliTheme.size }
    }

    // Choix de l'écran quand il y en a plusieurs (ou un éteint)
    PanelChips {
        visible: view.outputs.length > 1
        model: view.outputs.map(o => ({ label: o.name + (o.logical ? "" : " (éteint)"), value: o.name }))
        current: view.sel
        onPicked: v => view.sel = v
    }

    // Écran choisi
    RowLayout {
        visible: view.cur !== null
        Layout.fillWidth: true
        Layout.topMargin: 4
        Text {
            text: view.cur ? ((view.cur.make ?? "") + " " + (view.cur.model ?? "")).trim() || view.cur.name : ""
            color: FiliTheme.brume
            Layout.fillWidth: true
            elide: Text.ElideRight
            font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: Font.Medium }
        }
        PanelSwitch {
            objectName: "power"
            checked: view.cur !== null && view.cur.logical !== null
            // le dernier écran allumé ne s'éteint pas
            switchable: view.cur !== null && (view.cur.logical === null || view.active.length > 1)
            onToggled: view.setPower(view.cur, !checked)
        }
    }

    PanelSection { visible: view.curMode !== null; divided: false; text: "DÉFINITION" }
    PanelChips {
        objectName: "resolution"
        visible: view.curMode !== null
        model: view.resolutions
        current: view.curMode ? view.curMode.width + "x" + view.curMode.height : ""
        onPicked: v => view.setResolution(view.cur, view.resolutions.find(r => r.value === v))
    }
    PanelSection { visible: view.refreshes.length > 1; divided: false; text: "FRÉQUENCE" }
    PanelChips {
        objectName: "refresh"
        visible: view.refreshes.length > 1
        model: view.refreshes
        current: view.curMode ? view.curMode.refresh_rate : 0
        onPicked: v => view.setRefresh(view.cur, v)
    }
    PanelSection { visible: view.curMode !== null; divided: false; text: "ÉCHELLE" }
    PanelChips {
        objectName: "scale"
        visible: view.curMode !== null
        model: view.scales
        current: view.cur && view.cur.logical ? view.cur.logical.scale : 0
        onPicked: v => view.setScale(view.cur, v)
    }
    PanelSection { visible: view.curMode !== null; divided: false; text: "ROTATION" }
    PanelChips {
        objectName: "transform"
        visible: view.curMode !== null
        model: view.transforms
        current: view.cur && view.cur.logical ? view.transformName(view.cur.logical.transform) : ""
        onPicked: v => view.setTransform(view.cur, v)
    }
    RowLayout {
        visible: view.cur !== null && view.cur.vrr_supported && view.cur.logical !== null
        Layout.fillWidth: true
        Layout.topMargin: 4
        Text {
            text: "Fréquence variable (VRR)"
            color: FiliTheme.brume
            Layout.fillWidth: true
            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
        }
        PanelSwitch {
            objectName: "vrr"
            checked: view.cur !== null && view.cur.vrr_enabled
            onToggled: view.apply(view.cur.name, "vrr " + (checked ? "off" : "on"), false)
        }
    }

    // Confirmation des changements risqués
    Rectangle {
        objectName: "confirm"
        visible: view.snap !== null
        Layout.fillWidth: true
        Layout.topMargin: 6
        implicitHeight: 34
        radius: 6
        color: FiliTheme.nuit3
        RowLayout {
            anchors { fill: parent; leftMargin: 10; rightMargin: 6 }
            Text {
                text: "Garder ces réglages ? " + view.secs + " s"
                color: FiliTheme.sable
                Layout.fillWidth: true
                font { family: FiliTheme.font; pixelSize: FiliTheme.size }
            }
            PanelChips {
                Layout.fillWidth: false
                model: [{ label: "Garder", value: "keep" }, { label: "Annuler", value: "revert" }]
                onPicked: v => v === "keep" ? view.keep() : view.revert()
            }
        }
    }

    PanelSection { divided: false; text: "PROFIL" }
    PanelButton {
        objectName: "save"
        glyph: ""
        label: "Enregistrer pour ces écrans"
        detail: "kanshi"
        onClicked: { view.keep(); FiliTheme.run(FiliTheme.bin + "/display-save"); }
    }
    PanelSection { visible: view.screen >= 0; text: "LUMINOSITÉ" }
    PanelSlider {
        objectName: "screen"
        visible: view.screen >= 0
        glyph: ""
        value: Math.max(0, view.screen)
        onMoved: v => {
            view.screen = Math.max(0.01, v);
            FiliTheme.run("brightnessctl -q set " + Math.max(1, Math.round(v * 100)) + "%; " + FiliTheme.bin + "/fili-shell bar refresh 23");
        }
    }

    // Mode sombre (défaut) ou clair: shell, GTK, navigateur (portail), foot, niri, fond d'écran (fili-theme)
    PanelSection { text: "APPARENCE" }
    PanelChips {
        objectName: "theme"
        model: [{ label: "Sombre", value: "dark" }, { label: "Clair", value: "light" }]
        current: FiliTheme.mode
        onPicked: v => {
            FiliTheme.mode = v;
            FiliTheme.run(FiliTheme.bin + "/fili-theme " + v);
        }
    }

    PanelSection { text: "VEILLEUSE" }
    RowLayout {
        Layout.fillWidth: true
        Text {
            text: "Teinte chaude (4500 K)"
            color: FiliTheme.brume
            Layout.fillWidth: true
            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
        }
        PanelSwitch {
            objectName: "night"
            checked: view.night
            onToggled: {
                view.night = !view.night;
                FiliTheme.run(FiliTheme.bin + "/bar-toggle night " + (view.night ? "on" : "off"));
            }
        }
    }

    // Panneau fermé avec un changement à confirmer: on revient en arrière plutôt que de laisser un écran inutilisable
    Component.onDestruction: if (snap) revert()
}
