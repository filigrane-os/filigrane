pragma Singleton
// fili-panel: fenêtre d'actions unique sous l'élément cliqué de la fili-bar (réseau, son, Bluetooth, alimentation,
// moniteur), inspirée des panneaux d'Omarchy. Une vue à la fois, chargée à l'ouverture et libérée à la fermeture
// (rien ne tourne panneau fermé). Fermeture: Échap, clic sur une fenêtre (perte du focus), clic sur la barre ou même
// élément recliqué.
// Utilisation: FiliPanel.toggle(item, "network"|"audio"|"bluetooth"|"power"|"monitor"|"keyboard"|"display", fenêtreDeLaBarre)
// Clavier: Mod+A (`fili-shell panel toggle`) ouvre le dernier panneau ou ferme; ←/→ (Maj+←/→ sur un curseur, une rangée
// de choix ou un champ) passe au panneau voisin dans l'ordre de la barre, fili-notification-center compris (ring);
// ↑/↓ ou Tab/Maj+Tab d'élément en élément, Entrée ou Espace pour agir, Échap pour fermer.
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

    // Dernier panneau ouvert (Mod+A le rouvre)
    property string last: "monitor"
    // Ordre des panneaux au clavier (←/→): celui des modules de la barre; "center" = fili-notification-center
    readonly property var ring: ["monitor", "audio", "keyboard", "display", "bluetooth", "network", "center", "power"]
    // Module de la barre de chaque panneau, par écran: le panneau ouvert au clavier se place sous lui
    property var modules: ({})
    function register(name, item, win) {
        const s = win?.screen?.name ?? "";
        modules[s] = modules[s] ?? {};
        modules[s][name] = { item: item, win: win };
    }

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
        last = name;
    }
    // Commande `fili-shell panel NOM|toggle|close` (raccourcis clavier): sous le module du panneau
    function summon(name) {
        if (name === "toggle") {
            if (open || FiliNotification.centerOpen) {
                close();
                FiliNotification.centerOpen = false;
            } else {
                openKeyed(last);
            }
        } else if (name === "close" || view === name) {
            close();
        } else if (name in views) {
            openKeyed(name);
        }
    }
    // Panneau voisin (d = ±1) dans l'ordre de la barre
    function step(d) {
        const i = ring.indexOf(FiliNotification.centerOpen ? "center" : view);
        openKeyed(ring[(i + d + ring.length) % ring.length]);
    }
    // Ouverture au clavier: sous le module de la barre de l'écran courant (premier écran à défaut), premier élément choisi
    function openKeyed(name) {
        FiliTooltip.hide();
        const s = screen?.name ?? Quickshell.screens[0]?.name ?? "";
        const m = (modules[s] ?? Object.values(modules)[0] ?? {})[name];
        if (name === "center") {
            close();
            FiliShell.keyNav = true;
            if (!FiliNotification.centerOpen)
                FiliNotification.toggleCenter();
            return;
        }
        FiliShell.popupOpened("panel");
        FiliShell.keyNav = true;
        anchorX = m ? m.item.mapToItem(null, m.item.width / 2, 0).x : 100000;
        screen = m?.win?.screen ?? screen ?? Quickshell.screens[0] ?? null;
        view = name;
        last = name;
    }
    function close() {
        view = "";
    }
    // Élément suivant (ou précédent) de la chaîne de focus d'une fenêtre, à partir de l'élément actif (from, lu par
    // l'appelant: Window.activeFocusItem) ou de scope
    function moveFocus(scope, from, forward) {
        FiliShell.keyNav = true;
        const next = (from ?? scope).nextItemInFocusChain(forward);
        if (next && next !== scope && next.activeFocusOnTab)
            next.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason);
    }
    // Premier élément de la vue, à l'ouverture au clavier
    function focusFirst(scope) {
        const first = scope.nextItemInFocusChain(true);
        if (first && first !== scope && first.activeFocusOnTab)
            first.forceActiveFocus(Qt.TabFocusReason);
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
            Keys.onUpPressed: panel.moveFocus(scope, Window.activeFocusItem, false)
            Keys.onDownPressed: panel.moveFocus(scope, Window.activeFocusItem, true)
            Keys.onTabPressed: panel.moveFocus(scope, Window.activeFocusItem, true)
            Keys.onBacktabPressed: panel.moveFocus(scope, Window.activeFocusItem, false)
            Keys.onLeftPressed: panel.step(-1)
            Keys.onRightPressed: panel.step(1)
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
                radius: FiliTheme.radiusWindow
                Loader {
                    id: loader
                    objectName: "panel-view"
                    anchors { fill: parent; margins: FiliTheme.space5 }
                    source: panel.open ? panel.views[panel.view] : ""
                    onLoaded: if (FiliShell.keyNav) Qt.callLater(() => panel.focusFirst(scope))
                }
            }
        }
    }
}
