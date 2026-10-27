// Fiche d'informations des fili-panel ({ title, rows }, voir FiliInfo), demandée à l'ouverture et sur refresh()
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: info
    property string topic
    property var card: ({ rows: [] })
    property bool title: false
    spacing: 3
    Layout.fillWidth: true

    function refresh() {
        if (topic)
            FiliInfo.request(topic);
    }
    Component.onCompleted: refresh()
    Connections {
        target: FiliInfo
        function onReady(topic, card) {
            if (topic === info.topic)
                info.card = card;
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
