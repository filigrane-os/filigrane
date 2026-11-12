// Native fili-bar module: text + click and tooltip area (Hover)
import QtQuick
import qs
import qs.bar

BarModule {
    id: nat
    property string text
    property color color: FiliTheme.barText
    property alias hover: hov
    property var tip
    property alias tipInfo: hov.tipInfo
    property real pad: FiliTheme.pad
    property real maxWidth: Infinity
    readonly property bool vertical: FiliTheme.barVertical
    // On a column the icon sits above the value, and the module is as wide as the bar
    implicitWidth: !visible ? 0 : vertical ? FiliTheme.barWidth : Math.max(FiliTheme.isIcon(nat.text) ? FiliTheme.iconCell : 0, content.implicitWidth + 2 * pad)
    implicitHeight: !visible ? 0 : vertical ? Math.max(FiliTheme.isIcon(nat.text) ? FiliTheme.iconCell : 0, content.implicitHeight + 2 * FiliTheme.barPadV) : FiliTheme.barHeight
    visible: nat.text !== "" && (trayMode === "never" || BarState.trayOpen)
    // Icon in slate, value in white (FiliTheme.glyph)
    Grid {
        id: content
        anchors.centerIn: parent
        flow: Grid.LeftToRight
        columns: nat.vertical ? 1 : 2
        spacing: nat.vertical ? 1 : FiliTheme.labelGap
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter
        Text {
            id: glyphText
            visible: text !== "" && nat.display !== "value"
            text: FiliTheme.glyph(nat.text)
            color: FiliTheme.iconColor(nat.color)
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.size
        }
        Text {
            visible: nat.display !== "icon" || FiliTheme.glyph(nat.text) === ""
            text: FiliTheme.value(nat.text)
            // Truncated (…) when the text exceeds maxWidth (property set by the bar, no limit otherwise)
            elide: Text.ElideRight
            width: nat.vertical ? Math.min(implicitWidth, FiliTheme.barWidth - 2 * nat.pad) : Math.min(implicitWidth, Math.max(0, nat.maxWidth - 2 * nat.pad - (FiliTheme.glyph(nat.text) !== "" ? glyphText.implicitWidth + content.spacing : 0)))
            color: nat.color
            font.family: FiliTheme.font
            font.pixelSize: nat.vertical ? FiliTheme.sizeSmall : FiliTheme.size
        }
    }
    BarHover {
        id: hov
        anchors.fill: parent
        tip: nat.tip
    }
}
