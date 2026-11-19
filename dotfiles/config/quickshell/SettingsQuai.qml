// Settings page "Quai" (fili-settings): the taskbar, which lists the windows of each screen by workspace. On or off, edge,
// automatic hiding, background and screens; every change is made by `fili-bar taskbar`, which writes [taskbar] of
// ~/.config/filigrane/fili-bar.toml; the Quai re-reads it at once and this page follows (TaskbarLayout).
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.bar
import qs.controls

ColumnLayout {
    id: view
    spacing: FiliTheme.space1
    readonly property string cli: FiliTheme.bin + "/fili-bar"

    // Position of the size slider (0..1) not yet applied; -1 = follows the bar
    property real draft: -1
    Timer {
        id: sizeTimer
        interval: 100
        onTriggered: {
            const pct = Math.round((0.8 + view.draft * 0.8) * 100);
            if (pct === Math.round(TaskbarLayout.scale * 100))
                view.draft = -1;
            else
                FiliTheme.run(view.cli + " taskbar scale " + pct);
        }
    }
    Connections {
        target: TaskbarLayout
        function onScaleChanged() { view.draft = -1; }
    }

    Text {
        text: "Quai"
        color: FiliTheme.voile
        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("Every window of the screen by workspace, each with its number. Hold Mod+Alt and type a number to go to its window.")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: FiliTheme.space2
        PanelSwitch {
            objectName: "quai-enabled"
            checked: TaskbarLayout.enabled
            onToggled: FiliTheme.run(view.cli + " taskbar enabled " + (TaskbarLayout.enabled ? "false" : "true"))
        }
        Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: FiliI18n.tr("Show the Quai")
            color: TaskbarLayout.enabled ? FiliTheme.brume : FiliTheme.ardoise
            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
        }
    }
    // Size: the bar, its text and its icons together (fili-bar taskbar scale PERCENT), in steps of 10 %. While the knob is
    // dragged only the number moves; the bar changes once, on release (resizing it live makes the display stutter).
    PanelSection { text: FiliI18n.tr("SIZE") }
    PanelSlider {
        id: sizeSlider
        objectName: "quai-scale"
        from: 0.8
        to: 1.6
        steps: 8
        value: view.draft >= 0 ? view.draft : (TaskbarLayout.scale - 0.8) / 0.8
        glyph: "A"
        onMoved: v => {
            view.draft = v;
            if (!sizeSlider.dragging)
                sizeTimer.restart();
        }
        onReleased: sizeTimer.restart()
        onGlyphClicked: { view.draft = 0.25; sizeTimer.restart(); }
    }
    // Edge, background, hiding and screens: the same block as the right click panel of the Quai
    BarPlacement { Layout.fillWidth: true; target: "taskbar" }
}
