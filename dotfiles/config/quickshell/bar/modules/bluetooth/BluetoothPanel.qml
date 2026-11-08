// fili-panel Bluetooth (Quickshell.Bluetooth, BlueZ): turn on, scan, connect, disconnect, forget; at the bottom, file
// sharing (fili-share): AirDrop, Bluetooth or LocalSend, the same interface, greyed out when the protocol is unavailable
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import Quickshell.Io
import qs.bar
import qs.controls
import qs

ColumnLayout {
    id: view
    spacing: FiliTheme.space1
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: adapter ? adapter.devices.values.filter(d => d.name && (d.paired || d.connected || adapter.discovering)) : []

    // Quickshell registers no BlueZ pairing agent, so Device.pair() is refused: fili-bt-pair has
    // bluetoothctl register one (just works), then trusts and connects.
    property bool pairing: false
    readonly property var pairCommand: pairProc.command
    // Device in a transitional state: clicks are ignored
    function busy(d) {
        return pairing || d.pairing || d.state === BluetoothDeviceState.Connecting || d.state === BluetoothDeviceState.Disconnecting;
    }
    // Click on a device: connect / disconnect (pair first if new); right click: forget
    function activate(d, button) {
        if (busy(d))
            return;
        if (button === Qt.RightButton)
            d.forget();
        else if (d.connected)
            d.disconnect();
        else if (!d.paired)
            pairDevice(d.address);
        else
            d.connect();
    }
    function pairDevice(addr) {
        if (pairing)
            return;
        pairing = true;
        pairProc.command = [FiliTheme.bin + "/fili-bt-pair", addr];
        pairProc.running = true;
        if (!pairProc.running)
            pairing = false;
    }
    Process {
        id: pairProc
        onRunningChanged: if (!running) view.pairing = false
        // Never started (command missing): no running change follows, so release here too
        onExited: view.pairing = false
    }

    RowLayout {
        Layout.fillWidth: true
        Text {
            text: "Bluetooth"
            color: FiliTheme.voile
            font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
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
        text: FiliI18n.tr("No Bluetooth adapter found (no controller, or firmware not loaded)")
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
        label: view.adapter?.discovering ? FiliI18n.tr("Searching…") : FiliI18n.tr("Search for devices")
        detail: view.adapter?.discovering ? FiliI18n.tr("stop") : ""
        onClicked: view.adapter.discovering = !view.adapter.discovering
    }
    PanelSection { visible: view.devices.length > 0; text: FiliI18n.tr("DEVICES") }
    Repeater {
        model: view.adapter?.enabled ? view.devices : []
        PanelButton {
            required property var modelData
            objectName: "device"
            glyph: modelData.connected ? "" : ""
            label: modelData.name
            sel: modelData.connected
            dim: !modelData.paired && !modelData.connected
            detail: modelData.pairing ? FiliI18n.tr("pairing…")
                : modelData.state === BluetoothDeviceState.Connecting ? FiliI18n.tr("connecting…")
                : modelData.state === BluetoothDeviceState.Disconnecting ? FiliI18n.tr("disconnecting…")
                : modelData.connected ? (modelData.batteryAvailable ? Math.round(modelData.battery * 100) + " %" : FiliI18n.tr("connected"))
                : modelData.paired ? FiliI18n.tr("paired") : FiliI18n.tr("new")
            onClicked: b => view.activate(modelData, b)
        }
    }
    Text {
        visible: view.devices.length > 0
        Layout.topMargin: FiliTheme.space1
        text: FiliI18n.tr("click: connect / disconnect · right click: forget")
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList }
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
    // File choice (fili-file) then sending, in a separate window
    function sendTo(peer) {
        // command built before closing: closing the panel frees the view
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
        Layout.topMargin: FiliTheme.space2
        implicitHeight: 1
        color: FiliTheme.nuit4
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 2
        Text {
            text: FiliI18n.tr("Sharing")
            color: FiliTheme.voile
            Layout.fillWidth: true
            font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
        }
        PanelSwitch {
            objectName: "share-receive"
            checked: view.receiving
            switchable: view.shareOk
            onToggled: view.setReceiving(!view.receiving)
        }
    }
    Text {
        text: FiliI18n.tr("Receive: visible to nearby devices")
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList }
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
        text: view.current ? FiliI18n.tr("%1 unavailable: %2", view.current.label, view.current.why) : ""
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        Layout.maximumWidth: 300
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList }
    }
    PanelButton {
        objectName: "share-refresh"
        visible: view.shareOk
        glyph: ""
        label: FiliI18n.tr("Search nearby")
        onClicked: view.refreshShare()
    }
    Repeater {
        model: view.shareOk ? view.peers : []
        PanelButton {
            required property var modelData
            objectName: "share-peer"
            glyph: ""
            label: modelData.name
            detail: FiliI18n.tr("send")
            onClicked: view.sendTo(modelData)
        }
    }
}
