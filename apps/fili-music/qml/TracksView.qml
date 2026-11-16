// All the tracks of the library, 100 at a time as the list is scrolled, sortable, with a filter (full-text search).
import QtQuick
import Fili.Baladeur

Item {
    id: view
    // A menu is asked for a set of track ids: handled by Main (play, queue, playlists, delete)
    signal trackMenu(var ids, real x, real y)

    property string sortBy: "title"
    property string sortDir: "asc"
    property bool busy: false
    property bool exhausted: false
    property int serial: 0
    ListModel { id: tracks }
    property int total: 0

    function load(more) {
        if (busy || (more && exhausted))
            return;
        const mine = ++serial;
        busy = true;
        const offset = more ? tracks.count : 0;
        if (filter.text !== "") {
            Store.callAsync("search_tracks", [filter.text, 1000], d => {
                if (mine !== serial)
                    return;
                busy = false;
                exhausted = true;
                Store.fill(tracks, d ? d.tracks : [], false);
            });
            return;
        }
        Store.callAsync("get_tracks_page", [offset, 100, sortBy, sortDir], d => {
            if (mine !== serial)
                return;
            busy = false;
            const page = d ? d.tracks : [];
            exhausted = page.length < 100;
            Store.fill(tracks, page, more);
        });
    }
    function reset() {
        serial++;
        busy = false;
        exhausted = false;
        load(false);
    }
    Component.onCompleted: {
        const s = Store.call("get_library_stats");
        total = s ? s.track_count : 0;
        reset();
    }
    Connections {
        target: Store
        function onLibraryRevChanged() {
            const s = Store.call("get_library_stats");
            view.total = s ? s.track_count : 0;
            view.reset();
        }
    }
    Timer {
        id: debounce
        interval: 200
        onTriggered: view.reset()
    }

    FilterBar {
        id: filter
        width: parent.width
        placeholder: Fili.tr("Filter %1 tracks").replace("%1", view.total)
        onTextChanged: debounce.restart()
    }
    TrackTable {
        id: table
        anchors { top: filter.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        model: tracks
        sortable: true
        sortBy: view.sortBy
        sortDir: view.sortDir
        onSortRequested: (by, dir) => {
            if (filter.text !== "")
                return;
            view.sortBy = by;
            view.sortDir = dir;
            view.reset();
        }
        onLoadMore: if (filter.text === "")
            view.load(true)
        onActivated: (row, alt) => alt ? Store.addToQueue([tracks.get(row).id]) : Store.addAndPlay(tracks.get(row).id)
        onMenuRequested: (row, x, y) => view.trackMenu(selectedCount > 1 ? selectedIds() : [tracks.get(row).id], x, y)
        onDeleteRequested: view.trackMenu(selectedIds(), width / 2, height / 2)
    }
    Text {
        anchors.centerIn: table
        visible: tracks.count === 0 && !view.busy
        text: filter.text !== "" ? Fili.tr("No results") : Fili.tr("The library is empty")
        font.family: FiliTheme.font
        font.pixelSize: FiliTheme.size
        color: FiliTheme.muted
    }
}
