// fili-panel alimentation: batterie (fili-info power), actions système (verrouiller, veille, quitter, redémarrer, éteindre).
// Pas de profils d'énergie: Void n'a pas power-profiles-daemon (voir la skill filigrane pour tlp/cpupower).
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

ColumnLayout {
    id: view
    spacing: 4
    // Caféine: verrouillage automatique coupé (swayidle arrêté, voir bar-toggle idle)
    property bool caffeine: false

    Component.onCompleted: readIdle.running = true
    Process {
        id: readIdle
        command: ["sh", "-c", "pgrep -x swayidle >/dev/null"]
        onExited: code => view.caffeine = code !== 0
    }

    PanelInfo { title: true; cmd: FiliTheme.bin + "/fili-info power" }
    PanelSection { text: "CAFÉINE" }
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        spacing: 8
        Text {
            text: ""
            color: view.caffeine ? FiliTheme.sable : FiliTheme.brume
            Layout.preferredWidth: 18
            horizontalAlignment: Text.AlignHCenter
            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
        }
        Text {
            text: "Caféine (pas de verrouillage auto)"
            color: FiliTheme.brume
            Layout.fillWidth: true
            elide: Text.ElideRight
            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
        }
        PanelSwitch {
            objectName: "caffeine"
            checked: view.caffeine
            onToggled: {
                view.caffeine = !view.caffeine;
                FiliTheme.run(FiliTheme.bin + "/bar-toggle idle");
            }
        }
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
