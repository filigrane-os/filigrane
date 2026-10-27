pragma Singleton
// fili-hotkeys: fenêtre des raccourcis clavier de niri, au centre de l'écran, à la place de l'« Important Hotkeys »
// de niri (skip-at-startup). Lignes de ~/.local/bin/fili-hotkeys (binds avec hotkey-overlay-title), touches en
// pastilles. Affichée une fois par session au démarrage (marqueur dans $XDG_RUNTIME_DIR), puis par
// `fili-shell hotkeys` (Super+Maj+/) ou le panneau clavier. Fermeture: Échap, clic, ou 20 s au démarrage.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Singleton {
    id: hk
    property bool open: false
    property var entries: []
    // Ouverte par le démarrage: se referme seule
    property bool auto: false
    readonly property var caps: ({ Shift: "Maj", Space: "Espace", Slash: "/", Return: "↵", Tab: "Tab", Print: "Impr", Escape: "Échap" })

    function show() {
        FiliShell.popupOpened("hotkeys");
        FiliPanel.close();
        read.running = false;
        read.running = true;
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
        auto = false;
    }
    // Une fois par session: le marqueur disparaît avec $XDG_RUNTIME_DIR (tmpfs)
    function startup() {
        if (FiliTheme.testing)
            return;
        mark.running = true;
    }

    Process {
        id: read
        command: [FiliTheme.bin + "/fili-hotkeys"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    hk.entries = JSON.parse(text);
                } catch (e) {
                    hk.entries = [];
                }
            }
        }
    }
    Process {
        id: mark
        command: ["sh", "-c", 'm="${XDG_RUNTIME_DIR:-/tmp}/fili-hotkeys-shown"; [ -e "$m" ] && exit 1; : > "$m"']
        onExited: code => {
            if (code === 0) {
                hk.auto = true;
                hk.show();
            }
        }
    }
    Timer { interval: 20000; running: hk.open && hk.auto; onTriggered: hk.close() }
    Connections {
        target: FiliShell
        function onPopupOpened(who) {
            if (who !== "hotkeys")
                hk.close();
        }
    }

    PanelWindow {
        visible: hk.open && !FiliTheme.testing
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "fili-hotkeys"
        WlrLayershell.keyboardFocus: hk.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "#99101419"

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: hk.close()
        }
        FocusScope {
            anchors.fill: parent
            focus: true
            Keys.onPressed: hk.close()
            Rectangle {
                id: card
                anchors.centerIn: parent
                width: Math.min(parent.width - 48, 820)
                height: Math.min(parent.height - 48, content.implicitHeight + 40)
                color: FiliTheme.nuit
                border { color: FiliTheme.nuit4; width: 1 }
                radius: 12
                MouseArea { anchors.fill: parent }
                ColumnLayout {
                    id: content
                    anchors { fill: parent; margins: 20 }
                    spacing: 14
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Raccourcis clavier"
                            color: FiliTheme.voile
                            Layout.fillWidth: true
                            font { family: FiliTheme.font; pixelSize: 18; weight: Font.Medium }
                        }
                        Text {
                            text: "Échap pour fermer"
                            color: FiliTheme.ardoise
                            font { family: FiliTheme.font; pixelSize: 12 }
                        }
                    }
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: FiliTheme.nuit4 }
                    GridLayout {
                        columns: card.width > 640 ? 2 : 1
                        columnSpacing: 28
                        rowSpacing: 6
                        Layout.fillWidth: true
                        Repeater {
                            model: hk.entries
                            RowLayout {
                                id: row
                                required property var modelData
                                readonly property int colon: modelData.title.indexOf(": ")
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.preferredHeight: 38
                                Layout.alignment: Qt.AlignTop
                                spacing: 10
                                Row {
                                    Layout.preferredWidth: 150
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 4
                                    Repeater {
                                        model: row.modelData.key.split("+").map(k => hk.caps[k] ?? k)
                                        Rectangle {
                                            required property string modelData
                                            width: cap.implicitWidth + 12
                                            height: 22
                                            radius: 5
                                            color: FiliTheme.nuit3
                                            border { color: FiliTheme.nuit4; width: 1 }
                                            Text {
                                                id: cap
                                                anchors.centerIn: parent
                                                text: parent.modelData
                                                color: FiliTheme.brume
                                                font { family: FiliTheme.font; pixelSize: 12 }
                                            }
                                        }
                                    }
                                }
                                Column {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    Text {
                                        width: parent.width
                                        text: row.colon > 0 ? row.modelData.title.slice(row.colon + 2) : row.modelData.title
                                        elide: Text.ElideRight
                                        color: FiliTheme.brume
                                        font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                                    }
                                    Text {
                                        visible: row.colon > 0
                                        text: row.modelData.title.slice(0, row.colon)
                                        color: FiliTheme.ardoise
                                        font { family: FiliTheme.font; pixelSize: 11 }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
