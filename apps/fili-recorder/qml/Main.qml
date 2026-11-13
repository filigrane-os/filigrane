// Window of Cassette (fili-recorder): header (mode, search, window buttons), sidebar (what to show), the recordings and the
// player, or the recorder, and a footer: the anatomy of every fili-* window (app-window.md of the filigrane-ui skill, Casier is
// the reference). Two modes: Recordings (list, play, pause, previous / next, seek) and Record (choose an input and an output,
// each one optional, then record). Shortcuts: Space play / pause, Left / Right seek 10 s, Ctrl+Left / Ctrl+Right previous / next,
// Return play, Delete trash, Ctrl+1 / Ctrl+2 mode, Ctrl+R record or stop, Ctrl+F search, Ctrl+W close.
import QtQuick
import QtQuick.Controls.Basic
import Fili.Cassette

ApplicationWindow {
    id: win
    // Fonts embedded in the binary: same look on every distribution
    FontLoader { id: fontText; source: "qrc:/qt/qml/Fili/Cassette/fonts/Jost-Variable.ttf" }
    FontLoader { id: fontMono; source: "qrc:/qt/qml/Fili/Cassette/fonts/JetBrainsMono-Variable.ttf" }
    FontLoader { id: fontIcons; source: "qrc:/qt/qml/Fili/Cassette/fonts/FiliIcons.ttf" }
    width: 980
    height: 620
    minimumWidth: 640
    minimumHeight: 420
    visible: true
    color: FiliTheme.background
    title: "Cassette"

    Cassette { id: cas }

    // Glyphs of Fili Icons (the codes above U+FFFF need fromCodePoint)
    readonly property var g: ({
        play: "", pause: "", stop: String.fromCodePoint(0xf2f15), prev: String.fromCodePoint(0xf2f11),
        next: String.fromCodePoint(0xf2f12), back: String.fromCodePoint(0xf2f13), fwd: String.fromCodePoint(0xf2f14),
        folder: String.fromCodePoint(0xf2f16), mix: String.fromCodePoint(0xf2f17), mic: "", out: "",
        trash: "", rec: "", cassette: String.fromCodePoint(0xf2f10), search: ""
    })

    // ---- State -------------------------------------------------------------------------------------------------
    property string mode: Fili.uiState("mode") === "record" ? "record" : "library"
    // Filter of the sidebar: a date section (all, today, week, older) and a kind ("" for any)
    property string section: "all"
    property string kind: ""
    property bool searchOpen: false
    property bool aboutOpen: false
    property bool showHeader: Fili.header()
    property bool showFooter: Fili.footer()
    property bool windowButtons: Fili.windowButtons()
    readonly property bool typing: searchInput.activeFocus
    readonly property bool headerShown: showHeader || searchOpen || searchInput.text !== ""
    readonly property bool footerShown: showFooter || cas.message !== "" || cas.recording
    property var sources: ({ inputs: [], outputs: [], default_input: "", default_output: "" })

    readonly property var all: JSON.parse(cas.recordings)
    function startOfDay() {
        const d = new Date();
        d.setHours(0, 0, 0, 0);
        return d.getTime() / 1000;
    }
    function inSection(r, s) {
        const t0 = startOfDay();
        return s === "all" || (s === "today" && r.when >= t0) || (s === "week" && r.when >= t0 - 6 * 86400) || (s === "older" && r.when < t0 - 6 * 86400);
    }
    function countOf(s, k) {
        return all.filter(r => inSection(r, s) && (k === "" || r.kind === k)).length;
    }
    readonly property var items: {
        const q = searchInput.text.toLowerCase();
        return all.filter(r => inSection(r, section) && (kind === "" || r.kind === kind) && (q === "" || r.name.toLowerCase().includes(q)));
    }
    readonly property var selectedItem: list.currentIndex >= 0 && list.currentIndex < items.length ? items[list.currentIndex] : null
    readonly property string sectionTitle: kind !== "" ? kindLabel(kind) : ({ all: Fili.tr("All recordings"), today: Fili.tr("Today"), week: Fili.tr("Last 7 days"), older: Fili.tr("Older") })[section]

    function kindLabel(k) {
        return k === "mix" ? Fili.tr("Both sides") : k === "input" ? Fili.tr("Microphone") : Fili.tr("Speakers");
    }
    function kindGlyph(k) {
        return k === "input" ? g.mic : k === "output" ? g.out : g.mix;
    }
    function clock(s) {
        s = Math.max(0, Math.floor(s));
        const p = v => (v < 10 ? "0" : "") + v, h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60;
        return h > 0 ? h + ":" + p(m) + ":" + p(s % 60) : m + ":" + p(s % 60);
    }
    function sizeText(b) {
        return b >= 1048576 ? (b / 1048576).toFixed(1) + " MB" : Math.max(1, Math.round(b / 1024)) + " KB";
    }
    function whenText(t) {
        return Qt.formatDateTime(new Date(t * 1000), "d MMM yyyy  HH:mm");
    }
    function setMode(m) {
        mode = m;
        Fili.setUiState("mode", m);
        if (m === "record")
            loadSources();
        else
            list.forceActiveFocus();
    }
    function loadSources() {
        sources = JSON.parse(cas.sources());
    }
    function choices(devices, fallback) {
        const named = devices.find(d => d.name === fallback);
        return [{ label: Fili.tr("None"), value: "none" }, { label: Fili.tr("Default") + (named ? " · " + named.label : ""), value: "default" }]
            .concat(devices.map(d => ({ label: d.label, value: d.name })));
    }
    function toggleRecord() {
        cas.recording ? cas.stopRecord() : cas.startRecord();
    }
    function quit() {
        Qt.quit();
    }
    onClosing: close => cas.stopPlay()
    Component.onCompleted: {
        if (mode === "record")
            loadSources();
        else
            list.forceActiveFocus();
    }

    Connections {
        target: Fili
        function onThemeChanged() {
            win.showHeader = Fili.header();
            win.showFooter = Fili.footer();
        }
    }
    // Position and state while something plays or records; a slow look at the folder meanwhile (a recording started from the
    // fili-bar or a file that came from Casier)
    Timer { interval: 250; repeat: true; running: cas.playing || cas.recording; onTriggered: cas.tick() }
    Timer { interval: 2000; repeat: true; running: win.visible; onTriggered: cas.refresh() }
    // A notice goes away by itself, an error stays until it is clicked
    Timer {
        interval: 6000
        running: cas.message !== "" && !cas.failed
        onTriggered: cas.clearMessage()
    }
    // The recording just started or stopped from elsewhere: the pickers show what the recorder really uses
    Connections {
        target: cas
        function onRecordingChanged() {
            if (win.mode === "record")
                win.loadSources();
        }
    }

    // ---- Commands: the menu of the fili-bar and the assistant (fili-recorder ctl) -----------------------------------
    readonly property var actions: ({
        "about": { on: () => true, run: () => win.aboutOpen = !win.aboutOpen },
        "mode-library": { on: () => true, run: () => win.setMode("library") },
        "mode-record": { on: () => true, run: () => win.setMode("record") },
        "record-toggle": { on: () => !cas.saving, run: () => win.toggleRecord() },
        "play-pause": { on: () => cas.playing || win.selectedItem !== null, run: () => cas.playing ? cas.togglePause() : win.playSelected() },
        "stop": { on: () => cas.playing, run: () => cas.stopPlay() },
        "next": { on: () => cas.playing, run: () => cas.next() },
        "prev": { on: () => cas.playing, run: () => cas.prev() },
        "seek-back": { on: () => cas.playing, run: () => cas.seekBy(-10) },
        "seek-forward": { on: () => cas.playing, run: () => cas.seekBy(10) },
        "play-selected": { on: () => win.selectedItem !== null, run: () => win.playSelected() },
        "trash": { on: () => win.selectedItem !== null, run: () => win.trashSelected() },
        "show-in-casier": { on: () => win.selectedItem !== null, run: () => cas.reveal(win.selectedItem.path) },
        "open-folder": { on: () => true, run: () => cas.openFolder() },
        "copy-name": { on: () => win.selectedItem !== null, run: () => Fili.copyText(win.selectedItem.name) },
        "search": { on: () => win.mode === "library", run: () => win.openSearch() },
        "settings": { on: () => true, run: () => Fili.openSettings() },
        "toggle-header": { on: () => true, run: () => win.showHeader = !win.showHeader },
        "toggle-footer": { on: () => true, run: () => win.showFooter = !win.showFooter },
        "toggle-window-buttons": { on: () => true, run: () => { win.windowButtons = !win.windowButtons; Fili.setWindowButtons(win.windowButtons); } },
        "window-actions": { on: () => win.windowButtons, run: () => windowPanel.visible ? windowPanel.close() : windowPanel.open() },
        "close": { on: () => true, run: () => win.quit() }
    })
    function runAction(name) {
        const a = actions[name];
        if (!a)
            return { ok: false, error: "unknown action: " + name + " (fili-recorder ctl actions lists them)" };
        if (!a.on())
            return { ok: false, error: "action disabled now: " + name };
        a.run();
        return { ok: true };
    }
    function stateJson() {
        return {
            mode: mode, section: section, kind: kind, count: cas.count, selected: selectedItem ? selectedItem.path : "",
            playing: cas.playing, paused: cas.paused, current: cas.current, position: cas.position, duration: cas.duration,
            recording: cas.recording, saving: cas.saving, input: cas.input, output: cas.output, mix: cas.mix, folder: cas.dir
        };
    }
    Connections {
        target: Fili
        function onCommand(id, verb, arg) {
            let answer;
            if (verb === "action")
                answer = win.runAction(arg.split(" ")[0]);
            else if (verb === "actions")
                answer = { ok: true, actions: Object.keys(win.actions).map(n => ({ name: n, enabled: win.actions[n].on() })) };
            else if (verb === "state")
                answer = Object.assign({ ok: true }, win.stateJson());
            else
                answer = { ok: false, error: "unknown command: " + verb };
            Fili.reply(id, JSON.stringify(answer));
        }
    }

    function playSelected() {
        if (selectedItem)
            cas.play(selectedItem.path);
    }
    function trashSelected() {
        if (selectedItem)
            cas.trash(selectedItem.path);
    }
    function openSearch() {
        searchOpen = true;
        searchInput.forceActiveFocus();
    }

    // ---- Shortcuts -----------------------------------------------------------------------------------------------
    Shortcut { sequence: "Ctrl+W"; onActivated: win.quit() }
    Shortcut { sequence: "Ctrl+Q"; onActivated: win.quit() }
    Shortcut { sequence: "Ctrl+1"; onActivated: win.setMode("library") }
    Shortcut { sequence: "Ctrl+2"; onActivated: win.setMode("record") }
    Shortcut { sequence: "Ctrl+R"; enabled: !cas.saving; onActivated: win.toggleRecord() }
    Shortcut { sequence: "Ctrl+F"; enabled: win.mode === "library"; onActivated: win.openSearch() }
    Shortcut { sequence: "Ctrl+Shift+W"; enabled: win.windowButtons; onActivated: windowPanel.visible ? windowPanel.close() : windowPanel.open() }
    Shortcut { sequence: "Space"; enabled: win.mode === "library" && !win.typing && !win.aboutOpen; onActivated: win.runAction("play-pause") }
    Shortcut { sequence: "Return"; enabled: win.mode === "library" && !win.typing && !win.aboutOpen; onActivated: win.playSelected() }
    Shortcut { sequence: "Left"; enabled: win.mode === "library" && !win.typing && cas.playing; onActivated: cas.seekBy(-10) }
    Shortcut { sequence: "Right"; enabled: win.mode === "library" && !win.typing && cas.playing; onActivated: cas.seekBy(10) }
    Shortcut { sequence: "Ctrl+Left"; enabled: cas.playing; onActivated: cas.prev() }
    Shortcut { sequence: "Ctrl+Right"; enabled: cas.playing; onActivated: cas.next() }
    Shortcut { sequence: "Delete"; enabled: win.mode === "library" && !win.typing && win.selectedItem !== null; onActivated: win.trashSelected() }
    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (win.aboutOpen)
                win.aboutOpen = false;
            else if (win.searchOpen || searchInput.text !== "") {
                searchInput.text = "";
                win.searchOpen = false;
                list.forceActiveFocus();
            }
        }
    }

    // ---- Header ---------------------------------------------------------------------------------------------------
    Rectangle {
        id: toolbar
        width: parent.width
        height: win.headerShown ? FiliTheme.toolbarHeight : 0
        visible: win.headerShown
        color: FiliTheme.background
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: FiliTheme.borderWidth
            color: FiliTheme.border
        }
        // The two modes in a capsule, like the navigation buttons of Casier
        Rectangle {
            x: FiliTheme.margin
            anchors.verticalCenter: parent.verticalCenter
            width: modes.width + 2 * FiliTheme.space1 + 2
            height: 30
            radius: 8
            color: FiliTheme.surface
            border.width: FiliTheme.borderWidth
            border.color: FiliTheme.border
        }
        Row {
            id: modes
            x: FiliTheme.margin + FiliTheme.space1 + 1
            anchors.verticalCenter: parent.verticalCenter
            spacing: FiliTheme.space1
            Repeater {
                model: [{ id: "library", label: Fili.tr("Recordings") }, { id: "record", label: Fili.tr("Record") }]
                Rectangle {
                    id: seg
                    required property var modelData
                    readonly property bool on: win.mode === modelData.id
                    width: segText.implicitWidth + 2 * FiliTheme.space3
                    height: 22
                    radius: FiliTheme.radiusControl
                    color: on || segArea.containsMouse ? FiliTheme.surfaceHover : "transparent"
                    Text {
                        id: segText
                        anchors.centerIn: parent
                        text: seg.modelData.label
                        font.family: FiliTheme.font
                        font.pixelSize: FiliTheme.sizeList
                        font.weight: seg.on ? FiliTheme.weightAccent : Font.Normal
                        color: seg.on ? FiliTheme.accentColor : FiliTheme.textSecondary
                    }
                    MouseArea {
                        id: segArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: win.setMode(seg.modelData.id)
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: seg.modelData.label
                }
            }
        }
        Text {
            anchors { left: modes.right; leftMargin: FiliTheme.space4; right: search.left; rightMargin: FiliTheme.space3; verticalCenter: parent.verticalCenter }
            text: win.mode === "library" ? win.sectionTitle : Fili.tr("New recording")
            elide: Text.ElideRight
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.size
            font.weight: FiliTheme.weightAccent
            color: FiliTheme.text
        }
        // Window buttons at the far right: close, and the panel of window actions (niri only)
        Rectangle {
            id: closeButton
            visible: win.windowButtons
            anchors { right: parent.right; rightMargin: (toolbar.height - height) / 2; verticalCenter: parent.verticalCenter }
            width: 28
            height: 24
            radius: FiliTheme.radiusControl
            color: closeArea.pressed ? FiliTheme.danger : closeArea.containsMouse ? FiliTheme.alpha(FiliTheme.danger, 0.75) : "transparent"
            WindowGlyph {
                anchors.centerIn: parent
                kind: "close"
                width: 16
                height: 16
                color: closeArea.containsMouse ? "#ffffff" : FiliTheme.text
            }
            MouseArea {
                id: closeArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: win.quit()
            }
            Accessible.role: Accessible.Button
            Accessible.name: Fili.tr("Close window")
        }
        Rectangle {
            id: windowButton
            visible: win.windowButtons
            anchors { right: closeButton.left; rightMargin: FiliTheme.space1; verticalCenter: parent.verticalCenter }
            width: 28
            height: 24
            radius: FiliTheme.radiusControl
            color: windowArea.pressed ? FiliTheme.surfaceActive : windowArea.containsMouse || windowPanel.visible ? FiliTheme.surfaceHover : "transparent"
            WindowGlyph {
                anchors.centerIn: parent
                kind: "window"
                width: 16
                height: 16
            }
            MouseArea {
                id: windowArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: windowPanel.visible ? windowPanel.close() : windowPanel.open()
            }
            Accessible.role: Accessible.Button
            Accessible.name: Fili.tr("Window")
        }
        Rectangle {
            id: search
            visible: win.mode === "library"
            anchors { right: windowButton.visible ? windowButton.left : closeButton.visible ? closeButton.left : parent.right; rightMargin: windowButton.visible || closeButton.visible ? FiliTheme.space3 : FiliTheme.margin; verticalCenter: parent.verticalCenter }
            width: visible ? 180 : 0
            height: 26
            radius: FiliTheme.radiusControl
            color: FiliTheme.surface
            border.width: FiliTheme.borderWidth
            border.color: searchInput.activeFocus ? FiliTheme.accentColor : FiliTheme.border
            Text {
                anchors { left: parent.left; leftMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                visible: searchInput.text === ""
                text: Fili.tr("Search")
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.size
                color: FiliTheme.muted
            }
            TextInput {
                id: searchInput
                anchors { fill: parent; leftMargin: FiliTheme.space2; rightMargin: FiliTheme.space2 }
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.size
                color: FiliTheme.text
                selectionColor: FiliTheme.surfaceActive
                selectedTextColor: FiliTheme.text
                Accessible.name: Fili.tr("Search")
                onActiveFocusChanged: if (!activeFocus && text === "")
                    win.searchOpen = false
            }
        }
    }

    // ---- Sidebar --------------------------------------------------------------------------------------------------
    Rectangle {
        id: side
        anchors { top: toolbar.bottom; bottom: statusbar.top; left: parent.left }
        width: FiliTheme.sidebarWidth
        color: FiliTheme.backgroundDeep
        Rectangle {
            anchors.right: parent.right
            height: parent.height
            width: FiliTheme.borderWidth
            color: FiliTheme.border
        }
        // Sections folded by the user, for the session (headings fold as in Facteur)
        property var folded: ({})
        readonly property var groups: [
            { key: Fili.tr("Library"), rows: [
                { section: "all", kind: "", label: Fili.tr("All recordings") }, { section: "today", kind: "", label: Fili.tr("Today") },
                { section: "week", kind: "", label: Fili.tr("Last 7 days") }, { section: "older", kind: "", label: Fili.tr("Older") }] },
            { key: Fili.tr("Kind"), rows: [
                { section: "all", kind: "mix", label: Fili.tr("Both sides") }, { section: "all", kind: "input", label: Fili.tr("Microphone") },
                { section: "all", kind: "output", label: Fili.tr("Speakers") }] }
        ]
        Column {
            anchors { fill: parent; topMargin: FiliTheme.space1; leftMargin: FiliTheme.space2 + 2; rightMargin: FiliTheme.space2 + 2 }
            Repeater {
                model: side.groups
                Column {
                    id: group
                    required property var modelData
                    readonly property bool open: side.folded[modelData.key] !== true
                    width: parent.width
                    Item {
                        width: parent.width
                        height: FiliTheme.sideRowHeight + FiliTheme.space4
                        Rectangle {
                            anchors { fill: parent; topMargin: FiliTheme.space4 }
                            radius: FiliTheme.radiusControl
                            color: headArea.containsMouse ? FiliTheme.alpha(FiliTheme.surfaceHover, 0.5) : "transparent"
                        }
                        Text {
                            id: arrow
                            x: FiliTheme.margin / 2 - (FiliTheme.space2 + 2)
                            anchors { bottom: parent.bottom; bottomMargin: (FiliTheme.sideRowHeight - height) / 2 }
                            text: group.open ? "▾" : "▸"
                            font.pixelSize: FiliTheme.sizeSmall
                            color: FiliTheme.muted
                        }
                        Text {
                            anchors { left: arrow.right; leftMargin: FiliTheme.space2; right: parent.right; rightMargin: FiliTheme.space2; bottom: parent.bottom; bottomMargin: (FiliTheme.sideRowHeight - height) / 2 }
                            text: group.modelData.key
                            elide: Text.ElideRight
                            font.family: FiliTheme.font
                            font.pixelSize: FiliTheme.sizeSmall
                            font.weight: FiliTheme.weightAccent
                            color: FiliTheme.muted
                        }
                        MouseArea {
                            id: headArea
                            anchors { fill: parent; topMargin: FiliTheme.space4 }
                            hoverEnabled: true
                            onClicked: {
                                const next = Object.assign({}, side.folded);
                                next[group.modelData.key] = group.open;
                                side.folded = next;
                            }
                        }
                        Accessible.role: Accessible.Button
                        Accessible.name: group.modelData.key
                    }
                    Repeater {
                        model: group.open ? group.modelData.rows : []
                        Item {
                            id: srow
                            required property var modelData
                            readonly property bool sel: win.mode === "library" && win.section === modelData.section && win.kind === modelData.kind
                            width: group.width
                            height: FiliTheme.sideRowHeight + 4
                            Rectangle {
                                anchors { fill: parent; topMargin: 1; bottomMargin: 1 }
                                radius: FiliTheme.radiusControl
                                color: srow.sel || rowArea.containsMouse ? FiliTheme.surfaceHover : "transparent"
                            }
                            Text {
                                id: rowGlyph
                                x: FiliTheme.margin / 2 - (FiliTheme.space2 + 2)
                                width: 16
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: srow.modelData.kind !== "" ? win.kindGlyph(srow.modelData.kind) : win.g.cassette
                                font.family: FiliTheme.icons
                                font.pixelSize: 14
                                color: srow.sel ? FiliTheme.accentColor : FiliTheme.muted
                            }
                            Text {
                                anchors { left: rowGlyph.right; leftMargin: FiliTheme.space2; right: rowCount.left; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                                text: srow.modelData.label
                                elide: Text.ElideRight
                                font.family: FiliTheme.font
                                font.pixelSize: FiliTheme.size
                                color: srow.sel ? FiliTheme.accentColor : FiliTheme.text
                            }
                            Text {
                                id: rowCount
                                anchors { right: parent.right; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                                text: win.countOf(srow.modelData.section, srow.modelData.kind)
                                font.family: FiliTheme.font
                                font.pixelSize: FiliTheme.sizeSmall
                                color: FiliTheme.muted
                            }
                            MouseArea {
                                id: rowArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    win.section = srow.modelData.section;
                                    win.kind = srow.modelData.kind;
                                    win.setMode("library");
                                }
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: srow.modelData.label
                        }
                    }
                }
            }
        }
    }

    // ---- Content: recordings and player --------------------------------------------------------------------------
    Item {
        id: library
        visible: win.mode === "library"
        anchors { top: toolbar.bottom; left: side.right; right: parent.right; bottom: statusbar.top }

        // Column headings
        Rectangle {
            id: heads
            width: parent.width
            height: FiliTheme.rowHeight + FiliTheme.space1
            color: FiliTheme.background
            Row {
                anchors { fill: parent; leftMargin: FiliTheme.margin; rightMargin: FiliTheme.margin }
                Item { width: 28; height: parent.height }
                Text {
                    width: parent.width - 28 - 160 - 80 - 80
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: Fili.tr("Name")
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeSmall
                    color: FiliTheme.muted
                }
                Text {
                    width: 160
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: Fili.tr("Started")
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeSmall
                    color: FiliTheme.muted
                }
                Text {
                    width: 80
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignRight
                    text: Fili.tr("Length")
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeSmall
                    color: FiliTheme.muted
                }
                Text {
                    width: 80
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignRight
                    text: Fili.tr("Size")
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeSmall
                    color: FiliTheme.muted
                }
            }
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: FiliTheme.borderWidth
                color: FiliTheme.border
            }
        }

        ListView {
            id: list
            anchors { top: heads.bottom; left: parent.left; right: parent.right; bottom: transport.top }
            clip: true
            model: win.items
            currentIndex: 0
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: true
            activeFocusOnTab: true
            highlightMoveDuration: 0
            KineticScroll {}
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool playing: modelData.path === cas.current
                width: ListView.view.width
                height: FiliTheme.rowHeight
                color: ListView.isCurrentItem ? FiliTheme.surfaceHover : rowArea2.containsMouse ? FiliTheme.alpha(FiliTheme.surfaceHover, 0.5) : index % 2 === 1 ? FiliTheme.alpha(FiliTheme.surface, 0.5) : "transparent"
                Row {
                    anchors { fill: parent; leftMargin: FiliTheme.margin; rightMargin: FiliTheme.margin }
                    Text {
                        width: 28
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        text: row.playing ? (cas.paused ? win.g.pause : win.g.play) : win.kindGlyph(row.modelData.kind)
                        font.family: FiliTheme.icons
                        font.pixelSize: 14
                        color: row.playing ? FiliTheme.accentColor : FiliTheme.muted
                    }
                    Text {
                        width: parent.width - 28 - 160 - 80 - 80
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        text: row.modelData.name
                        elide: Text.ElideRight
                        font.family: FiliTheme.font
                        font.pixelSize: FiliTheme.sizeList
                        font.weight: row.playing ? FiliTheme.weightAccent : Font.Normal
                        color: row.playing ? FiliTheme.accentColor : FiliTheme.text
                    }
                    Text {
                        width: 160
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        text: win.whenText(row.modelData.when)
                        font.family: FiliTheme.font
                        font.pixelSize: FiliTheme.sizeList
                        color: FiliTheme.textSecondary
                    }
                    Text {
                        width: 80
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                        text: win.clock(row.modelData.duration)
                        font.family: FiliTheme.font
                        font.pixelSize: FiliTheme.sizeList
                        color: FiliTheme.textSecondary
                    }
                    Text {
                        width: 80
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                        text: win.sizeText(row.modelData.size)
                        font.family: FiliTheme.font
                        font.pixelSize: FiliTheme.sizeList
                        color: FiliTheme.textSecondary
                    }
                }
                MouseArea {
                    id: rowArea2
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPressed: list.currentIndex = row.index
                    onDoubleClicked: m => {
                        if (m.button === Qt.LeftButton)
                            cas.play(row.modelData.path);
                    }
                    onClicked: m => {
                        if (m.button === Qt.RightButton) {
                            const p = mapToItem(win.contentItem, m.x, m.y);
                            menu.open(p.x, p.y, win.rowMenu());
                        }
                    }
                }
            }
            // Nothing to show: what is missing and how to start
            Column {
                anchors.centerIn: parent
                visible: win.items.length === 0
                spacing: FiliTheme.space2
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: win.all.length === 0 ? Fili.tr("No recording yet") : Fili.tr("Nothing matches")
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeTitle
                    color: FiliTheme.textSecondary
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: win.all.length === 0
                    text: Fili.tr("Switch to Record to make the first one (Ctrl+2)")
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.size
                    color: FiliTheme.muted
                }
            }
        }

        FiliScrollBar {
            flick: list
            anchors { top: list.top; bottom: list.bottom; right: list.right }
        }

        // Player: previous, back 10 s, play / pause, forward 10 s, next; the position and the length around the bar
        Rectangle {
            id: transport
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 64
            color: FiliTheme.background
            Rectangle {
                width: parent.width
                height: FiliTheme.borderWidth
                color: FiliTheme.border
            }
            Row {
                id: controls
                x: FiliTheme.margin
                anchors.verticalCenter: parent.verticalCenter
                spacing: FiliTheme.space1
                IconButton { glyph: win.g.prev; enabledState: cas.playing; onClicked: cas.prev(); Accessible.name: Fili.tr("Previous") }
                IconButton { glyph: win.g.back; enabledState: cas.playing; onClicked: cas.seekBy(-10); Accessible.name: Fili.tr("Back 10 seconds") }
                Rectangle {
                    id: playButton
                    width: 40
                    height: 30
                    radius: FiliTheme.radiusControl
                    readonly property bool usable: cas.playing || win.selectedItem !== null
                    color: !usable ? "transparent" : playArea.pressed ? FiliTheme.surfaceActive : playArea.containsMouse ? FiliTheme.surfaceHover : FiliTheme.surface
                    border.width: FiliTheme.borderWidth
                    border.color: FiliTheme.border
                    Text {
                        anchors.centerIn: parent
                        text: cas.playing && !cas.paused ? win.g.pause : win.g.play
                        font.family: FiliTheme.icons
                        font.pixelSize: 18
                        color: playButton.usable ? FiliTheme.accentColor : FiliTheme.muted
                    }
                    MouseArea {
                        id: playArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: playButton.usable
                        onClicked: win.runAction("play-pause")
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: cas.playing && !cas.paused ? Fili.tr("Pause") : Fili.tr("Play")
                }
                IconButton { glyph: win.g.fwd; enabledState: cas.playing; onClicked: cas.seekBy(10); Accessible.name: Fili.tr("Forward 10 seconds") }
                IconButton { glyph: win.g.next; enabledState: cas.playing; onClicked: cas.next(); Accessible.name: Fili.tr("Next") }
                IconButton { glyph: win.g.stop; enabledState: cas.playing; onClicked: cas.stopPlay(); Accessible.name: Fili.tr("Stop") }
            }
            Text {
                id: elapsed
                anchors { left: controls.right; leftMargin: FiliTheme.space4; verticalCenter: parent.verticalCenter }
                width: 52
                text: win.clock(cas.position)
                horizontalAlignment: Text.AlignRight
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeSmall
                color: FiliTheme.textSecondary
            }
            // Seek bar: a click or a drag moves the position
            Item {
                id: bar
                anchors { left: elapsed.right; leftMargin: FiliTheme.space2; right: remaining.left; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                height: 20
                readonly property real fraction: cas.duration > 0 ? Math.min(1, cas.position / cas.duration) : 0
                Rectangle {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                    height: 4
                    radius: 2
                    color: FiliTheme.surface
                    border.width: FiliTheme.borderWidth
                    border.color: FiliTheme.border
                    Rectangle {
                        width: parent.width * bar.fraction
                        height: parent.height
                        radius: 2
                        color: FiliTheme.accentColor
                    }
                }
                Rectangle {
                    visible: cas.playing
                    x: (bar.width - width) * bar.fraction
                    anchors.verticalCenter: parent.verticalCenter
                    width: 12
                    height: 12
                    radius: 6
                    color: FiliTheme.accentColor
                    border.width: FiliTheme.borderWidth
                    border.color: FiliTheme.background
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: cas.playing
                    cursorShape: Qt.PointingHandCursor
                    onPressed: m => cas.seekTo(Math.max(0, Math.min(1, m.x / width)) * cas.duration)
                    onPositionChanged: m => {
                        if (pressed)
                            cas.seekTo(Math.max(0, Math.min(1, m.x / width)) * cas.duration);
                    }
                }
                Accessible.role: Accessible.Slider
                Accessible.name: Fili.tr("Position")
            }
            Text {
                id: remaining
                anchors { right: nowPlaying.left; rightMargin: FiliTheme.space3; verticalCenter: parent.verticalCenter }
                width: 52
                text: cas.playing ? "−" + win.clock(cas.duration - cas.position) : ""
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeSmall
                color: FiliTheme.textSecondary
            }
            Text {
                id: nowPlaying
                anchors { right: parent.right; rightMargin: FiliTheme.margin; verticalCenter: parent.verticalCenter }
                width: Math.min(220, Math.max(0, library.width * 0.22))
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideMiddle
                text: cas.playing ? cas.current.split("/").pop().replace(/\.wav$/, "") : ""
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeSmall
                color: FiliTheme.textSecondary
            }
        }
    }

    // ---- Content: the recorder -----------------------------------------------------------------------------------
    Item {
        id: recorder
        visible: win.mode === "record"
        anchors { top: toolbar.bottom; left: side.right; right: parent.right; bottom: statusbar.top }
        Column {
            width: Math.min(480, parent.width - 2 * FiliTheme.margin)
            anchors { top: parent.top; topMargin: FiliTheme.space6; horizontalCenter: parent.horizontalCenter }
            spacing: FiliTheme.space2
            Text {
                text: Fili.tr("What to record")
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeTitle
                color: FiliTheme.text
            }
            Text {
                width: parent.width
                text: Fili.tr("Both are optional. A call or a meeting: the microphone is you, the output is the voices of the others.")
                wrapMode: Text.Wrap
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.size
                color: FiliTheme.textSecondary
            }
            Item { width: 1; height: FiliTheme.space2 }
            Text {
                text: Fili.tr("Input")
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeSmall
                font.weight: FiliTheme.weightAccent
                color: FiliTheme.muted
            }
            SourcePicker {
                width: parent.width
                enabled: !cas.recording
                opacity: enabled ? 1 : 0.5
                model: win.choices(win.sources.inputs, win.sources.default_input)
                current: cas.input
                placeholder: cas.input
                onPicked: v => cas.setChoice("input", v)
            }
            Item { width: 1; height: FiliTheme.space1 }
            Text {
                text: Fili.tr("Output")
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeSmall
                font.weight: FiliTheme.weightAccent
                color: FiliTheme.muted
            }
            SourcePicker {
                width: parent.width
                enabled: !cas.recording
                opacity: enabled ? 1 : 0.5
                model: win.choices(win.sources.outputs, win.sources.default_output)
                current: cas.output
                placeholder: cas.output
                onPicked: v => cas.setChoice("output", v)
            }
            Item { width: 1; height: FiliTheme.space1 }
            Text {
                text: Fili.tr("Files")
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeSmall
                font.weight: FiliTheme.weightAccent
                color: FiliTheme.muted
            }
            Row {
                spacing: FiliTheme.space2
                Repeater {
                    model: [{ mix: true, label: Fili.tr("One mixed file") }, { mix: false, label: Fili.tr("One file per source") }]
                    Rectangle {
                        id: chip
                        required property var modelData
                        readonly property bool on: cas.mix === modelData.mix
                        enabled: !cas.recording
                        opacity: enabled ? 1 : 0.5
                        width: chipText.implicitWidth + 2 * FiliTheme.space3
                        height: 26
                        radius: FiliTheme.radiusControl
                        color: on ? FiliTheme.surfaceHover : chipArea.containsMouse ? FiliTheme.alpha(FiliTheme.surfaceHover, 0.5) : FiliTheme.surface
                        border.width: FiliTheme.borderWidth
                        border.color: on ? FiliTheme.accentColor : FiliTheme.border
                        Text {
                            id: chipText
                            anchors.centerIn: parent
                            text: chip.modelData.label
                            font.family: FiliTheme.font
                            font.pixelSize: FiliTheme.sizeList
                            color: chip.on ? FiliTheme.accentColor : FiliTheme.text
                        }
                        MouseArea {
                            id: chipArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: cas.setChoice("mode", chip.modelData.mix ? "mix" : "separate")
                        }
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: chip.modelData.label
                    }
                }
            }
            Item { width: 1; height: FiliTheme.space4 }
            // Record / stop: the one prominent action of the view
            Rectangle {
                id: recButton
                readonly property bool usable: !cas.saving && (cas.recording || cas.input !== "none" || cas.output !== "none")
                width: parent.width
                height: 44
                radius: FiliTheme.radiusControl
                color: !usable ? FiliTheme.surface : recArea.pressed ? FiliTheme.surfaceActive : recArea.containsMouse ? FiliTheme.surfaceHover : FiliTheme.surface
                border.width: FiliTheme.borderWidth
                border.color: cas.recording ? FiliTheme.danger : FiliTheme.border
                Row {
                    anchors.centerIn: parent
                    spacing: FiliTheme.space3
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: cas.recording ? win.g.stop : win.g.rec
                        font.family: FiliTheme.icons
                        font.pixelSize: 18
                        color: !recButton.usable ? FiliTheme.muted : cas.recording ? FiliTheme.danger : FiliTheme.accentColor
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: cas.saving ? Fili.tr("Saving…") : cas.recording ? Fili.tr("Stop recording") + "  " + win.clock(elapsedRec.seconds) : Fili.tr("Start recording")
                        font.family: FiliTheme.font
                        font.pixelSize: FiliTheme.size
                        font.weight: FiliTheme.weightAccent
                        color: recButton.usable ? FiliTheme.text : FiliTheme.muted
                    }
                }
                MouseArea {
                    id: recArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: recButton.usable
                    onClicked: win.toggleRecord()
                }
                Accessible.role: Accessible.Button
                Accessible.name: cas.recording ? Fili.tr("Stop recording") : Fili.tr("Start recording")
            }
            Text {
                visible: cas.input === "none" && cas.output === "none" && !cas.recording
                width: parent.width
                text: Fili.tr("Choose an input or an output")
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeSmall
                color: FiliTheme.muted
            }
            Text {
                visible: cas.recording
                width: parent.width
                text: Fili.tr("The sources apply to the next recording")
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeSmall
                color: FiliTheme.muted
            }
        }
        // Seconds since the start of the recording, one tick a second while it runs
        Item {
            id: elapsedRec
            property real now: Date.now()
            readonly property int seconds: cas.recording ? Math.max(0, Math.floor(now / 1000 - cas.recStart)) : 0
            Timer {
                running: cas.recording && !cas.saving && win.mode === "record"
                interval: 1000
                repeat: true
                triggeredOnStart: true
                onTriggered: elapsedRec.now = Date.now()
            }
        }
    }

    // ---- Footer ---------------------------------------------------------------------------------------------------
    Rectangle {
        id: statusbar
        anchors.bottom: parent.bottom
        width: parent.width
        height: win.footerShown ? FiliTheme.statusHeight : 0
        visible: win.footerShown
        // Recessed like Facteur's footer (app-window.md of the filigrane-ui skill)
        color: FiliTheme.backgroundDeep
        Rectangle {
            width: parent.width
            height: FiliTheme.borderWidth
            color: FiliTheme.border
        }
        // An error or a notice takes the whole bar
        Text {
            anchors { fill: parent; leftMargin: FiliTheme.space3; rightMargin: FiliTheme.space3; topMargin: 1 }
            visible: cas.message !== ""
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideMiddle
            text: cas.message
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.sizeSmall
            color: cas.failed ? FiliTheme.danger : FiliTheme.textSecondary
            MouseArea { anchors.fill: parent; onClicked: cas.clearMessage() }
        }
        Text {
            anchors { left: parent.left; leftMargin: FiliTheme.margin; right: parent.horizontalCenter; top: parent.top; topMargin: 1; bottom: parent.bottom }
            visible: cas.message === ""
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: cas.recording ? (cas.saving ? Fili.tr("Saving…") : "● " + Fili.tr("Recording") + "  " + win.clock(elapsedRec.seconds)) : win.items.length + " " + Fili.tr("recordings") + " · " + win.clock(win.items.reduce((a, r) => a + r.duration, 0))
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.sizeSmall
            color: cas.recording ? FiliTheme.danger : FiliTheme.textSecondary
        }
        Text {
            anchors { right: parent.right; rightMargin: FiliTheme.margin; left: parent.horizontalCenter; top: parent.top; topMargin: 1; bottom: parent.bottom }
            visible: cas.message === ""
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideMiddle
            text: win.mode === "library" && win.selectedItem ? win.selectedItem.name : win.mode === "record" ? cas.dir : ""
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.sizeSmall
            color: FiliTheme.textSecondary
        }
    }

    // ---- Window actions, menus, About -----------------------------------------------------------------------------
    WindowPanel {
        id: windowPanel
        anchorRight: width - (toolbar.height - closeButton.height) / 2
        anchorTop: toolbar.height + 1
    }
    function rowMenu() {
        return [
            { id: "play-selected", label: Fili.tr("Play") },
            { id: "separator1", separator: true },
            { id: "show-in-casier", label: Fili.tr("Show in Casier") },
            { id: "copy-name", label: Fili.tr("Copy name") },
            { id: "separator2", separator: true },
            { id: "trash", label: Fili.tr("Move to Trash"), hint: "Delete" }
        ];
    }
    ContextMenu {
        id: menu
        onActivated: id => win.runAction(id)
    }

    // About card: in front of the window, closed by Esc or a click outside
    Rectangle {
        id: about
        visible: win.aboutOpen
        anchors.fill: parent
        z: 300
        color: FiliTheme.alpha(FiliTheme.background, 0.6)
        focus: visible
        MouseArea { anchors.fill: parent; onClicked: win.aboutOpen = false }
        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(440, parent.width - 2 * FiliTheme.margin)
            height: cardColumn.implicitHeight + 2 * FiliTheme.space6
            radius: FiliTheme.radiusWindow
            color: FiliTheme.surface
            border.width: FiliTheme.borderWidth
            border.color: FiliTheme.border
            MouseArea { anchors.fill: parent }
            Column {
                id: cardColumn
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: FiliTheme.space6 }
                spacing: FiliTheme.space2
                Image {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 72
                    height: 72
                    source: "qrc:/qt/qml/Fili/Cassette/icons/fili-recorder.svg"
                    sourceSize: Qt.size(144, 144)
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Cassette"
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeTitle + 4
                    font.weight: Font.Light
                    color: FiliTheme.text
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: Fili.tr("Records a microphone and what the speakers play, and plays the recordings back")
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.size
                    color: FiliTheme.textSecondary
                }
                Item { width: 1; height: FiliTheme.space2 }
                Repeater {
                    model: win.aboutOpen ? JSON.parse(Fili.aboutRows()) : []
                    Row {
                        id: aboutRow
                        required property var modelData
                        width: cardColumn.width
                        spacing: FiliTheme.space3
                        Text {
                            width: 120
                            horizontalAlignment: Text.AlignRight
                            text: aboutRow.modelData[0]
                            font.family: FiliTheme.font
                            font.pixelSize: FiliTheme.size
                            color: FiliTheme.muted
                        }
                        Text {
                            width: parent.width - 120 - FiliTheme.space3
                            text: aboutRow.modelData[1]
                            elide: Text.ElideMiddle
                            font.family: FiliTheme.font
                            font.pixelSize: FiliTheme.size
                            color: FiliTheme.text
                        }
                    }
                }
            }
        }
    }
}
