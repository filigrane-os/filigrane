// Settings page "Default applications" (fili-settings): which program opens which kind of thing (browser, mail, folders,
// music...). `fili-defaults list` gives the categories and their current application, `fili-defaults candidates ID` the
// applications that can take one, `fili-defaults set ID DESKTOP_ID` writes the choice in ~/.config/mimeapps.list, which
// xdg-open, the portals and the toolkits read.
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.controls

ColumnLayout {
    id: view
    spacing: FiliTheme.space1
    // [{id, name, current}] from `fili-defaults list`
    property var categories: []

    function pick(id, desktop) {
        categories = categories.map(c => c.id === id ? { id: c.id, name: c.name, current: desktop } : c);
        FiliTheme.run(FiliTheme.bin + "/fili-defaults set " + id + " " + desktop);
    }

    Process {
        id: list
        running: !FiliTheme.testing
        command: [FiliTheme.bin + "/fili-defaults", "list"]
        stdout: StdioCollector {
            onStreamFinished: view.categories = text.split("\n").filter(l => l !== "").map(l => {
                const f = l.split("\t");
                return { id: f[0], name: f[1] ?? f[0], current: f[2] ?? "" };
            })
        }
    }

    Text {
        text: FiliI18n.tr("Default applications")
        color: FiliTheme.voile
        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("The program that opens each kind of file or link, for every application that follows the system rules.")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
    PanelSection { divided: false; text: FiliI18n.tr("OPEN WITH") }
    Repeater {
        model: view.categories
        delegate: RowLayout {
            id: row
            required property var modelData
            // [{label, value}] from `fili-defaults candidates ID`
            property var choices: []
            Layout.fillWidth: true
            Layout.topMargin: FiliTheme.space1

            Process {
                running: !FiliTheme.testing
                command: [FiliTheme.bin + "/fili-defaults", "candidates", row.modelData.id]
                stdout: StdioCollector {
                    onStreamFinished: row.choices = text.split("\n").filter(l => l !== "").map(l => {
                        const f = l.split("\t");
                        return { label: f[1] ?? f[0], value: f[0] };
                    })
                }
            }
            Text {
                Layout.fillWidth: true
                text: row.modelData.name
                elide: Text.ElideRight
                color: FiliTheme.brume
                font { family: FiliTheme.font; pixelSize: FiliTheme.size }
            }
            PanelSelect {
                objectName: "default-" + row.modelData.id
                Layout.preferredWidth: 200
                model: row.choices
                current: row.modelData.current
                placeholder: FiliI18n.tr("None")
                onPicked: v => view.pick(row.modelData.id, v)
            }
        }
    }
}
