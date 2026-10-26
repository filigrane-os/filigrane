// fili-panel luminosité: écran interne et rétroéclairage du clavier (brightnessctl)
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

ColumnLayout {
    id: view
    spacing: 4
    // -1: périphérique absent
    property real screen: -1
    property real keys: -1
    // Veilleuse (wlsunset): allumée quand l'écran est réellement réchauffé (même critère que l'indicateur de la barre)
    property bool night: false

    // Écran interne seulement (pas le rétroéclairage de la Touch Bar)
    readonly property string bin: FiliTheme.bin
    readonly property string screenCmd: "brightnessctl -m -c backlight -d '*' info 2>/dev/null | grep -v appletb | head -1 | cut -d, -f4 | tr -d %"
    readonly property string keysCmd: "brightnessctl -m -d '*kbd_backlight' info 2>/dev/null | head -1 | cut -d, -f4 | tr -d %"

    function read() {
        readScreen.running = true;
        readKeys.running = true;
        readNight.running = true;
    }
    Component.onCompleted: read()
    Process {
        id: readScreen
        command: ["sh", "-c", view.screenCmd]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseInt(text);
                view.screen = isNaN(v) ? -1 : v / 100;
            }
        }
    }
    Process {
        id: readNight
        command: ["sh", "-c", 'exec "$0" night | grep -q \'"class":"active"\'', view.bin + "/bar-status"]
        onExited: code => view.night = code === 0
    }
    Process {
        id: readKeys
        command: ["sh", "-c", view.keysCmd]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseInt(text);
                view.keys = isNaN(v) ? -1 : v / 100;
            }
        }
    }

    Text {
        text: "Luminosité"
        color: FiliTheme.voile
        font { family: FiliTheme.font; pixelSize: 14; weight: Font.Medium }
    }
    PanelSection { visible: view.screen >= 0; text: "ÉCRAN" }
    PanelSlider {
        objectName: "screen"
        visible: view.screen >= 0
        glyph: ""
        value: Math.max(0, view.screen)
        onMoved: v => {
            view.screen = Math.max(0.01, v);
            FiliTheme.run("brightnessctl -q set " + Math.max(1, Math.round(v * 100)) + "%");
        }
    }
    PanelSection { visible: view.keys >= 0; text: "CLAVIER" }
    PanelSlider {
        objectName: "keys"
        visible: view.keys >= 0
        glyph: ""
        value: Math.max(0, view.keys)
        onMoved: v => {
            view.keys = v;
            FiliTheme.run("brightnessctl -q -d '*kbd_backlight' set " + Math.round(v * 100) + "%");
        }
    }
    PanelSection { text: "VEILLEUSE" }
    RowLayout {
        Layout.fillWidth: true
        Text {
            text: "Teinte chaude (4500 K)"
            color: FiliTheme.brume
            Layout.fillWidth: true
            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
        }
        PanelSwitch {
            objectName: "night"
            checked: view.night
            onToggled: {
                view.night = !view.night;
                FiliTheme.run(view.bin + "/bar-toggle night " + (view.night ? "on" : "off"));
            }
        }
    }
    Text {
        visible: view.screen < 0 && view.keys < 0
        text: "Aucun rétroéclairage détecté"
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: FiliTheme.size }
    }
}
