// Drop-down choice of the fili-panel (pop-up button): same model as PanelChips, model = [{label, value, off?}],
// current = chosen value; for a long list of choices where chips would take several lines. Click or Enter/Space
// opens the list under the button (over the whole window, never clipped by a scrolling page); ↑/↓ moves, Enter or a
// click chooses, Esc or a click outside closes without changing anything.
import QtQuick
import QtQuick.Layouts
import qs

Rectangle {
    id: sel
    property var model: []
    property var current: null
    property string placeholder: ""
    signal picked(var value)

    property bool opened: false
    property int cursor: -1
    readonly property int currentIndex: model.findIndex(m => String(m.value) === String(current))
    readonly property string text: currentIndex >= 0 ? model[currentIndex].label : placeholder

    // Choice (also called by the tests)
    function pick(i) {
        if (i >= 0 && i < model.length && !model[i].off)
            picked(model[i].value);
        opened = false;
    }
    function open() {
        cursor = currentIndex >= 0 ? currentIndex : model.findIndex(m => !m.off);
        opened = true;
        forceActiveFocus();
    }
    function move(d) {
        FiliShell.keyNav = true;
        for (let i = cursor + d; i >= 0 && i < model.length; i += d) {
            if (!model[i].off) {
                cursor = i;
                return;
            }
        }
    }

    implicitWidth: Math.max(120, label.implicitWidth + arrow.implicitWidth + 3 * FiliTheme.space2)
    implicitHeight: 26
    radius: FiliTheme.radiusControl
    color: area.containsMouse || opened ? FiliTheme.nuit3 : FiliTheme.nuit2
    border { width: 1; color: opened ? FiliTheme.nuit4 : FiliTheme.nuit3 }
    activeFocusOnTab: model.some(m => !m.off)
    Accessible.role: Accessible.ComboBox
    Accessible.name: text
    FocusRing {}

    Keys.onPressed: e => {
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) {
            opened ? pick(cursor) : open();
        } else if (e.key === Qt.Key_Escape && opened) {
            opened = false;
        } else if (e.key === Qt.Key_Down && !(e.modifiers & Qt.ShiftModifier)) {
            opened ? move(1) : open();
        } else if (e.key === Qt.Key_Up && !(e.modifiers & Qt.ShiftModifier)) {
            opened ? move(-1) : open();
        } else {
            return;
        }
        e.accepted = true;
    }
    onActiveFocusChanged: if (!activeFocus) opened = false

    Text {
        id: label
        anchors { left: parent.left; leftMargin: FiliTheme.space2; right: arrow.left; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
        text: sel.text
        elide: Text.ElideRight
        color: sel.currentIndex >= 0 ? FiliTheme.brume : FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
    Text {
        id: arrow
        anchors { right: parent.right; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
        text: "▾"
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: sel.opened ? sel.opened = false : sel.open()
    }

    // The list: reparented over the window, under the button (above it when there is no room below)
    Item {
        id: layer
        visible: sel.opened
        parent: sel.Window.window ? sel.Window.window.contentItem : sel
        anchors.fill: parent
        z: 200
        MouseArea { anchors.fill: parent; onClicked: sel.opened = false }
        Rectangle {
            id: list
            readonly property point at: sel.opened ? sel.mapToItem(layer, 0, 0) : Qt.point(0, 0)
            readonly property bool below: at.y + sel.height + height + 4 <= layer.height
            x: Math.min(at.x, layer.width - width - 4)
            y: below ? at.y + sel.height + 2 : Math.max(4, at.y - height - 2)
            width: Math.max(sel.width, col.implicitWidth)
            height: Math.min(col.implicitHeight + 8, layer.height - 8)
            radius: FiliTheme.radiusControl
            color: FiliTheme.nuit2
            border { width: FiliTheme.borderWidth; color: FiliTheme.border }
            clip: true
            Flickable {
                anchors { fill: parent; margins: 4 }
                contentHeight: col.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: col
                    width: parent.width
                    Repeater {
                        model: sel.opened ? sel.model : []
                        Rectangle {
                            required property int index
                            required property var modelData
                            readonly property bool off: modelData.off === true
                            width: col.width
                            implicitWidth: opt.implicitWidth + 2 * FiliTheme.space2 + 16
                            height: 26
                            radius: FiliTheme.radiusControl
                            opacity: off ? 0.4 : 1
                            color: index === sel.cursor || optArea.containsMouse && !off ? FiliTheme.nuit3 : "transparent"
                            Text {
                                anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                                visible: index === sel.currentIndex
                                text: "✓"
                                color: FiliTheme.voile
                                font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                            }
                            Text {
                                id: opt
                                anchors { left: parent.left; leftMargin: FiliTheme.space2 + 12; verticalCenter: parent.verticalCenter }
                                text: modelData.label
                                color: FiliTheme.brume
                                font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                            }
                            MouseArea {
                                id: optArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: off ? Qt.ArrowCursor : Qt.PointingHandCursor
                                onClicked: sel.pick(index)
                            }
                        }
                    }
                }
            }
        }
    }
}
