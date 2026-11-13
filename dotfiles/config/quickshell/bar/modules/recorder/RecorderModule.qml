// Cassette (fili-recorder): records the sound of the machine, an input and an output, each one optional. The
// module sits in the drawer at rest (tray = "idle" in module.toml) and comes out into the bar, with REC, while a
// recording runs. Click = the panel (sources, start and stop), middle click = start or stop with the chosen sources.
// State: `fili-recorder status --json`, read at the start and each time the recorder asks for a refresh (signal 19).
import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs
import qs.bar

BarModule {
    id: rec
    panel: "recorder"
    panelSource: Qt.resolvedUrl("RecorderPanel.qml")
    anchorItem: item

    // The cassette of Fili Icons (Lucide cassette-tape, scripts/fili-icons.py), the monochrome mark of the application icon
    readonly property string mark: String.fromCodePoint(0xf2f10)
    property var info: ({ recording: false, saving: false, start: 0, input: "default", output: "default" })
    readonly property bool recording: info.recording === true
    function node(name) {
        return name === "default" || name === "none" ? null : (Pipewire.nodes.values.find(n => n.name === name) ?? null);
    }
    // Readable name of a choice ("none", "default" or the name of a node)
    function label(name) {
        if (name === "none")
            return FiliI18n.tr("None");
        if (name === "default")
            return FiliI18n.tr("Default");
        const n = node(name);
        return n ? (n.description || n.nickname || n.name) : name;
    }
    // Only the two chosen devices are followed (their description), not the whole graph
    PwObjectTracker { objects: [rec.node(rec.info.input), rec.node(rec.info.output)].filter(n => n) }

    Process {
        id: read
        command: [FiliTheme.bin + "/fili-recorder", "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    rec.info = JSON.parse(text);
                } catch (e) {
                }
            }
        }
    }
    Component.onCompleted: read.running = true
    Connections {
        target: FiliShell
        function onRefresh(n) {
            if (n === 19)
                read.running = true;
        }
    }

    BarRow {
        BarScript {
            id: item
            panelNeedsVisible: true
            objectName: "recorder"
            title: "Cassette"
            colors: ({ rec: FiliTheme.cendre, idle: FiliTheme.barMuted })
            mclick: FiliTheme.bin + "/fili-recorder toggle"
            value: rec.recording ? {
                text: rec.mark + " " + (rec.info.saving ? FiliI18n.tr("SAVING") : FiliI18n.tr("REC")),
                "class": "rec",
                tooltip: {
                    title: "Cassette",
                    rows: [[FiliI18n.tr("Since"), Qt.formatTime(new Date(rec.info.start * 1000), "HH:mm")],
                           [FiliI18n.tr("Input"), rec.label(rec.info.input)], [FiliI18n.tr("Output"), rec.label(rec.info.output)]],
                    hint: FiliI18n.tr("click: panel · middle click: stop")
                }
            } : {
                text: rec.mark,
                "class": "idle",
                tooltip: { title: "Cassette", text: FiliI18n.tr("Not recording"), hint: FiliI18n.tr("click: panel · middle click: record") }
            }
            hover.onLeftClicked: rec.togglePanel(hover)
        }
    }
}
