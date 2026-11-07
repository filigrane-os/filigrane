// Notifications: click = history, right click = do not disturb
import QtQuick
import qs
import qs.bar

BarItem {
    objectName: "notifications"
    panel: "center"
    text: FiliNotification.dnd ? " MUTE" : (FiliNotification.history.length + FiliNotification.popups.length > 0 ? "" : "") + " " + (FiliNotification.history.length + FiliNotification.popups.length)
    color: FiliNotification.dnd ? FiliTheme.sable : FiliTheme.brume
    tip: ({
        title: FiliNotification.dnd ? FiliI18n.tr("Do not disturb") : FiliI18n.tr("Notifications"),
        rows: [[FiliI18n.tr("Pop-ups"), FiliNotification.dnd ? FiliI18n.tr("hidden") : FiliI18n.tr("shown")], [FiliI18n.tr("History"), FiliI18n.tr("%1 notification(s)", FiliNotification.history.length)]],
        hint: FiliI18n.tr("click: fili-notification-center · right click: do not disturb")
    })
    hover.onLeftClicked: FiliNotification.toggleCenter()
    hover.onRightClicked: FiliNotification.dnd = !FiliNotification.dnd
}
