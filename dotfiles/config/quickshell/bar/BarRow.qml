// Container of the parts of a fili-bar module: side by side on a top or bottom bar, stacked on a left or right one
import QtQuick
import qs

Grid {
    flow: Grid.LeftToRight
    columns: FiliTheme.barVertical ? 1 : 1000
    horizontalItemAlignment: Grid.AlignHCenter
    verticalItemAlignment: Grid.AlignVCenter
}
