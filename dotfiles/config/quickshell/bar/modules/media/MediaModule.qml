// Click = play/pause, right click = player window, middle click = next, wheel up/down = previous / next
import QtQuick
import Quickshell.Services.Mpris
import qs
import qs.bar

BarItem {
    objectName: "media"
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
    text: {
        if (!player || !player.trackTitle)
            return "";
        const t = player.isPlaying ? " " + player.trackTitle + (player.trackArtist ? "  ·  " + player.trackArtist : "") : " " + player.trackTitle;
        return t.length > 40 ? t.slice(0, 39) + "…" : t;
    }
    color: FiliTheme.brume2
    function mmss(s) {
        s = Math.max(0, Math.round(s));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }
    tip: !player ? "" : {
        title: player.identity,
        rows: [[FiliI18n.tr("Title"), player.trackTitle], [FiliI18n.tr("Artist"), player.trackArtist], [FiliI18n.tr("Album"), player.trackAlbum],
               [FiliI18n.tr("State"), player.isPlaying ? FiliI18n.tr("playing") : FiliI18n.tr("paused")],
               [FiliI18n.tr("Position"), player.lengthSupported && player.length > 0 ? mmss(player.position) + " / " + mmss(player.length) : ""]].filter(r => r[1]),
        hint: FiliI18n.tr("click: play/pause · right click: player window · middle click: next · wheel: previous / next")
    }
    hover.onLeftClicked: player.togglePlaying()
    hover.onMiddleClicked: player.next()
    hover.onRightClicked: {
        const id = player ? Niri.playerWindow(Niri.windows, player.dbusName, player.desktopEntry, player.trackTitle) : null;
        if (id !== null)
            Niri.action("focus-window", "--id", String(id));
    }
    hover.onWheelUp: player.previous()
    hover.onWheelDown: player.next()
}
