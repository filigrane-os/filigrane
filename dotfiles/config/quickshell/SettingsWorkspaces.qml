// Settings page "Workspaces" (fili-settings): where the workspaces and the applications go when there are several
// displays. niri gives each display its own stack of workspaces, numbered from 1 on each display; two choices here:
// - Numbering: workspaces numbered across the displays (1 to 3 on the first display from the left, 4 to 6 on the next...),
//   as named workspaces pinned to their display; the number keys of the niri config then go to them (fili-app-output
//   numbered writes the rules and the bindings).
// - Applications: the display or the workspace on which each one opens its new windows (drop-down) and how they are
//   placed (icon buttons: first column on the left, last column on the right, maximized, floating); "Add an application" opens a
//   dialog with a search over the open windows and the installed applications (or an app-id typed in).
// Everything goes through fili-app-output (state in ~/.local/state/filigrane, rules in ~/.config/niri/app-outputs.kdl,
// re-read by niri by itself). Displays are stored by "make model serial", not by connector (DP-6 changes with the port).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.controls

ColumnLayout {
    id: view
    spacing: FiliTheme.space1
    readonly property string cli: FiliTheme.bin + "/fili-app-output"
    // Outputs of niri (Outputs request); those that are on, left to right then top to bottom
    property var outputs: []
    readonly property var active: outputs.filter(o => o.logical).sort((a, b) => a.logical.x - b.logical.x || a.logical.y - b.logical.y)
    // Saved choices (fili-app-output json)
    property var conf: ({ apps: [], workspaces: [] })
    // Picker of an application to add is open
    property bool adding: false

    function quote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }
    // Name of a display as niri matches it in its rules: "make model serial"
    function monitorId(o) {
        return (o.make ?? "") + " " + (o.model ?? "") + " " + (o.serial ?? "Unknown");
    }
    function outputOfMonitor(m) {
        return outputs.find(o => monitorId(o) === m) ?? null;
    }
    // Label of a display: its connector, or its model when it is not connected
    function displayLabel(m) {
        const o = outputOfMonitor(m);
        return o ? o.name : FiliI18n.tr("%1 (not connected)", m);
    }

    function read() {
        if (FiliTheme.testing)
            return;
        Niri.request("Outputs", o => {
            if (o && view)
                view.outputs = Object.values(o);
        });
        state.running = true;
    }
    Component.onCompleted: read()
    Process {
        id: state
        command: [view.cli, "json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    view.conf = JSON.parse(text);
                } catch (e) {}
            }
        }
    }
    Timer {
        id: reread
        interval: 300
        onTriggered: view.read()
    }
    Connections {
        target: Quickshell
        function onScreensChanged() {
            reread.restart();
        }
    }
    function run(c) {
        FiliTheme.run(c);
        reread.restart();
    }

    // Numbering: workspaces named "1", "2"... pinned to a display
    readonly property var numbered: conf.workspaces.filter(w => /^[0-9]+$/.test(w.name))
    readonly property bool numberedOn: numbered.length > 0
    function countOf(o) {
        return numbered.filter(w => w.output === monitorId(o)).length;
    }
    // Default: 3 per display, at most 9 in all (the number keys)
    readonly property int defaultCount: Math.max(1, Math.min(3, Math.floor(9 / Math.max(1, active.length))))
    // counts: connector -> count; the displays that are on, left to right
    function applyNumbering(counts) {
        let c = cli + " numbered";
        for (const o of active)
            c += " " + (counts[o.name] ?? defaultCount) + " " + quote(monitorId(o));
        run(c);
    }
    function setNumbering(on) {
        if (!on) {
            run(cli + " numbered");
            return;
        }
        const counts = {};
        for (const o of active)
            counts[o.name] = defaultCount;
        applyNumbering(counts);
    }
    function setCount(o, n) {
        const counts = {};
        for (const x of active)
            counts[x.name] = x.name === o.name ? n : countOf(x) || defaultCount;
        applyNumbering(counts);
    }
    // First and last number of a display ("1–3")
    function rangeOf(o) {
        const n = numbered.filter(w => w.output === monitorId(o)).map(w => parseInt(w.name)).sort((a, b) => a - b);
        return n.length === 0 ? "" : n.length === 1 ? String(n[0]) : n[0] + "–" + n[n.length - 1];
    }

    // Applications: where each one opens; target "o:<monitor>" or "w:<workspace name>"
    function targetOf(a) {
        return a.output !== undefined ? "o:" + a.output : a.workspace !== undefined ? "w:" + a.workspace : "";
    }
    // Placement of the new windows (fili-app-output layout): "" = tiled as niri decides; a second click on the
    // chosen one goes back to that
    readonly property var layouts: [
        { id: "left", glyph: "column-left", label: FiliI18n.tr("First column on the left") },
        { id: "right", glyph: "column-right", label: FiliI18n.tr("Last column on the right") },
        { id: "full", glyph: "maximize-edges", label: FiliI18n.tr("Maximized") },
        { id: "float", glyph: "float", label: FiliI18n.tr("Floating") }
    ]
    function setLayout(app, mode) {
        run(cli + " layout " + quote(app) + " " + (mode || "none"));
    }
    function targets(a) {
        const t = active.map(o => ({ label: o.name, value: "o:" + monitorId(o) }));
        if (a && a.output !== undefined && !t.some(x => x.value === "o:" + a.output))
            t.push({ label: displayLabel(a.output), value: "o:" + a.output });
        for (const w of conf.workspaces)
            t.push({ label: FiliI18n.tr("Workspace %1", w.name), value: "w:" + w.name });
        if (a && a.workspace !== undefined && !conf.workspaces.some(w => w.name === a.workspace))
            t.push({ label: FiliI18n.tr("Workspace %1", a.workspace), value: "w:" + a.workspace });
        return t;
    }
    function setTarget(app, v) {
        run(cli + (v.startsWith("o:") ? " set " : " set-workspace ") + quote(app) + " " + quote(v.slice(2)));
    }
    function forget(app) {
        run(cli + " forget " + quote(app));
    }
    // Open windows not saved yet, one per application: [{app, title, output}]
    readonly property var candidates: {
        const seen = {}, out = [];
        for (const w of Object.values(Niri.windows)) {
            const a = w.app_id ?? "";
            if (a === "" || seen[a] || conf.apps.some(x => x.app === a))
                continue;
            seen[a] = true;
            const ws = Niri.workspaces.find(x => x.id === w.workspace_id);
            out.push({ app: a, title: w.title ?? "", output: ws ? ws.output : "" });
        }
        return out.sort((a, b) => a.app.localeCompare(b.app));
    }
    // Added on the display where its window is now (else the first one)
    function add(app, connector) {
        app = app.trim();
        if (app === "")
            return;
        const o = active.find(x => x.name === connector) ?? active[0];
        adding = false;
        if (o)
            setTarget(app, "o:" + monitorId(o));
    }

    Text {
        text: FiliI18n.tr("Workspaces")
        color: FiliTheme.voile
        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
    }

    // Numbering across the displays
    PanelSection { text: FiliI18n.tr("NUMBERING") }
    RowLayout {
        Layout.fillWidth: true
        Text {
            text: FiliI18n.tr("Number the workspaces across the displays")
            color: FiliTheme.brume
            Layout.fillWidth: true
            elide: Text.ElideRight
            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
        }
        PanelSwitch {
            objectName: "numbered"
            checked: view.numberedOn
            switchable: view.active.length > 0
            onToggled: view.setNumbering(!checked)
        }
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("Workspace 1 on the first display from the left, the next numbers on the next display; the number keys go to them, wherever they are. Off: each display numbers its own workspaces from 1.")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
    Repeater {
        model: view.numberedOn ? view.active : []
        RowLayout {
            id: numRow
            required property var modelData
            Layout.fillWidth: true
            spacing: FiliTheme.space2
            Text {
                text: numRow.modelData.name + (view.rangeOf(numRow.modelData) ? " · " + view.rangeOf(numRow.modelData) : "")
                color: FiliTheme.brume
                Layout.preferredWidth: 120
                elide: Text.ElideRight
                font { family: FiliTheme.font; pixelSize: FiliTheme.size }
            }
            PanelChips {
                objectName: "count-" + numRow.modelData.name
                model: [1, 2, 3, 4, 5].map(n => ({ label: String(n), value: n }))
                current: view.countOf(numRow.modelData)
                onPicked: v => view.setCount(numRow.modelData, v)
            }
        }
    }
    PanelChips {
        visible: view.numberedOn
        model: [{ label: FiliI18n.tr("Identify"), value: "identify" }]
        onPicked: {
            const l = {};
            for (const o of view.outputs)
                l[o.name] = ((o.make ?? "") + " " + (o.model ?? "")).trim();
            FiliIdentify.show(l);
        }
    }

    // Applications and where they open
    PanelSection { text: FiliI18n.tr("APPLICATIONS") }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("Where each application opens its new windows. The windows already open stay where they are.")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
    Repeater {
        model: view.conf.apps
        ColumnLayout {
            id: appRow
            required property var modelData
            objectName: "app-" + modelData.app
            Layout.fillWidth: true
            Layout.topMargin: FiliTheme.space1
            spacing: 2
            RowLayout {
                Layout.fillWidth: true
                spacing: FiliTheme.space2
                Text {
                    text: appRow.modelData.app
                    color: FiliTheme.brume
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                }
                PanelButton {
                    objectName: "forget-" + appRow.modelData.app
                    Layout.fillWidth: false
                    Layout.preferredWidth: 30
                    label: "×"
                    Accessible.name: FiliI18n.tr("Remove")
                    onClicked: view.forget(appRow.modelData.app)
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: FiliTheme.space1
                // Display or workspace where it opens
                PanelSelect {
                    objectName: "target-" + appRow.modelData.app
                    Layout.fillWidth: true
                    placeholder: FiliI18n.tr("Display that has the focus")
                    model: view.targets(appRow.modelData)
                    current: view.targetOf(appRow.modelData)
                    onPicked: v => view.setTarget(appRow.modelData.app, v)
                }
                // Placement: segmented capsule like the list/grid switch of Casier, pictograms of Casier (WindowGlyph)
                Rectangle {
                    Layout.preferredWidth: view.layouts.length * 28 + 2 * FiliTheme.space1 + 2
                    Layout.preferredHeight: 30
                    radius: 8
                    color: FiliTheme.nuit2
                    border { color: FiliTheme.border; width: FiliTheme.borderWidth }
                    Row {
                        anchors.centerIn: parent
                        Repeater {
                            model: view.layouts
                            Rectangle {
                                id: lay
                                required property var modelData
                                readonly property bool on: (appRow.modelData.layout ?? "") === modelData.id
                                objectName: "layout-" + appRow.modelData.app + "-" + modelData.id
                                width: 28
                                height: 22
                                radius: FiliTheme.radiusControl
                                color: on || layHit.containsMouse ? FiliTheme.nuit3 : "transparent"
                                activeFocusOnTab: true
                                Accessible.role: Accessible.Button
                                Accessible.name: modelData.label
                                Accessible.checked: on
                                Keys.onReturnPressed: click()
                                Keys.onSpacePressed: click()
                                function click() {
                                    view.setLayout(appRow.modelData.app, on ? "" : modelData.id);
                                }
                                FocusRing {}
                                WindowGlyph {
                                    anchors.centerIn: parent
                                    width: 16
                                    height: 16
                                    kind: lay.modelData.glyph
                                    color: lay.on ? FiliTheme.voile : layHit.containsMouse ? FiliTheme.brume : FiliTheme.ardoise
                                }
                                MouseArea {
                                    id: layHit
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: lay.click()
                                }
                                // Name on hover
                                Rectangle {
                                    visible: layHit.containsMouse
                                    anchors { top: parent.bottom; topMargin: 4; horizontalCenter: parent.horizontalCenter }
                                    width: tip.implicitWidth + 2 * FiliTheme.space2
                                    height: tip.implicitHeight + 6
                                    z: 10
                                    radius: FiliTheme.radiusControl
                                    color: FiliTheme.nuit3
                                    border { color: FiliTheme.border; width: FiliTheme.borderWidth }
                                    Text {
                                        id: tip
                                        anchors.centerIn: parent
                                        text: lay.modelData.label
                                        color: FiliTheme.brume
                                        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    Text {
        visible: view.conf.apps.length === 0 && !view.adding
        text: FiliI18n.tr("No application yet: they open on the display that has the focus.")
        color: FiliTheme.ardoise
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
    PanelButton {
        objectName: "add-app"
        glyph: "+"
        label: FiliI18n.tr("Add an application…")
        onClicked: view.adding = true
    }

    // Picker of an application to add: a dialog over the settings window, search field on top; open windows first,
    // then the installed applications (desktop entries); Enter adds the selected one, Esc or Cancel closes
    property string query: ""
    property int pickIndex: 0
    readonly property var picks: pickList(query, DesktopEntries.applications.values)
    onAddingChanged: { query = ""; pickIndex = 0; }
    onQueryChanged: pickIndex = 0
    // [{app, name, detail, icon, output, open}]: entries matching the query (name or app-id), apps already saved left out;
    // a query that matches no app-id exactly ends the list as a typed app-id
    function pickList(raw, entries) {
        const typed = (raw ?? "").trim(), q = typed.toLowerCase();
        const has = a => conf.apps.some(x => x.app === a);
        const hit = (...t) => q === "" || t.some(x => (x ?? "").toLowerCase().indexOf(q) >= 0);
        const out = [], seen = {};
        for (const c of candidates)
            if (hit(c.app, c.title)) {
                seen[c.app] = true;
                out.push({ app: c.app, name: c.app, detail: c.title, icon: "", output: c.output, open: true });
            }
        const inst = [];
        for (const e of entries ?? []) {
            if (e.noDisplay)
                continue;
            const a = e.startupClass || e.id;
            if (!a || seen[a] || has(a) || !hit(e.name, a))
                continue;
            seen[a] = true;
            inst.push({ app: a, name: e.name || a, detail: a, icon: e.icon ?? "", output: "", open: false });
        }
        const all = out.concat(inst.sort((x, y) => x.name.localeCompare(y.name)));
        if (typed !== "" && !/\s/.test(typed) && !all.some(x => x.app === typed) && !has(typed))
            all.push({ app: typed, name: FiliI18n.tr("Use “%1” as app-id", typed), detail: "", icon: "", output: "", open: false, typed: true });
        return all;
    }

    // Holder outside the layout (the dialog itself is reparented over the whole settings window)
    Item {
        id: holder
        Layout.preferredHeight: 0
        Layout.fillWidth: true
        Item {
            id: dialog
            objectName: "add-app-dialog"
            visible: view.adding
            parent: view.Window.window ? view.Window.window.contentItem : holder
            anchors.fill: parent
            z: 100
            // Dim the settings behind; a click outside the box closes
            Rectangle {
                anchors.fill: parent
                radius: FiliTheme.radiusWindow
                color: FiliTheme.alpha(FiliTheme.nuit, 0.8)
                MouseArea { anchors.fill: parent; onClicked: view.adding = false }
            }
            Rectangle {
                id: box
                anchors.centerIn: parent
                width: Math.min(parent.width - 2 * FiliTheme.space5, 420)
                height: Math.min(parent.height - 2 * FiliTheme.space5, 440)
                radius: FiliTheme.radiusWindow
                color: FiliTheme.nuit2
                border { color: FiliTheme.border; width: FiliTheme.borderWidth }
                MouseArea { anchors.fill: parent }
                ColumnLayout {
                    anchors { fill: parent; margins: FiliTheme.space4 }
                    spacing: FiliTheme.space2
                    Text {
                        text: FiliI18n.tr("Add an application")
                        color: FiliTheme.brume
                        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: FiliTheme.radiusControl
                        color: FiliTheme.nuit
                        border { width: 1; color: search.activeFocus ? FiliTheme.nuit4 : FiliTheme.nuit3 }
                        TextInput {
                            id: search
                            objectName: "app-search"
                            anchors { fill: parent; leftMargin: FiliTheme.space2; rightMargin: FiliTheme.space2 }
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            color: FiliTheme.brume
                            selectionColor: FiliTheme.nuit4
                            selectedTextColor: FiliTheme.brume
                            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                            text: view.query
                            onTextEdited: view.query = text
                            Connections {
                                target: dialog
                                function onVisibleChanged() {
                                    if (dialog.visible) {
                                        search.text = "";
                                        search.forceActiveFocus();
                                    }
                                }
                            }
                            Keys.onEscapePressed: e => { view.adding = false; e.accepted = true; }
                            Keys.onDownPressed: view.pickIndex = Math.min(view.picks.length - 1, view.pickIndex + 1)
                            Keys.onUpPressed: view.pickIndex = Math.max(0, view.pickIndex - 1)
                            Keys.onTabPressed: e => { view.pickIndex = Math.min(view.picks.length - 1, view.pickIndex + 1); e.accepted = true; }
                            Keys.onBacktabPressed: e => { view.pickIndex = Math.max(0, view.pickIndex - 1); e.accepted = true; }
                            onAccepted: {
                                const p = view.picks[view.pickIndex];
                                if (p)
                                    view.add(p.app, p.output);
                            }
                            Text {
                                visible: !search.text
                                anchors.verticalCenter: parent.verticalCenter
                                text: FiliI18n.tr("Search applications or type an app-id")
                                color: FiliTheme.ardoise
                                font: search.font
                            }
                        }
                    }
                    ListView {
                        id: pickView
                        objectName: "app-picks"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: view.adding ? view.picks : []
                        currentIndex: view.pickIndex
                        highlightMoveDuration: 0
                        delegate: Item {
                            id: pick
                            required property var modelData
                            required property int index
                            objectName: "pick-" + modelData.app
                            // Group title above the first row of a group (open windows, installed applications)
                            readonly property bool first: !modelData.typed && (index === 0 || view.picks[index - 1].open !== modelData.open)
                            width: pickView.width
                            height: row.height + (first ? groupTitle.height : 0)
                            Text {
                                id: groupTitle
                                visible: pick.first
                                topPadding: pick.index === 0 ? 0 : FiliTheme.space2
                                bottomPadding: 2
                                leftPadding: FiliTheme.space2
                                text: pick.modelData.open ? FiliI18n.tr("OPEN WINDOWS") : FiliI18n.tr("APPLICATIONS")
                                color: FiliTheme.ardoise
                                font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                            }
                        Rectangle {
                            id: row
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 34
                            radius: FiliTheme.radiusControl
                            color: pick.index === view.pickIndex ? FiliTheme.nuit3 : hover.containsMouse ? FiliTheme.alpha(FiliTheme.nuit3, 0.6) : "transparent"
                            RowLayout {
                                anchors { fill: parent; leftMargin: FiliTheme.space2; rightMargin: FiliTheme.space2 }
                                spacing: FiliTheme.space2
                                Item {
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20
                                    IconImage {
                                        anchors.fill: parent
                                        visible: source != ""
                                        source: pick.modelData.icon && !pick.modelData.icon.startsWith("/") ? Quickshell.iconPath(pick.modelData.icon, true)
                                            : pick.modelData.icon ? "file://" + pick.modelData.icon : ""
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        visible: !pick.modelData.icon
                                        text: pick.modelData.typed ? "+" : pick.modelData.open ? "▣" : "□"
                                        color: FiliTheme.ardoise
                                        font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: pick.modelData.name
                                    color: FiliTheme.brume
                                    elide: Text.ElideRight
                                    font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                                }
                                Text {
                                    Layout.maximumWidth: pickView.width * 0.45
                                    text: pick.modelData.detail
                                    color: FiliTheme.ardoise
                                    elide: Text.ElideRight
                                    font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                                }
                            }
                            MouseArea {
                                id: hover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: view.add(pick.modelData.app, pick.modelData.output)
                            }
                        }
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: pickView.count === 0
                            text: FiliI18n.tr("No application found")
                            color: FiliTheme.ardoise
                            font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        PanelButton {
                            objectName: "add-app-cancel"
                            Layout.fillWidth: false
                            Layout.preferredWidth: 90
                            label: FiliI18n.tr("Cancel")
                            onClicked: view.adding = false
                        }
                    }
                }
            }
        }
    }
}
