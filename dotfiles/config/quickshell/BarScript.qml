// Module de la fili-bar alimenté par un script: même protocole que les modules custom de Waybar (une ligne JSON
// {text, class, tooltip} par mise à jour), pour réutiliser bar-status, bar-tray, bar-alert, bar-stats...
//   interval > 0: relancé toutes les N s; 0: une fois (puis sur signal); -1: résident (une ligne par mise à jour)
//   signal: rafraîchi par `fili-shell signal N` (ex-`pkill -RTMIN+N waybar`)
//   stat: sans script, état écrit par bar-stats (`stat NOM JSON`, voir FiliShell)
//   value: sans script, état lié à un objet {text, class, tooltip} (BarState)
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: mod
    property string cmd
    property string stat
    property var value: null
    onValueChanged: if (value) apply(value)
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
    property real pad: FiliTheme.pad
    // Étiquette en petites capitales devant la valeur (CPU, RAM)
    property string tag

    property string text: ""
    property string cls: ""
    // Texte ou fiche de la fili-tooltip (voir FiliTooltip)
    property var tip: ""
    // Ligne d'aide de la fili-tooltip (actions des clics)
    property string hint
    // Titre de la fiche d'un tooltip en texte simple (sinon l'étiquette); standard: titre à gauche, contenu à droite
    property string title
    // Fiche lue au survol (remplace le texte du script), voir BarHover
    property string tipInfo
    property bool pending: false

    visible: !(hideEmpty && text === "")
    implicitWidth: visible ? Math.max(FiliTheme.isIcon(mod.text) ? FiliTheme.iconCell : 0, content.implicitWidth + 2 * pad) : 0
    implicitHeight: FiliTheme.barHeight

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

    Row {
        id: content
        anchors.centerIn: parent
        spacing: FiliTheme.labelGap
        Text {
            visible: mod.tag !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: mod.tag
            color: FiliTheme.ardoise
            font { family: FiliTheme.font; pixelSize: 11; letterSpacing: 1 }
        }
        Text {
            visible: text !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: FiliTheme.glyph(mod.text)
            color: FiliTheme.iconColor(label.color)
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.size
        }
        Text {
            id: label
            text: FiliTheme.value(mod.text)
            color: mod.colors[mod.cls] ?? mod.colors[""] ?? mod.color
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.size
        }
    }
    // Clignotement (sauvegarde en cours): opacité basculée chaque seconde, deux rendus par cycle au lieu d'une
    // animation continue (60 rendus/s en rendu logiciel)
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
