// Baladeur (fili-music): "Artist - Title" of the music playing, shown while Baladeur is running (it stays alive when its
// window is closed). Click = the panel (player and queue), middle click = play / pause, wheel = previous / next, right
// click = the window. The player is the MPRIS one of Baladeur (media keys and playerctl see the same).
import QtQuick
import Quickshell.Services.Mpris
import qs
import qs.bar

BarModule {
    id: mod
    panel: "baladeur"
    panelSource: Qt.resolvedUrl("BaladeurPanel.qml")
    anchorItem: item
    readonly property var player: Mpris.players.values.find(p => p.desktopEntry === "fili-music" || p.dbusName.indexOf("fili_music") >= 0) ?? null

    // What the bar shows: kept while the player has no title for a moment (between two tracks)
    property string label: ""
    function follow() {
        if (player && player.trackTitle) {
            let t = (player.trackArtist ? player.trackArtist + " - " : "") + player.trackTitle;
            label = t.length > 28 ? t.slice(0, 27) + "…" : t;
        } else if (!player) {
            label = "";
        }
    }
    onPlayerChanged: follow()
    Connections {
        target: mod.player
        function onTrackTitleChanged() { mod.follow(); }
        function onTrackArtistChanged() { mod.follow(); }
    }
    Component.onCompleted: follow()

    BarRow {
        BarScript {
            id: item
            objectName: "baladeur"
            title: "Baladeur"
            panelNeedsVisible: true
            mclick: "fili-music ctl action play-pause"
            // The title stays when the bar is squeezed, only shorter
            value: mod.player && mod.label !== "" ? {
                text: mod.compact && mod.label.length > 18 ? mod.label.slice(0, 17) + "…" : mod.label,
                "class": mod.player.isPlaying ? "playing" : "paused",
                tooltip: { title: "Baladeur", text: mod.player.trackAlbum, hint: FiliI18n.tr("click: panel · middle click: play/pause · right click: window · wheel: previous / next") }
            } : { text: "" }
            colors: ({ playing: FiliTheme.barText, paused: FiliTheme.barMuted })
            rclick: "fili-music"
            hover.onLeftClicked: mod.togglePanel(hover)
            hover.onWheelUp: if (mod.player) mod.player.previous()
            hover.onWheelDown: if (mod.player) mod.player.next()
        }
    }
}
