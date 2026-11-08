// Information card of the fili-panel ({ title, rows }, see FiliInfo), requested on opening and on refresh()
import QtQuick
import QtQuick.Layouts
import qs
import qs.bar

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
    // Same standard as the fili-tooltip: title on the left, label / value rows on the right
    RowLayout {
        Layout.fillWidth: true
        spacing: FiliTheme.space4
        Text {
            visible: info.title && !!info.card.title
            Layout.alignment: Qt.AlignTop
            Layout.maximumWidth: 130
            elide: Text.ElideRight
            text: info.card.title ?? ""
            color: FiliTheme.voile
            font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
        }
        GridLayout {
            Layout.alignment: Qt.AlignTop
            // The values take what the title and the labels leave and are elided: nothing goes past the card
            Layout.fillWidth: true
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
                    Layout.fillWidth: !modelData.key
                    elide: Text.ElideRight
                    font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                }
            }
        }
    }
}
