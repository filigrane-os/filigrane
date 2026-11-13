// fili-panel recorder (Cassette): choose what to record, an input (microphone...) and an output (what the
// speakers play), each one optional, then start and stop. Recording only listens: the sound itself is never touched.
// `fili-recorder` does the work (apps/fili-recorder); the choices are its state, kept for the next recordings.
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.bar
import qs.controls
import qs

ColumnLayout {
    id: view
    spacing: FiliTheme.space1
    readonly property string cmd: FiliTheme.bin + "/fili-recorder"
    property var info: ({ recording: false, saving: false, start: 0, input: "default", output: "default", dir: "" })
    readonly property bool rec: info.recording === true
    readonly property bool saving: info.saving === true
    readonly property bool nothing: info.input === "none" && info.output === "none"
    // Result of the last action, shown under the button: an error (failed) or where the file went
    property string message: ""
    property bool failed: false
    property real now: Date.now()
    readonly property int elapsed: rec ? Math.max(0, Math.floor(now / 1000 - info.start)) : 0
    readonly property var nodes: Pipewire.nodes.values
    readonly property var sinks: nodes.filter(n => n.audio && n.isSink && !n.isStream)
    readonly property var sources: nodes.filter(n => n.audio && !n.isSink && !n.isStream)
    PwObjectTracker { objects: view.nodes }

    function name(n) {
        return n.description || n.nickname || n.name;
    }
    function choices(list, fallback) {
        return [{ label: FiliI18n.tr("None"), value: "none" },
                { label: FiliI18n.tr("Default") + (fallback ? " · " + name(fallback) : ""), value: "default" }]
            .concat(list.map(n => ({ label: name(n), value: n.name })));
    }
    function clock(s) {
        const p = v => (v < 10 ? "0" : "") + v;
        return Math.floor(s / 3600) > 0 ? Math.floor(s / 3600) + ":" + p(Math.floor(s / 60) % 60) + ":" + p(s % 60) : p(Math.floor(s / 60)) + ":" + p(s % 60);
    }
    function refresh() {
        read.running = true;
    }
    function toggle() {
        if (saving || (!rec && nothing))
            return;
        message = "";
        failed = false;
        action.command = [cmd, "toggle"];
        action.running = true;
    }
    function choose(which, value) {
        const next = Object.assign({}, info);
        next[which] = value;
        info = next;
        choice.command = [cmd, "set", which, value];
        choice.running = true;
    }

    Process {
        id: read
        command: [view.cmd, "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    view.info = JSON.parse(text);
                } catch (e) {
                }
            }
        }
    }
    // start / stop: the file written is on the standard output, a refusal on the error output
    Process {
        id: action
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").filter(l => l);
                if (!view.rec && lines.length > 0)
                    view.message = FiliI18n.tr("Saved: %1").replace("%1", lines[lines.length - 1].split("/").pop());
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const t = text.trim().replace(/^fili-recorder: /, "");
                if (t) {
                    view.message = t;
                    view.failed = true;
                }
            }
        }
        onExited: view.refresh()
    }
    Process { id: choice }
    Component.onCompleted: refresh()
    Connections {
        target: FiliShell
        function onRefresh(n) {
            if (n === 19)
                view.refresh();
        }
    }
    // The elapsed time is computed here, one tick a second while the panel is open and a recording runs
    Timer {
        running: view.rec && !view.saving
        interval: 1000
        repeat: true
        onTriggered: view.now = Date.now()
        onRunningChanged: if (running) view.now = Date.now()
    }

    Text {
        text: "Cassette"
        color: FiliTheme.voile
        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
    }
    PanelButton {
        objectName: "record"
        glyph: view.rec ? "" : ""
        label: view.saving ? FiliI18n.tr("Saving…") : view.rec ? FiliI18n.tr("Stop recording") : FiliI18n.tr("Start recording")
        detail: view.rec ? view.clock(view.elapsed) : ""
        tint: view.rec ? FiliTheme.cendre : FiliTheme.brume
        dim: view.saving || (!view.rec && view.nothing)
        onClicked: view.toggle()
    }
    Text {
        visible: text !== ""
        Layout.fillWidth: true
        Layout.leftMargin: FiliTheme.space2
        Layout.rightMargin: FiliTheme.space2
        text: view.message || (!view.rec && view.nothing ? FiliI18n.tr("Choose an input or an output") : "")
        wrapMode: Text.Wrap
        color: view.failed ? FiliTheme.cendre : FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }

    PanelSection { text: FiliI18n.tr("INPUT") }
    PanelSelect {
        objectName: "input"
        Layout.fillWidth: true
        enabled: !view.rec
        opacity: enabled ? 1 : 0.5
        model: view.choices(view.sources, Pipewire.defaultAudioSource)
        current: view.info.input
        placeholder: view.info.input
        onPicked: v => view.choose("input", v)
    }
    PanelSection { text: FiliI18n.tr("OUTPUT") }
    PanelSelect {
        objectName: "output"
        Layout.fillWidth: true
        enabled: !view.rec
        opacity: enabled ? 1 : 0.5
        model: view.choices(view.sinks, Pipewire.defaultAudioSink)
        current: view.info.output
        placeholder: view.info.output
        onPicked: v => view.choose("output", v)
    }
    Text {
        visible: view.rec
        Layout.fillWidth: true
        Layout.leftMargin: FiliTheme.space2
        text: FiliI18n.tr("The sources apply to the next recording")
        wrapMode: Text.Wrap
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }

    PanelButton {
        Layout.topMargin: FiliTheme.space1
        objectName: "folder"
        glyph: "\uf07c"
        label: FiliI18n.tr("Open recordings folder")
        dim: true
        onClicked: {
            FiliPanel.close();
            FiliTheme.run(view.cmd + " folder");
        }
    }
    PanelButton {
        objectName: "open-app"
        glyph: String.fromCodePoint(0xf2f10)
        label: FiliI18n.tr("Open Cassette")
        dim: true
        onClicked: {
            FiliPanel.close();
            FiliTheme.run("fili-recorder");
        }
    }
}
