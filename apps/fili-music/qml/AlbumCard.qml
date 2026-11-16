// An album in a grid: cover, title, artist (year); a click opens it, the menu is asked on right click.
import QtQuick
import Fili.Baladeur

Item {
    id: card
    required property var album
    property int cover: 150
    signal opened()
    signal menuRequested(real x, real y)

    width: cover
    height: cover + 44

    Artwork {
        id: art
        width: card.cover
        height: card.cover
        itemId: card.album.id
        radius: FiliTheme.radiusControl
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: area.containsMouse ? 2 : 0
            border.color: FiliTheme.accentColor
        }
    }
    Text {
        anchors { top: art.bottom; topMargin: FiliTheme.space1 + 2; left: parent.left; right: parent.right }
        elide: Text.ElideRight
        text: card.album.title
        font.family: FiliTheme.font
        font.pixelSize: FiliTheme.sizeList
        font.weight: FiliTheme.weightAccent
        color: FiliTheme.text
    }
    Text {
        anchors { top: art.bottom; topMargin: FiliTheme.space1 + 2 + 18; left: parent.left; right: parent.right }
        elide: Text.ElideRight
        text: card.album.artist_name + (card.album.year ? " · " + card.album.year : "")
        font.family: FiliTheme.font
        font.pixelSize: FiliTheme.sizeSmall
        color: FiliTheme.textSecondary
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: e => {
            if (e.button === Qt.RightButton) {
                const p = area.mapToItem(null, e.x, e.y);
                card.menuRequested(p.x, p.y);
            } else
                card.opened();
        }
    }
    Accessible.role: Accessible.Button
    Accessible.name: card.album.title
}
