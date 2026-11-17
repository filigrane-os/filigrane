// Long text clamped to a few lines, with a "Show more" / "Show less" link when it does not fit.
import QtQuick
import Fili.Baladeur

Column {
    id: box
    property string text: ""
    property int lines: 7
    property real pixelSize: FiliTheme.sizeSmall
    property color textColor: FiliTheme.textSecondary
    property bool expanded: false
    spacing: FiliTheme.space1

    Text {
        id: body
        width: parent.width
        text: box.text
        wrapMode: Text.Wrap
        maximumLineCount: box.expanded ? 1000000 : box.lines
        elide: Text.ElideRight
        lineHeight: 1.25
        font.family: FiliTheme.font
        font.pixelSize: box.pixelSize
        color: box.textColor
    }
    // The same text unclamped, invisible, tells whether the clamp cuts something
    Text {
        id: probe
        width: parent.width
        visible: false
        text: box.text
        wrapMode: Text.Wrap
        lineHeight: 1.25
        font.family: FiliTheme.font
        font.pixelSize: box.pixelSize
    }
    Text {
        visible: probe.lineCount > box.lines
        text: box.expanded ? Fili.tr("Show less") : Fili.tr("Show more")
        font.family: FiliTheme.font
        font.pixelSize: FiliTheme.sizeSmall
        color: more.containsMouse ? FiliTheme.text : FiliTheme.muted
        MouseArea { id: more; anchors { fill: parent; margins: -4 } hoverEnabled: true; onClicked: box.expanded = !box.expanded }
    }
}
