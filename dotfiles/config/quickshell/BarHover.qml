// Zone de clic et de fili-tooltip d'un module de la fili-bar: commandes shell par bouton et molette, ou signaux
// (onLeftClicked...). tip: texte ou fiche (voir FiliTooltip); tipCmd: commande lancée seulement au survol, dont la
// sortie JSON remplace la fiche (fili-info network|power|display), rien n'est sondé en continu.
import QtQuick
import Quickshell
import Quickshell.Io

MouseArea {
    id: area
    property var tip
    property string tipCmd
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
        early = FiliShell.panelOpen;
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
        if (tipCmd) {
            FiliTooltip.show(area, tip || { title: "…" });
            fetch.running = true;
        } else {
            FiliTooltip.show(area, tip);
        }
    }
    onTipChanged: if (containsMouse && !tipCmd) FiliTooltip.update(area, tip)

    Process {
        id: fetch
        command: ["sh", "-c", area.tipCmd]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    FiliTooltip.update(area, JSON.parse(text));
                } catch (e) {}
            }
        }
    }
}
