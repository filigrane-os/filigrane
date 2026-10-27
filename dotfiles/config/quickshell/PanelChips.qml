// Rangée de choix des fili-panel (échelle, rotation, définition): model = [{label, value, off?}], current = valeur choisie;
// off = indisponible (grisé, sans clic). Clavier: un seul arrêt; ←/→ déplace le curseur sans rien appliquer (une
// définition est à confirmer), Entrée ou Espace choisit; Maj+←/→ reste au fili-panel (panneau voisin)
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

    // Curseur clavier: choix suivant ou précédent disponible (appelé aussi par les tests)
    property int cursor: -1
    function move(d) {
        FiliShell.keyNav = true;
        for (let i = cursor + d; i >= 0 && i < model.length; i += d) {
            if (!model[i].off) {
                cursor = i;
                return;
            }
        }
    }
    activeFocusOnTab: model.some(m => !m.off)
    // Au focus: sur le choix courant, sinon le premier disponible
    onActiveFocusChanged: {
        if (!activeFocus)
            return;
        const i = model.findIndex(m => String(m.value) === String(current) && !m.off);
        cursor = i >= 0 ? i : model.findIndex(m => !m.off);
    }
    Keys.onLeftPressed: e => e.modifiers & Qt.ShiftModifier ? e.accepted = false : move(-1)
    Keys.onRightPressed: e => e.modifiers & Qt.ShiftModifier ? e.accepted = false : move(1)
    Keys.onReturnPressed: pick(cursor)
    Keys.onEnterPressed: pick(cursor)
    Keys.onSpacePressed: pick(cursor)

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
            readonly property bool atCursor: chips.activeFocus && FiliShell.keyNav && index === chips.cursor
            border.color: on || atCursor ? FiliTheme.voile : FiliTheme.nuit3
            border.width: atCursor ? 2 : 1
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
