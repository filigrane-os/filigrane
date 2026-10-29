// fili-panel alimentation: batterie (FiliInfo power), actions système (verrouiller, veille, quitter, redémarrer, éteindre).
// Pas de profils d'énergie: Void n'a pas power-profiles-daemon (voir la skill filigrane pour tlp/cpupower).
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

ColumnLayout {
    id: view
    spacing: FiliTheme.space1
    // Caféine: verrouillage automatique coupé (swayidle arrêté, voir bar-toggle idle)
    property bool caffeine: false

    Component.onCompleted: readIdle.running = true
    Process {
        id: readIdle
        command: ["sh", "-c", "pgrep -x swayidle >/dev/null"]
        onExited: code => view.caffeine = code !== 0
    }

    PanelInfo { title: true; topic: "power" }
    PanelSection { text: FiliI18n.tr("CAFFEINE") }
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: FiliTheme.space1
        Layout.leftMargin: FiliTheme.space2
        Layout.rightMargin: FiliTheme.space2
        spacing: FiliTheme.space2
        Text {
            text: ""
            color: view.caffeine ? FiliTheme.sable : FiliTheme.brume
            Layout.preferredWidth: 18
            horizontalAlignment: Text.AlignHCenter
            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
        }
        Text {
            text: FiliI18n.tr("Caffeine (no auto lock)")
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
    PanelSection { text: FiliI18n.tr("SYSTEM") }
    // Actions du menu système (menu system <action>: confirmation demandée pour quitter, redémarrer et éteindre)
    Repeater {
        model: [["", FiliI18n.tr("Lock"), "Lock"], ["", FiliI18n.tr("Sleep"), "Sleep"], ["", FiliI18n.tr("Log out"), "Log out"], ["", FiliI18n.tr("Reboot"), "Reboot"], ["", FiliI18n.tr("Power off"), "Power off"]]
        PanelButton {
            required property var modelData
            objectName: "system"
            glyph: modelData[0]
            label: modelData[1]
            onClicked: { FiliPanel.close(); FiliTheme.run("setsid -f " + FiliTheme.bin + "/menu system '" + modelData[2] + "'"); }
        }
    }
}
