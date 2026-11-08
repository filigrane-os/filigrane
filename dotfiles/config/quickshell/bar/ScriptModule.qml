// Script plugin of the fili-bar: a module folder with only a module.toml, no QML. BarLayout loads this file for a manifest
// that has a `cmd`, and hands over the manifest (conf) and the module name. The script prints the BarScript protocol, one
// JSON line {text, class, tooltip} per update. Commands run in the folder of the module, so `cmd = "./status.sh"` works.
//   cmd         command that prints the state
//   interval    seconds between two runs (0: once, then on signal; -1: resident, one line per update)
//   signal      refreshed by `fili-shell signal N`
//   click, rclick, mclick, scroll_up, scroll_down    commands run by the mouse
//   The commands get FILI_BAR_OPTIONS in their environment: ~/.config/filigrane/bar/<name>.toml, the options of the user
//   for this plugin (the file may not exist; the plugin documents its keys).
//   title       name in the tooltip (default: the module name); hint: help line of the tooltip
import QtQuick
import qs
import qs.bar

BarScript {
    id: sm
    // Module name and its manifest (set by BarSlot)
    property string name
    property var conf: ({})
    readonly property string dir: BarLayout.dir(name)

    objectName: name
    title: conf.title ?? name
    hint: conf.hint ?? ""
    cmd: inDir(conf.cmd)
    interval: parseInt(conf.interval ?? "0") || 0
    signal: conf.signal !== undefined && !isNaN(parseInt(conf.signal)) ? parseInt(conf.signal) : -1
    click: inDir(conf.click)
    rclick: inDir(conf.rclick)
    mclick: inDir(conf.mclick)
    scrollUp: inDir(conf.scroll_up)
    scrollDown: inDir(conf.scroll_down)

    // A command run from the folder of the module ("" stays empty)
    function inDir(c) {
        return c ? "export FILI_BAR_OPTIONS='" + BarLayout.options(name).replace(/'/g, "'\\''") + "'; cd '" + dir.replace(/'/g, "'\\''") + "' 2>/dev/null; " + c : "";
    }
}
