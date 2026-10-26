// Module de la fili-bar alimenté par un script: même protocole que les modules custom de Waybar (une ligne JSON
// {text, class, tooltip} par mise à jour), pour réutiliser bar-status, bar-tray, bar-alert, bar-stats...
//   interval > 0: relancé toutes les N s; 0: une fois (puis sur signal); -1: résident (une ligne par mise à jour)
//   signal: rafraîchi par `fili-shell signal N` (ex-`pkill -RTMIN+N waybar`)
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: mod
    property string cmd
    property int interval: 0
    property int signal: -1
    property bool hideEmpty: true
    // Couleur par classe (clé "" = défaut)
    property var colors: ({})
    property color color: FiliTheme.brume
    // Classe qui clignote (sauvegarde en cours)
    property string blinkClass: ""
    property string click
    property string rclick
    property string mclick
    property string scrollUp
    property string scrollDown
    property real pad: 4

    property string text: ""
    property string cls: ""
    property string tip: ""
    // Ligne d'aide de la fili-tooltip (actions des clics)
    property string hint
    // Fiche lue au survol (remplace le texte du script), voir BarHover
    property string tipCmd
    property bool pending: false

    visible: !(hideEmpty && text === "")
    implicitWidth: visible ? label.implicitWidth + 2 * pad : 0
    implicitHeight: FiliTheme.barHeight

    function parse(line) {
        line = line.trim();
        if (!line)
            return;
        try {
            const j = JSON.parse(line);
            mod.text = j.text ?? "";
            mod.cls = Array.isArray(j["class"]) ? (j["class"][0] ?? "") : (j["class"] ?? "");
            mod.tip = j.tooltip ?? "";
        } catch (e) {
            mod.text = line;
        }
    }

    function update() {
        if (proc.running) {
            if (interval >= 0)
                pending = true;
        } else {
            proc.running = true;
        }
    }

    Component.onCompleted: proc.running = true

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
            } else if (mod.interval < 0) {
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

    Text {
        id: label
        anchors.centerIn: parent
        text: mod.text
        color: mod.colors[mod.cls] ?? mod.colors[""] ?? mod.color
        font.family: FiliTheme.font
        font.pixelSize: FiliTheme.size
        SequentialAnimation on opacity {
            running: mod.blinkClass !== "" && mod.cls === mod.blinkClass
            loops: Animation.Infinite
            onStopped: label.opacity = 1
            NumberAnimation { to: 0.35; duration: 1000 }
            NumberAnimation { to: 1; duration: 1000 }
        }
    }

    property alias hover: hov
    BarHover {
        id: hov
        anchors.fill: parent
        tip: mod.hint ? { text: mod.tip, hint: mod.hint } : mod.tip
        tipCmd: mod.tipCmd
        click: mod.click
        rclick: mod.rclick
        mclick: mod.mclick
        scrollUp: mod.scrollUp
        scrollDown: mod.scrollDown
    }
}
