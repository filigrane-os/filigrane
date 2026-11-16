// Albums as a wrapping grid of covers (albums view, artist page, genre page). Gives `more` when the end is reached.
import QtQuick
import Fili.Baladeur

Item {
    id: grid
    property var albums: []
    readonly property int cell: 150
    readonly property int columns: Math.max(1, Math.floor((width - 2 * FiliTheme.margin + FiliTheme.space4) / (cell + FiliTheme.space4)))
    property alias view: gv
    signal opened(var album)
    signal albumMenu(var album, real x, real y)
    signal more()

    GridView {
        id: gv
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: grid.albums
        cellWidth: Math.floor((width - 2 * FiliTheme.margin + FiliTheme.space4) / grid.columns)
        cellHeight: grid.cell + 44 + FiliTheme.space4
        leftMargin: FiliTheme.margin
        topMargin: FiliTheme.space4
        bottomMargin: FiliTheme.space4
        KineticScroll {}
        onAtYEndChanged: if (atYEnd && count > 0)
            grid.more()
        delegate: Item {
            id: cellItem
            required property var modelData
            width: gv.cellWidth
            height: gv.cellHeight
            AlbumCard {
                album: cellItem.modelData
                cover: grid.cell
                onOpened: grid.opened(cellItem.modelData)
                onMenuRequested: (x, y) => grid.albumMenu(cellItem.modelData, x, y)
            }
        }
    }
    FiliScrollBar {
        flick: gv
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
    }
}
