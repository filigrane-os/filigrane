// Settings page "Appearance" (fili-settings): the interface font of the system, the accent colour and the headers of the fili-* windows.
// Both are written into ~/.config/filigrane/theme.toml by `fili-theme font` and `fili-theme header` (the file can be
// edited by hand: [theme] font, [window] header); the shell, GTK, Chrome and the fili-* applications follow it live.
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.controls

ColumnLayout {
    id: view
    spacing: FiliTheme.space1
    // Families offered by `fili-theme fonts` (Latin text fonts); the current font is always in the list
    property var families: []
    readonly property string defaultFont: "Jost"
    readonly property var fontModel: {
        const names = families.slice();
        for (const n of [defaultFont, FiliTheme.font])
            if (!names.includes(n))
                names.push(n);
        names.sort((a, b) => a.localeCompare(b));
        return names.map(n => ({ label: n === defaultFont ? n + " (" + FiliI18n.tr("default") + ")" : n, value: n }));
    }

    function pickFont(name) {
        FiliTheme.run(FiliTheme.bin + "/fili-theme font " + (name === defaultFont ? "default" : "'" + name + "'"));
    }
    function setHeaders(on) {
        FiliTheme.run(FiliTheme.bin + "/fili-theme header " + (on ? "on" : "off"));
    }
    function setFooters(on) {
        FiliTheme.run(FiliTheme.bin + "/fili-theme footer " + (on ? "on" : "off"));
    }

    Process {
        running: !FiliTheme.testing
        command: [FiliTheme.bin + "/fili-theme", "fonts"]
        stdout: StdioCollector {
            onStreamFinished: view.families = text.split("\n").map(l => l.trim()).filter(l => l)
        }
    }

    Text {
        text: FiliI18n.tr("Appearance")
        color: FiliTheme.voile
        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
    }

    PanelSection { divided: false; text: FiliI18n.tr("SYSTEM FONT") }
    PanelSelect {
        objectName: "font"
        Layout.fillWidth: true
        model: view.fontModel
        current: FiliTheme.font
        onPicked: v => view.pickFont(v)
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("The font of the shell, the bar, the Filigrane apps, GTK apps and Chrome's interface. Apps already open keep the old one until they are reopened.")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }

    // Accent colour (fili-theme accent): niri window focus, selections in the shell and fili-file
    PanelSection { text: FiliI18n.tr("ACCENT COLOR") }
    Row {
        id: accents
        objectName: "accent"
        spacing: FiliTheme.space2
        readonly property var names: ["voile", "ardoise", "sauge", "sable", "cendre", "brume"]
        readonly property var labels: ({ voile: FiliI18n.tr("Veil"), ardoise: FiliI18n.tr("Slate"), sauge: FiliI18n.tr("Sage"), sable: FiliI18n.tr("Sand"), cendre: FiliI18n.tr("Ash"), brume: FiliI18n.tr("Mist") })
        property int cursor: Math.max(0, names.indexOf(FiliTheme.accentName))
        function pick(n) {
            FiliTheme.accent = n;
            FiliTheme.run(FiliTheme.bin + "/fili-theme accent " + n);
        }
        activeFocusOnTab: true
        Keys.onLeftPressed: e => { if (e.modifiers & Qt.ShiftModifier) { e.accepted = false; return; } FiliShell.keyNav = true; cursor = Math.max(0, cursor - 1); }
        Keys.onRightPressed: e => { if (e.modifiers & Qt.ShiftModifier) { e.accepted = false; return; } FiliShell.keyNav = true; cursor = Math.min(names.length - 1, cursor + 1); }
        Keys.onReturnPressed: pick(names[cursor])
        Keys.onSpacePressed: pick(names[cursor])
        Repeater {
            model: accents.names
            Rectangle {
                id: dot
                required property string modelData
                required property int index
                readonly property bool on: modelData === FiliTheme.accentName
                width: 22
                height: 22
                radius: width / 2
                color: "transparent"
                border.width: on ? 2 : 0
                border.color: FiliTheme.brume
                Rectangle {
                    anchors.centerIn: parent
                    width: 14
                    height: 14
                    radius: 7
                    color: FiliTheme.accentTones[dot.modelData][FiliTheme.light ? 2 : 0]
                }
                FocusRing {
                    shown: accents.activeFocus && accents.cursor === dot.index
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: accents.pick(dot.modelData)
                }
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: accents.labels[FiliTheme.accentName]
            color: FiliTheme.brume2
            font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
        }
    }

    PanelSection { text: FiliI18n.tr("WINDOWS") }
    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: FiliI18n.tr("Show application headers")
            color: FiliTheme.brume
            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
        }
        PanelSwitch {
            objectName: "headers"
            checked: FiliTheme.headers
            onToggled: view.setHeaders(!FiliTheme.headers)
        }
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("Off: the Filigrane apps open without their header (navigation, title, search and window buttons) to give the content the whole window. Everything stays reachable from the keyboard and the menu of the bar; Ctrl+F shows the search. An app can also be launched with --no-header or --header.")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: FiliTheme.space2
        Text {
            Layout.fillWidth: true
            text: FiliI18n.tr("Show application status bars")
            color: FiliTheme.brume
            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
        }
        PanelSwitch {
            objectName: "footers"
            checked: FiliTheme.footers
            onToggled: view.setFooters(!FiliTheme.footers)
        }
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("Off: the status bar at the bottom of the Filigrane apps (place, counts) is hidden. It still appears while it has something to say: an operation in progress, an error or a notice. An app can also be launched with --no-footer or --footer.")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
}
