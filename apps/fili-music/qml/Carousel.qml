// A titled horizontal row of cards that moves page by page with two chevrons (albums of the artist, similar artists).
// Takes no room when empty. `card` is the delegate; it receives `modelData`.
import QtQuick
import Fili.Baladeur

Item {
    id: car
    property string title: ""
    property string subtitle: ""
    property var items: []
    property int pageSize: 4
    property int cardWidth: 120
    property int cardHeight: 160
    property int gap: FiliTheme.space3
    property Component card

    readonly property bool paged: items.length > pageSize
    readonly property int stride: cardWidth + gap
    width: parent ? parent.width : 0
    height: items.length > 0 ? head.height + FiliTheme.space2 + cardHeight : 0
    visible: items.length > 0

    function go(step) {
        const page = Math.max(1, Math.floor((row.width + gap) / stride));
        const max = Math.max(0, row.contentWidth - row.width);
        slide.to = Math.max(0, Math.min(max, row.contentX + step * page * stride));
        slide.from = row.contentX;
        slide.restart();
    }
    NumberAnimation { id: slide; target: row; property: "contentX"; duration: 250; easing.type: Easing.OutCubic }

    Row {
        id: head
        spacing: FiliTheme.space2
        height: 24
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: car.title
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.size
            font.weight: FiliTheme.weightAccent
            color: FiliTheme.text
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: car.subtitle
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.size
            color: FiliTheme.muted
        }
    }
    Row {
        anchors.right: parent.right
        height: head.height
        visible: car.paged
        spacing: FiliTheme.space1
        IconButton {
            glyph: ""
            enabledState: row.contentX > 0
            onClicked: car.go(-1)
            Accessible.name: Fili.tr("Previous")
        }
        IconButton {
            glyph: ""
            enabledState: row.contentX < row.contentWidth - row.width - 1
            onClicked: car.go(1)
            Accessible.name: Fili.tr("Next")
        }
    }
    ListView {
        id: row
        anchors { top: head.bottom; topMargin: FiliTheme.space2; left: parent.left; right: parent.right }
        height: car.cardHeight
        orientation: ListView.Horizontal
        spacing: car.gap
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: car.items
        delegate: car.card
    }
}
