// Messages: unread instant messages over every account. `fili-im daemon` (Conversations) keeps
// ~/.local/state/alerts/messages (the recent messages, shown in the tooltip) and messages.count (the real total); the
// indicator is an AlertModule of kind "messages", so it shows in the bar while there are unread messages and, at rest,
// only in the open drawer. Click = the panel (last conversations, peek and quick reply), middle click = open Conversations.
import QtQuick
import qs
import qs.bar
import qs.bar.modules.alert

BarModule {
    id: mod
    panel: "messages"
    panelSource: Qt.resolvedUrl("MessagesPanel.qml")
    anchorItem: item

    BarRow {
        AlertModule {
            id: item
            kind: "messages"
            title: FiliI18n.tr("Messages")
            glyph: "󰖣"
            accent: FiliTheme.barWarn
            openHint: FiliI18n.tr("click: panel · right click: menu · middle click: open Conversations")
            click: ""
            mclick: "fili-im"
            hover.onLeftClicked: mod.togglePanel(hover)
            hover.onRightClicked: mod.contextMenu([{ glyph: "\uf08e", text: FiliI18n.tr("Open Conversations"), cmd: "fili-im", app: true }], item)
        }
    }
}
