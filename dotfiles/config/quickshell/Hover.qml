// Zone de clic et d'infobulle d'un module: commandes shell par bouton et molette, ou fonctions (onLeft...).
// L'infobulle est partagée par la barre (Tip.qml), affichée après 400 ms de survol.
import QtQuick
import Quickshell

MouseArea {
    id: area
    property string tip
    property bool mono: tip.indexOf("<tt>") >= 0
    property string click
    property string rclick
    property string mclick
    property string scrollUp
    property string scrollDown
    signal leftClicked
    signal rightClicked
    signal middleClicked
    signal wheelUp
    signal wheelDown

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    cursorShape: (click || rclick) ? Qt.PointingHandCursor : Qt.ArrowCursor

    onClicked: m => {
        Tip.hide();
        if (m.button === Qt.LeftButton) {
            Theme.run(click);
            leftClicked();
        } else if (m.button === Qt.RightButton) {
            Theme.run(rclick);
            rightClicked();
        } else {
            Theme.run(mclick);
            middleClicked();
        }
    }
    onWheel: w => {
        if (w.angleDelta.y > 0) {
            Theme.run(scrollUp);
            wheelUp();
        } else if (w.angleDelta.y < 0) {
            Theme.run(scrollDown);
            wheelDown();
        }
    }
    onContainsMouseChanged: containsMouse ? Tip.show(area, tip, mono) : Tip.hide(area)
    onTipChanged: if (containsMouse) Tip.show(area, tip, mono)
}
