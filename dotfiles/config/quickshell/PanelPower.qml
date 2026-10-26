// fili-panel alimentation: batterie (fili-info power), luminosité de l'écran (brightnessctl), accès au menu système.
// Pas de profils d'énergie: Void n'a pas power-profiles-daemon (voir la skill filigrane pour tlp/cpupower).
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

ColumnLayout {
    id: view
    spacing: 4
    property real brightness: -1

    function readBrightness() {
        bl.running = true;
    }
    Component.onCompleted: readBrightness()
    Process {
        id: bl
        // Écran interne seulement (pas la rétro-éclairage de la Touch Bar)
        command: ["sh", "-c", "brightnessctl -m -c backlight -d '*' info 2>/dev/null | grep -v appletb | head -1 | cut -d, -f4 | tr -d %"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseInt(text);
                view.brightness = isNaN(v) ? -1 : v / 100;
            }
        }
    }
    PanelInfo { title: true; cmd: FiliTheme.bin + "/fili-info power" }
    PanelSection { visible: view.brightness >= 0; text: "LUMINOSITÉ" }
    PanelSlider {
        objectName: "brightness"
        visible: view.brightness >= 0
        glyph: ""
        value: Math.max(0, view.brightness)
        onMoved: v => {
            view.brightness = Math.max(0.01, v);
            FiliTheme.run("brightnessctl -q set " + Math.max(1, Math.round(v * 100)) + "%");
        }
    }
    PanelButton {
        Layout.topMargin: 6
        glyph: ""
        label: "Menu système (verrouiller, veille…)"
        dim: true
        onClicked: { FiliPanel.close(); FiliTheme.run("setsid -f " + FiliTheme.bin + "/menu system"); }
    }
}
