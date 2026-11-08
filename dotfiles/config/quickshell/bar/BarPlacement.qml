// Where the fili-bar sits: the edge of the screen and the screens that get a bar. Used by the right click panel of the bar
// and by the Bar page of the settings. Both choices go through `fili-bar` (edge, screens), which writes fili-bar.toml;
// the bar follows as soon as the file changes.
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.controls

ColumnLayout {
    id: view
    spacing: FiliTheme.space1
    // Called after a choice (the right click panel closes itself)
    signal chosen

    PanelSection { divided: false; text: FiliI18n.tr("BAR POSITION") }
    PanelChips {
        objectName: "bar-edge"
        model: [
            { label: FiliI18n.tr("Top"), value: "top" },
            { label: FiliI18n.tr("Bottom"), value: "bottom" },
            { label: FiliI18n.tr("Left"), value: "left" },
            { label: FiliI18n.tr("Right"), value: "right" }
        ]
        current: FiliTheme.barEdge
        onPicked: v => {
            FiliTheme.run(FiliTheme.bin + "/fili-bar edge " + v);
            view.chosen();
        }
    }

    // "All screens", or one of the connected screens (several screens: list them in fili-bar.toml)
    PanelSection { text: FiliI18n.tr("SCREENS") }
    PanelChips {
        objectName: "bar-screens"
        model: [{ label: FiliI18n.tr("All screens"), value: "all" }].concat(Quickshell.screens.map(s => ({ label: s.name, value: s.name })))
        current: BarLayout.screensChoice
        onPicked: v => {
            FiliTheme.run(FiliTheme.bin + "/fili-bar screens " + v);
            view.chosen();
        }
    }
}
