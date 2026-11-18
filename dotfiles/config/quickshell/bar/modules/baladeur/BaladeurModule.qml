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
        if (player && player.trackTitle)
            label = (player.trackArtist ? player.trackArtist + " - " : "") + player.trackTitle;
        else if (!player)
            label = "";
    }
    onPlayerChanged: follow()
    Connections {
        target: mod.player
        function onTrackTitleChanged() { mod.follow(); }
        function onTrackArtistChanged() { mod.follow(); }
    }
    Component.onCompleted: follow()

    BarRow {
        // Previous (Fili Icons skip-back)
        BarItem {
            objectName: "baladeur-prev"
            text: mod.player ? String.fromCodePoint(0xf2f11) : ""
            color: FiliTheme.barText2
            tip: FiliI18n.tr("Previous")
            hover.onLeftClicked: if (mod.player) mod.player.previous()
        }
        BarScript {
            id: item
            objectName: "baladeur"
            title: "Baladeur"
            panelNeedsVisible: true
            mclick: "fili-music ctl action play-pause"
            value: mod.player && mod.label !== "" ? {
                text: mod.label,
                "class": mod.player.isPlaying ? "playing" : "paused",
                tooltip: { title: "Baladeur", text: mod.player.trackAlbum, hint: FiliI18n.tr("click: panel · middle click: play/pause · right click: window · wheel: previous / next") }
            } : { text: "" }
            colors: ({ playing: FiliTheme.barText, paused: FiliTheme.barMuted })
            rclick: "fili-music"
            hover.onLeftClicked: mod.togglePanel(hover)
            hover.onWheelUp: if (mod.player) mod.player.previous()
            hover.onWheelDown: if (mod.player) mod.player.next()
        }
        // Next (Fili Icons skip-forward)
        BarItem {
            objectName: "baladeur-next"
            text: mod.player ? String.fromCodePoint(0xf2f12) : ""
            color: FiliTheme.barText2
            tip: FiliI18n.tr("Next")
            hover.onLeftClicked: if (mod.player) mod.player.next()
        }
    }
}
