// Settings page "Barre" (fili-settings): the modules of the fili-bar. Each module of the manifests (module.toml): a switch
// (shown or hidden), its title and description, buttons to move it up or down its row and to the other side. Every change
// is made by the `fili-bar` command, which writes ~/.config/filigrane/fili-bar.toml; the bar re-reads it at once and this
// page follows (BarLayout). An explicit left / right list in that file wins over the order set here (stated below).
import QtQuick
import QtQuick.Layouts
import qs.bar
import qs.controls

ColumnLayout {
    id: view
    spacing: FiliTheme.space1
    readonly property string cli: FiliTheme.bin + "/fili-bar"
    // An explicit list in fili-bar.toml: the order of the page does not apply
    readonly property bool listed: Array.isArray(BarLayout.parsed.modules?.left) || Array.isArray(BarLayout.parsed.modules?.right)

    // Modules of a row by position, shown or not: [{ name, title, description, enabled, order }]
    function entries(side) {
        return Object.keys(BarLayout.manifests)
            .filter(n => BarLayout.setting(n, "side", "right") === side)
            .map(n => ({
                name: n,
                title: BarLayout.manifests[n].title || n,
                description: BarLayout.manifests[n].description || "",
                enabled: BarLayout.enabled(n),
                order: parseInt(BarLayout.setting(n, "order", "50")) || 50
            }))
            .sort((a, b) => a.order - b.order || (a.name < b.name ? -1 : 1));
    }
    function toggle(name) {
        FiliTheme.run(cli + (BarLayout.enabled(name) ? " disable " : " enable ") + name);
    }
    // Move a module by one position in its row: the row is renumbered 10, 20, 30... (only the orders that change)
    function shift(side, name, by) {
        const list = entries(side);
        const i = list.findIndex(e => e.name === name);
        const j = i + by;
        if (i < 0 || j < 0 || j >= list.length)
            return;
        list.splice(j, 0, list.splice(i, 1)[0]);
        const cmds = [];
        list.forEach((e, k) => {
            if (e.order !== 10 * (k + 1))
                cmds.push(cli + " move " + e.name + " " + side + " " + 10 * (k + 1));
        });
        FiliTheme.run(cmds.join(" && "));
    }
    // To the other side, at the end of its row
    function flip(side, name) {
        const other = side === "left" ? "right" : "left";
        const last = entries(other).reduce((m, e) => Math.max(m, e.order), 0);
        FiliTheme.run(cli + " move " + name + " " + other + " " + (last + 10));
    }

    // Edge of the screen and screens (fili-bar edge, fili-bar screens; also in the right click menu of the bar)
    BarPlacement { Layout.fillWidth: true }
    PanelSection { text: FiliI18n.tr("MODULES") }
    Text {
        text: "Barre"
        color: FiliTheme.voile
        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: view.listed ? FiliI18n.tr("fili-bar.toml has an explicit list of modules: it wins over the order set here.") : FiliI18n.tr("Show, hide and order the modules of the bar. The drawer and the details of each module are in its own panel.")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }

    Repeater {
        model: ["left", "right"]
        ColumnLayout {
            id: row
            required property string modelData
            Layout.fillWidth: true
            spacing: FiliTheme.space1
            PanelSection { divided: false; text: row.modelData === "left" ? FiliI18n.tr("LEFT") : FiliI18n.tr("RIGHT") }
            Repeater {
                model: view.entries(row.modelData)
                RowLayout {
                    id: item
                    required property var modelData
                    required property int index
                    objectName: "mod-" + modelData.name
                    Layout.fillWidth: true
                    spacing: FiliTheme.space2
                    PanelSwitch {
                        objectName: "show-" + item.modelData.name
                        checked: item.modelData.enabled
                        onToggled: view.toggle(item.modelData.name)
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        // Takes what the buttons leave: a long description is elided instead of widening the page
                        Layout.preferredWidth: 0
                        Layout.minimumWidth: 0
                        spacing: 0
                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: item.modelData.title
                            color: item.modelData.enabled ? FiliTheme.brume : FiliTheme.ardoise
                            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                        }
                        Text {
                            visible: item.modelData.description !== ""
                            Layout.fillWidth: true
                            text: item.modelData.description
                            elide: Text.ElideRight
                            color: FiliTheme.ardoise
                            font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                        }
                    }
                    PanelButton {
                        objectName: "up-" + item.modelData.name
                        Layout.fillWidth: false
                        Layout.preferredWidth: 30
                        label: "↑"
                        dim: item.index === 0
                        onClicked: view.shift(row.modelData, item.modelData.name, -1)
                    }
                    PanelButton {
                        objectName: "down-" + item.modelData.name
                        Layout.fillWidth: false
                        Layout.preferredWidth: 30
                        label: "↓"
                        onClicked: view.shift(row.modelData, item.modelData.name, 1)
                    }
                    PanelButton {
                        objectName: "side-" + item.modelData.name
                        Layout.fillWidth: false
                        Layout.preferredWidth: 30
                        label: row.modelData === "left" ? "→" : "←"
                        onClicked: view.flip(row.modelData, item.modelData.name)
                    }
                }
            }
        }
    }
}
