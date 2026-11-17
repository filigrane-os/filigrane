// Library scanner, the sections of the macOS one: folder (with quick access folders), scan progress, M3U import, artwork
// fetch (new covers only or everything, with cancel), library cleanup, errors and statistics. Shown at the first launch (the
// library is empty), from the sidebar and from the menu.
import QtQuick
import Fili.Baladeur

Rectangle {
    id: dlg
    property bool scanning: false
    property bool fetching: false
    property var scanProgress: ({ total_files: 0, processed_files: 0, tracks_added: 0, current_file: "" })
    // Progress of the artwork fetch as the core gives it (camelCase), and how it ended
    property var artProgress: ({ totalItems: 0, processedItems: 0, currentItem: "", successful: 0, failed: 0 })
    property bool artDone: false
    property bool artAsk: false
    property string result: ""
    property string error: ""
    property string importedName: ""
    property string cleanResult: ""
    property var stats: null
    // Albums that still have no cover (null until asked), and the file of the report the core wrote for the last fetch
    property var missing: null
    property string reportFile: ""
    property bool welcome: false
    property bool quiet: false
    readonly property real scanFraction: scanProgress.total_files > 0 ? scanProgress.processed_files / scanProgress.total_files : 0
    readonly property real artFraction: artProgress.totalItems > 0 ? artProgress.processedItems / artProgress.totalItems : 0
    signal finished()
    // A path typed in the M3U section: Main imports it and tells the name of the playlist ("" when it failed)
    signal importRequested(string path)

    visible: false
    anchors.fill: parent
    z: 260
    color: FiliTheme.alpha(FiliTheme.background, 0.6)
    focus: visible
    Keys.onEscapePressed: close()

    function open(first) {
        welcome = first === true;
        if (folder.text === "")
            folder.text = Fili.uiState("scan_dir") || Fili.musicDir();
        result = "";
        error = "";
        artAsk = false;
        loadStats();
        reportFile = Fili.reportPath("artwork");
        visible = true;
    }
    // `fili-music ctl action scan PATH`: scan that folder now
    function scanPath(path) {
        open(false);
        folder.text = path;
        quiet = true;
        scan();
    }
    function close() {
        if (scanning)
            return;
        visible = false;
    }
    function loadStats() {
        Store.callAsync("get_library_stats", [], d => {
            if (d)
                stats = d;
        });
    }
    function scan() {
        const path = folder.text.trim();
        if (path === "" || scanning)
            return;
        Fili.setUiState("scan_dir", path);
        scanning = true;
        result = "";
        error = "";
        scanProgress = { total_files: 0, processed_files: 0, tracks_added: 0, current_file: "" };
        Store.callAsync("scan_library", [path], d => {
            scanning = false;
            welcome = false;
            if (d)
                result = Fili.tr("%1 added, %2 updated, %3 unchanged").replace("%1", d.tracks_added).replace("%2", d.tracks_updated).replace("%3", d.tracks_skipped);
            else
                error = Store.lastError !== "" ? Store.lastError : Fili.tr("The scan failed");
            Store.forget();
            loadStats();
            if (quiet) {
                quiet = false;
                visible = false;
                Store.notice(d ? result : error, d === null);
            }
            dlg.finished();
        });
    }
    // The core starts the fetch in the background and answers at once: the progress is polled until it has nothing to report
    property int idleTicks: 0
    property bool seenProgress: false
    function fetchArtwork(force) {
        if (fetching)
            return;
        artAsk = false;
        artDone = false;
        error = "";
        artProgress = { totalItems: 0, processedItems: 0, currentItem: "", successful: 0, failed: 0 };
        idleTicks = 0;
        seenProgress = false;
        Store.callAsync("fetch_all_artwork", [true, force], d => {
            if (d === null) {
                error = Store.lastError !== "" ? Store.lastError : Fili.tr("The artwork fetch failed");
                return;
            }
            fetching = true;
        });
    }
    function cancelArtwork() {
        Store.call("cancel_artwork_fetch");
        fetching = false;
        Store.forget();
        loadStats();
    }
    function endArtwork() {
        fetching = false;
        artDone = true;
        Store.forget();
        loadStats();
        reveal = true;
        loadMissing();
        // The core writes its report just after the last item: looked up a moment later
        reportTimer.restart();
    }
    // Albums with neither an embedded nor an online cover, read page after page
    property int missingSerial: 0
    property bool reveal: false
    function loadMissing() {
        const mine = ++missingSerial;
        const found = [];
        const page = offset => Store.callAsync("get_albums_page", [offset, 500], d => {
            if (mine !== missingSerial)
                return;
            const albums = d ? d.albums : [];
            for (const a of albums)
                if (!a.artwork_path && !a.online_artwork_path)
                    found.push({ id: a.id, text: a.artist_name + " — " + a.title });
            if (albums.length === 500)
                page(offset + 500);
            else {
                missing = found;
                // After a fetch the list is brought into view
                if (reveal) {
                    reveal = false;
                    Qt.callLater(() => body.contentY = Math.max(0, Math.min(missingBlock.y - FiliTheme.space4, body.contentHeight - body.height)));
                }
            }
        });
        page(0);
    }
    Timer {
        id: reportTimer
        interval: 1500
        onTriggered: dlg.reportFile = Fili.reportPath("artwork")
    }
    Timer {
        interval: 250
        repeat: true
        running: dlg.scanning || dlg.fetching
        onTriggered: {
            if (dlg.scanning) {
                const p = Store.call("get_scan_progress");
                if (p)
                    dlg.scanProgress = p;
            }
            if (dlg.fetching) {
                const p = Store.call("get_artwork_fetch_progress");
                // The core keeps the last progress after the end (processed = total) and has nothing before the first fetch
                if (p) {
                    dlg.artProgress = p;
                    dlg.seenProgress = true;
                    // Nothing to do (every album has its cover): the total stays 0, so it is given 3 s to move
                    dlg.idleTicks = p.processedItems >= p.totalItems ? dlg.idleTicks + 1 : 0;
                    if (dlg.idleTicks >= (p.totalItems > 0 ? 2 : 12))
                        dlg.endArtwork();
                } else if (++dlg.idleTicks >= (dlg.seenProgress ? 2 : 12))
                    dlg.endArtwork();
            }
        }
    }
    MouseArea { anchors.fill: parent; onClicked: dlg.close() }

    // A section: a rounded block on the surface
    component Block: Rectangle {
        default property alias content: inner.data
        width: parent ? parent.width : 0
        height: inner.implicitHeight + 2 * FiliTheme.space3
        radius: FiliTheme.radiusControl
        color: FiliTheme.background
        border.width: FiliTheme.borderWidth
        border.color: FiliTheme.border
        Column {
            id: inner
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: FiliTheme.space3 }
            spacing: FiliTheme.space2
        }
    }
    component Heading: Text {
        font.family: FiliTheme.font
        font.pixelSize: FiliTheme.size
        font.weight: FiliTheme.weightAccent
        color: FiliTheme.text
    }
    component Note: Text {
        width: parent ? parent.width : 0
        wrapMode: Text.Wrap
        font.family: FiliTheme.font
        font.pixelSize: FiliTheme.sizeSmall
        color: FiliTheme.textSecondary
    }
    component Bar: Rectangle {
        property real value: 0
        width: parent ? parent.width : 0
        height: 4
        radius: 2
        color: FiliTheme.alpha(FiliTheme.muted, 0.35)
        Rectangle { width: parent.width * Math.min(1, parent.value); height: parent.height; radius: 2; color: FiliTheme.accentColor }
    }
    component PathField: Rectangle {
        id: field
        property alias text: input.text
        property alias editable: input.enabled
        property string name: ""
        signal accepted()
        width: parent ? parent.width : 0
        height: 28
        radius: FiliTheme.radiusControl
        color: FiliTheme.surface
        border.width: FiliTheme.borderWidth
        border.color: input.activeFocus ? FiliTheme.accentColor : FiliTheme.border
        TextInput {
            id: input
            anchors { fill: parent; leftMargin: FiliTheme.space2; rightMargin: FiliTheme.space2 }
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.size
            color: FiliTheme.text
            selectionColor: FiliTheme.surfaceActive
            selectedTextColor: FiliTheme.text
            Keys.onReturnPressed: field.accepted()
            Accessible.name: field.name
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(600, parent.width - 2 * FiliTheme.margin)
        height: Math.min(parent.height - 2 * FiliTheme.margin, 640)
        radius: FiliTheme.radiusWindow
        color: FiliTheme.surface
        border.width: FiliTheme.borderWidth
        border.color: FiliTheme.border
        clip: true
        MouseArea { anchors.fill: parent }

        // Header
        Item {
            id: header
            width: parent.width
            height: 64
            Column {
                anchors { left: parent.left; leftMargin: FiliTheme.space4; right: doneButton.left; rightMargin: FiliTheme.space3; verticalCenter: parent.verticalCenter }
                spacing: 2
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: dlg.welcome ? Fili.tr("Welcome to Baladeur") : Fili.tr("Scan the library")
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeTitle + 2
                    font.weight: Font.Light
                    color: FiliTheme.text
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: dlg.welcome ? Fili.tr("Choose the folder that holds your music") : Fili.tr("Add music, fetch artwork and tidy the library")
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeSmall
                    color: FiliTheme.textSecondary
                }
            }
            TextButton {
                id: doneButton
                anchors { right: parent.right; rightMargin: FiliTheme.space4; verticalCenter: parent.verticalCenter }
                label: dlg.welcome ? Fili.tr("Later") : Fili.tr("Done")
                primary: true
                onClicked: dlg.close()
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: FiliTheme.borderWidth; color: FiliTheme.border }
        }

        Flickable {
            id: body
            anchors { top: header.bottom; bottom: actions.top; left: parent.left; right: parent.right }
            contentHeight: sections.implicitHeight + 2 * FiliTheme.space4
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            KineticScroll {}
            Column {
                id: sections
                x: FiliTheme.space4
                y: FiliTheme.space4
                width: body.width - 2 * FiliTheme.space4
                spacing: FiliTheme.space3

                // Folder
                Block {
                    Heading { text: Fili.tr("Folder to scan") }
                    PathField {
                        id: folder
                        name: Fili.tr("Folder to scan")
                        editable: !dlg.scanning
                        onAccepted: dlg.scan()
                    }
                    Flow {
                        width: parent.width
                        spacing: FiliTheme.space2
                        Repeater {
                            model: {
                                const home = Fili.musicDir().replace(/\/[^\/]*$/, "");
                                return [
                                    { name: Fili.tr("Music"), path: Fili.musicDir() },
                                    { name: Fili.tr("Downloads"), path: home + "/Downloads" },
                                    { name: Fili.tr("Documents"), path: home + "/Documents" }
                                ].filter(f => Fili.dirExists(f.path));
                            }
                            TextButton {
                                required property var modelData
                                label: modelData.name
                                enabled: !dlg.scanning
                                onClicked: folder.text = modelData.path
                            }
                        }
                    }
                }
                // Scan progress
                Block {
                    visible: dlg.scanning || dlg.result !== ""
                    Heading { text: dlg.scanning ? Fili.tr("Scanning") : Fili.tr("Scan finished") }
                    Bar { visible: dlg.scanning; value: dlg.scanFraction }
                    Note {
                        elide: Text.ElideMiddle
                        maximumLineCount: dlg.scanning ? 1 : 3
                        text: dlg.scanning ? dlg.scanProgress.processed_files + " / " + dlg.scanProgress.total_files + (dlg.scanProgress.current_file ? "  ·  " + dlg.scanProgress.current_file : "") : dlg.result
                    }
                }
                // M3U import
                Block {
                    visible: !dlg.welcome
                    Heading { text: Fili.tr("Import a playlist") }
                    Note { text: Fili.tr("Turns an .m3u file into a playlist of the library; its files must already be in it.") }
                    PathField {
                        id: m3u
                        name: Fili.tr("Path of an .m3u file")
                        onAccepted: importButton.clicked()
                    }
                    Row {
                        spacing: FiliTheme.space3
                        TextButton {
                            id: importButton
                            label: Fili.tr("Import")
                            enabled: m3u.text.trim() !== ""
                            onClicked: dlg.importRequested(m3u.text.trim())
                        }
                        Note {
                            width: implicitWidth
                            anchors.verticalCenter: importButton.verticalCenter
                            visible: dlg.importedName !== ""
                            text: "✓ " + dlg.importedName
                        }
                    }
                }
                // Artwork
                Block {
                    visible: !dlg.welcome
                    Heading { text: Fili.tr("Artwork") }
                    Note { text: Fili.tr("Fetches covers and artist photos online (MusicBrainz). Albums that already have a cover are skipped unless you ask for everything.") }
                    Note {
                        visible: dlg.stats !== null
                        text: dlg.stats ? Fili.tr("%1 of %2 albums have a cover").replace("%1", dlg.stats.artwork_count).replace("%2", dlg.stats.album_count) : ""
                    }
                    Column {
                        width: parent.width
                        visible: dlg.fetching || dlg.artDone
                        spacing: FiliTheme.space1
                        Bar { visible: dlg.fetching; value: dlg.artFraction }
                        Note { text: dlg.artProgress.processedItems + " / " + dlg.artProgress.totalItems + "  ·  ✓ " + dlg.artProgress.successful + "  ·  ✗ " + dlg.artProgress.failed }
                        Note {
                            visible: dlg.fetching && dlg.artProgress.currentItem !== ""
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            text: dlg.artProgress.currentItem
                        }
                    }
                    Row {
                        spacing: FiliTheme.space2
                        TextButton {
                            visible: !dlg.fetching && !dlg.artAsk
                            label: Fili.tr("Fetch artwork")
                            onClicked: dlg.artAsk = true
                        }
                        TextButton {
                            visible: !dlg.fetching && dlg.artAsk
                            label: Fili.tr("New covers only")
                            primary: true
                            onClicked: dlg.fetchArtwork(false)
                        }
                        TextButton {
                            visible: !dlg.fetching && dlg.artAsk
                            label: Fili.tr("Everything again")
                            onClicked: dlg.fetchArtwork(true)
                        }
                        TextButton {
                            visible: !dlg.fetching && dlg.artAsk
                            label: Fili.tr("Cancel")
                            onClicked: dlg.artAsk = false
                        }
                        TextButton {
                            visible: dlg.fetching
                            label: Fili.tr("Cancel")
                            onClicked: dlg.cancelArtwork()
                        }
                        TextButton {
                            visible: !dlg.fetching && !dlg.artAsk && dlg.missing === null
                            label: Fili.tr("Albums without a cover")
                            onClicked: dlg.loadMissing()
                        }
                    }
                }
                // Covers not found
                Block {
                    id: missingBlock
                    visible: !dlg.welcome && dlg.missing !== null
                    Heading { text: dlg.missing ? (dlg.missing.length === 0 ? Fili.tr("Every album has a cover") : Fili.tr("%1 albums without a cover").replace("%1", dlg.missing.length)) : "" }
                    Rectangle {
                        visible: dlg.missing !== null && dlg.missing.length > 0
                        width: parent.width
                        height: Math.min(180, (dlg.missing ? dlg.missing.length : 0) * 22 + 2 * FiliTheme.space1)
                        radius: FiliTheme.radiusControl
                        color: FiliTheme.surface
                        clip: true
                        ListView {
                            id: missingList
                            anchors { fill: parent; margins: FiliTheme.space1 }
                            model: dlg.missing || []
                            boundsBehavior: Flickable.StopAtBounds
                            KineticScroll {}
                            delegate: Text {
                                required property var modelData
                                width: missingList.width - 12
                                height: 22
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                                text: modelData.text
                                font.family: FiliTheme.font
                                font.pixelSize: FiliTheme.sizeSmall
                                color: FiliTheme.textSecondary
                            }
                        }
                        FiliScrollBar { flick: missingList; anchors { top: missingList.top; bottom: missingList.bottom; right: missingList.right } }
                    }
                    Row {
                        spacing: FiliTheme.space2
                        TextButton {
                            visible: dlg.reportFile !== ""
                            label: Fili.tr("Open the last report")
                            onClicked: Fili.openPath(dlg.reportFile)
                        }
                        TextButton {
                            visible: !dlg.fetching && dlg.missing !== null && dlg.missing.length > 0
                            label: Fili.tr("Try the missing covers again")
                            primary: true
                            onClicked: dlg.fetchArtwork(false)
                        }
                        TextButton { label: Fili.tr("Refresh"); onClicked: dlg.loadMissing() }
                    }
                }
                // Cleanup
                Block {
                    visible: !dlg.welcome
                    Heading { text: Fili.tr("Clean up the library") }
                    Note { text: Fili.tr("Removes the albums and artists that no longer have any track.") }
                    Row {
                        spacing: FiliTheme.space3
                        TextButton {
                            id: cleanButton
                            label: Fili.tr("Clean up")
                            onClicked: {
                                const r = Store.call("clean_library");
                                if (r === null) {
                                    dlg.error = Store.lastError !== "" ? Store.lastError : Fili.tr("The cleanup failed");
                                    return;
                                }
                                dlg.cleanResult = r.albums_deleted + r.artists_deleted === 0 ? Fili.tr("The library is already clean") : Fili.tr("%1 albums and %2 artists removed").replace("%1", r.albums_deleted).replace("%2", r.artists_deleted);
                                Store.forget();
                                dlg.loadStats();
                            }
                        }
                        Note {
                            width: implicitWidth
                            anchors.verticalCenter: cleanButton.verticalCenter
                            visible: dlg.cleanResult !== ""
                            text: dlg.cleanResult
                        }
                    }
                }
                // Error
                Block {
                    visible: dlg.error !== ""
                    border.color: FiliTheme.danger
                    Heading { text: Fili.tr("Something went wrong"); color: FiliTheme.danger }
                    Note { text: dlg.error }
                    TextButton { label: Fili.tr("Dismiss"); onClicked: dlg.error = "" }
                }
                // Statistics
                Block {
                    visible: dlg.stats !== null && !dlg.welcome
                    Heading { text: Fili.tr("Library") }
                    Flow {
                        width: parent.width
                        spacing: FiliTheme.space4
                        Repeater {
                            model: dlg.stats ? [
                                { label: Fili.tr("Tracks"), value: dlg.stats.track_count },
                                { label: Fili.tr("Albums"), value: dlg.stats.album_count },
                                { label: Fili.tr("Artists"), value: dlg.stats.artist_count },
                                { label: Fili.tr("Total time"), value: Store.longDuration(dlg.stats.total_duration_seconds) },
                                { label: Fili.tr("Covers"), value: dlg.stats.artwork_count + "/" + dlg.stats.album_count }
                            ] : []
                            Column {
                                required property var modelData
                                Text { text: String(modelData.value); font.family: FiliTheme.font; font.pixelSize: FiliTheme.sizeTitle; font.weight: Font.Light; color: FiliTheme.text }
                                Text { text: modelData.label; font.family: FiliTheme.font; font.pixelSize: FiliTheme.sizeSmall; color: FiliTheme.textSecondary }
                            }
                        }
                    }
                }
            }
        }
        FiliScrollBar { flick: body; anchors { top: body.top; bottom: body.bottom; right: body.right } }

        // Action bar
        Item {
            id: actions
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: 52
            Rectangle { width: parent.width; height: FiliTheme.borderWidth; color: FiliTheme.border }
            Text {
                anchors { left: parent.left; leftMargin: FiliTheme.space4; right: scanButton.left; rightMargin: FiliTheme.space3; verticalCenter: parent.verticalCenter }
                elide: Text.ElideMiddle
                text: folder.text
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeSmall
                color: FiliTheme.textSecondary
            }
            TextButton {
                id: scanButton
                anchors { right: parent.right; rightMargin: FiliTheme.space4; verticalCenter: parent.verticalCenter }
                label: dlg.scanning ? Fili.tr("Scanning…") : Fili.tr("Scan")
                primary: true
                enabled: !dlg.scanning && folder.text.trim() !== ""
                onClicked: dlg.scan()
            }
        }
    }
}
