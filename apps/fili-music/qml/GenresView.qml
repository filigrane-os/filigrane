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
    property string query: ""
    readonly property var shown: query === "" ? genres : genres.filter(g => g.name.toLowerCase().includes(query))

    function reload() {
        Store.callAsync("get_genres", [], d => genres = d ? d.genres : []);
    }
    function choose(genre) {
        chosen = genre;
        albums = [];
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
        readonly property int cols: Math.max(1, Math.floor((width - 2 * FiliTheme.margin + FiliTheme.space4) / 196))
        cellWidth: Math.floor((width - 2 * FiliTheme.margin + FiliTheme.space4) / cols)
        cellHeight: 150 + FiliTheme.space4
        leftMargin: FiliTheme.margin
        topMargin: FiliTheme.space4
        KineticScroll {}
        delegate: Item {
            id: cell
            required property var modelData
            width: gv.cellWidth
            height: gv.cellHeight
            Rectangle {
                width: gv.cellWidth - FiliTheme.space4
                height: 138
                radius: FiliTheme.radiusControl + 2
                color: FiliTheme.surface
                border.width: cardArea.containsMouse ? 2 : FiliTheme.borderWidth
                border.color: cardArea.containsMouse ? FiliTheme.accentColor : FiliTheme.border
                clip: true
                // Up to four covers of the genre as a mosaic
                Grid {
                    anchors.fill: parent
                    columns: 2
                    Repeater {
                        model: (cell.modelData.album_ids || []).slice(0, 4)
                        Artwork {
                            required property int modelData
                            width: parent.width / 2
                            height: parent.height / 2
                            radius: 0
                            itemId: modelData
                        }
                    }
                }
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 44
                    color: FiliTheme.alpha(FiliTheme.background, 0.85)
                    Column {
                        anchors { left: parent.left; leftMargin: FiliTheme.space3; right: parent.right; rightMargin: FiliTheme.space3; verticalCenter: parent.verticalCenter }
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
                            text: (cell.modelData.album_count || 0) + " " + Fili.tr("albums") + " · " + (cell.modelData.track_count || 0) + " " + Fili.tr("tracks")
                            font.family: FiliTheme.font
                            font.pixelSize: FiliTheme.sizeSmall
                            color: FiliTheme.textSecondary
                        }
                    }
                }
                MouseArea { id: cardArea; anchors.fill: parent; hoverEnabled: true; onClicked: view.choose(cell.modelData) }
            }
        }
    }
    FiliScrollBar { flick: gv; visible: gv.visible; anchors { top: gv.top; bottom: gv.bottom; right: gv.right } }

    // One genre
    Item {
        anchors.fill: parent
        visible: view.chosen !== null
        Rectangle {
            id: head
            width: parent.width
            height: 76
            color: FiliTheme.background
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: FiliTheme.borderWidth; color: FiliTheme.border }
            Text {
                x: FiliTheme.margin
                y: FiliTheme.space3
                text: "‹ " + Fili.tr("Genres")
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeSmall
                color: backArea.containsMouse ? FiliTheme.text : FiliTheme.muted
                MouseArea { id: backArea; anchors { fill: parent; margins: -4 } hoverEnabled: true; onClicked: view.chosen = null }
            }
            Text {
                x: FiliTheme.margin
                y: FiliTheme.space3 + 18
                text: view.chosen ? view.chosen.name : ""
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeTitle + 4
                font.weight: Font.Light
                color: FiliTheme.text
            }
            TextButton {
                anchors { right: parent.right; rightMargin: FiliTheme.margin; verticalCenter: parent.verticalCenter }
                label: Fili.tr("Play all")
                primary: true
                onClicked: view.playAll()
            }
        }
        AlbumGrid {
            anchors { top: head.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
            albums: view.albums
            onOpened: album => view.openAlbum(album)
            onAlbumMenu: (album, x, y) => view.albumMenu(album, x, y)
        }
    }
}
