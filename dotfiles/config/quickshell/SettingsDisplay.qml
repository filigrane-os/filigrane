// Settings page "Display" (fili-settings): the outputs on a canvas (drag to place them, snapping to edges), then for
// the chosen output power, resolution, refresh rate, scale, rotation and VRR, the kanshi profile and the accent
// colour. Changes go through `niri msg output` (temporary, applied at once); resolution, rotation and power-off must
// be confirmed within 15 s (or when the window closes), else the previous state comes back. Scale applies without
// confirmation: it never makes the screen unusable and can be picked again with one click. Dragging only stages the
// layout; "Apply" commits it (the screens do not move at each drag), "Reset" lines the screens up again and
// "Identify" shows each output's name on its own screen. All connected outputs are listed, on or off; turning one on
// beyond what the graphics card drives shows a message (turn another one off first). "Save" writes the kanshi
// profile (display-save), re-applied whenever a display is plugged in. Brightness, appearance and night light stay in
// the fili-panel (PanelDisplay): they are frequent, instant and reversible.
import QtQuick
import QtQuick.Layouts
import qs.controls

ColumnLayout {
    id: view
    spacing: FiliTheme.space2
    // Outputs sorted by name (niri msg -j outputs); logical = null for an output that is off
    property var outputs: []
    property string sel: ""
    readonly property var cur: outputs.find(o => o.name === sel) ?? null
    readonly property var active: outputs.filter(o => o.logical)
    // Drag in progress: {name, x, y} in logical pixels
    property var ghost: null
    // Positions staged by dragging, not applied yet: name -> {x, y}
    property var pending: ({})
    readonly property bool dirty: Object.keys(pending).length > 0
    // Message under the canvas (e.g. too many outputs for the graphics card), and the number of outputs found
    // drivable at once (0 = not known yet)
    property string notice: ""
    property int limit: 0
    property string enabling: ""
    // State before the first change to confirm, and seconds left
    property var snap: null
    property int secs: 0
    readonly property int canvasH: 140

    function cmd(name, args) {
        return "niri msg output '" + name + "' " + args;
    }
    function transformName(t) {
        return String(t).replace(/^Flipped(\d+)$/, "flipped-$1").toLowerCase();
    }
    function modeArg(m) {
        return m.width + "x" + m.height + "@" + (m.refresh_rate / 1000).toFixed(3);
    }
    // Logical size of an output (niri's own; the same while dragging)
    function rect(o) {
        const g = ghost && ghost.name === o.name ? ghost : pending[o.name] ?? o.logical;
        return { x: g.x, y: g.y, w: o.logical.width, h: o.logical.height };
    }

    // Outputs requested on niri's socket (Outputs request), without `niri msg`
    function read() {
        Niri.request("Outputs", o => {
            // Closed before the reply: nothing left to update
            if (!o || !view)
                return;
            view.outputs = Object.values(o).sort((a, b) => a.name.localeCompare(b.name));
            if (!view.cur)
                view.sel = (view.active[0] ?? view.outputs[0] ?? { name: "" }).name;
            // An output asked to turn on that stayed off: the graphics card drives no more outputs
            const e = view.enabling;
            view.enabling = "";
            const eo = e ? view.outputs.find(x => x.name === e) : null;
            if (eo && !eo.logical && view.active.length > 0) {
                view.limit = view.active.length;
                view.notice = FiliI18n.tr("Only %1 display(s) can be on at once with this graphics card: turn one off first", view.active.length);
            }
        });
    }
    Component.onCompleted: {
        read();
    }
    Timer {
        id: reread
        interval: 500
        onTriggered: view.read()
    }
    // Applies `niri msg output` arguments; risky = to be confirmed (back to the previous state after 15 s)
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
        notice = "";
        if (on && limit > 0 && active.length >= limit) {
            notice = FiliI18n.tr("Only %1 display(s) can be on at once with this graphics card: turn one off first", limit);
            return;
        }
        if (on)
            enabling = o.name;
        apply(o.name, on ? "on" : "off", !on);
    }
    // Resolution: keeps the current refresh rate if the new mode has it, else the highest
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
        // neighbours re-snap: the logical size changes
        apply(o.name, "scale " + s, false);
    }
    function setTransform(o, t) {
        apply(o.name, "transform " + t, true);
    }

    // Snapping: edges stuck or aligned to the other outputs within 40 logical px
    function snapPos(o, x, y) {
        const r = rect(o);
        const T = 40;
        let bx = x, by = y, dx = T, dy = T;
        for (const p of active) {
            if (p.name === o.name)
                continue;
            const q = rect(p);
            q.width = q.w;
            q.height = q.h;
            for (const c of [q.x + q.width, q.x - r.w, q.x, q.x + q.width - r.w]) {
                if (Math.abs(c - x) < dx) { dx = Math.abs(c - x); bx = c; }
            }
            for (const c of [q.y + q.height, q.y - r.h, q.y, q.y + q.height - r.h]) {
                if (Math.abs(c - y) < dy) { dy = Math.abs(c - y); by = c; }
            }
        }
        return { x: Math.round(bx), y: Math.round(by) };
    }
    // Stages a position (nothing moves until Apply)
    function move(o, x, y) {
        const p = snapPos(o, x, y);
        const m = Object.assign({}, pending);
        if (p.x === o.logical.x && p.y === o.logical.y)
            delete m[o.name];
        else
            m[o.name] = p;
        pending = m;
        return p;
    }
    // Commits the staged positions in one go
    function applyLayout() {
        if (!dirty)
            return;
        const c = Object.keys(pending).map(n => cmd(n, "position set " + pending[n].x + " " + pending[n].y));
        pending = ({});
        FiliTheme.run(c.join("; "));
        reread.restart();
    }
    // Outputs that are on lined up left to right (the internal panel first), tops aligned, applied at once
    function resetLayout() {
        pending = ({});
        notice = "";
        const list = active.slice().sort((a, b) => (/^eDP/.test(b.name) ? 1 : 0) - (/^eDP/.test(a.name) ? 1 : 0) || a.name.localeCompare(b.name));
        let x = 0;
        const c = [];
        for (const o of list) {
            c.push(cmd(o.name, "position set " + x + " 0"));
            x += o.logical.width;
        }
        if (c.length)
            FiliTheme.run(c.join("; "));
        reread.restart();
    }
    function identify() {
        const l = {};
        for (const o of outputs)
            l[o.name] = ((o.make ?? "") + " " + (o.model ?? "")).trim();
        FiliIdentify.show(l);
    }

    // Resolution and refresh rate choices of the chosen output
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
        text: FiliI18n.tr("Displays")
        color: FiliTheme.voile
        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
    }

    // Canvas: outputs that are on, to scale; drag to move
    Item {
        id: canvas
        objectName: "canvas"
        Layout.fillWidth: true
        implicitHeight: view.canvasH
        visible: view.active.length > 0
        // Logical area covered (with a margin to drag outwards) and scale factor
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
            radius: FiliTheme.radiusControl
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
                radius: FiliTheme.radiusMark
                color: picked ? FiliTheme.nuit4 : FiliTheme.nuit
                border.color: picked ? FiliTheme.voile : FiliTheme.ardoise
                border.width: FiliTheme.borderWidth
                Text {
                    anchors.centerIn: parent
                    width: parent.width - 4
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: tile.modelData.name
                    color: tile.picked ? FiliTheme.voile : FiliTheme.brume2
                    font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
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
        text: FiliI18n.tr("No display found")
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: FiliTheme.size }
    }

    RowLayout {
        visible: view.active.length > 0
        Layout.fillWidth: true
        // Layout actions below the canvas they act on, right-aligned, default action (Apply) last
        Item { Layout.fillWidth: true }
        PanelChips {
            Layout.fillWidth: false
            model: [{ label: FiliI18n.tr("Identify"), value: "identify" }, { label: FiliI18n.tr("Reset"), value: "reset" }]
            onPicked: v => v === "identify" ? view.identify() : view.resetLayout()
        }
        PanelChips {
            objectName: "apply"
            Layout.fillWidth: false
            opacity: view.dirty ? 1 : 0.4
            model: [{ label: FiliI18n.tr("Apply"), value: "apply" }]
            onPicked: view.applyLayout()
        }
    }
    Text {
        visible: view.notice !== ""
        objectName: "notice"
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: view.notice
        color: FiliTheme.sable
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }

    // All connected outputs, on or off (the lid closed removes the internal one from the canvas, not from here)
    PanelSection { visible: view.outputs.length > 0; text: FiliI18n.tr("CONNECTED DISPLAYS") }
    PanelChips {
        visible: view.outputs.length > 0
        model: view.outputs.map(o => ({ label: o.name + " · " + (o.logical ? FiliI18n.tr("on") : FiliI18n.tr("off")), value: o.name }))
        current: view.sel
        onPicked: v => view.sel = v
    }

    // Chosen output
    PanelSection { visible: view.cur !== null; text: FiliI18n.tr("SELECTED DISPLAY") }
    RowLayout {
        visible: view.cur !== null
        Layout.fillWidth: true
        Text {
            text: view.cur ? ((view.cur.make ?? "") + " " + (view.cur.model ?? "")).trim() || view.cur.name : ""
            color: FiliTheme.brume
            Layout.fillWidth: true
            elide: Text.ElideRight
            font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
        }
        PanelSwitch {
            objectName: "power"
            checked: view.cur !== null && view.cur.logical !== null
            // the last output that is on cannot be turned off
            switchable: view.cur !== null && (view.cur.logical === null || view.active.length > 1)
            onToggled: view.setPower(view.cur, !checked)
        }
    }

    PanelSection { visible: view.curMode !== null; divided: false; Layout.topMargin: FiliTheme.space1; text: FiliI18n.tr("RESOLUTION") }
    PanelChips {
        objectName: "resolution"
        visible: view.curMode !== null
        model: view.resolutions
        current: view.curMode ? view.curMode.width + "x" + view.curMode.height : ""
        onPicked: v => view.setResolution(view.cur, view.resolutions.find(r => r.value === v))
    }
    PanelSection { visible: view.refreshes.length > 1; divided: false; Layout.topMargin: FiliTheme.space1; text: FiliI18n.tr("REFRESH RATE") }
    PanelChips {
        objectName: "refresh"
        visible: view.refreshes.length > 1
        model: view.refreshes
        current: view.curMode ? view.curMode.refresh_rate : 0
        onPicked: v => view.setRefresh(view.cur, v)
    }
    PanelSection { visible: view.curMode !== null; divided: false; Layout.topMargin: FiliTheme.space1; text: FiliI18n.tr("SCALE") }
    PanelChips {
        objectName: "scale"
        visible: view.curMode !== null
        model: view.scales
        current: view.cur && view.cur.logical ? view.cur.logical.scale : 0
        onPicked: v => view.setScale(view.cur, v)
    }
    PanelSection { visible: view.curMode !== null; divided: false; Layout.topMargin: FiliTheme.space1; text: FiliI18n.tr("ROTATION") }
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
        Layout.topMargin: FiliTheme.space1
        Text {
            text: FiliI18n.tr("Variable refresh rate (VRR)")
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

    // Confirmation of risky changes
    Rectangle {
        objectName: "confirm"
        visible: view.snap !== null
        Layout.fillWidth: true
        Layout.topMargin: FiliTheme.space2
        implicitHeight: 34
        radius: FiliTheme.radiusControl
        color: FiliTheme.nuit3
        RowLayout {
            anchors { fill: parent; leftMargin: FiliTheme.space2; rightMargin: FiliTheme.space2 }
            Text {
                text: FiliI18n.tr("Keep these settings? %1 s", view.secs)
                color: FiliTheme.sable
                Layout.fillWidth: true
                font { family: FiliTheme.font; pixelSize: FiliTheme.size }
            }
            PanelChips {
                Layout.fillWidth: false
                model: [{ label: FiliI18n.tr("Keep"), value: "keep" }, { label: FiliI18n.tr("Cancel"), value: "revert" }]
                onPicked: v => v === "keep" ? view.keep() : view.revert()
            }
        }
    }

    PanelSection { text: FiliI18n.tr("PROFILE") }
    PanelButton {
        objectName: "save"
        glyph: ""
        label: FiliI18n.tr("Save for these displays")
        detail: "kanshi"
        onClicked: { view.keep(); FiliTheme.run(FiliTheme.bin + "/display-save"); }
    }
    // Accent colour (fili-theme accent): niri window focus, selections in the shell and fili-file
    PanelSection { text: FiliI18n.tr("ACCENT COLOR") }
    Row {
        id: accents
        objectName: "accent"
        spacing: FiliTheme.space2
        readonly property var names: ["voile", "ardoise", "sauge", "sable", "cendre", "brume"]
        readonly property var labels: ({ voile: FiliI18n.tr("Veil"), ardoise: FiliI18n.tr("Slate"), sauge: FiliI18n.tr("Sage"), sable: FiliI18n.tr("Sand"), cendre: FiliI18n.tr("Ash"), brume: FiliI18n.tr("Mist") })
        property int cursor: Math.max(0, names.indexOf(FiliTheme.accentName))
        function pick(n) {
            FiliTheme.accent = n;
            FiliTheme.run(FiliTheme.bin + "/fili-theme accent " + n);
        }
        activeFocusOnTab: true
        Keys.onLeftPressed: e => { if (e.modifiers & Qt.ShiftModifier) { e.accepted = false; return; } FiliShell.keyNav = true; cursor = Math.max(0, cursor - 1); }
        Keys.onRightPressed: e => { if (e.modifiers & Qt.ShiftModifier) { e.accepted = false; return; } FiliShell.keyNav = true; cursor = Math.min(names.length - 1, cursor + 1); }
        Keys.onReturnPressed: pick(names[cursor])
        Keys.onSpacePressed: pick(names[cursor])
        Repeater {
            model: accents.names
            Rectangle {
                id: dot
                required property string modelData
                required property int index
                readonly property bool on: modelData === FiliTheme.accentName
                width: 22
                height: 22
                radius: width / 2
                color: "transparent"
                border.width: on ? 2 : 0
                border.color: FiliTheme.brume
                Rectangle {
                    anchors.centerIn: parent
                    width: 14
                    height: 14
                    radius: 7
                    color: FiliTheme.accentTones[dot.modelData][FiliTheme.light ? 2 : 0]
                }
                FocusRing {
                    shown: accents.activeFocus && accents.cursor === dot.index
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: accents.pick(dot.modelData)
                }
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: accents.labels[FiliTheme.accentName]
            color: FiliTheme.brume2
            font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
        }
    }

    // Closed with a change pending confirmation: go back rather than leave an unusable screen
    Component.onDestruction: if (snap) revert()
}
