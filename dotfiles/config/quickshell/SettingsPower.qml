// Settings page "Power" (fili-settings): how long the computer waits, without activity, before it locks, turns the
// screen off and goes to sleep, plugged in and on battery (two sets of delays). The delays live in
// ~/.config/filigrane/power.toml ([idle] plugged in, [battery]) and are applied by `bar-toggle idle set` (swayidle restarted
// at once, unless caffeine is on); the power module of the bar switches to the other set when the cable is plugged or
// unplugged. Without a battery only the plugged-in set exists. Caffeine stays in the fili-panel (PowerPanel): it is
// frequent, instant and reversible.
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.controls

ColumnLayout {
    id: view
    spacing: FiliTheme.space1
    // The set being edited ("ac" = plugged in, "battery") and the one in use right now
    property string source: "ac"
    property string inUse: "ac"
    property bool hasBattery: false
    // Delays in seconds, 0 = never; read from `bar-toggle idle get SOURCE`
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
    readonly property var sourceChoices: [{ label: FiliI18n.tr("Plugged in"), value: "ac" }, { label: FiliI18n.tr("On battery"), value: "battery" }]

    function apply(l, s, z) {
        lock = l;
        screenOff = s;
        sleep = z;
        FiliTheme.run(FiliTheme.bin + "/bar-toggle idle set " + source + " " + l + " " + s + " " + z);
    }
    function pick(src) {
        source = src;
        reread.running = false;
        reread.running = !FiliTheme.testing;
    }

    // Source in use, battery present (line 1: ac|battery, line 2: a battery path or nothing)
    Process {
        id: probe
        running: !FiliTheme.testing
        command: ["sh", "-c", FiliTheme.bin + "/bar-toggle idle source; ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                view.inUse = l[0] === "battery" ? "battery" : "ac";
                view.hasBattery = l.length > 1 && l[1] !== "";
                view.pick(view.hasBattery ? view.inUse : "ac");
            }
        }
    }
    Process {
        id: reread
        command: [FiliTheme.bin + "/bar-toggle", "idle", "get", view.source]
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
        text: FiliI18n.tr("What the computer does when you stop using it: lock, turn the screen off, sleep. Each step waits for its own time without activity; plugged in and on battery have their own times, and the right ones apply by themselves when you plug or unplug. Caffeine, in the power panel, pauses them all.")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }

    PanelSection { divided: false; visible: view.hasBattery; text: FiliI18n.tr("POWER SOURCE") }
    PanelChips {
        objectName: "source"
        visible: view.hasBattery
        model: view.sourceChoices
        current: view.source
        onPicked: v => view.pick(v)
    }
    Text {
        Layout.fillWidth: true
        visible: view.hasBattery
        text: view.source === view.inUse ? FiliI18n.tr("These delays are in use now.") : FiliI18n.tr("These delays apply when the power source changes.")
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
