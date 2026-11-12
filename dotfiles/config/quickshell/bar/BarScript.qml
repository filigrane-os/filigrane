// fili-bar module fed by a script: same protocol as the custom Waybar modules (one JSON line
// {text, class, tooltip} per update), to reuse bar-status, bar-tray, bar-alert, bar-stats...
//   interval > 0: run again every N s; 0: once (then on signal); -1: resident (one line per update)
//   signal: refreshed by `fili-shell signal N` (ex-`pkill -RTMIN+N waybar`)
//   stat: without a script, state written by bar-stats (`stat NAME JSON`, see FiliShell)
//   value: without a script, state bound to a {text, class, tooltip} object (BarState)
import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.bar

BarModule {
    id: mod
    property string cmd
    property string stat
    property var value: null
    onValueChanged: if (value) apply(value)
    property int interval: 0
    property int signal: -1
    property bool hideEmpty: true
    // Colour by class (key "" = default)
    property var colors: ({})
    property color color: FiliTheme.barText
    // Class that blinks (backup running)
    property string blinkClass: ""
    property string click
    property string rclick
    property string mclick
    property string scrollUp
    property string scrollDown
    property real pad: FiliTheme.pad
    // Label in small capitals before the value (CPU, RAM)
    property string tag

    property string text: ""
    property string cls: ""
    // Text or card of the fili-tooltip (see FiliTooltip)
    property var tip: ""
    // Help line of the fili-tooltip (what the clicks do)
    property string hint
    // Title of the card of a plain-text tooltip (else the label); standard: title on the left, content on the right
    property string title
    // Card read on hover (replaces the text of the script), see BarHover
    property string tipInfo
    property bool pending: false

    // Drawer (trayMode): "idle" shows the module in the bar only while it is in use (not in the "idle" class)
    readonly property bool inDrawer: trayMode === "never" || BarState.trayOpen || (trayMode === "idle" && cls !== "idle")
    visible: !(hideEmpty && text === "") && inDrawer
    readonly property bool vertical: FiliTheme.barVertical
    // On a column the icon sits above the value (and the tag above both), and the module is as wide as the bar
    implicitWidth: !visible ? 0 : vertical ? FiliTheme.barWidth : Math.max(FiliTheme.isIcon(mod.text) ? FiliTheme.iconCell : 0, content.implicitWidth + 2 * pad)
    implicitHeight: !visible ? 0 : vertical ? Math.max(FiliTheme.isIcon(mod.text) ? FiliTheme.iconCell : 0, content.implicitHeight + 2 * FiliTheme.barPadV) : FiliTheme.barHeight

    function parse(line) {
        line = line.trim();
        if (!line)
            return;
        try {
            apply(JSON.parse(line));
        } catch (e) {
            mod.text = line;
        }
    }
    function apply(j) {
        mod.text = j.text ?? "";
        mod.cls = Array.isArray(j["class"]) ? (j["class"][0] ?? "") : (j["class"] ?? "");
        mod.tip = j.tooltip ?? "";
    }

    function update() {
        if (proc.running) {
            if (interval >= 0)
                pending = true;
        } else if (cmd) {
            proc.running = true;
        }
    }

    Component.onCompleted: {
        if (value)
            apply(value);
        else if (cmd)
            proc.running = true;
        else if (FiliShell.stats[stat])
            apply(FiliShell.stats[stat]);
    }
    Connections {
        target: FiliShell
        enabled: mod.stat !== ""
        function onStat(name, data) {
            if (name === mod.stat)
                mod.apply(data);
        }
    }

    Process {
        id: proc
        command: ["sh", "-c", mod.cmd]
        stdout: SplitParser {
            onRead: line => mod.parse(line)
        }
        onExited: {
            if (mod.pending) {
                mod.pending = false;
                proc.running = true;
            } else if (mod.interval < 0 && mod.cmd) {
                respawn.start();
            }
        }
    }
    Timer {
        id: respawn
        interval: 5000
        onTriggered: proc.running = true
    }
    Timer {
        running: mod.interval > 0
        repeat: true
        interval: Math.max(1, mod.interval) * 1000
        onTriggered: mod.update()
    }
    Connections {
        target: FiliShell
        enabled: mod.signal >= 0
        function onRefresh(n) {
            if (n === mod.signal)
                mod.update();
        }
    }

    Grid {
        id: content
        anchors.centerIn: parent
        flow: Grid.LeftToRight
        columns: mod.vertical ? 1 : 3
        spacing: mod.vertical ? 1 : FiliTheme.labelGap
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter
        Text {
            visible: mod.tag !== ""
            text: mod.tag
            color: FiliTheme.barMuted
            font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall; letterSpacing: 1 }
        }
        Text {
            visible: text !== "" && mod.display !== "value"
            text: FiliTheme.glyph(mod.text)
            color: FiliTheme.iconColor(label.color)
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.size
        }
        Text {
            id: label
            visible: mod.display !== "icon" || FiliTheme.glyph(mod.text) === ""
            text: FiliTheme.value(mod.text)
            elide: Text.ElideRight
            width: mod.vertical ? Math.min(implicitWidth, FiliTheme.barWidth - 2 * mod.pad) : implicitWidth
            color: mod.colors[mod.cls] ?? mod.colors[""] ?? mod.color
            font.family: FiliTheme.font
            font.pixelSize: mod.vertical ? FiliTheme.sizeSmall : FiliTheme.size
        }
    }
    // Blinking (backup running): opacity toggled every second, two renders per cycle instead of a continuous
    // animation (60 renders/s with software rendering)
    Timer {
        running: mod.blinkClass !== "" && mod.cls === mod.blinkClass
        repeat: true
        interval: 1000
        onTriggered: content.opacity = content.opacity < 1 ? 1 : 0.35
        onRunningChanged: content.opacity = 1
    }

    property alias hover: hov
    BarHover {
        id: hov
        anchors.fill: parent
        tip: {
            const name = mod.title || mod.tag;
            if (typeof mod.tip === "string" && mod.tip && (name || mod.hint))
                return { title: name, text: mod.tip, hint: mod.hint };
            return mod.tip;
        }
        tipInfo: mod.tipInfo
        click: mod.click
        rclick: mod.rclick
        mclick: mod.mclick
        scrollUp: mod.scrollUp
        scrollDown: mod.scrollDown
    }
}
