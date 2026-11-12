pragma Singleton
// Luminance of the wallpaper under the edges of the screen (bar-luma), for the text colour of a see-through bar:
// FiliTheme.wallLuma, read by BarLayout.toneFor. Measured again when the wallpaper changes (`wallpaper` writes
// ~/.local/state/wallpaper) and when the screens change; nothing runs while both bars are solid.
import QtQuick
import Quickshell
import Quickshell.Io
import qs

Singleton {
    id: tone
    // A see-through bar is on (otherwise the measure is not needed)
    readonly property bool needed: BarLayout.alpha < 1 || (TaskbarLayout.enabled && TaskbarLayout.alpha < 1)
    readonly property string wallpaper: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/wallpaper"
    readonly property var screen: Quickshell.screens[0] ?? null
    readonly property string command: screen ? FiliTheme.bin + "/bar-luma " + screen.width + " " + screen.height + " " + Math.max(FiliTheme.barThickness, FiliTheme.taskbarHeight) : ""
    onNeededChanged: if (needed) measure.restart()
    onCommandChanged: if (needed) measure.restart()
    Timer {
        id: measure
        interval: 300
        onTriggered: if (tone.command !== "" && !FiliTheme.testing) probe.running = true
    }
    FileView {
        path: FiliTheme.testing ? "" : tone.wallpaper
        watchChanges: true
        printErrors: false
        onFileChanged: if (tone.needed) measure.restart()
    }
    Process {
        id: probe
        command: ["sh", "-c", tone.command]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = text.trim().split(/\s+/).map(Number);
                if (v.length === 4 && v.every(n => !isNaN(n)))
                    FiliTheme.wallLuma = { top: v[0], bottom: v[1], left: v[2], right: v[3] };
            }
        }
    }
}
