// Module natif de la fili-bar: texte + zone de clic et d'infobulle (Hover)
import QtQuick

Item {
    id: nat
    property alias text: lbl.text
    property alias color: lbl.color
    property alias font: lbl.font
    property alias hover: hov
    property var tip
    property alias tipCmd: hov.tipCmd
    property real pad: 4
    implicitWidth: visible ? lbl.implicitWidth + 2 * pad : 0
    implicitHeight: FiliTheme.barHeight
    visible: lbl.text !== ""
    Text {
        id: lbl
        anchors.centerIn: parent
        color: FiliTheme.brume
        font.family: FiliTheme.font
        font.pixelSize: FiliTheme.size
    }
    BarHover {
        id: hov
        anchors.fill: parent
        tip: nat.tip
    }
}
