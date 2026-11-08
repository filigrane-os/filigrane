// fili-bar: top bar, one per screen: the layout only. Every element is a module (bar/modules/<name>/<Name>Module.qml,
// see BarModule) with its panel next to it. Click: main action; right/middle click and wheel: see each module. TUIs open
// through bar-tui. Hover: fili-tooltip (detailed state + reminder of the clicks); network, power and display are read
// on hover only (FiliInfo).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.bar.modules.appmenu
import qs.bar.modules.logo
import qs.bar.modules.media
import qs.bar.modules.notifications
import qs.bar.modules.status
import qs.bar.modules.tray
import qs.bar.modules.workspaces
import qs.bar.modules.agent
import qs.bar.modules.audio
import qs.bar.modules.bluetooth
import qs.bar.modules.clock
import qs.bar.modules.display
import qs.bar.modules.keyboard
import qs.bar.modules.network
import qs.bar.modules.power
import qs.bar.modules.resources

PanelWindow {
    id: bar
    required property var modelData
    screen: modelData
    anchors { top: true; left: true; right: true }
    implicitHeight: FiliTheme.barHeight
    color: FiliTheme.nuit
    visible: !FiliTheme.testing
    WlrLayershell.namespace: "fili-bar"

    readonly property string b: FiliTheme.bin

    // Click on the bar background (outside the modules): closes fili-panel, the pinned calendar and the notification center
    MouseArea {
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.AllButtons
        onPressed: FiliShell.popupOpened("")
    }

    // Thin line under the bar
    Rectangle {
        z: -1
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1
        color: FiliTheme.nuit3
    }

    // ───────── Left: logo, workspaces, application menu ─────────
    RowLayout {
        id: leftRow
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        spacing: 0

        LogoModule { bar: bar; Layout.leftMargin: 10 }
        WorkspacesModule { bar: bar; Layout.fillHeight: true }

        // Menu of the active application (AppMenu): AT-SPI menu bar or fallback menu; replaces the window title.
        // Folded to the application name alone when the menus do not fit before the first right-hand module
        AppmenuModule {
            id: appMenu
            objectName: "appmenu"
            bar: bar
            maxWidth: Math.max(0, rightRow.x - leftRow.x - appMenu.x - FiliTheme.space3)
        }
    }

    // ───────── Right: indicators, drawer, media, resources, system, date, battery ─────────
    RowLayout {
        id: rightRow
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom; rightMargin: 6 }
        spacing: 0

        // Personal alerts: new Proton mails / imminent Proton Calendar event (hidden otherwise, see BarState), click = open and clear
        BarScript { objectName: "mail"; value: BarState.mail; color: FiliTheme.voile; click: bar.b + "/bar-alert open mail" }
        BarScript { objectName: "whatsapp"; value: BarState.whatsapp; click: bar.b + "/bar-alert open whatsapp" }
        BarScript { objectName: "cal"; value: BarState.cal; color: FiliTheme.sable; click: bar.b + "/bar-alert open cal" }
        StatusModule { bar: bar }

        TrayModule { bar: bar }

        MediaModule { bar: bar }

        ResourcesModule { bar: bar }
        AgentModule { bar: bar }
        AudioModule { bar: bar }
        KeyboardModule { bar: bar }
        DisplayModule { bar: bar }
        BluetoothModule { bar: bar }
        NetworkModule { bar: bar }
        NotificationsModule { bar: bar }
        ClockModule { bar: bar }
        PowerModule { bar: bar }
    }
}
