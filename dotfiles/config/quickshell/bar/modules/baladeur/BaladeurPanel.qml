// fili-panel Baladeur: the player and the queue of Baladeur, drawn like its window (PlayerControls.qml, QueuePanel.qml,
// VolumeDial.qml of fili-music repository): the player on top (cover tinted with its colour, title, volume dial that follows the
// sound, transport and progress), the queue under it (filter, the whole list with a scroll bar, the bar of queue actions).
// The player's state is Baladeur's MPRIS one plus `fili-music ctl queue`; the rows are read by pieces (`ctl tracks 3,4,5`) as
// the list scrolls, like the window's virtual list, and `ctl filter` finds the places that match the filter field. The band
// levels for the dial come on a socket kept open to Baladeur (`levels-stream`), only while this panel is open.
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Services.Mpris
import qs
import qs.bar
import qs.controls

ColumnLayout {
    id: view
    spacing: 0
    implicitWidth: 350
    readonly property string icons: "Fili Icons"
    readonly property var player: Mpris.players.values.find(p => p.desktopEntry === "fili-music" || p.dbusName.indexOf("fili_music") >= 0) ?? null
    // State of the player kept by Baladeur: current place, size of the queue, shuffle, repeat, volume, format of the track
    property var st: ({ current: -1, total: 0, shuffle: false, repeat: "off", playing: false, volume: 1, info: "" })
    readonly property int total: st.total
    readonly property bool empty: total === 0
    property real now: 0
    readonly property real length: player && player.lengthSupported ? player.length : 0
    property var levels: []

    function clock(s) {
        s = Math.max(0, Math.round(s));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }
    function action(name) {
        run.command = ["fili-music", "ctl", "action"].concat(name.split(" "));
        run.running = true;
        settle.restart();
    }
    function refresh() {
        read.running = true;
    }
    Timer { id: settle; interval: 350; onTriggered: view.refresh() }
    Timer { interval: 3000; running: true; repeat: true; onTriggered: view.refresh() }
    Process { id: run }
    // `fili-music` alone shows the hidden window or brings the open one to the front
    Process {
        id: openWindow
        command: ["fili-music"]
        onExited: (code, status) => console.log("baladeur: fili-music exited", code, status)
    }
    Process {
        id: read
        command: ["fili-music", "ctl", "queue"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const q = JSON.parse(text);
                    if (!q.ok)
                        return;
                    // Another size: the places moved, the rows are asked again
                    if (q.total !== view.st.total) {
                        view.rowsByPlace = ({});
                        view.rowsRev++;
                        view.matches = null;
                        filterTimer.restart();
                    }
                    const first = view.st.current < 0;
                    view.st = q;
                    if (first || view.scrollToCurrent)
                        list.toCurrent();
                } catch (e) {
                }
            }
        }
    }
    property bool scrollToCurrent: true
    Component.onCompleted: refresh()
    Connections {
        target: view.player
        function onTrackTitleChanged() { view.refresh(); }
    }

    // ---- Levels for the dial -------------------------------------------------------------------------------------------
    Process {
        id: where
        command: ["fili-music", "ctl", "socket"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim();
                if (path !== "") {
                    levelsSocket.path = path;
                    levelsSocket.connected = true;
                }
            }
        }
    }
    Socket {
        id: levelsSocket
        onConnectedChanged: {
            if (connected) {
                write("levels-stream\n");
                flush();
            }
        }
        parser: SplitParser {
            onRead: line => {
                try {
                    view.levels = view.player && view.player.isPlaying ? JSON.parse(line) : [];
                } catch (e) {
                }
            }
        }
    }

    Timer {
        interval: 250
        running: view.player !== null
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (view.player && view.player.isPlaying)
                view.player.positionChanged();
            view.now = view.player ? view.player.position : 0;
        }
    }

    Text {
        visible: !view.player
        Layout.fillWidth: true
        Layout.margins: FiliTheme.space2
        text: FiliI18n.tr("Baladeur is not running")
        wrapMode: Text.Wrap
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }

    // ============================== Player ==============================================================================
    Rectangle {
        id: controls
        visible: view.player !== null
        Layout.fillWidth: true
        implicitHeight: top.height + transport.height + FiliTheme.space4 + FiliTheme.space3
        color: FiliTheme.nuit
        property color ambient: "transparent"
        readonly property string art: view.player ? view.player.trackArtUrl : ""

        // Dominant colour of the cover (the image shrunk to a few pixels, weighted by saturation)
        Canvas {
            id: canvas
            width: 16
            height: 16
            opacity: 0
            renderTarget: Canvas.Image
            onImageLoaded: requestPaint()
            onPaint: {
                if (controls.art === "" || !isImageLoaded(controls.art))
                    return;
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                ctx.drawImage(controls.art, 0, 0, width, height);
                const px = ctx.getImageData(0, 0, width, height).data;
                let r = 0, g = 0, b = 0, w = 0;
                for (let i = 0; i < px.length; i += 4) {
                    const mx = Math.max(px[i], px[i + 1], px[i + 2]), mn = Math.min(px[i], px[i + 1], px[i + 2]);
                    if (px[i + 3] < 128 || mx < 30 || mn > 235)
                        continue;
                    const sat = (mx - mn) / mx;
                    const k = 0.05 + sat * sat;
                    r += px[i] * k;
                    g += px[i + 1] * k;
                    b += px[i + 2] * k;
                    w += k;
                }
                controls.ambient = w > 0 ? Qt.rgba(r / w / 255, g / w / 255, b / w / 255, 1) : "transparent";
            }
        }
        onArtChanged: {
            ambient = "transparent";
            if (art === "")
                return;
            if (canvas.isImageLoaded(art))
                canvas.requestPaint();
            else
                canvas.loadImage(art);
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: FiliTheme.alpha(controls.ambient, 0.30) }
                GradientStop { position: 1; color: FiliTheme.alpha(controls.ambient, 0.05) }
            }
            opacity: controls.ambient.a > 0 ? 1 : 0
        }

        Row {
            id: top
            x: FiliTheme.space3
            y: FiliTheme.space3
            width: parent.width - 2 * FiliTheme.space3
            spacing: FiliTheme.space3
            Rectangle {
                id: cover
                width: 80
                height: 80
                radius: FiliTheme.radiusControl
                color: FiliTheme.nuit2
                clip: true
                Image {
                    anchors.fill: parent
                    source: controls.art
                    visible: status === Image.Ready
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize: Qt.size(160, 160)
                }
                Text {
                    anchors.centerIn: parent
                    visible: controls.art === ""
                    text: "♫"
                    font { family: FiliTheme.font; pixelSize: 26 }
                    color: FiliTheme.ardoise
                }
            }
            Column {
                width: parent.width - cover.width - dial.width - 2 * parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: view.player && view.player.trackTitle ? view.player.trackTitle : FiliI18n.tr("Not playing")
                    font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
                    color: FiliTheme.brume
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: view.player ? view.player.trackAlbum : ""
                    font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                    color: FiliTheme.brume2
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: view.player ? view.player.trackArtist : ""
                    font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                    color: FiliTheme.brume2
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: view.st.info
                    font { family: FiliTheme.font; pixelSize: FiliTheme.sizeLabel }
                    color: FiliTheme.ardoise
                }
            }

            // Round volume control: 40 ticks on a 270 degree arc; the active ones follow the sound
            Item {
                id: dial
                width: 80
                height: 80
                property real dragVolume: -1
                readonly property real shown: dragVolume >= 0 ? dragVolume : view.st.volume
                readonly property int ticks: 40
                // Colour of the tick at `fraction` of the arc: its band's level, stretched (music sits between 0.3 and 0.75 of the
                // raw scale) and sharpened, goes from a very dark accent through the accent to a lightened one
                function lit(fraction) {
                    const l = view.levels;
                    if (!l || l.length === 0)
                        return FiliTheme.voile;
                    const at = fraction * (l.length - 1);
                    const i = Math.floor(at), j = Math.min(l.length - 1, i + 1);
                    const raw = l[i] + (l[j] - l[i]) * (at - i);
                    const level = Math.pow(Math.max(0, Math.min(1, (raw - 0.3) / 0.45)), 1.5);
                    const dark = Qt.tint(FiliTheme.nuit, FiliTheme.alpha(FiliTheme.voile, 0.2));
                    if (level < 0.6)
                        return Qt.tint(dark, FiliTheme.alpha(FiliTheme.voile, level / 0.6));
                    return Qt.tint(FiliTheme.voile, FiliTheme.alpha(Qt.lighter(FiliTheme.voileVif, 1.35), (level - 0.6) / 0.4));
                }
                function fromPoint(x, y) {
                    let angle = Math.atan2(y - height / 2, x - width / 2) * 180 / Math.PI;
                    if (angle < 0)
                        angle += 360;
                    const n = angle >= 135 ? angle - 135 : angle + 225;
                    return Math.max(0, Math.min(1, n / 270));
                }
                function send(v) {
                    const next = Object.assign({}, view.st);
                    next.volume = v;
                    view.st = next;
                    view.action("set-volume " + v.toFixed(3));
                }
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: FiliTheme.nuit2
                    border { width: FiliTheme.borderWidth; color: FiliTheme.border }
                }
                Repeater {
                    model: dial.ticks
                    Item {
                        id: tick
                        required property int index
                        readonly property real fraction: index / (dial.ticks - 1)
                        x: dial.width / 2
                        y: dial.height / 2
                        width: 0
                        height: 0
                        rotation: 225 + 270 * fraction
                        Rectangle {
                            x: -1
                            y: -(dial.height / 2 - 8) - 2
                            width: 2
                            height: 5
                            radius: 1
                            color: tick.fraction <= dial.shown ? dial.lit(tick.fraction) : FiliTheme.border
                        }
                    }
                }
                Column {
                    anchors.centerIn: parent
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Math.round(dial.shown * 100)
                        font { family: FiliTheme.font; pixelSize: 20; weight: Font.Medium }
                        color: FiliTheme.brume
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "%"
                        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                        color: FiliTheme.ardoise
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onPressed: e => dial.dragVolume = dial.fromPoint(e.x, e.y)
                    onPositionChanged: e => dial.dragVolume = dial.fromPoint(e.x, e.y)
                    onReleased: {
                        if (dial.dragVolume >= 0)
                            dial.send(dial.dragVolume);
                        dial.dragVolume = -1;
                    }
                    onWheel: e => dial.send(Math.max(0, Math.min(1, view.st.volume + (e.angleDelta.y > 0 ? 0.02 : -0.02))))
                }
                Accessible.role: Accessible.Slider
                Accessible.name: FiliI18n.tr("Volume")
            }
        }

        // The cover and the texts open the window of Baladeur
        MouseArea {
            x: top.x
            y: top.y
            width: top.width - dial.width - top.spacing
            height: top.height
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                console.log("baladeur: click on the player, opening the window");
                openWindow.running = true;
            }
            Accessible.role: Accessible.Button
            Accessible.name: FiliI18n.tr("Open Baladeur")
        }

        Item {
            id: transport
            anchors { left: parent.left; right: parent.right; top: top.bottom; topMargin: FiliTheme.space3; leftMargin: FiliTheme.space3; rightMargin: FiliTheme.space3 }
            height: 36
            Row {
                id: buttons
                anchors.verticalCenter: parent.verticalCenter
                spacing: FiliTheme.space4
                Repeater {
                    model: [
                        { key: "prev", glyph: String.fromCodePoint(0xf2f11), size: 16 },
                        { key: "play", glyph: "", size: 20 },
                        { key: "next", glyph: String.fromCodePoint(0xf2f12), size: 16 }
                    ]
                    Item {
                        id: tb
                        required property var modelData
                        width: 28
                        height: 28
                        Rectangle {
                            anchors.fill: parent
                            radius: FiliTheme.radiusControl
                            color: tbArea.pressed ? FiliTheme.nuit4 : tbArea.containsMouse ? FiliTheme.nuit3 : "transparent"
                        }
                        Text {
                            anchors.centerIn: parent
                            text: tb.modelData.key === "play" ? (view.player && view.player.isPlaying ? "" : "") : tb.modelData.glyph
                            font { family: view.icons; pixelSize: tb.modelData.size }
                            color: FiliTheme.brume
                        }
                        MouseArea {
                            id: tbArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: view.action(tb.modelData.key === "prev" ? "prev" : tb.modelData.key === "next" ? "next" : "play-pause")
                        }
                        Accessible.role: Accessible.Button
                        Accessible.name: tb.modelData.key === "prev" ? FiliI18n.tr("Previous") : tb.modelData.key === "next" ? FiliI18n.tr("Next") : FiliI18n.tr("Play or Pause")
                    }
                }
            }
            // Progress: a bar that grows on hover, seek by click or drag
            Item {
                id: progress
                anchors { left: buttons.right; leftMargin: FiliTheme.space4; right: parent.right; verticalCenter: parent.verticalCenter }
                height: 30
                property real drag: -1
                readonly property real fraction: drag >= 0 ? drag : (view.length > 0 ? Math.min(1, view.now / view.length) : 0)
                Rectangle {
                    id: bar
                    y: 6
                    width: parent.width
                    height: barArea.containsMouse || progress.drag >= 0 ? 6 : 4
                    radius: 2
                    color: FiliTheme.alpha(FiliTheme.ardoise, 0.35)
                    Rectangle {
                        width: bar.width * progress.fraction
                        height: parent.height
                        radius: 2
                        color: FiliTheme.voile
                    }
                }
                MouseArea {
                    id: barArea
                    width: parent.width
                    height: 18
                    hoverEnabled: true
                    enabled: view.length > 0
                    onPressed: e => progress.drag = Math.max(0, Math.min(1, e.x / width))
                    onPositionChanged: e => {
                        if (pressed)
                            progress.drag = Math.max(0, Math.min(1, e.x / width));
                    }
                    onReleased: {
                        if (progress.drag >= 0) {
                            const at = progress.drag * view.length;
                            view.now = at;
                            view.action("seek " + at.toFixed(1));
                        }
                        progress.drag = -1;
                    }
                }
                Text {
                    anchors { left: parent.left; bottom: parent.bottom }
                    text: view.clock(progress.drag >= 0 ? progress.drag * view.length : view.now)
                    font { family: FiliTheme.font; pixelSize: FiliTheme.sizeLabel }
                    color: FiliTheme.ardoise
                }
                Text {
                    anchors { right: parent.right; bottom: parent.bottom }
                    text: view.clock(view.length)
                    font { family: FiliTheme.font; pixelSize: FiliTheme.sizeLabel }
                    color: FiliTheme.ardoise
                }
            }
        }
    }

    // ============================== Queue ===============================================================================
    // Rows by place in the play order, read by pieces as they are drawn; `matches` = places kept by the filter (null = all)
    property var rowsByPlace: ({})
    property int rowsRev: 0
    property var wanted: ({})
    readonly property var flags: ({ scheduled: false })
    property var matches: null
    property string filter: ""
    readonly property real numberWidth: Math.ceil(numberMetrics.advanceWidth) + FiliTheme.space2
    TextMetrics {
        id: numberMetrics
        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
        text: "9".repeat(String(view.total).length) + "."
    }
    function rowAt(pos) {
        rowsRev;
        const r = rowsByPlace[pos];
        if (r !== undefined)
            return r;
        wanted[pos] = true;
        // `flags` is a plain object: reading `fetchTimer.running` here would make the row's binding depend on what it starts
        // (a binding loop on `info`)
        if (!flags.scheduled) {
            flags.scheduled = true;
            fetchTimer.start();
        }
        return null;
    }
    Timer {
        id: fetchTimer
        interval: 40
        onTriggered: {
            view.flags.scheduled = false;
            const places = Object.keys(view.wanted).slice(0, 80);
            if (places.length === 0)
                return;
            if (fetch.running) {
                view.flags.scheduled = true;
                fetchTimer.start();
                return;
            }
            for (const p of places)
                delete view.wanted[p];
            fetch.command = ["fili-music", "ctl", "tracks", places.join(",")];
            fetch.running = true;
        }
    }
    Process {
        id: fetch
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const answer = JSON.parse(text);
                    if (answer.ok) {
                        for (const r of answer.rows)
                            view.rowsByPlace[r.pos] = r;
                        view.rowsRev++;
                    }
                } catch (e) {
                }
                if (Object.keys(view.wanted).length > 0 && !view.flags.scheduled) {
                    view.flags.scheduled = true;
                    fetchTimer.start();
                }
            }
        }
    }
    Timer {
        id: filterTimer
        interval: 250
        onTriggered: {
            if (view.filter === "") {
                view.matches = null;
                return;
            }
            find.command = ["fili-music", "ctl", "filter", view.filter];
            find.running = true;
        }
    }
    Process {
        id: find
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const answer = JSON.parse(text);
                    if (answer.ok && view.filter !== "")
                        view.matches = answer.places;
                } catch (e) {
                }
            }
        }
    }

    // Filter
    Rectangle {
        id: filterBar
        visible: view.player !== null && !view.empty
        Layout.fillWidth: true
        implicitHeight: visible ? 36 : 0
        color: FiliTheme.nuit
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: FiliTheme.borderWidth
            color: FiliTheme.border
        }
        Text {
            id: lens
            x: FiliTheme.space3
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            font { family: view.icons; pixelSize: 13 }
            color: FiliTheme.ardoise
        }
        Text {
            anchors { left: lens.right; leftMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
            visible: filterInput.text === ""
            text: FiliI18n.tr("Filter the queue")
            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
            color: FiliTheme.ardoise
        }
        TextInput {
            id: filterInput
            anchors { left: lens.right; leftMargin: FiliTheme.space2; right: clear.left; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
            clip: true
            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
            color: FiliTheme.brume
            onTextChanged: {
                view.filter = text.trim().toLowerCase();
                if (view.filter === "")
                    view.matches = null;
                else
                    filterTimer.restart();
            }
            Keys.onEscapePressed: text = ""
        }
        Text {
            id: clear
            anchors { right: parent.right; rightMargin: FiliTheme.space3; verticalCenter: parent.verticalCenter }
            visible: filterInput.text !== ""
            text: "×"
            font { family: FiliTheme.font; pixelSize: 16 }
            color: FiliTheme.ardoise
            MouseArea { anchors.fill: parent; onClicked: filterInput.text = "" }
        }
    }

    Text {
        visible: view.player !== null && view.empty
        Layout.fillWidth: true
        Layout.margins: FiliTheme.space3
        horizontalAlignment: Text.AlignHCenter
        text: FiliI18n.tr("The queue is empty")
        wrapMode: Text.Wrap
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeTitle; weight: FiliTheme.weightAccent }
        color: FiliTheme.brume
    }

    ListView {
        id: list
        visible: view.player !== null && !view.empty
        Layout.fillWidth: true
        // Never the whole height of the screen: the list scrolls
        implicitHeight: Math.min(count * 44, 440)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: view.matches === null ? view.total : view.matches.length
        function toCurrent() {
            if (view.st.current >= 0 && view.matches === null)
                positionViewAtIndex(Math.max(0, view.st.current - 2), ListView.Beginning);
        }
        FiliScrollBar { view: list; anchors { right: parent.right; top: parent.top; bottom: parent.bottom } }
        delegate: Rectangle {
            id: row
            required property int index
            readonly property int position: view.matches === null ? index : view.matches[index]
            readonly property var info: view.rowAt(position)
            readonly property bool current: position === view.st.current
            width: ListView.view.width
            height: 44
            color: current ? FiliTheme.alpha(FiliTheme.voile, 0.12) : area.containsMouse ? FiliTheme.alpha(FiliTheme.nuit3, 0.5) : "transparent"
            Text {
                id: number
                x: FiliTheme.space3
                width: view.numberWidth
                anchors.verticalCenter: parent.verticalCenter
                text: (row.position + 1) + "."
                font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: row.current ? FiliTheme.weightAccent : Font.Normal }
                color: row.current ? FiliTheme.brume : FiliTheme.ardoise
            }
            Column {
                anchors { left: number.right; right: bin.left; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                spacing: 2
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: row.info ? row.info.title : ""
                    font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: row.current ? FiliTheme.weightAccent : Font.Normal }
                    color: FiliTheme.brume
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: row.info ? row.info.artist : ""
                    font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                    color: FiliTheme.brume2
                }
            }
            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                onDoubleClicked: view.action("play-queue-at " + row.position)
            }
            Text {
                id: bin
                anchors { right: parent.right; rightMargin: FiliTheme.space3 + 8; verticalCenter: parent.verticalCenter }
                visible: area.containsMouse || binArea.containsMouse
                text: ""
                font { family: view.icons; pixelSize: 14 }
                color: binArea.containsMouse ? FiliTheme.cendre : FiliTheme.brume2
                MouseArea {
                    id: binArea
                    anchors { fill: parent; margins: -6 }
                    hoverEnabled: true
                    onClicked: view.action("remove-queue-at " + row.position)
                }
                Accessible.name: FiliI18n.tr("Remove from queue")
            }
        }
    }

    // Queue actions
    Rectangle {
        visible: view.player !== null
        Layout.fillWidth: true
        implicitHeight: 44
        color: FiliTheme.nuit
        Rectangle {
            width: parent.width
            height: FiliTheme.borderWidth
            color: FiliTheme.border
        }
        Row {
            anchors.fill: parent
            Repeater {
                model: [
                    { key: "random", glyph: "⚄", tip: FiliI18n.tr("Add 30 random tracks") },
                    { key: "repeat", glyph: "↻", tip: FiliI18n.tr("Repeat") },
                    { key: "shuffle", glyph: "⇄", tip: FiliI18n.tr("Shuffle") },
                    { key: "save", glyph: "≡+", tip: FiliI18n.tr("Save the queue as a playlist") },
                    { key: "clear", glyph: "", tip: FiliI18n.tr("Clear the queue") }
                ]
                Item {
                    id: qb
                    required property var modelData
                    readonly property bool lit: (modelData.key === "repeat" && view.st.repeat !== "off") || (modelData.key === "shuffle" && view.st.shuffle === true)
                    readonly property bool off: (modelData.key === "save" || modelData.key === "clear") && view.empty
                    width: parent.width / 5
                    height: 44
                    Rectangle { anchors.fill: parent; color: qbArea.containsMouse && !qb.off ? FiliTheme.alpha(FiliTheme.nuit3, 0.5) : "transparent" }
                    Text {
                        anchors.centerIn: parent
                        text: qb.modelData.glyph + (qb.modelData.key === "repeat" && view.st.repeat === "one" ? "¹" : "")
                        font { family: qb.modelData.key === "clear" ? view.icons : FiliTheme.font; pixelSize: qb.lit ? 20 : 17 }
                        color: qb.off ? FiliTheme.alpha(FiliTheme.ardoise, 0.5) : qb.lit ? FiliTheme.voile : FiliTheme.brume2
                    }
                    MouseArea {
                        id: qbArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !qb.off
                        onClicked: {
                            switch (qb.modelData.key) {
                            case "random":
                                view.action("add-random");
                                break;
                            case "repeat":
                                view.action("repeat");
                                break;
                            case "shuffle":
                                view.action("shuffle");
                                break;
                            case "save":
                                // The name is asked in the window of Baladeur
                                view.action("save-queue-window");
                                break;
                            default:
                                view.action("clear-queue");
                            }
                        }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: qb.modelData.tip
                }
            }
        }
    }
}
