// Artists: a list on the left, the chosen artist on the right (photo, facts, biography, albums, play all).
import QtQuick
import Fili.Baladeur

Item {
    id: view
    signal albumMenu(var album, real x, real y)
    signal openAlbum(var album)

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
                MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; onClicked: view.choose(row.modelData) }
            }
        }
        FiliScrollBar { flick: list; anchors { top: list.top; bottom: list.bottom; right: list.right } }
    }

    // Detail
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
        Rectangle {
            id: head
            visible: view.chosen !== null
            width: parent.width
            height: 120 + 2 * FiliTheme.space4
            color: FiliTheme.background
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: FiliTheme.borderWidth; color: FiliTheme.border }
            Artwork {
                id: bigPhoto
                x: FiliTheme.margin
                y: FiliTheme.space4
                width: 120
                height: 120
                radius: 60
                kind: "artist"
                itemId: view.chosen ? view.chosen.id : -1
            }
            Column {
                anchors { left: bigPhoto.right; leftMargin: FiliTheme.space4; right: parent.right; rightMargin: FiliTheme.margin; top: bigPhoto.top }
                spacing: FiliTheme.space1
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: view.chosen ? view.chosen.name : ""
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeTitle + 6
                    font.weight: Font.Light
                    color: FiliTheme.text
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: view.chosen ? [view.chosen.genre, view.chosen.country, view.chosen.formed_year ? Fili.tr("Formed") + " " + view.chosen.formed_year : (view.chosen.born_year ? Fili.tr("Born") + " " + view.chosen.born_year : "")].filter(x => x).join(" · ") : ""
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeSmall
                    color: FiliTheme.muted
                }
                Text {
                    width: parent.width
                    maximumLineCount: 3
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    visible: text !== ""
                    text: view.chosen && view.chosen.bio ? view.chosen.bio : ""
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeSmall
                    color: FiliTheme.textSecondary
                }
                Row {
                    spacing: FiliTheme.space2
                    TextButton { label: Fili.tr("Play all"); primary: true; onClicked: view.playAll() }
                }
            }
        }
        ArtistStrip {
            id: similarStrip
            anchors.top: head.bottom
            width: parent.width
            title: Fili.tr("Similar artists")
            artists: view.chosen ? view.similar : []
            onOpened: artist => view.choose(artist)
        }
        AlbumGrid {
            anchors { top: similarStrip.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
            visible: view.chosen !== null
            albums: view.albums
            onOpened: album => view.openAlbum(album)
            onAlbumMenu: (album, x, y) => view.albumMenu(album, x, y)
        }
    }
}
