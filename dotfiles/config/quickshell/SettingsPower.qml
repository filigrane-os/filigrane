// Settings page "Power" (fili-settings): how long the computer waits, without activity, before it locks, turns the
// screen off and goes to sleep. The delays live in ~/.config/filigrane/power.toml and are applied by
// `bar-toggle idle set` (swayidle restarted at once, unless caffeine is on). Caffeine stays in the fili-panel
// (PowerPanel): it is frequent, instant and reversible.
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.controls

ColumnLayout {
    id: view
    spacing: FiliTheme.space1
    // Delays in seconds, 0 = never; read from `bar-toggle idle get`
    property int lock: 300
    property int screenOff: 600
    property int sleep: 0
    property bool ready: false

    function minutes(list) {
        return list.map(m => ({ label: m === 0 ? FiliI18n.tr("Never") : FiliI18n.tr("%1 min", m), value: m * 60 }));
    }
    readonly property var lockChoices: minutes([1, 2, 5, 10, 15, 30, 0])
    readonly property var screenChoices: minutes([1, 2, 5, 10, 15, 30, 0])
    readonly property var sleepChoices: minutes([15, 30, 60, 120, 0])

    function apply(l, s, z) {
        lock = l;
        screenOff = s;
        sleep = z;
        FiliTheme.run(FiliTheme.bin + "/bar-toggle idle set " + l + " " + s + " " + z);
    }

    Process {
        id: read
        running: !FiliTheme.testing
        command: [FiliTheme.bin + "/bar-toggle", "idle", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = text.trim().split(/\s+/).map(Number);
                if (v.length === 3 && v.every(n => !isNaN(n))) {
                    view.lock = v[0];
                    view.screenOff = v[1];
                    view.sleep = v[2];
                }
                view.ready = true;
            }
        }
    }

    Text {
        text: FiliI18n.tr("Power")
        color: FiliTheme.voile
        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("Time without activity before each step. Caffeine, in the power panel, pauses them all.")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }

    PanelSection { divided: false; text: FiliI18n.tr("LOCK AFTER") }
    PanelChips {
        objectName: "lock"
        model: view.lockChoices
        current: view.lock
        onPicked: v => view.apply(v, view.screenOff, view.sleep)
    }
    PanelSection { divided: false; text: FiliI18n.tr("TURN THE SCREEN OFF AFTER") }
    PanelChips {
        objectName: "screen-off"
        model: view.screenChoices
        current: view.screenOff
        onPicked: v => view.apply(view.lock, v, view.sleep)
    }
    PanelSection { divided: false; text: FiliI18n.tr("SLEEP AFTER") }
    PanelChips {
        objectName: "sleep"
        model: view.sleepChoices
        current: view.sleep
        onPicked: v => view.apply(view.lock, view.screenOff, v)
    }
    Text {
        Layout.fillWidth: true
        Layout.topMargin: FiliTheme.space1
        visible: view.sleep > 0
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("The screen locks before going to sleep. On some laptops a long sleep on battery can lose the session.")
        color: FiliTheme.sable
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
}
