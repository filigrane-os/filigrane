// A row of artists under a header (similar artists, featuring): a round photo and a name each, a click opens the artist.
// Takes no room when the list is empty.
import QtQuick
import Fili.Baladeur

Item {
    id: strip
    property string title: ""
    property var artists: []
    signal opened(var artist)

    width: parent ? parent.width : 0
    height: artists.length > 0 ? 28 + 76 + FiliTheme.space2 : 0
    visible: artists.length > 0

    Text {
        x: FiliTheme.margin
        y: FiliTheme.space2
        text: strip.title
        font.family: FiliTheme.font
        font.pixelSize: FiliTheme.sizeSmall
        font.weight: FiliTheme.weightAccent
        color: FiliTheme.muted
    }
    ListView {
        id: row
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: FiliTheme.space1 }
        height: 76
        orientation: ListView.Horizontal
        leftMargin: FiliTheme.margin
        rightMargin: FiliTheme.margin
        spacing: FiliTheme.space3
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: strip.artists
        delegate: Item {
            id: chip
            required property var modelData
            width: 72
            height: row.height
            Artwork {
                id: photo
                anchors.horizontalCenter: parent.horizontalCenter
                width: 48
                height: 48
                radius: 24
                kind: "artist"
                itemId: chip.modelData.id
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    border.width: area.containsMouse ? 2 : 0
                    border.color: FiliTheme.accentColor
                }
            }
            Text {
                anchors { top: photo.bottom; topMargin: FiliTheme.space1; left: parent.left; right: parent.right }
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: chip.modelData.name
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeSmall
                color: FiliTheme.text
            }
            MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; onClicked: strip.opened(chip.modelData) }
            Accessible.role: Accessible.Button
            Accessible.name: chip.modelData.name
        }
    }
}
