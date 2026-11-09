// Base of every fili-bar module (BarItem and BarScript build on it): the bar window the module sits in, and the
// optional fili-panel it opens. A module is a folder under bar/modules/<name>/ with <Name>Module.qml (its root is a
// BarModule, BarItem or BarScript) and, when it has one, its panel next to it. BarLayout loads a module by its file: Quickshell
// only sees the sibling files of a folder that a static import reaches, so a module folder with helper files next to its
// module (AppMenu, FiliCalendar, Equalizer...) is imported in BarLayout.qml. Other modules, including the personal ones
// of a user layer, rely on `qs`, `qs.bar` and `qs.controls` only.
import QtQuick
import qs

Item {
    id: mod
    // fili-bar window of the screen this module lives in (set by FiliBar; null for the items nested in a module)
    property var bar: null
    // Name of the module's panel (FiliPanel), "" for none; it opens under anchorItem
    property string panel: ""
    // QML file of the panel view (next to the module); loaded by FiliPanel when the panel opens
    property url panelSource
    property Item anchorItem: mod
    // How the module shows, from its manifest / fili-bar.toml (BarSlot sets them on the module of a row; the items nested
    // in a module follow the nearest module above them). display: "both" | "icon" | "value" (the icon alone, the value
    // alone; a module without icon always shows its value). trayMode: "never" (always in the bar) | "idle" (in the drawer
    // at rest, in the bar while it has something to say) | "always" (only in the open drawer)
    property string display: inherited("display", "both")
    property string trayMode: inherited("trayMode", "never")
    function inherited(key, def) {
        for (let p = parent; p; p = p.parent)
            if (p[key] !== undefined)
                return p[key];
        return def;
    }
    implicitWidth: FiliTheme.barVertical ? FiliTheme.barWidth : childrenRect.width
    implicitHeight: FiliTheme.barVertical ? childrenRect.height : FiliTheme.barHeight

    // Open or close the panel, under item (default: anchorItem)
    function togglePanel(item) {
        FiliPanel.toggle(item ?? anchorItem, panel, bar);
    }
    Component.onCompleted: if (panel)
        FiliPanel.register(panel, anchorItem, bar, panelSource)
    Component.onDestruction: if (panel)
        FiliPanel.unregister(panel, bar)
}
