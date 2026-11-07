// Settings page "Casier" (fili-settings): the file manager. One setting for now, the resident mode: a copy of Casier
// stays loaded in the background so that it opens at once (`fili-file spare on|off|status`, see spare.rs in the
// fili-file repository). It is a trade of memory for speed, so the cost is stated here next to the switch.
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

ColumnLayout {
    id: view
    spacing: FiliTheme.space1
    property bool resident: false
    readonly property string bin: "/usr/bin/fili-file"

    function setResident(on) {
        resident = on;
        FiliTheme.run(bin + " spare " + (on ? "on" : "off"));
    }

    Process {
        id: read
        running: !FiliTheme.testing
        command: [view.bin, "spare", "status"]
        stdout: StdioCollector {
            onStreamFinished: view.resident = text.trim() === "on"
        }
    }

    Text {
        text: "Casier"
        color: FiliTheme.voile
        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
    }
    PanelSection { divided: false; text: FiliI18n.tr("STARTUP") }
    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: FiliI18n.tr("Open instantly")
            color: FiliTheme.brume
            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
        }
        PanelSwitch {
            objectName: "resident"
            checked: view.resident
            onToggled: view.setResident(!view.resident)
        }
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("Keeps a copy of Casier loaded in the background, so that its window appears in about 0.2 s instead of 0.4 s. It uses about 35 MB of memory, as long as it is on; a new copy loads each time you open Casier. Off: nothing runs while Casier is closed.")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
}
