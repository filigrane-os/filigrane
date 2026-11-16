// Search results (full text): artists, albums and tracks of the library for what is typed in the header.
import QtQuick
import Fili.Baladeur

Item {
    id: view
    property string query: ""
    signal trackMenu(var ids, real x, real y)
    signal albumMenu(var album, real x, real y)
    signal openAlbum(var album)
    signal openArtist(var artist)

    property var result: ({ tracks: [], albums: [], artists: [] })
    property bool searched: false
    ListModel { id: tracks }
    property int serial: 0

    function run() {
        const mine = ++serial;
        if (query.trim() === "") {
            result = { tracks: [], albums: [], artists: [] };
            tracks.clear();
            searched = false;
            return;
        }
        Store.callAsync("search_tracks", [query, 100], d => {
            if (mine !== serial)
                return;
            searched = true;
            result = d || { tracks: [], albums: [], artists: [] };
            Store.fill(tracks, result.tracks, false);
        });
    }
    onQueryChanged: debounce.restart()
    Timer { id: debounce; interval: 200; onTriggered: view.run() }
    Component.onCompleted: run()

    readonly property bool empty: searched && result.tracks.length === 0 && result.albums.length === 0 && result.artists.length === 0

    Text {
        anchors.centerIn: parent
        visible: view.empty || !view.searched
        text: view.empty ? Fili.tr("No results") : Fili.tr("Type in the search field to search the library")
        font.family: FiliTheme.font
        font.pixelSize: FiliTheme.size
        color: FiliTheme.muted
    }
    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentHeight: content.height + FiliTheme.space4
        KineticScroll {}
        Column {
            id: content
            width: flick.width
            Item { width: 1; height: FiliTheme.space2 }
            // Artists
            Text {
                x: FiliTheme.margin
                visible: view.result.artists.length > 0
                height: visible ? implicitHeight + FiliTheme.space3 : 0
                text: Fili.tr("Artists")
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeSmall
                font.weight: FiliTheme.weightAccent
                color: FiliTheme.muted
            }
            Flow {
                x: FiliTheme.margin
                width: parent.width - 2 * FiliTheme.margin
                spacing: FiliTheme.space2
                Repeater {
                    model: view.result.artists
                    Rectangle {
                        id: chip
                        required property var modelData
                        width: chipRow.width + 2 * FiliTheme.space2
                        height: 36
                        radius: 18
                        color: chipArea.containsMouse ? FiliTheme.surfaceHover : FiliTheme.surface
                        border.width: FiliTheme.borderWidth
                        border.color: FiliTheme.border
                        Row {
                            id: chipRow
                            x: FiliTheme.space1
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: FiliTheme.space2
                            Artwork { width: 28; height: 28; radius: 14; kind: "artist"; itemId: chip.modelData.id }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: chip.modelData.name
                                font.family: FiliTheme.font
                                font.pixelSize: FiliTheme.sizeList
                                color: FiliTheme.text
                            }
                        }
                        MouseArea { id: chipArea; anchors.fill: parent; hoverEnabled: true; onClicked: view.openArtist(chip.modelData) }
                    }
                }
            }
            // Albums
            Text {
                x: FiliTheme.margin
                visible: view.result.albums.length > 0
                height: visible ? implicitHeight + FiliTheme.space3 : 0
                topPadding: FiliTheme.space3
                text: Fili.tr("Albums")
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeSmall
                font.weight: FiliTheme.weightAccent
                color: FiliTheme.muted
            }
            ListView {
                width: parent.width
                height: view.result.albums.length > 0 ? 150 + 44 + FiliTheme.space3 : 0
                visible: view.result.albums.length > 0
                orientation: ListView.Horizontal
                spacing: FiliTheme.space4
                leftMargin: FiliTheme.margin
                rightMargin: FiliTheme.margin
                clip: true
                model: view.result.albums
                delegate: AlbumCard {
                    required property var modelData
                    album: modelData
                    onOpened: view.openAlbum(modelData)
                    onMenuRequested: (x, y) => view.albumMenu(modelData, x, y)
                }
            }
            // Tracks
            Text {
                x: FiliTheme.margin
                visible: tracks.count > 0
                height: visible ? implicitHeight + FiliTheme.space3 : 0
                topPadding: FiliTheme.space3
                text: Fili.tr("Tracks")
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeSmall
                font.weight: FiliTheme.weightAccent
                color: FiliTheme.muted
            }
            TrackTable {
                id: table
                width: parent.width
                height: tracks.count > 0 ? (FiliTheme.rowHeight + FiliTheme.space1) + tracks.count * (FiliTheme.rowHeight + 4) : 0
                visible: tracks.count > 0
                model: tracks
                Component.onCompleted: list.interactive = false
                onActivated: (row, alt) => alt ? Store.addToQueue([tracks.get(row).id]) : Store.addAndPlay(tracks.get(row).id)
                onMenuRequested: (row, x, y) => view.trackMenu(selectedCount > 1 ? selectedIds() : [tracks.get(row).id], x, y)
            }
        }
    }
    FiliScrollBar { flick: flick; anchors { top: parent.top; bottom: parent.bottom; right: parent.right } }
}
