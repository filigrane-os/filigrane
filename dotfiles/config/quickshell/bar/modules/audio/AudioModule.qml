// Audio output: click = sound panel, middle click = mute, wheel = volume, right click = mixer (wiremix)
import QtQuick
import Quickshell.Services.Pipewire
import qs
import qs.bar

BarItem {
    objectName: "volume"
    panel: "audio"
    panelSource: Qt.resolvedUrl("AudioPanel.qml")
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var audio: sink?.audio ?? null
    readonly property int vol: audio ? Math.round(audio.volume * 100) : 0
    readonly property string kind: FiliTheme.sinkGlyph(sink?.properties)
    PwObjectTracker { objects: [sink, source] }
    text: !audio ? "" : (kind || (audio.muted ? "" : vol < 34 ? "" : vol < 67 ? "" : ""))
        + (audio.muted ? " " + FiliI18n.tr("muted") : " " + vol + "%")
    color: audio?.muted ? FiliTheme.barMuted : FiliTheme.barText
    tip: !audio ? "" : {
        title: audio.muted ? FiliI18n.tr("Sound muted") : FiliI18n.tr("Sound"),
        rows: [[FiliI18n.tr("Output"), sink.description || sink.nickname || sink.name], [FiliI18n.tr("Volume"), vol + " %"],
               [FiliI18n.tr("Input"), source ? (source.description || source.name) : ""]].filter(r => r[1]),
        hint: FiliI18n.tr("click: sound panel · middle click: mute · wheel: volume · right click: mixer")
    }
    hover.onLeftClicked: togglePanel()
    hover.onMiddleClicked: audio.muted = !audio.muted
    hover.onWheelUp: audio.volume = Math.min(1, audio.volume + 0.03)
    hover.onWheelDown: audio.volume = Math.max(0, audio.volume - 0.03)
    hover.rclick: FiliTheme.bin + "/bar-tui wiremix --tab output"
}
