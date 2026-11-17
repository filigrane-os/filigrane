// Genres as cards (a mosaic of covers of the genre, its name and counts); a genre opens its albums and can be played.
import QtQuick
import Fili.Baladeur

Item {
    id: view
    signal albumMenu(var album, real x, real y)
    signal openAlbum(var album)

    property var genres: []
    property var chosen: null
    property var albums: []
    property var artists: []
    property string query: ""
    readonly property var shown: query === "" ? genres : genres.filter(g => g.name.toLowerCase().includes(query))

    function reload() {
        Store.callAsync("get_genres", [], d => genres = d ? d.genres : []);
    }
    function choose(genre) {
        chosen = genre;
        albums = [];
        artists = [];
        Store.callAsync("get_genre_artists", [genre.id], d => {
            if (chosen && chosen.id === genre.id)
                artists = d ? d.artists : [];
        });
        Store.callAsync("get_genre_albums", [genre.id], d => {
            if (chosen && chosen.id === genre.id)
                albums = d ? d.albums : [];
        });
    }
    function playAll() {
        if (!chosen)
            return;
        Store.callAsync("get_genre_tracks", [chosen.id], d => Store.playNow(d ? d.tracks.map(t => t.id) : [], 0));
    }
    Component.onCompleted: reload()
    Connections {
        target: Store
        function onLibraryRevChanged() {
            view.reload();
        }
    }

    FilterBar {
        id: filter
        visible: view.chosen === null
        width: parent.width
        height: visible ? 36 : 0
        placeholder: Fili.tr("Filter genres")
        onTextChanged: view.query = text.toLowerCase()
    }
    GridView {
        id: gv
        anchors { top: filter.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        visible: view.chosen === null
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: view.shown
        readonly property int cols: Math.max(1, Math.floor((width - 2 * FiliTheme.margin + FiliTheme.space4) / (150 + FiliTheme.space4)))
        cellWidth: Math.floor((width - 2 * FiliTheme.margin + FiliTheme.space4) / cols)
        cellHeight: 150 + 44 + FiliTheme.space4
        leftMargin: FiliTheme.margin
        topMargin: FiliTheme.space4
        KineticScroll {}
        delegate: Item {
            id: cell
            required property var modelData
            width: gv.cellWidth
            height: gv.cellHeight
            // The mosaic of up to four covers of the genre, then its name and counts under it
            Rectangle {
                id: mosaic
                width: 150
                height: 150
                radius: FiliTheme.radiusControl + 2
                color: FiliTheme.surface
                border.width: cardArea.containsMouse ? 2 : 0
                border.color: FiliTheme.accentColor
                clip: true
                Text {
                    anchors.centerIn: parent
                    visible: !cell.modelData.album_ids || cell.modelData.album_ids.length === 0
                    text: "\u266b"
                    font.family: FiliTheme.font
                    font.pixelSize: 56
                    color: FiliTheme.muted
                }
                Grid {
                    anchors.fill: parent
                    columns: cell.modelData.album_ids && cell.modelData.album_ids.length > 1 ? 2 : 1
                    Repeater {
                        model: (cell.modelData.album_ids || []).slice(0, 4)
                        Artwork {
                            required property int modelData
                            readonly property int shown: Math.min(4, cell.modelData.album_ids.length)
                            width: shown === 1 ? 150 : 75
                            height: shown === 1 ? 150 : (shown === 2 ? 150 : 75)
                            radius: 0
                            itemId: modelData
                        }
                    }
                }
                DragArea {
                    id: cardArea
                    anchors.fill: parent
                    label: cell.modelData.name
                    payload: ({ genreId: cell.modelData.id })
                    onActivated: view.choose(cell.modelData)
                }
            }
            Column {
                anchors { top: mosaic.bottom; topMargin: FiliTheme.space2; left: mosaic.left; right: mosaic.right }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: cell.modelData.name
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.size
                    font.weight: FiliTheme.weightAccent
                    color: FiliTheme.text
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: (cell.modelData.track_count || 0) + " " + Fili.tr("tracks")
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeSmall
                    color: FiliTheme.textSecondary
                }
            }
        }
    }
    FiliScrollBar { flick: gv; visible: gv.visible; anchors { top: gv.top; bottom: gv.bottom; right: gv.right } }

    // One genre: its artists and its albums on one scrolled page
    Item {
        anchors.fill: parent
        visible: view.chosen !== null
        Rectangle {
            id: head
            width: parent.width
            height: 40
            color: FiliTheme.background
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: FiliTheme.borderWidth; color: FiliTheme.border }
            Text {
                x: FiliTheme.margin
                anchors.verticalCenter: parent.verticalCenter
                text: "‹ " + Fili.tr("Genres")
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeSmall
                color: backArea.containsMouse ? FiliTheme.text : FiliTheme.muted
                MouseArea { id: backArea; anchors { fill: parent; margins: -4 } hoverEnabled: true; onClicked: view.chosen = null }
            }
        }
        AlbumGrid {
            id: albumGrid
            anchors { top: head.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
            albums: view.albums
            onOpened: album => view.openAlbum(album)
            onAlbumMenu: (album, x, y) => view.albumMenu(album, x, y)
            header: Item {
                id: top
                width: albumGrid.width - 2 * FiliTheme.margin
                height: col.implicitHeight + FiliTheme.space4
                AmbientColor {
                    id: ambient
                    source: view.chosen && view.chosen.album_ids && view.chosen.album_ids.length > 0 ? Store.cover("album", view.chosen.album_ids[0]) : ""
                }
                Rectangle {
                    x: -FiliTheme.margin
                    width: albumGrid.width
                    height: parent.height
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0; color: FiliTheme.alpha(ambient.color, 0.30) }
                        GradientStop { position: 1; color: FiliTheme.alpha(ambient.color, 0) }
                    }
                    opacity: ambient.color.a > 0 ? 1 : 0
                }
                Column {
                    id: col
                    width: parent.width
                    topPadding: FiliTheme.space4
                    spacing: FiliTheme.space4
                    Row {
                        spacing: FiliTheme.space4
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\u266b"
                            font.family: FiliTheme.font
                            font.pixelSize: 72
                            color: FiliTheme.muted
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: FiliTheme.space2
                            Text {
                                text: view.chosen ? view.chosen.name : ""
                                font.family: FiliTheme.font
                                font.pixelSize: FiliTheme.sizeTitle + 10
                                font.weight: Font.Light
                                color: FiliTheme.text
                            }
                            Text {
                                text: view.chosen ? (view.chosen.track_count || 0) + " " + Fili.tr("tracks") + " · " + (view.chosen.album_count || 0) + " " + Fili.tr("albums") : ""
                                font.family: FiliTheme.font
                                font.pixelSize: FiliTheme.size
                                color: FiliTheme.textSecondary
                            }
                            TextButton { label: Fili.tr("Play all"); primary: true; onClicked: view.playAll() }
                        }
                    }
                    Column {
                        width: parent.width
                        spacing: FiliTheme.space3
                        visible: view.artists.length > 0
                        Text {
                            text: Fili.tr("Artists of this genre")
                            font.family: FiliTheme.font
                            font.pixelSize: FiliTheme.size
                            font.weight: FiliTheme.weightAccent
                            color: FiliTheme.text
                        }
                        Flow {
                            width: parent.width
                            spacing: FiliTheme.space4
                            Repeater {
                                model: view.artists
                                Item {
                                    id: chip
                                    required property var modelData
                                    width: 100
                                    height: 140
                                    Artwork {
                                        id: photo
                                        width: 100
                                        height: 100
                                        radius: 50
                                        kind: "artist"
                                        itemId: chip.modelData.id
                                        border.width: chipArea.containsMouse ? 2 : 0
                                        border.color: FiliTheme.accentColor
                                    }
                                    Text {
                                        anchors { top: photo.bottom; topMargin: FiliTheme.space1; left: parent.left; right: parent.right }
                                        horizontalAlignment: Text.AlignHCenter
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                        text: chip.modelData.name
                                        font.family: FiliTheme.font
                                        font.pixelSize: FiliTheme.sizeSmall
                                        color: FiliTheme.text
                                    }
                                    MouseArea { id: chipArea; anchors.fill: parent; hoverEnabled: true; onClicked: Store.artistRequested(chip.modelData.id) }
                                }
                            }
                        }
                    }
                    Text {
                        visible: view.albums.length > 0
                        text: Fili.tr("Albums")
                        font.family: FiliTheme.font
                        font.pixelSize: FiliTheme.size
                        font.weight: FiliTheme.weightAccent
                        color: FiliTheme.text
                    }
                }
            }
        }
    }
}
