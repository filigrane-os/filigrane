// Speaker equalizer (T2 DSP, sound-tune) for the sound fili-panel: three vertical bands (bass, mids,
// treble) and the loudness. Applied live while dragging (at most one command at a time), saved on release.
// The cut-off frequencies stay with sound-tune (TUI).
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.bar
import qs.controls
import qs

ColumnLayout {
    id: eq
    spacing: FiliTheme.space1
    property var vals: ({})
    property var range: ({})
    property var origin: ({})
    property bool save: false
    property bool dirty: false
    readonly property bool ready: range.bass !== undefined
    readonly property string tune: FiliTheme.bin + "/sound-tune"
    // Bands: key, label, display unit
    readonly property var bands: [
        { key: "bass", label: FiliI18n.tr("Bass"), db: false },
        { key: "mid_gain", label: FiliI18n.tr("Mids"), db: true },
        { key: "treb_gain", label: FiliI18n.tr("Treble"), db: true }
    ]

    function frac(key) {
        const r = range[key];
        return r ? (vals[key] - r.min) / (r.max - r.min) : 0;
    }
    function text(b) {
        const v = vals[b.key], r = range[b.key];
        if (!r)
            return "";
        if (b.db)
            return (v > 0 ? "+" : v < 0 ? "−" : "") + Math.abs(v).toLocaleString(Qt.locale(), "f", Math.abs(v % 1) > 0 ? 1 : 0) + " dB";
        return Math.round(v / r.max * 100) + "%";
    }
    // Value of a band at fraction f (0..1), rounded to the sound-tune step
    function setFrac(key, f) {
        const r = range[key];
        const v = r.min + Math.max(0, Math.min(1, f)) * (r.max - r.min);
        set(key, Math.round(v / r.step) * r.step);
    }
    function set(key, v) {
        const r = range[key];
        vals = Object.assign({}, vals, { [key]: Math.round(Math.max(r.min, Math.min(r.max, v)) * 1000) / 1000 });
        push(false);
    }
    // Sending: one command at a time, the last value goes as soon as the previous one has finished
    function push(final) {
        save = save || final;
        dirty = true;
        if (!job.running)
            send();
    }
    function send() {
        const args = Object.keys(vals).map(k => k + "=" + vals[k]);
        job.command = [tune, "--set"].concat(args, save ? ["--save"] : []);
        dirty = false;
        save = false;
        job.running = true;
    }
    function reset() {
        vals = Object.assign({}, origin);
        push(true);
    }
    // Read on first appearance (without DSP, the component stays hidden and runs nothing)
    onVisibleChanged: if (visible && !ready && !get.running) get.running = true
    Component.onCompleted: if (visible) get.running = true

    Process {
        id: get
        command: [eq.tune, "--get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text);
                    eq.vals = j.vals;
                    eq.range = j.params;
                    eq.origin = j.default;
                } catch (e) {}
            }
        }
    }
    Process {
        id: job
        onExited: if (eq.dirty) eq.send()
    }

    RowLayout {
        visible: eq.ready
        Layout.fillWidth: true
        spacing: FiliTheme.space2
        Repeater {
            model: eq.bands
            ColumnLayout {
                id: band
                required property var modelData
                readonly property real f: eq.frac(modelData.key)
                Layout.preferredWidth: 56
                Layout.alignment: Qt.AlignTop
                spacing: FiliTheme.space1
                // Keyboard: ↑/↓ = one step (Shift+←/→ stays with the fili-panel: neighbouring panel)
                activeFocusOnTab: true
                Keys.onUpPressed: { FiliShell.keyNav = true; eq.set(modelData.key, eq.vals[modelData.key] + eq.range[modelData.key].step); eq.push(true); }
                Keys.onDownPressed: { FiliShell.keyNav = true; eq.set(modelData.key, eq.vals[modelData.key] - eq.range[modelData.key].step); eq.push(true); }
                Text {
                    text: eq.text(band.modelData)
                    color: FiliTheme.ardoise
                    Layout.alignment: Qt.AlignHCenter
                    font { family: FiliTheme.mono; pixelSize: FiliTheme.sizeList }
                }
                Item {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 24
                    implicitHeight: 76
                    FocusRing { shown: band.activeFocus; gap: 4 }
                    Rectangle {
                        id: track
                        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; bottom: parent.bottom }
                        width: 4
                        radius: FiliTheme.radiusMark
                        color: FiliTheme.nuit3
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            height: parent.height * band.f
                            radius: FiliTheme.radiusMark
                            color: FiliTheme.voile
                        }
                    }
                    Rectangle {
                        y: track.height * (1 - band.f) - 6
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 12; height: 12; radius: FiliTheme.radiusControl
                        color: FiliTheme.brume
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        function at(y) { eq.setFrac(band.modelData.key, 1 - y / height); }
                        onPressed: m => at(m.y)
                        onPositionChanged: m => { if (pressed) at(m.y); }
                        onReleased: eq.push(true)
                        onWheel: w => { eq.set(band.modelData.key, eq.vals[band.modelData.key] + (w.angleDelta.y > 0 ? 1 : -1) * eq.range[band.modelData.key].step); eq.push(true); }
                    }
                }
                Text {
                    text: band.modelData.label
                    color: FiliTheme.brume2
                    Layout.alignment: Qt.AlignHCenter
                    font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList }
                }
            }
        }
        // Right of the bands: linked settings, one per line
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: FiliTheme.space1
            PanelButton {
                objectName: "loudness"
                glyph: "\uf028"
                label: FiliI18n.tr("Loudness")
                detail: eq.vals.loudness ? FiliI18n.tr("on") : FiliI18n.tr("off")
                sel: eq.vals.loudness > 0
                onClicked: { eq.set("loudness", eq.vals.loudness ? 0 : 1); eq.push(true); }
            }
            PanelButton {
                objectName: "eq-reset"
                glyph: "\uf0e2"
                label: FiliI18n.tr("Reset")
                dim: true
                onClicked: eq.reset()
            }
            PanelButton {
                glyph: "\uf0e7"
                label: FiliI18n.tr("All settings")
                dim: true
                onClicked: { FiliPanel.close(); FiliTheme.run(FiliTheme.bin + "/bar-tui sound-tune"); }
            }
        }
    }
}
