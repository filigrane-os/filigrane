// Fiche d'informations des fili-panel: lance `cmd` (JSON { title, rows }, comme fili-info) à l'ouverture et sur refresh()
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

ColumnLayout {
    id: info
    property string cmd
    property var card: ({ rows: [] })
    property bool title: false
    spacing: 3
    Layout.fillWidth: true

    function refresh() {
        if (cmd)
            proc.running = true;
    }
    Component.onCompleted: refresh()
    Process {
        id: proc
        command: ["sh", "-c", info.cmd]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    info.card = JSON.parse(text);
                } catch (e) {}
            }
        }
    }
    Text {
        visible: info.title && !!info.card.title
        text: info.card.title ?? ""
        color: FiliTheme.voile
        font { family: FiliTheme.font; pixelSize: 14; weight: Font.Medium }
    }
    GridLayout {
        columns: 2
        columnSpacing: 16
        rowSpacing: 3
        Repeater {
            model: (info.card.rows ?? []).reduce((a, r) => a.concat([{ t: r[0], key: true }, { t: r[1], key: false }]), [])
            Text {
                required property var modelData
                text: modelData.t
                color: modelData.key ? FiliTheme.ardoise : FiliTheme.brume
                Layout.maximumWidth: modelData.key ? 130 : 200
                elide: Text.ElideRight
                font { family: FiliTheme.font; pixelSize: 13 }
            }
        }
    }
}
