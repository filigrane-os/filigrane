pragma Singleton
// fili-panel: fenêtre d'actions unique sous l'élément cliqué de la fili-bar (réseau, son, Bluetooth, alimentation,
// moniteur), inspirée des panneaux d'Omarchy. Une vue à la fois, chargée à l'ouverture et libérée à la fermeture
// (rien ne tourne panneau fermé). Fermeture: Échap, clic sur une fenêtre (perte du focus), clic sur la barre ou même
// élément recliqué.
// Utilisation: FiliPanel.toggle(item, "network"|"audio"|"bluetooth"|"power"|"monitor"|"keyboard"|"display", fenêtreDeLaBarre)
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
        power: "PanelPower.qml", monitor: "PanelMonitor.qml", keyboard: "PanelKeyboard.qml", display: "PanelDisplay.qml"
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

    // Fenêtre de la taille de la carte (pas de calque plein écran: 32 Mo d'image en moins tant qu'un panneau est ouvert).
    // Clic ailleurs: niri donne le focus à une autre fenêtre, celle-ci perd le sien et le panneau se ferme.
    PanelWindow {
        id: win
        visible: panel.open && !FiliTheme.testing
        screen: panel.screen
        anchors { top: true; left: true }
        margins.top: FiliTheme.barHeight + 6
        margins.left: Math.max(8, Math.min((panel.screen?.width ?? 0) - card.width - 8, panel.anchorX - card.width / 2))
        implicitWidth: card.width
        implicitHeight: card.height
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "fili-panel"
        // Vue « passive » (visualiseur de clavier): pas de focus, la frappe de wtype arrive dans la fenêtre d'avant
        WlrLayershell.keyboardFocus: panel.open && !(loader.item?.passive ?? false) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        FocusScope {
            id: scope
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: panel.close()
            // Focus reçu à l'ouverture puis perdu (clic sur une fenêtre): fermeture
            property bool held: false
            Window.onActiveChanged: {
                if (Window.active)
                    held = true;
                else if (held)
                    panel.close();
            }
            Connections {
                target: panel
                function onOpenChanged() {
                    scope.held = false;
                }
            }
            Rectangle {
                id: card
                width: 340
                height: (loader.item ? loader.item.implicitHeight : 0) + 28
                color: FiliTheme.nuit
                border.color: FiliTheme.nuit4
                border.width: 1
                radius: 10
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
