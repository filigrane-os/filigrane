// Rangée de choix des fili-panel (échelle, rotation, définition): model = [{label, value, off?}], current = valeur choisie;
// off = indisponible (grisé, sans clic)
import QtQuick
import QtQuick.Layouts

Flow {
    id: chips
    property var model: []
    property var current: null
    signal picked(var value)

    Layout.fillWidth: true
    spacing: 4

    // Choix (appelé aussi par les tests)
    function pick(i) {
        if (i >= 0 && i < model.length && !model[i].off)
            picked(model[i].value);
    }

    Repeater {
        model: chips.model
        Rectangle {
            required property int index
            required property var modelData
            readonly property bool on: String(modelData.value) === String(chips.current)
            readonly property bool off: modelData.off === true
            opacity: off ? 0.4 : 1
            width: label.implicitWidth + 16
            height: 24
            radius: 6
            color: on ? FiliTheme.nuit4 : area.containsMouse && !off ? FiliTheme.nuit3 : "transparent"
            border.color: on ? FiliTheme.voile : FiliTheme.nuit3
            border.width: 1
            Text {
                id: label
                anchors.centerIn: parent
                text: parent.modelData.label
                color: parent.on ? FiliTheme.voile : FiliTheme.brume
                font { family: FiliTheme.font; pixelSize: 12; weight: parent.on ? Font.Medium : Font.Normal }
            }
            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: parent.off ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: chips.pick(parent.index)
            }
        }
    }
}
