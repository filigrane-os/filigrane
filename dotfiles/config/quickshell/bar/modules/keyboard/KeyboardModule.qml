// Keyboard layout (bépo / Australian qwerty): click = panel, middle click = next layout
import QtQuick
import qs
import qs.bar

BarItem {
    objectName: "keyboard"
    panel: "keyboard"
    panelSource: Qt.resolvedUrl("KeyboardPanel.qml")
    readonly property string name: Niri.layouts[Niri.layout] ?? ""
    text: name ? " " + Niri.shortName(name) : ""
    tip: ({
        title: FiliI18n.tr("Keyboard"),
        rows: Niri.layouts.map((l, i) => [i === Niri.layout ? "●" : "", l]),
        hint: FiliI18n.tr("click: keyboard panel · middle click: next layout")
    })
    hover.onLeftClicked: togglePanel()
    hover.onMiddleClicked: Niri.action("switch-layout", "next")
}
