pragma Singleton
// Which modules the fili-bar shows, and in which order. Every module folder has a manifest, module.toml (title,
// description, side = "left"|"right", order = position in the row, smaller = more to the left, default 50): the default
// rows are the manifests sorted by order. ~/.config/filigrane/fili-bar.toml is optional and re-read as soon as it changes:
//   [modules]
//   left  = ["logo", "workspaces", "appmenu"]
//   right = ["status", "tray", "media", "resources", "agent", "audio", "keyboard", "display", "bluetooth", "network",
//            "notifications", "clock", "power"]
//   [bar]
//   edge = "top"           # "top" (default) | "bottom" | "left" | "right" (a narrow column: the modules stack)
//   screens = "all"        # "all" (default) or a list of output names, e.g. ["eDP-1", "DP-6"]
// (dotfiles/config/filigrane/fili-bar.toml lists every option with its comment)
//   [modules.clock]        # per-module override of the manifest
//   side = "left"
//   order = 5
//   enabled = false
//   display = "icon"       # "both" (default) | "icon" | "value"
//   tray = "idle"          # drawer: "never" (default) | "idle" (in the drawer at rest) | "always" (only in the open drawer)
//   show = "always"        # "active" (default: hidden while it has nothing to show) | "always"
// A name is a folder of bar/modules/ (<name>/<Name>Module.qml, hyphens make camel case: "my-thing" -> MyThingModule),
// from the distribution or from a user layer. An explicit left / right list gives the exact order of the row; "..."
// stands for the default modules of the row (the ones not listed yet), so a user layer can add its own without restating
// the rest: right = ["mail", "..."]. A module with a manifest joins the default row by itself. Invalid names (anything but
// lowercase letters, digits and hyphens), duplicates and disabled modules are ignored; a module that does not exist
// leaves a loading error in the log and no gap in the bar. A manifest with a `cmd` makes a script plugin (ScriptModule).
// The manifests are read once at start (reload() reads them again).
import QtQuick
import Quickshell
import Quickshell.Io
import qs
// Module folders with helper files next to their module: imported so that Quickshell scans them (see BarModule)
import qs.bar.modules.alert
import qs.bar.modules.appmenu
import qs.bar.modules.audio
import qs.bar.modules.clock

Singleton {
    id: layout
    // Manifests by module name: { side, order, title, description }; ready once they are read (the bar waits for it)
    property var manifests: ({})
    property bool ready: false
    readonly property var defaultLeft: row("left")
    readonly property var defaultRight: row("right")
    property var parsed: ({})
    readonly property var left: pick("left", defaultLeft)
    readonly property var right: pick("right", defaultRight)
    // Edge of the screen: [bar] edge = "top" (default) | "bottom" | "left" | "right"
    readonly property string edge: ["top", "bottom", "left", "right"].indexOf(parsed.bar?.edge) >= 0 ? parsed.bar.edge : "top"
    Binding { target: FiliTheme; property: "barEdge"; value: layout.edge }
    // Screens that get a bar: [bar] screens = "all" (default) or a list of output names. A list that matches no connected
    // screen gives a bar on every screen, so the bar never disappears (a screen unplugged, a name mistyped).
    readonly property var wantedScreens: {
        const v = parsed.bar?.screens;
        const list = Array.isArray(v) ? v : (v ? [v] : []);
        return list.indexOf("all") >= 0 ? [] : list;
    }
    readonly property var barScreens: {
        const all = Quickshell.screens;
        const some = all.filter(s => wantedScreens.indexOf(s.name) >= 0);
        return some.length > 0 ? some : all;
    }
    // What the choice shows as selected: "all", or the name when a single screen is asked for
    readonly property string screensChoice: wantedScreens.length === 1 && barScreens.length === 1 && barScreens[0].name === wantedScreens[0] ? wantedScreens[0] : (wantedScreens.length === 0 ? "all" : "")

    Component.onCompleted: reload()
    function reload() {
        scan.running = true;
    }
    Process {
        id: scan
        command: ["sh", "-c", 'for f in "$1"/modules/*/module.toml; do [ -f "$f" ] || continue; printf "@@%s\\n" "$(basename "$(dirname "$f")")"; cat "$f"; echo; done', "sh", Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")]
        stdout: StdioCollector {
            onStreamFinished: layout.load(text)
        }
    }
    // Manifests from the text of scan: "@@name" lines followed by the content of each module.toml
    function load(text) {
        const out = {};
        for (const part of text.split("@@").slice(1)) {
            const nl = part.indexOf("\n");
            const name = part.slice(0, nl).trim();
            if (/^[a-z][a-z0-9-]*$/.test(name))
                out[name] = parseToml(part.slice(nl + 1));
        }
        manifests = out;
        ready = true;
    }
    function parseToml(text) {
        return FiliTheme.parseToml(text)[""] ?? ({});
    }
    // Value of a key for a module: [modules.<name>] of fili-bar.toml, then its manifest, then the fallback
    function setting(name, key, fallback) {
        return parsed["modules." + name]?.[key] ?? manifests[name]?.[key] ?? fallback;
    }
    // A setting restricted to a list of values (anything else gives the fallback)
    function choice(name, key, values, fallback) {
        const v = setting(name, key, fallback);
        return values.indexOf(v) >= 0 ? v : fallback;
    }
    function enabled(name) {
        return setting(name, "enabled", "true") !== "false";
    }
    // Default modules of a row: the enabled manifests of that side, by order then name
    function row(side) {
        const order = n => { const v = parseInt(setting(n, "order", "50")); return isNaN(v) ? 50 : v; };
        return Object.keys(manifests)
            .filter(n => enabled(n) && setting(n, "side", "right") === side)
            .sort((x, y) => order(x) - order(y) || (x < y ? -1 : 1));
    }

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
        if (!Array.isArray(v))
            return def;
        const out = [];
        for (const n of v)
            for (const m of n === "..." ? def : [n])
                if (/^[a-z][a-z0-9-]*$/.test(m) && out.indexOf(m) < 0 && enabled(m))
                    out.push(m);
        return out;
    }
    // A module whose manifest has a cmd is a script plugin (no QML): it runs ScriptModule
    function isScript(name) {
        return manifests[name]?.cmd !== undefined;
    }
    // Folder of a module
    function dir(name) {
        return Qt.resolvedUrl("modules/" + name).toString().replace(/^file:\/\//, "");
    }
    // Options of the user for a module: ~/.config/filigrane/bar/<name>.toml (optional; a QML module reads it with a
    // FileView and FiliTheme.parseToml, a script plugin gets the path in FILI_BAR_OPTIONS)
    function options(name) {
        return (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/filigrane/bar/" + name + ".toml";
    }
    // QML file of a module
    function source(name) {
        if (isScript(name))
            return Qt.resolvedUrl("ScriptModule.qml");
        const type = name.split("-").map(s => s.charAt(0).toUpperCase() + s.slice(1)).join("");
        return Qt.resolvedUrl("modules/" + name + "/" + type + "Module.qml");
    }
}
