// Place of one module in a fili-bar row (BarLayout): loads the module with its bar window set from the start, so the
// module can register its panel when it is created. free >= 0 (left row): width available up to the right row, handed to
// the modules that have a maxWidth (the application menu).
import QtQuick
import QtQuick.Layouts
import qs

Loader {
    id: slot
    required property string modelData
    // fili-bar window of the screen
    property var bar: null
    property real free: -1
    // Squeeze level of the bar (FiliBar): from compact_at the module compacts, from drawer_at it goes into the drawer
    readonly property int level: bar ? bar.level : 0
    readonly property bool compactNow: BarLayout.level(modelData, "compact_at") > 0 && level >= BarLayout.level(modelData, "compact_at")
    readonly property bool drawerNow: BarLayout.level(modelData, "drawer_at") > 0 && level >= BarLayout.level(modelData, "drawer_at")
    // Fills the thickness of the bar: its height in a row, its width in a column
    Layout.fillHeight: !FiliTheme.barVertical
    Layout.fillWidth: FiliTheme.barVertical
    Component.onCompleted: setSource(BarLayout.source(modelData), BarLayout.isScript(modelData) ? { bar: slot.bar, name: modelData, conf: BarLayout.manifests[modelData] } : { bar: slot.bar })
    onLoaded: {
        if (!item)
            return;
        // Manifest / fili-bar.toml settings, followed live
        // A squeezed bar turns "both" into the icon alone and puts a "never" module into the drawer; what the user chose
        // ("value", "idle", "always") stays
        item.display = Qt.binding(() => {
            const d = BarLayout.choice(modelData, "display", ["both", "icon", "value"], "both");
            return slot.compactNow && d === "both" ? "icon" : d;
        });
        item.trayMode = Qt.binding(() => {
            const t = BarLayout.choice(modelData, "tray", ["never", "idle", "always"], "never");
            return slot.drawerNow && t === "never" ? "always" : t;
        });
        if (item.compact !== undefined)
            item.compact = Qt.binding(() => slot.compactNow);
        // show: only when a manifest or fili-bar.toml says so (some modules set hideEmpty themselves)
        if (item.hideEmpty !== undefined && BarLayout.choice(modelData, "show", ["active", "always"], "") !== "")
            item.hideEmpty = Qt.binding(() => BarLayout.choice(modelData, "show", ["active", "always"], "active") === "active");
        if (free >= 0 && item.maxWidth !== undefined)
            item.maxWidth = Qt.binding(() => Math.max(0, slot.free - slot.x - FiliTheme.space3));
    }
}
