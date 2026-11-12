// Settings page "Quai" (fili-settings): the taskbar, which lists the windows of each screen by workspace. On or off, edge,
// automatic hiding, background and screens; every change is made by `fili-bar taskbar`, which writes [taskbar] of
// ~/.config/filigrane/fili-bar.toml; the Quai re-reads it at once and this page follows (TaskbarLayout).
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.bar
import qs.controls

ColumnLayout {
    id: view
    spacing: FiliTheme.space1
    readonly property string cli: FiliTheme.bin + "/fili-bar"

    Text {
        text: "Quai"
        color: FiliTheme.voile
        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("Every window of the screen by workspace, each with its number. Hold Mod+Alt and type a number to go to its window.")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: FiliTheme.space2
        PanelSwitch {
            objectName: "quai-enabled"
            checked: TaskbarLayout.enabled
            onToggled: FiliTheme.run(view.cli + " taskbar enabled " + (TaskbarLayout.enabled ? "false" : "true"))
        }
        Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: FiliI18n.tr("Show the Quai")
            color: TaskbarLayout.enabled ? FiliTheme.brume : FiliTheme.ardoise
            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
        }
    }
    // Edge, background, hiding and screens: the same block as the right click panel of the Quai
    BarPlacement { Layout.fillWidth: true; target: "taskbar" }
}
