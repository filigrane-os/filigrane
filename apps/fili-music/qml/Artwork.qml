// Cover of an album or photo of an artist: the file comes from the core (Store.cover), a note stands in until it arrives
// or when there is none.
import QtQuick
import Fili.Baladeur

Rectangle {
    id: art
    // "album" or "artist"
    property string kind: "album"
    property int itemId: -1
    readonly property string source: itemId >= 0 ? Store.cover(kind, itemId) : ""

    color: FiliTheme.surface
    radius: FiliTheme.radiusControl
    clip: true

    Image {
        anchors.fill: parent
        source: art.source
        visible: status === Image.Ready
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize: Qt.size(Math.max(64, art.width * 2), Math.max(64, art.height * 2))
    }
    Text {
        anchors.centerIn: parent
        visible: art.source === ""
        text: art.kind === "artist" ? "♪" : "♫"
        font.family: FiliTheme.font
        font.pixelSize: Math.max(12, art.width / 3)
        color: FiliTheme.muted
    }
}
