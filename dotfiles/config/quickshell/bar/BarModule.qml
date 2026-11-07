// Base of every fili-bar module (BarItem and BarScript build on it): the bar window the module sits in, and the
// optional fili-panel it opens. A module is a folder under bar/modules/<name>/ with <Name>Module.qml (its root is a
// BarModule, BarItem or BarScript) and, when it has one, its panel next to it.
import QtQuick
import qs

Item {
    id: mod
    // fili-bar window of the screen this module lives in (set by FiliBar; null for the items nested in a module)
    property var bar: null
    // Name of the module's panel (FiliPanel), "" for none; it opens under anchorItem
    property string panel: ""
    property Item anchorItem: mod
    implicitWidth: childrenRect.width
    implicitHeight: FiliTheme.barHeight

    function togglePanel() {
        FiliPanel.toggle(anchorItem, panel, bar);
    }
    Component.onCompleted: if (panel)
        FiliPanel.register(panel, anchorItem, bar)
}
