// fili-panel opened by a right click on a fili-bar module: the commands of the module (BarModule.contextMenu), one row each.
// Items: [{ glyph, text, cmd }] (cmd = shell command), { glyph, text, settings: "page" } (page of the settings window) or
// { glyph, text, run: function }.
// The first row opens the application of the module when it has one.
import QtQuick
import QtQuick.Layouts
import qs
import qs.controls

ColumnLayout {
    id: view
    spacing: FiliTheme.space1

    Repeater {
        model: FiliPanel.ctxItems
        PanelButton {
            required property var modelData
            required property int index
            objectName: "ctx-" + index
            glyph: modelData.glyph ?? ""
            label: modelData.text
            sel: index === 0 && (modelData.app ?? false)
            onClicked: {
                FiliPanel.close();
                if (modelData.run)
                    modelData.run();
                else if (modelData.settings !== undefined)
                    FiliSettings.show(modelData.settings);
                else
                    FiliTheme.run(modelData.cmd);
            }
        }
    }
}
