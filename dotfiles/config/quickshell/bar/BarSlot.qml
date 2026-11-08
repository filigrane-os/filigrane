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
    Layout.fillHeight: true
    Component.onCompleted: setSource(BarLayout.source(modelData), { bar: slot.bar })
    onLoaded: {
        if (!item)
            return;
        // Manifest / fili-bar.toml settings, followed live
        item.display = Qt.binding(() => BarLayout.choice(modelData, "display", ["both", "icon", "value"], "both"));
        item.trayMode = Qt.binding(() => BarLayout.choice(modelData, "tray", ["never", "idle", "always"], "never"));
        // show: only when a manifest or fili-bar.toml says so (some modules set hideEmpty themselves)
        if (item.hideEmpty !== undefined && BarLayout.choice(modelData, "show", ["active", "always"], "") !== "")
            item.hideEmpty = Qt.binding(() => BarLayout.choice(modelData, "show", ["active", "always"], "active") === "active");
        if (free >= 0 && item.maxWidth !== undefined)
            item.maxWidth = Qt.binding(() => Math.max(0, slot.free - slot.x - FiliTheme.space3));
    }
}
