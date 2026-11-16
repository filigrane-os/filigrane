// One album: cover and facts, play / queue buttons, the tracks. `back` returns to the grid; the artist name opens the artist.
import QtQuick
import Fili.Baladeur

Item {
    id: detail
    required property var album
    signal back()
    signal trackMenu(var ids, real x, real y)

    ListModel { id: tracks }
    property real totalMs: 0
    property var featuring: []
    function reload() {
        Store.callAsync("get_album_featuring_artists", [album.id, album.artist_id], d => featuring = d ? d.artists : []);
        Store.callAsync("get_album_tracks", [album.id], d => {
            Store.fill(tracks, d ? d.tracks : [], false);
            let ms = 0;
            for (let i = 0; i < tracks.count; i++)
                ms += tracks.get(i).duration;
            totalMs = ms;
        });
    }
    Component.onCompleted: reload()
    Connections {
        target: Store
        function onLibraryRevChanged() {
            detail.reload();
        }
    }

    Rectangle {
        id: head
        width: parent.width
        height: 180 + 2 * FiliTheme.space4
        color: FiliTheme.background
        // Ambient colour of the cover: a wash fading into the background
        AmbientColor {
            id: ambient
            source: art.source
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: FiliTheme.alpha(ambient.color, 0.34) }
                GradientStop { position: 1; color: FiliTheme.alpha(ambient.color, 0.06) }
            }
            opacity: ambient.color.a > 0 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 250 } }
        }
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: FiliTheme.borderWidth
            color: FiliTheme.border
        }
        Artwork {
            id: art
            x: FiliTheme.margin
            y: FiliTheme.space4
            width: 180
            height: 180
            itemId: detail.album.id
        }
        Column {
            anchors { left: art.right; leftMargin: FiliTheme.space4; right: parent.right; rightMargin: FiliTheme.margin; top: art.top }
            spacing: FiliTheme.space1
            Text {
                text: "‹ " + Fili.tr("Albums")
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeSmall
                color: backArea.containsMouse ? FiliTheme.text : FiliTheme.muted
                MouseArea { id: backArea; anchors { fill: parent; margins: -4 } hoverEnabled: true; onClicked: detail.back() }
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: detail.album.title
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeTitle + 6
                font.weight: Font.Light
                color: FiliTheme.text
            }
            Text {
                text: detail.album.artist_name
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.size
                color: artistArea.containsMouse ? FiliTheme.accentColor : FiliTheme.textSecondary
                MouseArea { id: artistArea; anchors.fill: parent; hoverEnabled: true; onClicked: Store.artistRequested(detail.album.artist_id) }
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: [detail.album.year ? detail.album.year : "", tracks.count + " " + Fili.tr("tracks"), Store.longDuration(detail.totalMs / 1000), detail.album.label ? detail.album.label : "", detail.album.album_type ? detail.album.album_type : ""].filter(x => x !== "").join(" · ")
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeSmall
                color: FiliTheme.muted
            }
            Item { width: 1; height: FiliTheme.space2 }
            Row {
                spacing: FiliTheme.space2
                TextButton { label: Fili.tr("Play"); primary: true; onClicked: Store.playNow(Store.ids(tracks), 0) }
                TextButton { label: Fili.tr("Add to queue"); onClicked: Store.addToQueue(Store.ids(tracks)) }
                TextButton { label: Fili.tr("Edit metadata…"); onClicked: Store.tagEditorRequested("album", [detail.album.id]) }
            }
            Text {
                width: parent.width
                visible: detail.album.description !== null && detail.album.description !== undefined && detail.album.description !== ""
                maximumLineCount: 3
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                text: detail.album.description || ""
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeSmall
                color: FiliTheme.textSecondary
            }
        }
    }
    ArtistStrip {
        id: featuringStrip
        anchors.top: head.bottom
        width: parent.width
        title: Fili.tr("Also featuring")
        artists: detail.featuring
        onOpened: artist => Store.artistRequested(artist.id)
    }
    TrackTable {
        id: table
        anchors { top: featuringStrip.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        model: tracks
        showAlbum: false
        showArtist: false
        trackNumbers: true
        onActivated: (row, alt) => alt ? Store.addToQueue([tracks.get(row).id]) : Store.playNow(Store.ids(tracks), row)
        onMenuRequested: (row, x, y) => detail.trackMenu(selectedCount > 1 ? selectedIds() : [tracks.get(row).id], x, y)
    }
}
