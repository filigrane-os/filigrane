// Where a bar sits and how it looks: the edge of the screen, the background, the screens that get it (and, for the Quai, the
// automatic hiding). One block for the fili-bar and for the Quai (target "bar" | "taskbar"), used by the right click panel of
// each bar and by their pages of the settings. Every choice goes through `fili-bar` (edge, background, screens, taskbar ...),
// which writes fili-bar.toml; the bars follow as soon as the file changes.
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.bar
import qs.controls

ColumnLayout {
    id: view
    spacing: FiliTheme.space1
    // "bar": the fili-bar; "taskbar": the Quai
    property string target: "bar"
    readonly property bool quai: target === "taskbar"
    readonly property string prefix: quai ? "quai-" : "bar-"
    readonly property string cli: FiliTheme.bin + "/fili-bar " + (quai ? "taskbar " : "")
    // Called after a choice (the right click panel closes itself)
    signal chosen

    readonly property var wanted: view.quai ? TaskbarLayout.conf : BarLayout.parsed.bar ?? ({})
    function run(key, value) {
        FiliTheme.run(view.cli + key + " " + value);
        view.chosen();
    }

    PanelSection { divided: false; text: view.quai ? FiliI18n.tr("QUAI POSITION") : FiliI18n.tr("BAR POSITION") }
    PanelChips {
        objectName: view.prefix + "edge"
        model: [
            { label: FiliI18n.tr("Top"), value: "top" },
            { label: FiliI18n.tr("Bottom"), value: "bottom" },
            { label: FiliI18n.tr("Left"), value: "left" },
            { label: FiliI18n.tr("Right"), value: "right" }
        ]
        current: ["top", "left", "right"].indexOf(view.wanted.edge) >= 0 ? view.wanted.edge : view.quai ? "bottom" : "top"
        onPicked: v => view.run("edge", v)
    }

    PanelSection { text: FiliI18n.tr("BACKGROUND") }
    PanelChips {
        objectName: view.prefix + "background"
        model: [
            { label: FiliI18n.tr("Solid"), value: "solid" },
            { label: FiliI18n.tr("Translucent"), value: "translucent" },
            { label: FiliI18n.tr("Transparent"), value: "transparent" }
        ]
        current: view.quai ? TaskbarLayout.background : BarLayout.background
        onPicked: v => view.run("background", v)
    }

    // Automatic hiding (the Quai only)
    PanelSection { visible: view.quai; text: FiliI18n.tr("BEHAVIOUR") }
    RowLayout {
        visible: view.quai
        Layout.fillWidth: true
        spacing: FiliTheme.space2
        PanelSwitch {
            objectName: "quai-autohide"
            checked: TaskbarLayout.autohide
            onToggled: view.run("autohide", TaskbarLayout.autohide ? "false" : "true")
        }
        Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: FiliI18n.tr("Hide it until the pointer touches its edge")
            color: TaskbarLayout.autohide ? FiliTheme.brume : FiliTheme.ardoise
            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
        }
    }

    // "All screens", or one of the connected screens (several screens: list them in fili-bar.toml)
    PanelSection { text: FiliI18n.tr("SCREENS") }
    PanelChips {
        objectName: view.prefix + "screens"
        model: [{ label: FiliI18n.tr("All screens"), value: "all" }].concat(Quickshell.screens.map(s => ({ label: s.name, value: s.name })))
        current: {
            if (!view.quai)
                return BarLayout.screensChoice;
            const v = TaskbarLayout.conf.screens;
            const list = Array.isArray(v) ? v : (v ? [v] : []);
            return list.length === 1 && list[0] !== "all" ? list[0] : "all";
        }
        onPicked: v => view.run("screens", v)
    }
}
