// fili-panel clavier: dispositions xkb de la session niri (Niri.layouts), choix direct ou retour à la précédente
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: view
    spacing: 4
    readonly property bool hasPrevious: Niri.previousLayout >= 0 && Niri.previousLayout < Niri.layouts.length

    Text {
        text: "Clavier"
        color: FiliTheme.voile
        font { family: FiliTheme.font; pixelSize: 14; weight: Font.Medium }
    }
    PanelSection { visible: Niri.layouts.length > 0; text: "DISPOSITIONS" }
    Repeater {
        model: Niri.layouts
        PanelButton {
            required property string modelData
            required property int index
            objectName: "layout"
            glyph: index === Niri.layout ? "●" : ""
            label: modelData
            sel: index === Niri.layout
            detail: Niri.shortName(modelData)
            onClicked: Niri.selectLayout(index)
        }
    }
    PanelButton {
        objectName: "previous"
        visible: view.hasPrevious
        glyph: "↺"
        label: "Disposition précédente"
        detail: view.hasPrevious ? Niri.shortName(Niri.layouts[Niri.previousLayout]) : ""
        onClicked: Niri.selectLayout(Niri.previousLayout)
    }
    Text {
        visible: Niri.layouts.length === 0
        text: "Aucune disposition détectée"
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: FiliTheme.size }
    }
    Text {
        visible: Niri.layouts.length > 1
        Layout.topMargin: 4
        text: "Dispositions: XKB_LAYOUT dans config.env"
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: 12 }
    }
}
