// Mail: unread total over every account. `fili-mail daemon` (Facteur) keeps ~/.local/state/alerts/mail (the recent
// messages, shown in the tooltip) and mail.count (the real total); the module is an AlertModule of kind "mail", so it
// shows in the bar while there is unread mail and, at rest, only in the open drawer. Click = open Facteur.
import QtQuick
import qs
import qs.bar
import qs.bar.modules.alert

AlertModule {
    kind: "mail"
    title: FiliI18n.tr("Mail")
    glyph: ""
    accent: FiliTheme.barWarn
    openHint: FiliI18n.tr("click: open Facteur")
    click: "fili-mail"
}
