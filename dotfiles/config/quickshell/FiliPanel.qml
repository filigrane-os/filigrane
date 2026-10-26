pragma Singleton
// fili-panel: fenêtre d'actions unique sous l'élément cliqué de la fili-bar (réseau, son, Bluetooth, alimentation,
// moniteur), inspirée des panneaux d'Omarchy. Une vue à la fois, chargée à l'ouverture et libérée à la fermeture
// (rien ne tourne panneau fermé). Fermeture: Échap, clic hors du panneau ou même élément recliqué.
// Utilisation: FiliPanel.toggle(item, "network"|"audio"|"bluetooth"|"power"|"monitor"|"brightness"|"keyboard"|"display", fenêtreDeLaBarre)
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

Singleton {
    id: panel
    property string view: ""
    onViewChanged: FiliShell.panelOpen = view !== ""
    property real anchorX: 0
    property var screen: null
    readonly property bool open: view !== ""
    // Vue chargée (tests)
    property alias loaded: loader.item
    readonly property var views: ({
        network: "PanelNetwork.qml", audio: "PanelAudio.qml", bluetooth: "PanelBluetooth.qml",
        power: "PanelPower.qml", monitor: "PanelMonitor.qml", brightness: "PanelBrightness.qml", keyboard: "PanelKeyboard.qml", display: "PanelDisplay.qml"
    })

    function toggle(item, name, win) {
        FiliTooltip.hide();
        if (view === name) {
            close();
            return;
        }
        FiliShell.popupOpened("panel");
        anchorX = item.mapToItem(null, item.width / 2, 0).x;
        screen = win?.screen ?? null;
        view = name;
    }
    // Commande `fili-shell panel NOM` (raccourci clavier): sous le coin droit de la barre du premier écran
    function summon(name) {
        if (name === "close" || view === name) {
            close();
            return;
        }
        FiliTooltip.hide();
        FiliShell.popupOpened("panel");
        anchorX = 100000;
        screen = Quickshell.screens[0] ?? null;
        view = name in views ? name : "";
    }
    function close() {
        view = "";
    }

    Connections {
        target: FiliShell
        function onPopupOpened(who) {
            if (who !== "panel")
                panel.close();
        }
    }

    PanelWindow {
        visible: panel.open && !FiliTheme.testing
        screen: panel.screen
        anchors { top: true; bottom: true; left: true; right: true }
        margins.top: FiliTheme.barHeight
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "fili-panel"
        // Vue « passive » (visualiseur de clavier): pas de focus, la frappe de wtype arrive dans la fenêtre d'avant
        WlrLayershell.keyboardFocus: panel.open && !(loader.item?.passive ?? false) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: panel.close()
        }
        FocusScope {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: panel.close()
            Rectangle {
                id: card
                width: 340
                height: (loader.item ? loader.item.implicitHeight : 0) + 28
                x: Math.max(8, Math.min(parent.width - width - 8, panel.anchorX - width / 2))
                y: 6
                color: FiliTheme.nuit
                border.color: FiliTheme.nuit4
                border.width: 1
                radius: 10
                MouseArea { anchors.fill: parent }
                Loader {
                    id: loader
                    objectName: "panel-view"
                    anchors { fill: parent; margins: 14 }
                    source: panel.open ? panel.views[panel.view] : ""
                }
            }
        }
    }
}
