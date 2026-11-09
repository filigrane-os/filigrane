// fili-panel opened by a right click on the fili-bar background: where the bar sits (edge, screens) and the shortcut to
// the Bar page of the settings window (gear of the panel).
import QtQuick
import QtQuick.Layouts
import qs
import qs.controls

ColumnLayout {
    id: view
    // Settings page opened by the gear at the top right of the panel (FiliPanel)
    readonly property string settingsPage: "bar"
    spacing: FiliTheme.space1

    BarPlacement { Layout.fillWidth: true; onChosen: FiliPanel.close() }
}
