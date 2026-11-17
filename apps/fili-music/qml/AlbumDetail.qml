// One album, laid out like the macOS app: the title and the tracks (one column, or two when there is room) on the left, the cover
// and the facts (artist, year, genres, folder, type, status, label, country, description) on the right; under them three carousels:
// the other albums of the artist, the artists who also appear on the album, and the artists of the same genre.
// `back` returns to the grid; the artist name opens the artist.
import QtQuick
import Fili.Baladeur

Item {
    id: detail
    required property var album
    signal back()
    signal trackMenu(var ids, real x, real y)

    ListModel { id: tracks }
    property real totalMs: 0
    property var genres: []
    property var featuring: []
    property var sameGenre: []
    property var byArtist: []
    property string folder: ""
    property int serial: 0

    function reload() {
        const mine = ++serial;
        const a = album;
        featuring = [];
        sameGenre = [];
        byArtist = [];
        genres = [];
        Store.callAsync("get_album_featuring_artists", [a.id, a.artist_id], d => {
            if (mine === serial)
                featuring = d ? d.artists : [];
        });
        Store.callAsync("get_similar_artists", [a.artist_id], d => {
            if (mine === serial)
                sameGenre = d ? d.artists.filter(x => x.id !== a.artist_id) : [];
        });
        Store.callAsync("get_artist_albums", [a.artist_id], d => {
            if (mine === serial)
                byArtist = d ? d.albums.filter(x => x.id !== a.id) : [];
        });
        Store.callAsync("get_album_genres", [a.id], d => {
            if (mine === serial)
                genres = d ? d.genres : [];
        });
        Store.callAsync("get_album_tracks", [a.id], d => {
            if (mine !== serial)
                return;
            Store.fill(tracks, d ? d.tracks : [], false);
            let ms = 0;
            for (let i = 0; i < tracks.count; i++)
                ms += tracks.get(i).duration;
            totalMs = ms;
            const p = tracks.count > 0 ? tracks.get(0).path : "";
            folder = p.lastIndexOf("/") > 0 ? p.substring(0, p.lastIndexOf("/")) : "";
        });
    }
    onAlbumChanged: reload()
    Component.onCompleted: reload()
    Connections {
        target: Store
        function onLibraryRevChanged() {
            detail.reload();
        }
    }

    // Ambient colour of the cover: a wash fading into the background
    AmbientColor {
        id: ambient
        source: art.source
    }
    Rectangle {
        width: parent.width
        height: Math.min(parent.height, 420)
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0; color: FiliTheme.alpha(ambient.color, 0.34) }
            GradientStop { position: 1; color: FiliTheme.alpha(ambient.color, 0) }
        }
        opacity: ambient.color.a > 0 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 250 } }
    }

    Flickable {
        id: page
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.height + 2 * FiliTheme.space6
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        KineticScroll {}

        Item {
            id: content
            x: FiliTheme.margin
            y: FiliTheme.space4
            width: page.width - 2 * FiliTheme.margin - 10
            height: carousels.y + carousels.height

            readonly property real side: Math.max(180, Math.min(320, Math.round(width * 0.3)))
            readonly property real main: width - side - FiliTheme.space6

            // Left: the title and the tracks
            Column {
                id: leftCol
                width: content.main
                spacing: FiliTheme.space4
                Text {
                    text: "‹ " + Fili.tr("Albums")
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeSmall
                    color: backArea.containsMouse ? FiliTheme.text : FiliTheme.muted
                    MouseArea { id: backArea; anchors { fill: parent; margins: -4 } hoverEnabled: true; onClicked: detail.back() }
                }
                Column {
                    width: parent.width
                    spacing: FiliTheme.space2
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: detail.album.title
                        font.family: FiliTheme.font
                        font.pixelSize: FiliTheme.sizeTitle + 10
                        font.weight: Font.Light
                        color: FiliTheme.text
                    }
                    Text {
                        text: Fili.tr("by %1").replace("%1", detail.album.artist_name)
                        font.family: FiliTheme.font
                        font.pixelSize: FiliTheme.sizeTitle - 2
                        color: artistArea.containsMouse ? FiliTheme.accentColor : FiliTheme.textSecondary
                        MouseArea { id: artistArea; anchors.fill: parent; hoverEnabled: true; onClicked: Store.artistRequested(detail.album.artist_id) }
                    }
                    Text {
                        text: [tracks.count + " " + Fili.tr("tracks"), Store.longDuration(detail.totalMs / 1000)].join(" · ")
                        font.family: FiliTheme.font
                        font.pixelSize: FiliTheme.sizeSmall
                        color: FiliTheme.muted
                    }
                }
                Row {
                    spacing: FiliTheme.space2
                    TextButton { label: Fili.tr("Play"); primary: true; onClicked: Store.playNow(Store.ids(tracks), 0) }
                    TextButton { label: Fili.tr("Add to queue"); onClicked: Store.addToQueue(Store.ids(tracks)) }
                    TextButton { label: Fili.tr("Edit metadata…"); onClicked: Store.tagEditorRequested("album", [detail.album.id]) }
                }
                TrackColumns {
                    id: table
                    width: parent.width
                    model: tracks
                    onActivated: (row, alt) => alt ? Store.addToQueue([tracks.get(row).id]) : Store.playNow(Store.ids(tracks), row)
                    onMenuRequested: (row, x, y) => detail.trackMenu(selectedCount > 1 ? selectedIds() : [tracks.get(row).id], x, y)
                }
            }

            // Right: the cover and the facts
            Column {
                id: rightCol
                x: content.main + FiliTheme.space6
                width: content.side
                spacing: FiliTheme.space4
                Artwork {
                    id: art
                    width: parent.width
                    height: width
                    radius: FiliTheme.radiusWindow
                    itemId: detail.album.id
                }
                Column {
                    width: parent.width
                    spacing: FiliTheme.space2
                    Text {
                        text: Fili.tr("About this album")
                        font.family: FiliTheme.font
                        font.pixelSize: FiliTheme.size
                        font.weight: FiliTheme.weightAccent
                        color: FiliTheme.text
                    }
                    Repeater {
                        model: [
                            { k: Fili.tr("Artist"), v: detail.album.artist_name },
                            { k: Fili.tr("Year"), v: detail.album.year ? String(detail.album.year) : "" },
                            { k: Fili.tr("Tracks"), v: String(tracks.count) },
                            { k: Fili.tr("Genre"), v: detail.genres.map(g => g.name).join(", ") },
                            { k: Fili.tr("Folder"), v: detail.folder },
                            { k: Fili.tr("Type"), v: detail.album.album_type || "" },
                            { k: Fili.tr("Status"), v: detail.album.release_status || "" },
                            { k: Fili.tr("Label"), v: detail.album.label || "" },
                            { k: Fili.tr("Country"), v: detail.album.country || "" }
                        ].filter(r => r.v !== "")
                        Row {
                            id: fact
                            required property var modelData
                            width: rightCol.width
                            spacing: FiliTheme.space2
                            Text {
                                width: 56
                                text: fact.modelData.k
                                font.family: FiliTheme.font
                                font.pixelSize: FiliTheme.sizeSmall
                                color: FiliTheme.muted
                            }
                            Text {
                                width: fact.width - 56 - FiliTheme.space2
                                wrapMode: Text.WrapAnywhere
                                text: fact.modelData.v
                                font.family: FiliTheme.font
                                font.pixelSize: FiliTheme.sizeSmall
                                color: FiliTheme.textSecondary
                            }
                        }
                    }
                    Rectangle {
                        visible: desc.visible
                        width: parent.width
                        height: FiliTheme.borderWidth
                        color: FiliTheme.border
                    }
                    ExpandableText {
                        id: desc
                        width: parent.width
                        visible: text !== ""
                        text: detail.album.description || ""
                    }
                }
            }

            // Under both columns: the carousels
            Column {
                id: carousels
                y: Math.max(leftCol.height, rightCol.height) + FiliTheme.space6
                width: parent.width
                spacing: FiliTheme.space5
                Carousel {
                    title: Fili.tr("Albums")
                    subtitle: Fili.tr("by this artist")
                    items: detail.byArtist
                    cardHeight: 160
                    card: Item {
                        id: albumCard
                        required property var modelData
                        width: 120
                        height: 160
                        Artwork {
                            id: cover
                            width: 120
                            height: 120
                            itemId: albumCard.modelData.id
                            border.width: albumArea.containsMouse ? 2 : 0
                            border.color: FiliTheme.accentColor
                        }
                        Text {
                            anchors { top: cover.bottom; topMargin: FiliTheme.space1; left: parent.left; right: parent.right }
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            text: albumCard.modelData.title
                            font.family: FiliTheme.font
                            font.pixelSize: FiliTheme.sizeSmall
                            color: FiliTheme.text
                        }
                        MouseArea { id: albumArea; anchors.fill: parent; hoverEnabled: true; onClicked: Store.albumRequested(albumCard.modelData.id) }
                        Accessible.role: Accessible.Button
                        Accessible.name: albumCard.modelData.title
                    }
                }
                Carousel {
                    title: Fili.tr("Also featuring")
                    items: detail.featuring
                    pageSize: 5
                    cardHeight: 156
                    card: artistCard
                }
                Carousel {
                    title: Fili.tr("Similar artists")
                    subtitle: Fili.tr("same genre")
                    items: detail.sameGenre
                    pageSize: 5
                    cardHeight: 156
                    card: artistCard
                }
            }
        }
    }
    FiliScrollBar { flick: page; anchors { top: page.top; bottom: page.bottom; right: page.right } }

    Component {
        id: artistCard
        Item {
            id: chip
            required property var modelData
            width: 120
            height: 156
            Artwork {
                id: photo
                width: 120
                height: 120
                radius: 60
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
            Accessible.role: Accessible.Button
            Accessible.name: chip.modelData.name
        }
    }
}
