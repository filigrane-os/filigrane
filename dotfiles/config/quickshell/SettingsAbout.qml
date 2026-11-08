// Settings page "About" (fili-settings): the About card of Réglages. Every fili-* application with a display name
// (alias) has one: the alias as the name, "Also known as" the program name (skill filigrane-ui, references/hig.md §7).
// Nothing is read from the system: the page is static, so it costs nothing while the window is closed.
import QtQuick
import QtQuick.Layouts
import qs.controls

ColumnLayout {
    id: view
    spacing: FiliTheme.space3
    // Display name (alias) and program name (aka)
    readonly property string name: "Réglages"
    readonly property string aka: "fili-settings"
    readonly property var rows: [
        [FiliI18n.tr("Also known as"), aka + " (Settings)"],
        [FiliI18n.tr("Part of"), "Filigrane"],
        [FiliI18n.tr("Opens with"), "fili-shell settings [PAGE]"]
    ]

    Text {
        Layout.alignment: Qt.AlignHCenter
        text: String.fromCodePoint(0xf013)
        color: FiliTheme.voile
        font { family: FiliTheme.font; pixelSize: 64 }
    }
    Text {
        Layout.alignment: Qt.AlignHCenter
        text: view.name
        color: FiliTheme.brume
        font { family: FiliTheme.font; pixelSize: 28; weight: FiliTheme.weightAccent }
    }
    Text {
        Layout.alignment: Qt.AlignHCenter
        text: FiliI18n.tr("The settings of this machine")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: Font.Light }
    }
    Rectangle { Layout.fillWidth: true; Layout.topMargin: FiliTheme.space2; implicitHeight: 1; color: FiliTheme.nuit4 }
    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 16
        rowSpacing: 3
        Repeater {
            model: view.rows.reduce((a, r) => a.concat([{ t: r[0], key: true }, { t: r[1], key: false }]), [])
            Text {
                required property var modelData
                text: modelData.t
                color: modelData.key ? FiliTheme.brume2 : FiliTheme.brume
                Layout.preferredWidth: modelData.key ? 130 : -1
                Layout.fillWidth: !modelData.key
                elide: Text.ElideRight
                font { family: FiliTheme.font; pixelSize: FiliTheme.size }
            }
        }
    }
}
