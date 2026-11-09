// Settings page "Language" (fili-settings): the language of the session (fili-lang). The shell, the bar, the menu and
// the scripts switch at once; apps launched afterwards by niri get LANG when the glibc locale is installed.
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.controls

ColumnLayout {
    id: view
    spacing: FiliTheme.space1
    // [{code, name, locale, available, current}] from `fili-lang list`
    property var languages: []
    readonly property var language: languages.find(l => l.code === FiliI18n.lang) ?? null

    function pick(code) {
        FiliTheme.run(FiliTheme.bin + "/fili-lang set " + code);
    }

    Process {
        id: langs
        running: !FiliTheme.testing
        command: [FiliTheme.bin + "/fili-lang", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    view.languages = JSON.parse(text);
                } catch (e) {}
            }
        }
    }
    Connections {
        target: FiliI18n
        function onLangChanged() {
            if (!FiliTheme.testing)
                langs.running = true;
        }
    }

    Text {
        text: FiliI18n.tr("Language")
        color: FiliTheme.voile
        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("The language of the shell, the bar, the menu and the scripts changes at once; apps opened afterwards follow it.")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
    PanelSection { divided: false; text: FiliI18n.tr("LANGUAGE") }
    PanelChips {
        objectName: "language"
        model: view.languages.map(l => ({ label: l.name, value: l.code }))
        current: FiliI18n.lang
        onPicked: v => view.pick(v)
    }
    Text {
        visible: view.language !== null && !view.language.available
        Layout.fillWidth: true
        Layout.topMargin: FiliTheme.space1
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("Dates and other apps: run ./bootstrap.sh to install this language")
        color: FiliTheme.sable
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
}
