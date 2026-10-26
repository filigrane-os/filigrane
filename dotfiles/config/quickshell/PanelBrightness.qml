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

    // Écran interne seulement (pas le rétroéclairage de la Touch Bar)
    readonly property string screenCmd: "brightnessctl -m -c backlight -d '*' info 2>/dev/null | grep -v appletb | head -1 | cut -d, -f4 | tr -d %"
    readonly property string keysCmd: "brightnessctl -m -d '*kbd_backlight' info 2>/dev/null | head -1 | cut -d, -f4 | tr -d %"

    function read() {
        readScreen.running = true;
        readKeys.running = true;
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
    Text {
        visible: view.screen < 0 && view.keys < 0
        text: "Aucun rétroéclairage détecté"
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: FiliTheme.size }
    }
}
