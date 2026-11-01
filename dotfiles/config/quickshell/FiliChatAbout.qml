pragma Singleton
// fili-chat-about: fiche « À propos de Rob » (le chat de Filigrane), au centre de l'écran: icône robot (celle du module
// IA de la fili-bar), nom, agent et version (lus par `fili-ai status` à chaque ouverture, rien ne tourne fenêtre
// fermée), session et présentation du tiroir. Ouverture: menu Rob › About Rob (`fili-shell chat about`).
// Fermeture: Échap, clic hors de la carte.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Singleton {
    id: about
    property bool open: false
    // Champs de `fili-ai status`: agent, modèle, version de l'agent installé
    property var info: ({ agent: "", model: "", version: "" })
    readonly property string icon: String.fromCodePoint(0xf06a9)
    readonly property string name: "Rob"
    readonly property var rows: [
        [FiliI18n.tr("Agent"), info.agent || "—"],
        [FiliI18n.tr("Version"), info.version || "—"],
        [FiliI18n.tr("Model"), info.model || FiliI18n.tr("default")],
        [FiliI18n.tr("Sessions"), String(FiliChat.sessions.length)],
        [FiliI18n.tr("View"), FiliI18n.tr(FiliChat.dock ? "Dock Beside Windows" : "Float Above Windows") + " · " + FiliChat.viewWidth + " px"],
        [FiliI18n.tr("Follow"), FiliChat.follow]
    ]

    function show() {
        FiliShell.popupOpened("chat-about");
        if (!FiliTheme.testing) {
            read.running = false;
            read.running = true;
        }
        open = true;
    }
    function toggle() {
        if (open)
            close();
        else
            show();
    }
    function close() {
        open = false;
    }

    Process {
        id: read
        command: [FiliTheme.bin + "/fili-ai", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                const field = k => (lines.find(l => l.startsWith(k + ":")) ?? "").slice(k.length + 1).trim();
                const agent = field("Agent");
                // « claude (Claude Code (Anthropic)) »: le nom lisible est entre parenthèses
                const nice = /\((.*)\)\s*$/.exec(agent);
                const key = agent.split(" ")[0];
                const inst = lines.find(l => /^\s+\S+ \S+/.test(l) && l.trim().startsWith(key + " "));
                about.info = { agent: nice ? nice[1] : agent, model: field("Model") === "default" ? "" : field("Model"), version: inst ? inst.trim().split(" ")[1] : "" };
            }
        }
    }
    Connections {
        target: FiliShell
        function onPopupOpened(who) {
            if (who !== "chat-about")
                about.close();
        }
    }

    PanelWindow {
        visible: about.open && !FiliTheme.testing
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "fili-chat-about"
        WlrLayershell.keyboardFocus: about.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "#99101419"

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: about.close()
        }
        FocusScope {
            anchors.fill: parent
            focus: true
            Keys.onPressed: e => about.close()
            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width - 48, 400)
                height: Math.min(parent.height - 48, content.implicitHeight + 48)
                color: FiliTheme.nuit
                border { color: FiliTheme.nuit4; width: 1 }
                radius: FiliTheme.radiusWindow
                clip: true
                MouseArea { anchors.fill: parent }
                ColumnLayout {
                    id: content
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: FiliTheme.space6 }
                    spacing: FiliTheme.space3
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: about.icon
                        color: FiliTheme.voile
                        font { family: FiliTheme.font; pixelSize: 64 }
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: about.name
                        color: FiliTheme.brume
                        font { family: FiliTheme.font; pixelSize: 28; weight: FiliTheme.weightAccent }
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: FiliI18n.tr("The assistant of Filigrane")
                        color: FiliTheme.brume2
                        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: Font.Light }
                    }
                    Rectangle { Layout.fillWidth: true; Layout.topMargin: FiliTheme.space2; implicitHeight: 1; color: FiliTheme.nuit4 }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 16
                        rowSpacing: 3
                        Repeater {
                            model: about.rows.reduce((a, r) => a.concat([{ t: r[0], key: true }, { t: r[1], key: false }]), [])
                            Text {
                                required property var modelData
                                text: modelData.t
                                color: modelData.key ? FiliTheme.brume2 : FiliTheme.brume
                                Layout.preferredWidth: modelData.key ? 100 : -1
                                Layout.fillWidth: !modelData.key
                                elide: Text.ElideRight
                                font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                            }
                        }
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: FiliTheme.space1
                        text: FiliI18n.tr("Esc to close")
                        color: FiliTheme.ardoise
                        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList }
                    }
                }
            }
        }
    }
}
