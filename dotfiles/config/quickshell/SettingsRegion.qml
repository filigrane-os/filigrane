// Settings page "Region" (fili-settings): how dates, numbers, money, units and paper are written, apart from the language
// (page Language) and from the keyboard (fili-keymap, the keyboard panel). `fili-region list` gives the regions that are
// installed, `fili-region set` changes it (the shell follows at once, applications opened afterwards too). The time zone is
// chosen in a searchable list (`fili-region zones`); `fili-region zone-set` changes the system file through polkit.
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.controls

ColumnLayout {
    id: view
    spacing: FiliTheme.space1
    // [{locale, code, current}] from `fili-region list`, and the time zone from `fili-region zone`
    property var regions: []
    property string zone: ""
    // [{id, name, detail}] from `fili-region zones`, for the picker
    property var zones: []
    property bool choosingZone: false
    // "" = the formats follow the language
    readonly property string region: FiliI18n.region
    // Example of a date, a number and an amount in the region shown now
    readonly property var sample: new Date(2026, 11, 24, 18, 30)

    function pick(value) {
        FiliTheme.run(FiliTheme.bin + "/fili-region set " + value);
    }
    function setZone(zone) {
        view.zone = zone;
        choosingZone = false;
        FiliTheme.run(FiliTheme.bin + "/fili-region zone-set " + zone);
    }
    function nameOf(code) {
        const l = Qt.locale(code);
        return l.nativeLanguageName.length > 0 ? l.nativeLanguageName.charAt(0).toUpperCase() + l.nativeLanguageName.slice(1) + " (" + l.nativeCountryName + ")" : code;
    }

    Process {
        id: list
        running: !FiliTheme.testing
        command: [FiliTheme.bin + "/fili-region", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    view.regions = JSON.parse(text);
                } catch (e) {}
            }
        }
    }
    Process {
        running: !FiliTheme.testing
        command: [FiliTheme.bin + "/fili-region", "zone"]
        stdout: StdioCollector {
            onStreamFinished: view.zone = text.trim()
        }
    }

    Process {
        running: !FiliTheme.testing
        command: [FiliTheme.bin + "/fili-region", "zones"]
        stdout: StdioCollector {
            onStreamFinished: view.zones = text.split("\n").filter(l => l !== "").map(l => {
                const f = l.split("\t");
                return { id: f[0], name: f[0].replace(/_/g, " "), detail: [f[1], f[2]].filter(x => x).join(" · ") };
            })
        }
    }
    Text {
        text: FiliI18n.tr("Region")
        color: FiliTheme.voile
        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("How dates, numbers, money, units and paper are written. It is independent of the language of the interface and of the keyboard.")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
    PanelSection { divided: false; text: FiliI18n.tr("FORMATS") }
    PanelSelect {
        objectName: "region"
        Layout.fillWidth: true
        model: [{ label: FiliI18n.tr("Same as the language"), value: "language" }].concat(view.regions.map(r => ({ label: view.nameOf(r.code), value: r.code })))
        current: view.region === "" ? "language" : view.region
        onPicked: v => view.pick(v)
    }
    Text {
        objectName: "region-sample"
        Layout.fillWidth: true
        Layout.topMargin: FiliTheme.space1
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("Example: %1 · %2", FiliI18n.locale.toString(view.sample, "dddd d MMMM yyyy, HH:mm"), FiliI18n.locale.toString(1234567.89, "f", 2))
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
    PanelSection { text: FiliI18n.tr("TIME ZONE") }
    RowLayout {
        Layout.fillWidth: true
        Text {
            objectName: "zone"
            Layout.fillWidth: true
            text: view.zone.replace(/_/g, " ")
            elide: Text.ElideRight
            color: FiliTheme.brume
            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
        }
        PanelButton {
            objectName: "zone-change"
            label: FiliI18n.tr("Change…")
            onClicked: view.choosingZone = true
        }
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("The time zone belongs to the system: changing it asks for your password, and it is kept in your configuration so that ./bootstrap.sh does not undo it.")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
    AppPicker {
        open: view.choosingZone
        title: FiliI18n.tr("Choose a time zone")
        placeholder: FiliI18n.tr("Search a city or a country code")
        emptyText: FiliI18n.tr("No time zone found")
        entries: view.zones
        onPicked: e => view.setZone(e.id)
        onClosed: view.choosingZone = false
    }
}
