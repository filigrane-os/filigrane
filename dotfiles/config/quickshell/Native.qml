// Module natif de la barre: texte + zone de clic et d'infobulle (Hover)
import QtQuick

Item {
    id: nat
    property alias text: lbl.text
    property alias color: lbl.color
    property alias font: lbl.font
    property alias hover: hov
    property string tip
    property real pad: 4
    implicitWidth: visible ? lbl.implicitWidth + 2 * pad : 0
    implicitHeight: Theme.barHeight
    visible: lbl.text !== ""
    Text {
        id: lbl
        anchors.centerIn: parent
        color: Theme.brume
        font.family: Theme.font
        font.pixelSize: Theme.size
    }
    Hover {
        id: hov
        anchors.fill: parent
        tip: nat.tip
    }
}
