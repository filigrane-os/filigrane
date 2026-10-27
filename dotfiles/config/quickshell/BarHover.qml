// Zone de clic et de fili-tooltip d'un module de la fili-bar: commandes shell par bouton et molette, ou signaux
// (onLeftClicked...). tip: texte ou fiche (voir FiliTooltip); tipInfo: fiche demandée seulement au survol (FiliInfo:
// network, power, display), qui remplace tip; rien n'est sondé en continu.
import QtQuick
import Quickshell

MouseArea {
    id: area
    property var tip
    property string tipInfo
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

    // Panneau ouvert: niri retire le focus clavier au fili-panel dès le clic sur la barre et le clic (appui puis
    // relâchement) est perdu, d'où deux clics. Alors l'action part à l'appui, et le relâchement ne la rejoue pas.
    property bool early: false
    onPressed: m => down(m.button)
    onClicked: m => up(m.button)
    onWheel: w => {
        if (w.angleDelta.y !== 0)
            roll(w.angleDelta.y > 0);
    }

    function down(button) {
        early = FiliShell.anyOpen;
        if (early)
            press(button);
    }
    function up(button) {
        if (early)
            early = false;
        else
            press(button);
    }
    // Clic et molette (appelés aussi par les tests)
    function press(button) {
        FiliTooltip.hide();
        if (button === Qt.LeftButton) {
            FiliTheme.run(click);
            leftClicked();
        } else if (button === Qt.RightButton) {
            FiliTheme.run(rclick);
            rightClicked();
        } else {
            FiliTheme.run(mclick);
            middleClicked();
        }
    }
    function roll(up) {
        if (up) {
            FiliTheme.run(scrollUp);
            wheelUp();
        } else {
            FiliTheme.run(scrollDown);
            wheelDown();
        }
    }
    onContainsMouseChanged: {
        if (!containsMouse) {
            FiliTooltip.hide(area);
            return;
        }
        if (tipInfo) {
            FiliTooltip.show(area, tip || { title: "…" });
            FiliInfo.request(tipInfo);
        } else {
            FiliTooltip.show(area, tip);
        }
    }
    onTipChanged: if (containsMouse && !tipInfo) FiliTooltip.update(area, tip)

    Connections {
        target: FiliInfo
        enabled: area.tipInfo !== "" && area.containsMouse
        function onReady(topic, card) {
            if (topic === area.tipInfo)
                FiliTooltip.update(area, card);
        }
    }
}
