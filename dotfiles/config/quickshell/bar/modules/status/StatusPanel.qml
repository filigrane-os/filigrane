// fili-panel status: one row per active indicator (BarState.statusRows); the ones that have an action (stop the
// recording, leave airplane mode, update) run it on click
import QtQuick
import QtQuick.Layouts
import qs.bar
import qs.controls
import qs

ColumnLayout {
    id: view
    spacing: FiliTheme.space1

    PanelSection { text: FiliI18n.tr("STATUS") }
    Repeater {
        model: BarState.statusRows
        PanelButton {
            required property var modelData
            objectName: "status-" + modelData.key
            glyph: modelData.glyph
            label: modelData.title
            detail: modelData.detail
            dim: modelData.click === ""
            onClicked: {
                if (modelData.click === "")
                    return;
                FiliPanel.close();
                FiliTheme.run(modelData.click);
            }
        }
    }
    Text {
        visible: BarState.statusRows.length === 0
        text: FiliI18n.tr("Nothing to report")
        Layout.fillWidth: true
        Layout.leftMargin: FiliTheme.space2
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList }
    }
}
