// fili-panel alimentation: batterie (fili-info power), actions système (verrouiller, veille, quitter, redémarrer, éteindre).
// Pas de profils d'énergie: Void n'a pas power-profiles-daemon (voir la skill filigrane pour tlp/cpupower).
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: view
    spacing: 4

    PanelInfo { title: true; cmd: FiliTheme.bin + "/fili-info power" }
    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 4
        implicitHeight: 1
        color: FiliTheme.nuit3
    }
    PanelSection { text: "SYSTÈME" }
    // Actions du menu système (menu system <action>: confirmation demandée pour quitter, redémarrer et éteindre)
    Repeater {
        model: [["", "Verrouiller", "Lock"], ["", "Veille", "Sleep"], ["", "Quitter la session", "Log out"], ["", "Redémarrer", "Reboot"], ["", "Éteindre", "Power off"]]
        PanelButton {
            required property var modelData
            objectName: "system"
            glyph: modelData[0]
            label: modelData[1]
            onClicked: { FiliPanel.close(); FiliTheme.run("setsid -f " + FiliTheme.bin + "/menu system '" + modelData[2] + "'"); }
        }
    }
}
