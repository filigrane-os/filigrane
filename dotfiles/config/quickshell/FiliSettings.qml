pragma Singleton
// fili-settings ("Settings" for the user): the settings that are set once, in a window centred on the screen. A list of
// pages on the left, one per module of the fili-bar (Display, Sound, Network...), the chosen page on the right. The
// frequent, instant and reversible settings stay in the fili-panel of their module, whose foot opens the matching page
// here (`FiliSettings.show("display")`). Pages are loaded when the window opens and freed when it closes (nothing runs
// while it is closed). Like a fili-panel, it closes on Esc or when it loses focus (a change pending confirmation is
// reverted by its page, see SettingsDisplay).
// Opening: `fili-shell settings [PAGE]`, the foot of a fili-panel, menu > System > Settings.
// Keyboard: Tab / Shift+Tab through the page list then the page, Enter acts, Esc closes.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

Singleton {
    id: settings
    property bool open: false
    property string page: "display"
    // Page loaded (tests)
    property alias loaded: loader.item
    // id, label (translated), page file; the order is the one of the bar modules
    readonly property var pages: [
        { id: "display", label: FiliI18n.tr("Display"), source: "SettingsDisplay.qml" },
        { id: "language", label: FiliI18n.tr("Language"), source: "SettingsLanguage.qml" },
        { id: "power", label: FiliI18n.tr("Power"), source: "SettingsPower.qml" },
        { id: "files", label: "Casier", source: "SettingsFiles.qml" }
    ]
    readonly property var current: pages.find(p => p.id === page) ?? pages[0]

    function show(id) {
        FiliShell.popupOpened("settings");
        FiliPanel.close();
        if (id && pages.some(p => p.id === id))
            page = id;
        open = true;
    }
    function toggle(id) {
        if (open)
            close();
        else
            show(id);
    }
    function close() {
        open = false;
    }

    Connections {
        target: FiliShell
        function onPopupOpened(who) {
            if (who !== "settings")
                settings.close();
        }
    }

    PanelWindow {
        id: win
        visible: settings.open && !FiliTheme.testing
        // No anchors: the compositor centres the window
        implicitWidth: card.width
        implicitHeight: card.height
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "fili-settings"
        WlrLayershell.keyboardFocus: settings.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        FocusScope {
            id: scope
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: settings.close()
            Keys.onTabPressed: FiliPanel.moveFocus(scope, Window.activeFocusItem, true)
            Keys.onBacktabPressed: FiliPanel.moveFocus(scope, Window.activeFocusItem, false)
            // Focus received on opening then lost (click on another window): close, as a fili-panel does
            property bool held: false
            Window.onActiveChanged: {
                if (Window.active)
                    held = true;
                else if (held)
                    settings.close();
            }
            Connections {
                target: settings
                function onOpenChanged() {
                    scope.held = false;
                }
            }
            Rectangle {
                id: card
                width: 640
                height: Math.min((win.screen?.height ?? 800) - 2 * (FiliTheme.barHeight + 24), 560)
                color: FiliTheme.nuit
                border { color: FiliTheme.border; width: FiliTheme.borderWidth }
                radius: FiliTheme.radiusWindow
                clip: true

                // Pages
                ColumnLayout {
                    id: side
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: FiliTheme.space3 }
                    width: 160
                    spacing: FiliTheme.space1
                    Repeater {
                        model: settings.pages
                        PanelButton {
                            required property var modelData
                            objectName: "page-" + modelData.id
                            label: modelData.label
                            sel: modelData.id === settings.page
                            onClicked: settings.page = modelData.id
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
                Rectangle {
                    id: rule
                    anchors { left: side.right; top: parent.top; bottom: parent.bottom; leftMargin: FiliTheme.space3 }
                    width: 1
                    color: FiliTheme.nuit4
                }
                // Page: scrolls when taller than the window
                Flickable {
                    id: flick
                    anchors { left: rule.right; right: parent.right; top: parent.top; bottom: parent.bottom; margins: FiliTheme.space5 }
                    contentWidth: width
                    contentHeight: loader.item ? loader.item.implicitHeight : 0
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    KineticScroll {}
                    Loader {
                        id: loader
                        objectName: "settings-page"
                        width: flick.width
                        source: settings.open ? settings.current.source : ""
                    }
                }
            }
        }
    }
}
