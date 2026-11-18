// The albums of the library as a grid of covers; an album opens its page. One cell per album, pages of 60 read as the cells are drawn.
import QtQuick
import Fili.Baladeur

Item {
    id: view
    signal trackMenu(var ids, real x, real y)
    signal albumMenu(var album, real x, real y)

    // The library is not loaded as a whole: `total` cells, and each asks for its page of 60 albums when it is drawn
    readonly property int pageSize: 60
    property int total: 0
    property var pages: ({})
    property var asked: ({})
    property int pagesRev: 0
    property var opened: null
    property int serial: 0
    property string query: ""
    // With a filter: the albums that match (every page is read to find them)
    property var matches: []
    property bool filtering: false

    function albumAt(i) {
        pagesRev;
        const k = Math.floor(i / pageSize);
        const page = pages[k];
        if (page === undefined) {
            askPage(k);
            return null;
        }
        return page[i - k * pageSize] || null;
    }
    function askPage(k, done) {
        if (asked[k] && !done)
            return;
        asked[k] = true;
        const mine = serial;
        Store.callAsync("get_albums_page", [k * pageSize, pageSize], d => {
            if (mine !== serial)
                return;
            if (d) {
                pages[k] = d.albums;
                pagesRev++;
            } else {
                delete asked[k];
            }
            if (done)
                done();
        });
    }
    function runFilter() {
        const q = query;
        if (q === "") {
            matches = [];
            filtering = false;
            return;
        }
        filtering = true;
        const finish = () => {
            if (query !== q)
                return;
            const out = [];
            for (let k = 0; k * pageSize < total; k++)
                for (const a of pages[k] || [])
                    if (a.title.toLowerCase().includes(q) || a.artist_name.toLowerCase().includes(q))
                        out.push(a);
            matches = out;
            filtering = false;
        };
        const missing = [];
        for (let k = 0; k * pageSize < total; k++)
            if (pages[k] === undefined)
                missing.push(k);
        if (missing.length === 0) {
            finish();
            return;
        }
        let left = missing.length;
        for (const k of missing)
            askPage(k, () => {
                if (--left === 0)
                    finish();
            });
    }
    onQueryChanged: runFilter()
    function reset() {
        serial++;
        pages = ({});
        asked = ({});
        pagesRev++;
        Store.callAsync("get_library_stats", [], d => {
            total = d ? d.album_count : 0;
            runFilter();
        });
    }
    function openById(id) {
        Store.callAsync("get_album_by_id", [id], a => {
            if (a)
                view.opened = a;
        });
    }
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
        total: view.query === "" ? view.total : -1
        albumAt: view.albumAt
        albums: view.matches
        onOpened: album => view.opened = album
        onAlbumMenu: (album, x, y) => view.albumMenu(album, x, y)
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
        visible: view.opened === null && (view.query === "" ? view.total === 0 : view.matches.length === 0 && !view.filtering)
        text: Fili.tr("No albums")
        font.family: FiliTheme.font
        font.pixelSize: FiliTheme.size
        color: FiliTheme.muted
    }
}
