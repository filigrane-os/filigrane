// The albums of the library as a grid of covers; an album opens its page. Pages of 60 as the grid is scrolled.
import QtQuick
import Fili.Baladeur

Item {
    id: view
    signal trackMenu(var ids, real x, real y)
    signal albumMenu(var album, real x, real y)

    property var albums: []
    property var opened: null
    property bool busy: false
    property bool exhausted: false
    property int serial: 0
    property string query: ""

    function load(more) {
        if (busy || (more && exhausted))
            return;
        const mine = ++serial;
        busy = true;
        const offset = more ? albums.length : 0;
        Store.callAsync("get_albums_page", [offset, 60], d => {
            if (mine !== serial)
                return;
            busy = false;
            const page = d ? d.albums : [];
            exhausted = page.length < 60;
            albums = more ? albums.concat(page) : page;
        });
    }
    function reset() {
        serial++;
        busy = false;
        exhausted = false;
        load(false);
    }
    function openById(id) {
        Store.callAsync("get_album_by_id", [id], a => {
            if (a)
                view.opened = a;
        });
    }
    readonly property var shown: query === "" ? albums : albums.filter(a => a.title.toLowerCase().includes(query) || a.artist_name.toLowerCase().includes(query))

    Component.onCompleted: {
        reset();
        if (Store.pendingAlbumId >= 0) {
            openById(Store.pendingAlbumId);
            Store.pendingAlbumId = -1;
        }
    }
    onOpenedChanged: Store.detailChanged("albums", opened ? opened.id : -1)
    Connections {
        target: Store
        function onCloseDetails(kind) {
            if (kind === "albums")
                view.opened = null;
        }
        function onAlbumRequested(id) {
            view.openById(id);
            Store.pendingAlbumId = -1;
        }
        function onLibraryRevChanged() {
            view.reset();
        }
    }

    FilterBar {
        id: filter
        visible: view.opened === null
        width: parent.width
        height: visible ? 36 : 0
        placeholder: Fili.tr("Filter albums")
        onTextChanged: view.query = text.toLowerCase()
    }
    AlbumGrid {
        anchors { top: filter.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        visible: view.opened === null
        albums: view.shown
        onOpened: album => view.opened = album
        onAlbumMenu: (album, x, y) => view.albumMenu(album, x, y)
        onMore: if (view.query === "")
            view.load(true)
    }
    Loader {
        anchors.fill: parent
        active: view.opened !== null
        sourceComponent: AlbumDetail {
            album: view.opened
            onBack: view.opened = null
            onTrackMenu: (ids, x, y) => view.trackMenu(ids, x, y)
        }
    }
    Text {
        anchors.centerIn: parent
        visible: view.opened === null && view.shown.length === 0 && !view.busy
        text: Fili.tr("No albums")
        font.family: FiliTheme.font
        font.pixelSize: FiliTheme.size
        color: FiliTheme.muted
    }
}
