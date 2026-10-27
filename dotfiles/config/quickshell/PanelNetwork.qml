// fili-panel réseau (iwd): réseaux Wi-Fi (clic = connecter, mot de passe si nouveau, clic droit = oublier), activer,
// déconnecter, état de la liaison (FiliInfo network). Les actions passent par fili-net (iwctl).
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

ColumnLayout {
    id: view
    spacing: 4
    property var wifi: ({ device: "", powered: false, networks: [] })
    property string asking: ""
    property string message: ""
    readonly property string net: FiliTheme.bin + "/fili-net"

    // Icône selon la force du signal (0-100, par paliers de 25): codes md-wifi_strength_1..4 (police Fili Icons)
    function signalGlyph(signal) {
        return String.fromCodePoint(signal >= 75 ? 0xF0928 : signal >= 50 ? 0xF0925 : signal >= 25 ? 0xF0922 : 0xF091F);
    }
    function refresh() {
        if (!list.running)
            list.running = true;
    }
    function act(args, env) {
        message = "";
        job.command = ["sh", "-c", (env ?? "") + 'exec "$0" "$@"', net].concat(args);
        job.running = true;
    }
    function connect(n) {
        if (n.connected) {
            act(["disconnect"]);
        } else if (n.known || n.security === "open") {
            act(["connect", n.ssid]);
        } else {
            asking = n.ssid;
        }
    }
    Component.onCompleted: {
        refresh();
        scan.start();
    }
    Process {
        id: list
        command: [view.net, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    view.wifi = JSON.parse(text);
                } catch (e) {}
            }
        }
    }
    Process {
        id: job
        stderr: StdioCollector { id: jobErr }
        onExited: code => {
            view.message = code === 0 ? "" : jobErr.text.replace(/\x1b\[[0-9;]*m/g, "").trim().split("\n")[0];
            view.asking = "";
            view.refresh();
            info.refresh();
        }
    }
    // Recherche à l'ouverture, liste relue ensuite (iwd met quelques secondes à rafraîchir)
    Timer {
        id: scan
        interval: 100
        onTriggered: {
            view.act(["scan"]);
            relist.start();
        }
    }
    Timer { id: relist; interval: 3000; repeat: true; running: false; onTriggered: view.refresh() }

    RowLayout {
        Layout.fillWidth: true
        Text {
            text: "Wi-Fi"
            color: FiliTheme.voile
            font { family: FiliTheme.font; pixelSize: 14; weight: Font.Medium }
        }
        Item { Layout.fillWidth: true }
        PanelSwitch {
            objectName: "wifi-power"
            visible: view.wifi.device !== ""
            checked: view.wifi.powered
            onToggled: view.act(["power", view.wifi.powered ? "off" : "on"])
        }
    }
    PanelSection { visible: view.wifi.networks.length > 0; text: "RÉSEAUX" }
    Repeater {
        model: view.wifi.powered ? view.wifi.networks : []
        ColumnLayout {
            required property var modelData
            required property int index
            spacing: 2
            Layout.fillWidth: true
            PanelButton {
                objectName: "network"
                glyph: view.signalGlyph(modelData.signal)
                label: modelData.ssid
                sel: modelData.connected
                detail: modelData.connected ? "connecté" : modelData.known ? "connu" : modelData.security === "open" ? "ouvert" : "chiffré"
                onClicked: b => {
                    if (b === Qt.RightButton) {
                        if (modelData.known)
                            view.act(["forget", modelData.ssid]);
                    } else {
                        view.connect(modelData);
                    }
                }
            }
            Rectangle {
                visible: view.asking === modelData.ssid
                Layout.fillWidth: true
                implicitHeight: 30
                radius: 6
                color: FiliTheme.nuit3
                border.color: FiliTheme.voile
                TextInput {
                    id: pass
                    objectName: "passphrase"
                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    activeFocusOnTab: true
                    onVisibleChanged: if (visible) { text = ""; forceActiveFocus(); }
                    color: FiliTheme.brume
                    font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                    onAccepted: view.act(["connect", view.asking], "FILI_NET_PASS=" + "'" + text.replace(/'/g, "'\\''") + "' ")
                    Keys.onEscapePressed: view.asking = ""
                    Text {
                        visible: !parent.text
                        text: "Mot de passe, Entrée pour se connecter"
                        color: FiliTheme.ardoise
                        font: parent.font
                    }
                }
            }
            Rectangle {
                visible: modelData.connected && index < view.wifi.networks.length - 1
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.bottomMargin: 2
                implicitHeight: 1
                color: FiliTheme.nuit3
            }
        }
    }
    Text {
        visible: view.message !== ""
        text: view.message
        color: FiliTheme.cendre
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        Layout.maximumWidth: 300
        font { family: FiliTheme.font; pixelSize: 12 }
    }
    PanelSection { text: "LIAISON" }
    PanelInfo { id: info; topic: "network" }
    PanelButton {
        Layout.topMargin: 4
        glyph: ""
        label: "Réseaux avancés (impala)"
        dim: true
        onClicked: { FiliPanel.close(); FiliTheme.run(FiliTheme.bin + "/bar-tui impala"); }
    }
}
