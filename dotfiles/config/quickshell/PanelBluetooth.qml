// fili-panel Bluetooth (Quickshell.Bluetooth, BlueZ): activer, rechercher, connecter, déconnecter, oublier
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth

ColumnLayout {
    id: view
    spacing: 4
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: adapter ? adapter.devices.values.filter(d => d.name && (d.paired || d.connected || adapter.discovering)) : []

    Text {
        text: "Bluetooth"
        color: FiliTheme.voile
        font { family: FiliTheme.font; pixelSize: 14; weight: Font.Medium }
    }
    Text {
        visible: !view.adapter
        text: "Aucun adaptateur"
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: FiliTheme.size }
    }
    PanelButton {
        objectName: "power"
        visible: !!view.adapter
        glyph: ""
        label: view.adapter?.enabled ? "Activé" : "Désactivé"
        sel: view.adapter?.enabled ?? false
        onClicked: view.adapter.enabled = !view.adapter.enabled
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
}
