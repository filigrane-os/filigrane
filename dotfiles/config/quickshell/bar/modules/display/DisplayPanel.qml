// fili-panel display: the frequent, instant and reversible settings of the screen: brightness of the internal display
// (read by bar-stats, set by brightnessctl), dark or light appearance (fili-theme) and night light. Everything you set
// once (layout of the outputs, resolution, refresh rate, scale, rotation, VRR, profile, accent colour) lives in the
// Display page of fili-settings (SettingsDisplay), one click away from the foot of this panel.
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.controls
import qs

ColumnLayout {
    id: view
    spacing: FiliTheme.space1
    property real screen: -1

    Component.onCompleted: {
        // Brightness of the internal display (display stat of bar-stats, in %), -1: none
        const b = FiliShell.stats.display?.screen ?? -1;
        screen = b < 0 ? -1 : b / 100;
        readNight.running = true;
    }
    // Night light (wlsunset): on when the screen is really warmed (same criterion as bar-status)
    property bool night: false
    Process {
        id: readNight
        command: ["sh", "-c", 'exec "$0" night | grep -q \'"class":"active"\'', FiliTheme.bin + "/bar-status"]
        onExited: code => view.night = code === 0
    }

    Text {
        text: FiliI18n.tr("Displays")
        color: FiliTheme.voile
        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
    }

    PanelSection { visible: view.screen >= 0; text: FiliI18n.tr("BRIGHTNESS") }
    PanelSlider {
        objectName: "screen"
        visible: view.screen >= 0
        glyph: ""
        value: Math.max(0, view.screen)
        onMoved: v => {
            view.screen = Math.max(0.01, v);
            FiliTheme.run("brightnessctl -q set " + Math.max(1, Math.round(v * 100)) + "%; " + FiliTheme.bin + "/fili-shell bar refresh 23");
        }
    }

    // Dark (default) or light mode: shell, GTK, browser (portal), foot, niri, wallpaper (fili-theme)
    PanelSection { text: FiliI18n.tr("APPEARANCE") }
    PanelChips {
        objectName: "theme"
        model: [{ label: FiliI18n.tr("Dark"), value: "dark" }, { label: FiliI18n.tr("Light"), value: "light" }]
        current: FiliTheme.mode
        onPicked: v => {
            FiliTheme.mode = v;
            FiliTheme.run(FiliTheme.bin + "/fili-theme " + v);
        }
    }

    PanelSection { text: FiliI18n.tr("NIGHT LIGHT") }
    RowLayout {
        Layout.fillWidth: true
        Text {
            text: FiliI18n.tr("Warm tint (4500 K)")
            color: FiliTheme.brume
            Layout.fillWidth: true
            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
        }
        PanelSwitch {
            objectName: "night"
            checked: view.night
            onToggled: {
                view.night = !view.night;
                FiliTheme.run(FiliTheme.bin + "/bar-toggle night " + (view.night ? "on" : "off"));
            }
        }
    }

    // Foot: the rarely changed settings are in the settings window, on the page of this module
    PanelSection { text: FiliI18n.tr("MORE") }
    PanelButton {
        objectName: "open-settings"
        glyph: ""
        label: FiliI18n.tr("Display settings…")
        onClicked: FiliSettings.show("display")
    }
}
