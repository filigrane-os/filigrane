pragma Singleton
// fili-settings ("Réglages" for the user, alias of Settings; its About card is the last page): the settings that are set once, in a window centred on the screen. A list of
// pages on the left, one per module of the fili-bar (Display, Sound, Network...), the chosen page on the right. The
// frequent, instant and reversible settings stay in the fili-panel of their module, whose gear (top right) opens the matching page
// here (`FiliSettings.show("display")`). Pages are loaded when the window opens and freed when it closes (nothing runs
// while it is closed). Unlike a fili-panel, it is a window: it closes on Esc or with the button at the top right, never
// when it loses focus (a change pending confirmation is reverted by its page, see SettingsDisplay).
// Opening: `fili-shell settings [PAGE]`, the gear of a fili-panel, menu > System > Settings.
// Keyboard: Tab / Shift+Tab through the page list then the page, Enter acts, Esc closes.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.bar
import qs.controls

Singleton {
    id: settings
    property bool open: false
    property string page: "display"
    // Page loaded (tests)
    property alias loaded: loader.item
    // id, label (translated), page file; the order is the one of the bar modules
    readonly property var pages: [
        { id: "display", label: FiliI18n.tr("Display"), source: "SettingsDisplay.qml" },
        { id: "workspaces", label: FiliI18n.tr("Workspaces"), source: "SettingsWorkspaces.qml" },
        { id: "language", label: FiliI18n.tr("Language"), source: "SettingsLanguage.qml" },
        { id: "power", label: FiliI18n.tr("Power"), source: "SettingsPower.qml" },
        { id: "bar", label: "Barre", source: "SettingsBar.qml" },
        { id: "files", label: "Casier", source: "SettingsFiles.qml" },
        { id: "about", label: FiliI18n.tr("About"), source: "SettingsAbout.qml" }
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
                    anchors { left: rule.right; right: parent.right; top: parent.top; bottom: parent.bottom; margins: FiliTheme.space5; topMargin: 40 }
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
                // Close button (top right); Esc does the same
                Rectangle {
                    id: closeBtn
                    objectName: "settings-close"
                    anchors { top: parent.top; right: parent.right; margins: FiliTheme.space2 }
                    width: 24
                    height: 24
                    radius: 6
                    color: closeHover.containsMouse ? FiliTheme.nuit3 : "transparent"
                    Accessible.role: Accessible.Button
                    Accessible.name: FiliI18n.tr("Close")
                    // A cross drawn with two bars (no glyph: no font dependency)
                    Repeater {
                        model: [45, -45]
                        Rectangle {
                            required property int modelData
                            anchors.centerIn: parent
                            width: 12
                            height: 1.5
                            radius: 1
                            rotation: modelData
                            color: closeHover.containsMouse ? FiliTheme.brume : FiliTheme.ardoise
                        }
                    }
                    MouseArea {
                        id: closeHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: settings.close()
                    }
                }
            }
        }
    }
}
