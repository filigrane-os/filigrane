// fili-panel Bluetooth (Quickshell.Bluetooth, BlueZ): activer, rechercher, connecter, déconnecter, oublier; en bas, partage
// de fichiers (fili-share): AirDrop, Bluetooth ou LocalSend, la même interface, grisés quand le protocole est indisponible
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import Quickshell.Io

ColumnLayout {
    id: view
    spacing: 4
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: adapter ? adapter.devices.values.filter(d => d.name && (d.paired || d.connected || adapter.discovering)) : []

    RowLayout {
        Layout.fillWidth: true
        Text {
            text: "Bluetooth"
            color: FiliTheme.voile
            font { family: FiliTheme.font; pixelSize: 14; weight: Font.Medium }
        }
        Item { Layout.fillWidth: true }
        PanelSwitch {
            objectName: "power"
            checked: view.adapter?.enabled ?? false
            switchable: !!view.adapter
            onToggled: view.adapter.enabled = !view.adapter.enabled
        }
    }
    Text {
        visible: !view.adapter
        text: "Aucun adaptateur Bluetooth détecté (contrôleur absent ou micrologiciel non chargé)"
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        Layout.maximumWidth: 300
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: FiliTheme.size }
    }
    PanelButton {
        objectName: "scan"
        visible: !!view.adapter && view.adapter.enabled
        glyph: ""
        label: view.adapter?.discovering ? "Recherche en cours…" : "Rechercher des appareils"
        detail: view.adapter?.discovering ? "arrêter" : ""
        onClicked: view.adapter.discovering = !view.adapter.discovering
    }
    PanelSection { visible: view.devices.length > 0; text: "APPAREILS" }
    Repeater {
        model: view.adapter?.enabled ? view.devices : []
        PanelButton {
            required property var modelData
            objectName: "device"
            glyph: modelData.connected ? "" : ""
            label: modelData.name
            sel: modelData.connected
            dim: !modelData.paired && !modelData.connected
            detail: modelData.connected ? (modelData.batteryAvailable ? Math.round(modelData.battery * 100) + " %" : "connecté")
                : modelData.paired ? "appairé" : "nouveau"
            // clic: connecter / déconnecter (appairer d'abord si nouveau); clic droit: oublier
            onClicked: b => {
                if (b === Qt.RightButton) {
                    modelData.forget();
                } else if (modelData.connected) {
                    modelData.disconnect();
                } else if (!modelData.paired) {
                    modelData.pair();
                } else {
                    modelData.connect();
                }
            }
        }
    }
    Text {
        visible: view.devices.length > 0
        Layout.topMargin: 4
        text: "clic: connecter / déconnecter · clic droit: oublier"
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: 12 }
    }

    // ───── partage de fichiers (fili-share) ─────
    // protocols: [{id, label, available, why}]; peers: [{id, name}] du protocole choisi
    property var protocols: []
    property string proto: ""
    property var peers: []
    property bool receiving: false
    readonly property var current: protocols.find(p => p.id === proto) ?? null
    readonly property bool shareOk: current !== null && current.available
    readonly property string share: FiliTheme.bin + "/fili-share"

    function shq(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }
    function refreshShare() {
        peers = [];
        receiving = false;
        if (!shareOk)
            return;
        peersProc.command = [share, "peers", proto];
        peersProc.running = true;
        statusProc.command = [share, "receive", proto, "status"];
        statusProc.running = true;
    }
    function choose(id) {
        proto = id;
        refreshShare();
    }
    function setReceiving(on) {
        receiving = on;
        FiliTheme.run(share + " receive " + proto + " " + (on ? "on" : "off"));
    }
    // Choix des fichiers (yazi) puis envoi, dans une fenêtre à part
    function sendTo(peer) {
        // commande composée avant la fermeture: fermer le panneau libère la vue
        const cmd = share + " send " + proto + " " + shq(peer.id) + " " + shq(peer.name);
        FiliPanel.close();
        FiliTheme.run(cmd);
    }
    Component.onCompleted: protocolsProc.running = true
    Process {
        id: protocolsProc
        command: [view.share, "protocols"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    view.protocols = JSON.parse(text);
                    const first = view.protocols.find(p => p.available) ?? view.protocols[0];
                    if (first)
                        view.choose(first.id);
                } catch (e) {}
            }
        }
    }
    Process {
        id: peersProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    view.peers = JSON.parse(text);
                } catch (e) {}
            }
        }
    }
    Process {
        id: statusProc
        stdout: StdioCollector { onStreamFinished: view.receiving = text.trim() === "on" }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 6
        implicitHeight: 1
        color: FiliTheme.nuit4
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 2
        Text {
            text: "Partage"
            color: FiliTheme.voile
            Layout.fillWidth: true
            font { family: FiliTheme.font; pixelSize: 14; weight: Font.Medium }
        }
        PanelSwitch {
            objectName: "share-receive"
            checked: view.receiving
            switchable: view.shareOk
            onToggled: view.setReceiving(!view.receiving)
        }
    }
    Text {
        text: "Recevoir: visible des appareils proches"
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: 12 }
    }
    PanelChips {
        objectName: "share-protocols"
        Layout.topMargin: 2
        model: view.protocols.map(p => ({ label: p.label, value: p.id, off: !p.available }))
        current: view.proto
        onPicked: v => view.choose(v)
    }
    Text {
        visible: view.current !== null && !view.current.available
        text: view.current ? view.current.label + " indisponible: " + view.current.why : ""
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        Layout.maximumWidth: 300
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: 12 }
    }
    PanelButton {
        objectName: "share-refresh"
        visible: view.shareOk
        glyph: ""
        label: "Rechercher à proximité"
        onClicked: view.refreshShare()
    }
    Repeater {
        model: view.shareOk ? view.peers : []
        PanelButton {
            required property var modelData
            objectName: "share-peer"
            glyph: ""
            label: modelData.name
            detail: "envoyer"
            onClicked: view.sendTo(modelData)
        }
    }
}
