pragma Singleton
// fili-audio-switch: when a new audio output appears (Bluetooth headset connected, HDMI screen, USB DAC...), a small
// modal asks whether to switch to it, with a checkbox "Always do this for this device". The remembered choice
// ("switch" or "keep") lives in ~/.local/state/filigrane/audio-switch.json, keyed by device (Bluetooth address or node
// name); a remembered device is handled silently. Nothing is asked for outputs present at startup.
// Keys: Enter = switch, Esc = keep the current output, Space = toggle the checkbox.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import qs.controls

Singleton {
    id: sw
    // Output being proposed (PwNode) or null; its device key and the checkbox state
    property var candidate: null
    property bool remember: false
    // device key -> "switch" | "keep"
    property var choices: ({})
    // Device keys of the outputs seen at the previous check
    property var known: null
    readonly property bool open: candidate !== null
    readonly property string stateFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/filigrane/audio-switch.json"

    readonly property var nodes: Pipewire.nodes.values
    // Real outputs only: no streams, no filter-chain sinks (the T2 speaker DSP is one)
    readonly property var sinks: nodes.filter(n => n.audio && n.isSink && !n.isStream && n.properties["media.class"] === "Audio/Sink"
        && n.properties["device.api"] !== "dsp" && !n.properties["node.virtual"])
    PwObjectTracker { objects: sw.nodes }

    function key(n) {
        const p = n.properties;
        return p["api.bluez5.address"] || p["device.name"] || p["node.name"] || n.name;
    }
    function label(n) {
        return n.description || n.nickname || n.name;
    }

    FileView {
        path: FiliTheme.testing ? "" : sw.stateFile
        printErrors: false
        onLoaded: {
            try {
                sw.choices = JSON.parse(text());
            } catch (e) {
                sw.choices = ({});
            }
        }
        onLoadFailed: sw.choices = ({})
        id: store
    }
    function save() {
        if (FiliTheme.testing)
            return;
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s" "$2" > "$1"', "sh", sw.stateFile, JSON.stringify(sw.choices)]);
    }

    function switchTo(n) {
        Pipewire.preferredDefaultAudioSink = n;
    }
    function answer(doSwitch) {
        const n = candidate;
        if (!n)
            return;
        if (doSwitch)
            switchTo(n);
        if (remember) {
            const c = Object.assign({}, choices);
            c[key(n)] = doSwitch ? "switch" : "keep";
            choices = c;
            save();
        }
        candidate = null;
        remember = false;
    }

    // An output is "present" when its node exists and its active port is not reported unplugged: a jack headphone
    // keeps its node and only flips the port availability, so ports (pactl) decide, not node creation.
    // Checked when the node list changes and on PulseAudio-compatible events (pactl subscribe), after a settle time
    // (a Bluetooth sink appears before its properties).
    onSinksChanged: settle.restart()
    Timer {
        id: settle
        interval: 600
        onTriggered: {
            if (Pipewire.ready && !FiliTheme.testing) {
                ports.running = false;
                ports.running = true;
            }
        }
    }
    Process {
        id: ports
        command: ["pactl", "-f", "json", "list", "sinks"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list = [];
                try {
                    list = JSON.parse(text);
                } catch (e) {}
                const present = {};
                for (const s of list) {
                    const port = (s.ports ?? []).find(p => p.name === s.active_port);
                    if (port && port.availability === "not available")
                        continue;
                    const n = sw.sinks.find(n => n.name === s.name);
                    if (n)
                        present[sw.key(n)] = n;
                }
                sw.found(present);
            }
        }
    }
    Process {
        id: events
        running: !FiliTheme.testing
        command: ["pactl", "subscribe"]
        stdout: SplitParser {
            onRead: line => {
                if (/'(change|new)' on (card|sink) /.test(line))
                    settle.restart();
            }
        }
        onExited: retry.start()
    }
    Timer {
        id: retry
        interval: 5000
        onTriggered: events.running = true
    }
    // Present outputs (key -> PwNode): propose or apply the choice for those that were not present before
    function found(now) {
        const before = known;
        known = Object.keys(now);
        if (before === null)
            return;
        for (const k of known) {
            const n = now[k];
            if (before.indexOf(k) >= 0 || n.id === Pipewire.defaultAudioSink?.id)
                continue;
            const c = choices[k];
            if (c === "switch")
                switchTo(n);
            else if (c !== "keep" && candidate === null)
                candidate = n;
        }
    }
    // The proposed output vanished: close the modal
    onNodesChanged: if (candidate && sinks.every(n => n.id !== candidate.id)) { candidate = null; remember = false; }
    Component.onCompleted: settle.restart()

    PanelWindow {
        visible: sw.open && !FiliTheme.testing
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "fili-audio-switch"
        WlrLayershell.keyboardFocus: sw.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "#99101419"

        MouseArea { anchors.fill: parent; onPressed: sw.answer(false) }
        FocusScope {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: sw.answer(false)
            Keys.onReturnPressed: sw.answer(true)
            Keys.onEnterPressed: sw.answer(true)
            Keys.onSpacePressed: sw.remember = !sw.remember
            Rectangle {
                anchors.centerIn: parent
                width: 380
                height: col.implicitHeight + 2 * FiliTheme.space6
                color: FiliTheme.nuit
                border { color: FiliTheme.border; width: FiliTheme.borderWidth }
                radius: FiliTheme.radiusWindow
                MouseArea { anchors.fill: parent }
                ColumnLayout {
                    id: col
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: FiliTheme.space6 }
                    spacing: FiliTheme.space3
                    RowLayout {
                        spacing: FiliTheme.space3
                        Text {
                            text: FiliTheme.sinkGlyph(sw.candidate?.properties) || ""
                            color: FiliTheme.voile
                            font { family: FiliTheme.font; pixelSize: 28 }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                Layout.fillWidth: true
                                text: FiliI18n.tr("New audio output")
                                color: FiliTheme.voile
                                font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: sw.candidate ? sw.label(sw.candidate) : ""
                                color: FiliTheme.brume
                                elide: Text.ElideRight
                                font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: FiliI18n.tr("Switch the sound to this output?")
                        color: FiliTheme.brume2
                        wrapMode: Text.WordWrap
                        font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: FiliTheme.space2
                        PanelSwitch {
                            checked: sw.remember
                            onToggled: sw.remember = !sw.remember
                        }
                        Text {
                            Layout.fillWidth: true
                            text: FiliI18n.tr("Always do this for this device")
                            color: FiliTheme.brume
                            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sw.remember = !sw.remember }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: FiliTheme.space2
                        Item { Layout.fillWidth: true }
                        PanelButton {
                            objectName: "keep"
                            Layout.fillWidth: false
                            implicitWidth: 120
                            label: FiliI18n.tr("Keep current")
                            onClicked: sw.answer(false)
                        }
                        PanelButton {
                            objectName: "switch"
                            Layout.fillWidth: false
                            implicitWidth: 120
                            label: FiliI18n.tr("Switch")
                            sel: true
                            onClicked: sw.answer(true)
                        }
                    }
                }
            }
        }
    }
}
