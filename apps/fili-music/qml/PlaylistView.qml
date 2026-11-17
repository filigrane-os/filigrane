// One playlist: its name, play / queue / rename / delete, and its tracks (a track leaves it from the menu).
import QtQuick
import Fili.Baladeur

Item {
    id: view
    required property int playlistId
    property var playlist: null
    // The order of the playlist, one entry per row of the table (a track can appear twice)
    signal trackMenu(var ids, real x, real y, var positions)
    signal renameRequested(var playlist)
    signal deleteRequested(var playlist)
    signal exportRequested(var playlist, string text)
    // The playlist as an extended M3U file
    function m3u() {
        let out = "#EXTM3U\n";
        for (let i = 0; i < tracks.count; i++) {
            const t = tracks.get(i);
            out += "#EXTINF:" + Math.round(t.duration / 1000) + "," + (t.artists !== "" ? t.artists : Store.artistName(t.artistId)) + " - " + t.title + "\n" + t.path + "\n";
        }
        return out;
    }
    ListModel { id: tracks }

    function reload() {
        Store.callAsync("get_playlists", [], d => {
            const found = d ? d.playlists.filter(p => p.id === playlistId) : [];
            playlist = found.length > 0 ? found[0] : null;
            if (!playlist) {
                tracks.clear();
                return;
            }
            const ids = playlist.tracks.map(t => t.track_id);
            Store.callAsync("tracks_by_ids", [JSON.stringify(ids)], list => {
                tracks.clear();
                if (!list)
                    return;
                // tracks_by_ids drops unknown ids: positions follow the rows that survived
                const byId = {};
                for (const t of list)
                    byId[t.id] = t;
                ids.forEach((id, pos) => {
                    if (byId[id]) {
                        const r = Store.row(byId[id]);
                        r.position = pos;
                        tracks.append(r);
                    }
                });
            });
        });
    }
    onPlaylistIdChanged: reload()
    Component.onCompleted: reload()
    Connections {
        target: Store
        function onPlaylistRevChanged() {
            view.reload();
        }
    }

    Rectangle {
        id: head
        width: parent.width
        height: 84
        color: FiliTheme.background
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: FiliTheme.borderWidth; color: FiliTheme.border }
        Text {
            x: FiliTheme.margin
            y: FiliTheme.space3
            width: parent.width - 2 * FiliTheme.margin
            elide: Text.ElideRight
            text: view.playlist ? view.playlist.name : ""
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.sizeTitle + 4
            font.weight: Font.Light
            color: FiliTheme.text
        }
        Text {
            x: FiliTheme.margin
            y: FiliTheme.space3 + 30
            text: tracks.count + " " + Fili.tr("tracks")
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.sizeSmall
            color: FiliTheme.muted
        }
        Row {
            anchors { left: parent.left; leftMargin: FiliTheme.margin; bottom: parent.bottom; bottomMargin: FiliTheme.space2 }
            spacing: FiliTheme.space2
            TextButton { label: Fili.tr("Play"); primary: true; onClicked: Store.playNow(Store.ids(tracks), 0) }
            TextButton { label: Fili.tr("Add to queue"); onClicked: Store.addToQueue(Store.ids(tracks)) }
            TextButton { label: Fili.tr("Export as M3U…"); enabled: tracks.count > 0; onClicked: view.exportRequested(view.playlist, view.m3u()) }
            TextButton { label: Fili.tr("Rename…"); onClicked: view.renameRequested(view.playlist) }
            TextButton { label: Fili.tr("Delete"); onClicked: view.deleteRequested(view.playlist) }
        }
    }
    TrackTable {
        id: table
        anchors { top: head.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        model: tracks
        onActivated: (row, alt) => Store.wantsPlay(alt) ? Store.playNow(Store.ids(tracks), row) : Store.addToQueue([tracks.get(row).id])
        onMenuRequested: (row, x, y) => {
            const ids = selectedCount > 1 ? selectedIds() : [tracks.get(row).id];
            // Positions of the selected rows, from the last, so removing them one by one stays right
            const pos = [];
            for (let i = 0; i < tracks.count; i++)
                if (ids.indexOf(tracks.get(i).id) >= 0)
                    pos.push(tracks.get(i).position);
            view.trackMenu(ids, x, y, pos.sort((a, b) => b - a));
        }
    }
    Text {
        anchors.centerIn: table
        visible: tracks.count === 0
        text: Fili.tr("This playlist is empty")
        font.family: FiliTheme.font
        font.pixelSize: FiliTheme.size
        color: FiliTheme.muted
    }
}
