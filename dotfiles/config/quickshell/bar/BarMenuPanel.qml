// fili-panel opened by a right click on the background of the fili-bar or of the Quai (the same panel for both): where the bar
// sits (edge, background, screens; hiding for the Quai) and the shortcut to its page of the settings window (gear of the panel).
import QtQuick
import QtQuick.Layouts
import qs
import qs.controls

ColumnLayout {
    id: view
    // Settings page opened by the gear at the top right of the panel (FiliPanel)
    readonly property string settingsPage: FiliPanel.menuTarget === "taskbar" ? "quai" : "bar"
    spacing: FiliTheme.space1

    BarPlacement { Layout.fillWidth: true; target: FiliPanel.menuTarget; onChosen: FiliPanel.close() }
}
