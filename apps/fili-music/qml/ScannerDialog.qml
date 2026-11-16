// Library scanner: a folder to scan with its progress, then the artwork fetch (online covers and photos), and library cleanup.
// Shown at the first launch (the library is empty) and from the sidebar.
import QtQuick
import Fili.Baladeur

Rectangle {
    id: dlg
    property bool scanning: false
    property bool fetching: false
    property var scanProgress: ({ total_files: 0, processed_files: 0, tracks_added: 0, current_file: "" })
    property var artProgress: ({ total_items: 0, processed_items: 0, current_item: "", successful: 0, failed: 0 })
    property string result: ""
    property bool welcome: false
    readonly property real scanFraction: scanProgress.total_files > 0 ? scanProgress.processed_files / scanProgress.total_files : 0
    readonly property real artFraction: artProgress.total_items > 0 ? artProgress.processed_items / artProgress.total_items : 0
    signal finished()

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
        visible = true;
    }
    // `fili-music ctl action scan PATH`: scan that folder now
    function scanPath(path) {
        open(false);
        folder.text = path;
        quiet = true;
        scan();
    }
    // Started from a command: the dialog goes away when the scan is over, the footer tells the result
    property bool quiet: false
    function close() {
        if (scanning)
            return;
        visible = false;
    }
    function scan() {
        const path = folder.text.trim();
        if (path === "" || scanning)
            return;
        Fili.setUiState("scan_dir", path);
        scanning = true;
        result = "";
        scanProgress = { total_files: 0, processed_files: 0, tracks_added: 0, current_file: "" };
        Store.callAsync("scan_library", [path], d => {
            scanning = false;
            welcome = false;
            if (d)
                result = Fili.tr("%1 added, %2 updated, %3 unchanged").replace("%1", d.tracks_added).replace("%2", d.tracks_updated).replace("%3", d.tracks_skipped);
            else
                result = Store.lastError !== "" ? Store.lastError : Fili.tr("The scan failed");
            Store.forget();
            if (quiet) {
                quiet = false;
                visible = false;
                Store.notice(result, d === null);
            }
            dlg.finished();
        });
    }
    function fetchArtwork() {
        if (fetching)
            return;
        fetching = true;
        artProgress = { total_items: 0, processed_items: 0, current_item: "", successful: 0, failed: 0 };
        Store.callAsync("fetch_all_artwork", [true, false], () => {
            fetching = false;
            Store.forget();
        });
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
                if (p)
                    dlg.artProgress = p;
            }
        }
    }
    MouseArea { anchors.fill: parent; onClicked: dlg.close() }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(520, parent.width - 2 * FiliTheme.margin)
        height: col.implicitHeight + 2 * FiliTheme.space6
        radius: FiliTheme.radiusWindow
        color: FiliTheme.surface
        border.width: FiliTheme.borderWidth
        border.color: FiliTheme.border
        MouseArea { anchors.fill: parent }
        Column {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: FiliTheme.space6 }
            spacing: FiliTheme.space3
            Text {
                width: parent.width
                text: dlg.welcome ? Fili.tr("Welcome to Baladeur") : Fili.tr("Scan the library")
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeTitle + 4
                font.weight: Font.Light
                color: FiliTheme.text
            }
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: dlg.welcome ? Fili.tr("Choose the folder that holds your music. Baladeur reads the tags of FLAC, MP3, AAC and ALAC files and builds the library; your files are never changed.") : Fili.tr("Folder to scan for music. Files already in the library are checked again, new ones are added.")
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.size
                color: FiliTheme.textSecondary
            }
            Rectangle {
                width: parent.width
                height: 28
                radius: FiliTheme.radiusControl
                color: FiliTheme.background
                border.width: FiliTheme.borderWidth
                border.color: folder.activeFocus ? FiliTheme.accentColor : FiliTheme.border
                TextInput {
                    id: folder
                    anchors { fill: parent; leftMargin: FiliTheme.space2; rightMargin: FiliTheme.space2 }
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    enabled: !dlg.scanning
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.size
                    color: FiliTheme.text
                    selectionColor: FiliTheme.surfaceActive
                    selectedTextColor: FiliTheme.text
                    Keys.onReturnPressed: dlg.scan()
                    Accessible.name: Fili.tr("Folder to scan")
                }
            }
            // Scan progress
            Column {
                width: parent.width
                visible: dlg.scanning
                spacing: FiliTheme.space1
                Rectangle {
                    width: parent.width
                    height: 4
                    radius: 2
                    color: FiliTheme.alpha(FiliTheme.muted, 0.35)
                    Rectangle { width: parent.width * dlg.scanFraction; height: parent.height; radius: 2; color: FiliTheme.accentColor }
                }
                Text {
                    width: parent.width
                    elide: Text.ElideMiddle
                    text: dlg.scanProgress.processed_files + " / " + dlg.scanProgress.total_files + (dlg.scanProgress.current_file ? "  ·  " + dlg.scanProgress.current_file : "")
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeSmall
                    color: FiliTheme.textSecondary
                }
            }
            Text {
                width: parent.width
                visible: dlg.result !== "" && !dlg.scanning
                wrapMode: Text.Wrap
                text: dlg.result
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.size
                color: FiliTheme.text
            }
            // Artwork
            Column {
                width: parent.width
                visible: dlg.fetching
                spacing: FiliTheme.space1
                Rectangle {
                    width: parent.width
                    height: 4
                    radius: 2
                    color: FiliTheme.alpha(FiliTheme.muted, 0.35)
                    Rectangle { width: parent.width * dlg.artFraction; height: parent.height; radius: 2; color: FiliTheme.accentColor }
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: Fili.tr("Artwork") + " " + dlg.artProgress.processed_items + " / " + dlg.artProgress.total_items + (dlg.artProgress.current_item ? "  ·  " + dlg.artProgress.current_item : "")
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeSmall
                    color: FiliTheme.textSecondary
                }
            }
            Row {
                anchors.right: parent.right
                spacing: FiliTheme.space2
                TextButton {
                    visible: !dlg.welcome
                    label: Fili.tr("Fetch artwork")
                    onClicked: dlg.fetchArtwork()
                }
                TextButton {
                    visible: !dlg.welcome
                    label: Fili.tr("Clean up")
                    onClicked: {
                        const r = Store.call("clean_library");
                        dlg.result = r ? Fili.tr("%1 albums and %2 artists removed").replace("%1", r.albums_deleted).replace("%2", r.artists_deleted) : Fili.tr("Nothing to clean");
                        Store.forget();
                    }
                }
                TextButton { label: dlg.welcome ? Fili.tr("Later") : Fili.tr("Close"); onClicked: dlg.close() }
                TextButton { label: dlg.scanning ? Fili.tr("Scanning…") : Fili.tr("Scan"); primary: true; onClicked: dlg.scan() }
            }
        }
    }
}
