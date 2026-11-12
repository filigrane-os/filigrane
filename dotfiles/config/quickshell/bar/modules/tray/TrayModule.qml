// Drawer (BarState, bar-tray toggle): when folded only the indicators in use stay visible; click the chevron to show everything
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import qs
import qs.bar

BarModule {
    BarRow {
        Repeater {
            model: SystemTray.items
            Item {
                id: trayItem
                required property var modelData
                implicitWidth: FiliTheme.barVertical ? FiliTheme.barWidth : FiliTheme.iconCell
                implicitHeight: FiliTheme.barHeight
                IconImage {
                    anchors.centerIn: parent
                    implicitSize: 16
                    source: parent.modelData.icon
                }
                BarHover {
                    anchors.fill: parent
                    tip: parent.modelData.tooltipTitle || parent.modelData.title
                    onLeftClicked: parent.modelData.onlyMenu ? menuAnchor.open() : parent.modelData.activate()
                    onRightClicked: if (parent.modelData.hasMenu) menuAnchor.open()
                    onMiddleClicked: parent.modelData.secondaryActivate()
                    onWheelUp: parent.modelData.scroll(1, false)
                    onWheelDown: parent.modelData.scroll(-1, false)
                }
                QsMenuAnchor {
                    id: menuAnchor
                    menu: trayItem.modelData.menu
                    anchor.item: trayItem
                    anchor.edges: FiliTheme.popupEdges
                    anchor.gravity: FiliTheme.popupEdges
                }
            }
        }
        // restic backup: grey when idle, blinking while running, red on failure; click = back up now
        BarScript {
            objectName: "backup"
            title: FiliI18n.tr("Backup")
            value: BarState.backup
            colors: ({ idle: FiliTheme.barMuted, active: FiliTheme.barText, failed: FiliTheme.cendre }); blinkClass: "active"
            click: FiliTheme.bin + "/bar-backup run"
        }
        // Drawer chevron: click = show / fold
        BarScript { objectName: "tray-handle"; value: BarState.trayHandle; hideEmpty: false; colors: ({ "": FiliTheme.barMuted, open: FiliTheme.barText2 }); click: FiliTheme.bin + "/bar-tray toggle" }
    }
}
