// fili-panel opened by a right click on the fili-bar background: where the bar sits (edge, screens) and the shortcut to
// the Bar page of the settings window.
import QtQuick
import QtQuick.Layouts
import qs
import qs.controls

ColumnLayout {
    id: view
    spacing: FiliTheme.space1

    BarPlacement { Layout.fillWidth: true; onChosen: FiliPanel.close() }
    PanelSection { text: FiliI18n.tr("MORE") }
    PanelButton {
        objectName: "open-settings"
        glyph: ""
        label: FiliI18n.tr("Settings…")
        onClicked: {
            FiliPanel.close();
            FiliSettings.show("bar");
        }
    }
}
