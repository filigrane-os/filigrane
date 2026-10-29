// fili-panel audio: volume de la sortie et de l'entrée (PipeWire natif), choix des périphériques, mixeur par application
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire

ColumnLayout {
    id: view
    spacing: FiliTheme.space1
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var nodes: Pipewire.nodes.values
    readonly property var sinks: nodes.filter(n => n.audio && n.isSink && !n.isStream)
    readonly property var sources: nodes.filter(n => n.audio && !n.isSink && !n.isStream)
    readonly property var streams: nodes.filter(n => n.audio && n.isStream && n.isSink)
    PwObjectTracker { objects: view.nodes }

    function name(n) {
        return n.description || n.nickname || n.name;
    }
    // Casque ou enceinte Bluetooth: codec négocié (api.bluez5.codec), « Bluetooth » seul tant qu'il est inconnu
    readonly property var codecs: ({
        sbc: "SBC", sbc_xq: "SBC-XQ", aac: "AAC", ldac: "LDAC", aptx: "aptX", aptx_hd: "aptX HD",
        aptx_ll: "aptX LL", aptx_ll_duplex: "aptX LL", faststream: "FastStream", faststream_duplex: "FastStream",
        lc3: "LC3", lc3_swb: "LC3", msbc: "mSBC", cvsd: "CVSD", opus_05: "Opus", opus_05_51: "Opus",
        opus_05_71: "Opus", opus_05_duplex: "Opus", opus_05_pro: "Opus"
    })
    function detail(n) {
        const p = n.properties;
        if (p["device.api"] !== "bluez5" && !(p["node.name"] ?? "").startsWith("bluez_"))
            return "";
        const c = p["api.bluez5.codec"];
        return c ? "Bluetooth · " + (codecs[c] ?? c.toUpperCase()) : "Bluetooth";
    }
    function app(n) {
        return n.properties["application.name"] || n.properties["node.name"] || n.name;
    }

    Text {
        text: FiliI18n.tr("Sound")
        color: FiliTheme.voile
        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
    }
    PanelSlider {
        objectName: "volume"
        glyph: FiliTheme.sinkGlyph(view.sink?.properties) || (view.sink?.audio?.muted ? "" : "")
        muted: view.sink?.audio?.muted ?? false
        value: view.sink?.audio?.volume ?? 0
        onMoved: v => { if (view.sink?.audio) view.sink.audio.volume = v; }
        onGlyphClicked: view.sink.audio.muted = !view.sink.audio.muted
    }
    PanelSection { text: FiliI18n.tr("OUTPUT") }
    Repeater {
        model: view.sinks
        PanelButton {
            required property var modelData
            objectName: "sink"
            glyph: FiliTheme.sinkGlyph(modelData.properties) || ""
            label: view.name(modelData)
            detail: view.detail(modelData)
            sel: modelData.id === view.sink?.id
            onClicked: Pipewire.preferredDefaultAudioSink = modelData
        }
    }
    PanelSection { text: FiliI18n.tr("INPUT") }
    PanelSlider {
        objectName: "micro"
        glyph: view.source?.audio?.muted ? "" : ""
        muted: view.source?.audio?.muted ?? false
        value: view.source?.audio?.volume ?? 0
        onMoved: v => { if (view.source?.audio) view.source.audio.volume = v; }
        onGlyphClicked: view.source.audio.muted = !view.source.audio.muted
    }
    Repeater {
        model: view.sources
        PanelButton {
            required property var modelData
            objectName: "source"
            label: view.name(modelData)
            detail: view.detail(modelData)
            sel: modelData.id === view.source?.id
            onClicked: Pipewire.preferredDefaultAudioSource = modelData
        }
    }
    PanelSection { visible: view.streams.length > 0; text: FiliI18n.tr("APPLICATIONS") }
    Repeater {
        model: view.streams
        PanelSlider {
            required property var modelData
            glyph: ""
            value: modelData.audio.volume
            muted: modelData.audio.muted
            onMoved: v => modelData.audio.volume = v
            onGlyphClicked: modelData.audio.muted = !modelData.audio.muted
        }
    }
    PanelButton {
        Layout.topMargin: FiliTheme.space1
        glyph: ""
        label: FiliI18n.tr("Full mixer")
        dim: true
        onClicked: { FiliPanel.close(); FiliTheme.run(FiliTheme.bin + "/bar-tui wiremix"); }
    }
    PanelButton {
        glyph: ""
        label: FiliI18n.tr("Speaker equalizer")
        dim: true
        onClicked: { FiliPanel.close(); FiliTheme.run(FiliTheme.bin + "/bar-tui sound-tune"); }
    }
}
