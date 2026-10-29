// Module natif de la fili-bar: texte + zone de clic et d'infobulle (Hover)
import QtQuick

Item {
    id: nat
    property string text
    property color color: FiliTheme.brume
    property alias hover: hov
    property var tip
    property alias tipInfo: hov.tipInfo
    property real pad: FiliTheme.pad
    property real maxWidth: Infinity
    implicitWidth: visible ? Math.max(FiliTheme.isIcon(nat.text) ? FiliTheme.iconCell : 0, content.implicitWidth + 2 * pad) : 0
    implicitHeight: FiliTheme.barHeight
    visible: nat.text !== ""
    // Icône en ardoise, valeur en blanc (FiliTheme.glyph)
    Row {
        id: content
        anchors.centerIn: parent
        spacing: FiliTheme.labelGap
        Text {
            id: glyphText
            visible: text !== ""
            text: FiliTheme.glyph(nat.text)
            color: FiliTheme.iconColor(nat.color)
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.size
        }
        Text {
            text: FiliTheme.value(nat.text)
            // Tronqué (…) quand le texte dépasse maxWidth (propriété posée par la barre, sinon sans limite)
            elide: Text.ElideRight
            width: Math.min(implicitWidth, Math.max(0, nat.maxWidth - 2 * nat.pad - (FiliTheme.glyph(nat.text) !== "" ? glyphText.implicitWidth + content.spacing : 0)))
            color: nat.color
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.size
        }
    }
    BarHover {
        id: hov
        anchors.fill: parent
        tip: nat.tip
    }
}
