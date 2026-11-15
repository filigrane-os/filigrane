// Messages: unread instant messages over every account. `fili-im daemon` (Conversations) keeps
// ~/.local/state/alerts/messages (the recent messages, shown in the tooltip) and messages.count (the real total); the
// module is an AlertModule of kind "messages", so it shows in the bar while there are unread messages and, at rest,
// only in the open drawer. Click = open Conversations.
import QtQuick
import qs
import qs.bar
import qs.bar.modules.alert

AlertModule {
    kind: "messages"
    title: FiliI18n.tr("Messages")
    glyph: "󰖣"
    accent: FiliTheme.barWarn
    openHint: FiliI18n.tr("click: open Conversations")
    click: "fili-im"
}
