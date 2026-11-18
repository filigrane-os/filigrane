// Albums as a wrapping grid of covers (albums view, artist page, genre page). Two ways to feed it: `albums`, an array, or for a
// big library `total` and `albumAt(index)`, the grid then holds one cell per album and each asks for its album when drawn
// (null while it loads), so the scrollbar covers the whole library and nothing jumps when pages arrive.
import QtQuick
import Fili.Baladeur

Item {
    id: grid
    property var albums: []
    property int total: -1
    property var albumAt: null
    readonly property int cell: 150
    readonly property int columns: Math.max(1, Math.floor((width - 2 * FiliTheme.margin + FiliTheme.space4) / (cell + FiliTheme.space4)))
    property alias view: gv
    // Optional blocks above and below the covers, scrolled with them
    property Component header
    property Component footer
    signal opened(var album)
    signal albumMenu(var album, real x, real y)
    signal more()

    GridView {
        id: gv
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: grid.total >= 0 ? grid.total : grid.albums
        cellWidth: Math.floor((width - 2 * FiliTheme.margin + FiliTheme.space4) / grid.columns)
        cellHeight: grid.cell + 44 + FiliTheme.space4
        leftMargin: FiliTheme.margin
        topMargin: FiliTheme.space4
        bottomMargin: FiliTheme.space4
        header: grid.header
        footer: grid.footer
        KineticScroll {}
        onAtYEndChanged: if (atYEnd && count > 0)
            grid.more()
        delegate: Item {
            id: cellItem
            required property int index
            required property var modelData
            readonly property var info: grid.total >= 0 ? grid.albumAt(index) : modelData
            width: gv.cellWidth
            height: gv.cellHeight
            Loader {
                active: cellItem.info !== null && cellItem.info !== undefined
                sourceComponent: AlbumCard {
                    album: cellItem.info
                    cover: grid.cell
                    onOpened: grid.opened(cellItem.info)
                    onMenuRequested: (x, y) => grid.albumMenu(cellItem.info, x, y)
                }
            }
        }
    }
    FiliScrollBar {
        flick: gv
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
    }
}
