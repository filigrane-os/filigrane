pragma Singleton
// Which modules the fili-bar shows, and in which order. ~/.config/filigrane/fili-bar.toml is optional (the defaults below
// apply without it) and re-read as soon as it changes:
//   [modules]
//   left  = ["logo", "workspaces", "appmenu"]
//   right = ["status", "tray", "media", "resources", "agent", "audio", "keyboard", "display", "bluetooth", "network",
//            "notifications", "clock", "power"]
// A name is a folder of bar/modules/ (<name>/<Name>Module.qml, hyphens make camel case: "my-thing" -> MyThingModule).
// Invalid names (anything but lowercase letters, digits and hyphens) and duplicates are ignored; a module that does
// not exist leaves a loading error in the log and no gap in the bar.
import QtQuick
import Quickshell
import Quickshell.Io
import qs
// Module folders with helper files next to their module: imported so that Quickshell scans them (see BarModule)
import qs.bar.modules.appmenu
import qs.bar.modules.audio
import qs.bar.modules.clock

Singleton {
    id: layout
    readonly property var defaultLeft: ["logo", "workspaces", "appmenu"]
    readonly property var defaultRight: ["alerts", "status", "tray", "media", "resources", "agent", "audio", "keyboard", "display", "bluetooth", "network", "notifications", "clock", "power"]
    property var parsed: ({})
    readonly property var left: pick("left", defaultLeft)
    readonly property var right: pick("right", defaultRight)

    FileView {
        path: FiliTheme.testing ? "" : (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/filigrane/fili-bar.toml"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: layout.parsed = FiliTheme.parseToml(text())
        onLoadFailed: layout.parsed = ({})
    }

    function pick(side, def) {
        const v = parsed.modules?.[side];
        return Array.isArray(v) ? v.filter((n, i) => /^[a-z][a-z0-9-]*$/.test(n) && v.indexOf(n) === i) : def;
    }
    // QML file of a module
    function source(name) {
        const type = name.split("-").map(s => s.charAt(0).toUpperCase() + s.slice(1)).join("");
        return Qt.resolvedUrl("modules/" + name + "/" + type + "Module.qml");
    }
}
