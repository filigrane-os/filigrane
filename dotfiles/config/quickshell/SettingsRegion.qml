// Settings page "Region" (fili-settings): how dates, numbers, money, units and paper are written, apart from the language
// (page Language) and from the keyboard (fili-keymap, the keyboard panel). `fili-region list` gives the regions that are
// installed, `fili-region set` changes it (the shell follows at once, applications opened afterwards too).
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
    // "" = the formats follow the language
    readonly property string region: FiliI18n.region
    // Example of a date, a number and an amount in the region shown now
    readonly property var sample: new Date(2026, 11, 24, 18, 30)

    function pick(value) {
        FiliTheme.run(FiliTheme.bin + "/fili-region set " + value);
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
    Text {
        Layout.fillWidth: true
        text: view.zone
        elide: Text.ElideRight
        color: FiliTheme.brume
        font { family: FiliTheme.font; pixelSize: FiliTheme.size }
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("The time zone belongs to the system: set TIMEZONE in config.env, then run ./bootstrap.sh.")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
}
