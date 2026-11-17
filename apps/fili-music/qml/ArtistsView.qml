// Artists: a list on the left, the chosen artist on the right (photo, facts, biography, albums, play all).
import QtQuick
import Fili.Baladeur

Item {
    id: view
    signal albumMenu(var album, real x, real y)
    signal openAlbum(var album)
    signal trackMenu(var ids, real x, real y)

    property var artists: []
    property var chosen: null
    property var albums: []
    property var similar: []
    property bool busy: false
    property bool exhausted: false
    property int serial: 0
    property string query: ""
    readonly property var shown: query === "" ? artists : artists.filter(a => a.name.toLowerCase().includes(query))

    function load(more) {
        if (busy || (more && exhausted))
            return;
        const mine = ++serial;
        busy = true;
        Store.callAsync("get_artists_page", [more ? artists.length : 0, 100], d => {
            if (mine !== serial)
                return;
            busy = false;
            const page = d ? d.artists : [];
            exhausted = page.length < 100;
            artists = more ? artists.concat(page) : page;
        });
    }
    function choose(artist) {
        chosen = artist;
        albums = [];
        similar = [];
        view.loadSingles(artist);
        Store.callAsync("get_similar_artists", [artist.id], d => {
            if (chosen && chosen.id === artist.id)
                similar = d ? d.artists.slice(0, 20) : [];
        });
        Store.callAsync("get_artist_albums", [artist.id], d => {
            if (chosen && chosen.id === artist.id)
                albums = d ? d.albums : [];
        });
    }
    function chooseById(id) {
        Store.callAsync("get_artist_by_id", [id], a => {
            if (a)
                view.choose(a);
        });
    }
    function playAll() {
        if (!chosen)
            return;
        // Tracks of every album of the artist, in album order
        let left = albums.length;
        if (left === 0)
            return;
        const parts = new Array(left);
        albums.forEach((al, i) => Store.callAsync("get_album_tracks", [al.id], d => {
            parts[i] = d ? d.tracks.map(t => t.id) : [];
            if (--left === 0)
                Store.playNow([].concat(...parts), 0);
        }));
    }
    Component.onCompleted: {
        load(false);
        if (Store.pendingArtistId >= 0) {
            chooseById(Store.pendingArtistId);
            Store.pendingArtistId = -1;
        }
    }
    onChosenChanged: Store.detailChanged("artists", chosen ? chosen.id : -1)
    Connections {
        target: Store
        function onCloseDetails(kind) {
            if (kind === "artists") {
                view.chosen = null;
                view.albums = [];
            }
        }
        function onArtistRequested(id) {
            view.chooseById(id);
            Store.pendingArtistId = -1;
        }
        function onLibraryRevChanged() {
            view.serial++;
            view.busy = false;
            view.exhausted = false;
            view.load(false);
        }
    }

    // List
    Rectangle {
        id: left
        width: 280
        height: parent.height
        color: FiliTheme.background
        Rectangle {
            anchors.right: parent.right
            width: FiliTheme.borderWidth
            height: parent.height
            color: FiliTheme.border
        }
        FilterBar {
            id: filter
            width: parent.width - FiliTheme.borderWidth
            placeholder: Fili.tr("Filter artists")
            onTextChanged: view.query = text.toLowerCase()
        }
        ListView {
            id: list
            anchors { top: filter.bottom; bottom: parent.bottom; left: parent.left; right: parent.right; rightMargin: FiliTheme.borderWidth }
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: view.shown
            KineticScroll {}
            onAtYEndChanged: if (atYEnd && count > 0 && view.query === "")
                view.load(true)
            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property bool sel: view.chosen !== null && view.chosen.id === modelData.id
                width: list.width
                height: 44
                color: sel ? FiliTheme.surfaceHover : rowArea.containsMouse ? FiliTheme.alpha(FiliTheme.surfaceHover, 0.5) : "transparent"
                Artwork {
                    id: photo
                    x: FiliTheme.margin
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32
                    height: 32
                    radius: 16
                    kind: "artist"
                    itemId: row.modelData.id
                }
                Text {
                    anchors { left: photo.right; leftMargin: FiliTheme.space3; right: parent.right; rightMargin: FiliTheme.space3; verticalCenter: parent.verticalCenter }
                    elide: Text.ElideRight
                    text: row.modelData.name
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.size
                    font.weight: row.sel ? FiliTheme.weightAccent : Font.Normal
                    color: FiliTheme.text
                }
                DragArea {
                    id: rowArea
                    anchors.fill: parent
                    label: row.modelData.name
                    payload: ({ artistId: row.modelData.id })
                    onActivated: view.choose(row.modelData)
                }
            }
        }
        FiliScrollBar { flick: list; anchors { top: list.top; bottom: list.bottom; right: list.right } }
    }

    // Detail: the page of the artist is the grid of its albums with the header (photo, facts, biography, similar artists) above
    // and the tracks without an album below, all scrolled together
    property var singles: []
    property int singlesSerial: 0
    ListModel { id: singleTracks }
    function loadSingles(artist) {
        const mine = ++singlesSerial;
        singleTracks.clear();
        Store.artistSingles(artist.id, found => {
            if (mine === singlesSerial)
                Store.fill(singleTracks, found, false);
        });
    }
    Item {
        anchors { left: left.right; right: parent.right; top: parent.top; bottom: parent.bottom }
        Text {
            anchors.centerIn: parent
            visible: view.chosen === null
            text: Fili.tr("Choose an artist")
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.size
            color: FiliTheme.muted
        }
        AlbumGrid {
            id: albumGrid
            anchors.fill: parent
            visible: view.chosen !== null
            albums: view.albums.slice().sort((a, b) => (b.year || 0) - (a.year || 0))
            onOpened: album => view.openAlbum(album)
            onAlbumMenu: (album, x, y) => view.albumMenu(album, x, y)
            header: Item {
                id: top
                width: albumGrid.width - 2 * FiliTheme.margin
                height: topColumn.implicitHeight + FiliTheme.space4
                AmbientColor { id: ambient; source: bigPhoto.source }
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
                    id: topColumn
                    width: parent.width
                    topPadding: FiliTheme.space4
                    spacing: FiliTheme.space4
                    Row {
                        spacing: FiliTheme.space4
                        Artwork {
                            id: bigPhoto
                            width: 120
                            height: 120
                            radius: 60
                            kind: "artist"
                            itemId: view.chosen ? view.chosen.id : -1
                        }
                        Column {
                            width: top.width - 120 - FiliTheme.space4
                            anchors.verticalCenter: bigPhoto.verticalCenter
                            spacing: FiliTheme.space1
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: view.chosen ? view.chosen.name : ""
                                font.family: FiliTheme.font
                                font.pixelSize: FiliTheme.sizeTitle + 10
                                font.weight: Font.Light
                                color: FiliTheme.text
                            }
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                visible: text !== ""
                                text: view.chosen ? [view.chosen.country, view.chosen.genre, view.chosen.formed_year ? Fili.tr("Formed in %1").replace("%1", view.chosen.formed_year) : (view.chosen.born_year ? Fili.tr("Born in %1").replace("%1", view.chosen.born_year) : "")].filter(x => x).join(" · ") : ""
                                font.family: FiliTheme.font
                                font.pixelSize: FiliTheme.size
                                color: FiliTheme.textSecondary
                            }
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                visible: text !== ""
                                text: view.chosen ? [view.chosen.style, view.chosen.mood].filter(x => x).join(" · ") : ""
                                font.family: FiliTheme.font
                                font.pixelSize: FiliTheme.sizeSmall
                                color: FiliTheme.muted
                            }
                            Item { width: 1; height: FiliTheme.space1 }
                            Row {
                                spacing: FiliTheme.space2
                                TextButton { label: Fili.tr("Play all"); primary: true; onClicked: view.playAll() }
                            }
                        }
                    }
                    Column {
                        width: parent.width
                        spacing: FiliTheme.space2
                        visible: view.chosen !== null && !!view.chosen.bio
                        Text {
                            text: Fili.tr("About")
                            font.family: FiliTheme.font
                            font.pixelSize: FiliTheme.size
                            font.weight: FiliTheme.weightAccent
                            color: FiliTheme.text
                        }
                        ExpandableText {
                            width: Math.min(parent.width, 760)
                            text: view.chosen && view.chosen.bio ? view.chosen.bio : ""
                            pixelSize: FiliTheme.size
                        }
                    }
                    Carousel {
                        title: Fili.tr("Similar artists")
                        items: view.chosen ? view.similar : []
                        pageSize: 5
                        cardHeight: 156
                        card: Item {
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
                            MouseArea { id: chipArea; anchors.fill: parent; hoverEnabled: true; onClicked: view.choose(chip.modelData) }
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
            footer: Column {
                width: albumGrid.width - 2 * FiliTheme.margin
                spacing: FiliTheme.space2
                visible: singleTracks.count > 0
                height: visible ? implicitHeight + FiliTheme.space4 : 0
                Text {
                    topPadding: FiliTheme.space2
                    text: Fili.tr("Singles")
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.size
                    font.weight: FiliTheme.weightAccent
                    color: FiliTheme.text
                }
                TrackColumns {
                    id: singlesTable
                    width: parent.width
                    model: singleTracks
                    threshold: 100000
                    onActivated: (row, alt) => Store.wantsPlay(alt) ? Store.playNow(Store.ids(singleTracks), row) : Store.addToQueue([singleTracks.get(row).id])
                    onMenuRequested: (row, x, y) => view.trackMenu(selectedCount > 1 ? selectedIds() : [singleTracks.get(row).id], x, y)
                }
            }
        }
    }
}
