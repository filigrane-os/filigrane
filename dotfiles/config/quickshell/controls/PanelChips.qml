// Row of choices of the fili-panel (scale, rotation, resolution): model = [{label, value, off?}], current = chosen value;
// off = unavailable (greyed out, no click). Keyboard: a single stop; ←/→ moves the cursor without applying anything (a
// resolution has to be confirmed), Enter or Space chooses; Shift+←/→ stays with the fili-panel (neighbouring panel)
import QtQuick
import QtQuick.Layouts
import qs

Flow {
    id: chips
    property var model: []
    property var current: null
    signal picked(var value)

    Layout.fillWidth: true
    spacing: FiliTheme.space1

    // Choice (also called by the tests)
    function pick(i) {
        if (i >= 0 && i < model.length && !model[i].off)
            picked(model[i].value);
    }

    // Keyboard cursor: next or previous available choice (also called by the tests)
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
    // On focus: on the current choice, else the first available
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
            radius: FiliTheme.radiusControl
            color: on ? FiliTheme.nuit4 : area.containsMouse && !off ? FiliTheme.nuit3 : "transparent"
            readonly property bool atCursor: chips.activeFocus && FiliShell.keyNav && index === chips.cursor
            border.color: on || atCursor ? FiliTheme.voile : FiliTheme.nuit3
            border.width: atCursor ? 2 : 1
            Text {
                id: label
                anchors.centerIn: parent
                text: parent.modelData.label
                color: parent.on ? FiliTheme.voile : FiliTheme.brume
                font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList; weight: parent.on ? FiliTheme.weightAccent : Font.Normal }
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
