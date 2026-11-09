// Bluetooth (always visible, greyed out without an adapter): click = panel (turn on, pair, connect, forget)
import QtQuick
import Quickshell.Io
import Quickshell.Bluetooth
import qs
import qs.bar

BarItem {
    id: btItem
    objectName: "bluetooth"
    panel: "bluetooth"
    panelSource: Qt.resolvedUrl("BluetoothPanel.qml")
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var connected: adapter ? adapter.devices.values.filter(d => d.connected) : []
    // File reception active (fili-share, one of the protocols): SHARE when no device is connected
    property bool sharing: false
    Process {
        id: shareProc
        command: [FiliTheme.bin + "/fili-share", "receive", "any", "status"]
        stdout: SplitParser { onRead: line => btItem.sharing = line.trim() === "on" }
    }
    Connections {
        target: FiliShell
        function onRefresh(n) {
            if (n === 24 && !shareProc.running)
                shareProc.running = true;
        }
    }
    Component.onCompleted: shareProc.running = true
    text: {
        if (!adapter)
            return "";
        if (!adapter.enabled)
            return " OFF";
        // Connected devices: their count (names and batteries in the card); none and reception active: SHARE
        if (connected.length === 0 && sharing)
            return " SHARE";
        return " " + connected.length;
    }
    color: !adapter ? FiliTheme.ardoise : FiliTheme.brume
    tip: !adapter ? { title: "Bluetooth", rows: [[FiliI18n.tr("State"), FiliI18n.tr("no adapter found")]], hint: FiliI18n.tr("click: Bluetooth panel") } : {
        title: "Bluetooth",
        rows: [[adapter.name, adapter.enabled ? FiliI18n.tr("on") : FiliI18n.tr("off")]].concat(
            adapter.devices.values.filter(d => d.paired || d.connected).map(d => [d.name,
                (d.connected ? FiliI18n.tr("connected") : FiliI18n.tr("paired")) + (d.connected && d.batteryAvailable ? ", " + Math.round(d.battery * 100) + " %" : "")])),
        hint: FiliI18n.tr("click: Bluetooth panel (pair, connect, forget)")
    }
    hover.onLeftClicked: togglePanel()
}
