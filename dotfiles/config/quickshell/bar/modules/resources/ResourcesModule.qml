// Resources: CPU and memory (top 5 in the tooltip); temperature (from 50 °C) and disk (from 90 %) only when they are
// very high (bar-stats empties them otherwise); click = monitor panel, opened under the clicked item
import QtQuick
import qs
import qs.bar

BarModule {
    id: res
    panel: "monitor"
    panelSource: Qt.resolvedUrl("ResourcesPanel.qml")
    anchorItem: cpu

    BarRow {
        BarScript { id: cpu; objectName: "cpu"; tag: "CPU"; stat: "cpu"; color: FiliTheme.barText2; hover.onLeftClicked: res.togglePanel(hover); hint: FiliI18n.tr("click: monitor") }
        BarScript { objectName: "temp"; stat: "temp"; colors: ({ "": FiliTheme.barWarn, critical: FiliTheme.cendre }); hover.onLeftClicked: res.togglePanel(hover); hint: FiliI18n.tr("click: monitor") }
        BarScript { objectName: "mem"; tag: "RAM"; stat: "mem"; color: FiliTheme.barText2; hover.onLeftClicked: res.togglePanel(hover); hint: FiliI18n.tr("click: monitor") }
        BarScript {
            objectName: "disk"
            stat: "disk"; hint: FiliI18n.tr("click: monitor")
            colors: ({ "": FiliTheme.barWarn, critical: FiliTheme.cendre })
            hover.onLeftClicked: res.togglePanel(hover)
        }
    }
}
