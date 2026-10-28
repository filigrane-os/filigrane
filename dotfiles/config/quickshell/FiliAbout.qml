pragma Singleton
// fili-about: fenêtre « À propos » au centre de l'écran: logo, nom de la machine, puis Filigrane (version du dépôt),
// système et machine, lus par ~/.local/bin/fili-about (JSON) à chaque ouverture, rien ne tourne fenêtre fermée.
// Ouverture: `fili-shell about`, menu › System › About, clic milieu sur le logo de la fili-bar.
// Fermeture: Échap, clic hors de la carte. C (ou le lien) copie la fiche en texte (rapport de bug).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Singleton {
    id: about
    property bool open: false
    property var card: ({ host: "", sections: [] })

    function show() {
        FiliShell.popupOpened("about");
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
    }
    // Fiche en texte brut: une section par bloc, « libellé: valeur »
    function text() {
        return ["Filigrane · " + card.host].concat(card.sections.map(s => s.name + "\n" + s.rows.map(r => "  " + r[0] + ": " + r[1]).join("\n"))).join("\n\n");
    }
    function copy() {
        if (FiliTheme.testing)
            FiliTheme.ran = FiliTheme.ran.concat(["wl-copy " + text()]);
        else
            Quickshell.execDetached(["wl-copy", text()]);
        close();
    }

    Process {
        id: read
        command: [FiliTheme.bin + "/fili-about"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    about.card = JSON.parse(text);
                } catch (e) {
                    about.card = { host: "", sections: [] };
                }
            }
        }
    }
    Connections {
        target: FiliShell
        function onPopupOpened(who) {
            if (who !== "about")
                about.close();
        }
    }

    PanelWindow {
        visible: about.open && !FiliTheme.testing
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "fili-about"
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
            Keys.onPressed: e => {
                if (e.key === Qt.Key_C)
                    about.copy();
                else
                    about.close();
            }
            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width - 48, 520)
                height: Math.min(parent.height - 48, content.implicitHeight + 48)
                color: FiliTheme.nuit
                border { color: FiliTheme.nuit4; width: 1 }
                radius: 12
                clip: true
                MouseArea { anchors.fill: parent }
                ColumnLayout {
                    id: content
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
                    spacing: 14
                    // Logo empilé (brand/, lié dans ~/.local/share/filigrane), version claire ou sombre
                    Image {
                        Layout.alignment: Qt.AlignHCenter
                        source: "file://" + Quickshell.env("HOME") + "/.local/share/filigrane/filigrane-empile-" + (FiliTheme.light ? "clair" : "sombre") + ".svg"
                        sourceSize.width: 150
                        fillMode: Image.PreserveAspectFit
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "L'OS en toute discrétion" + (about.card.host ? "  ·  " + about.card.host : "")
                        color: FiliTheme.brume2
                        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: Font.Light }
                    }
                    Repeater {
                        model: about.card.sections
                        ColumnLayout {
                            id: section
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 4
                            Rectangle { Layout.fillWidth: true; Layout.bottomMargin: 6; implicitHeight: 1; color: FiliTheme.nuit4 }
                            Text {
                                text: section.modelData.name.toUpperCase()
                                color: FiliTheme.ardoise
                                font { family: FiliTheme.font; pixelSize: 11; weight: Font.Medium; letterSpacing: 1.6 }
                            }
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: 16
                                rowSpacing: 3
                                Repeater {
                                    model: section.modelData.rows.reduce((a, r) => a.concat([{ t: r[0], key: true }, { t: r[1], key: false }]), [])
                                    Text {
                                        required property var modelData
                                        text: modelData.t
                                        color: modelData.key ? FiliTheme.brume2 : FiliTheme.brume
                                        Layout.preferredWidth: modelData.key ? 110 : -1
                                        Layout.fillWidth: !modelData.key
                                        elide: Text.ElideRight
                                        font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                                    }
                                }
                            }
                        }
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 4
                        text: "C pour copier · Échap pour fermer"
                        color: FiliTheme.ardoise
                        font { family: FiliTheme.font; pixelSize: 12 }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: about.copy()
                        }
                    }
                }
            }
        }
    }
}
