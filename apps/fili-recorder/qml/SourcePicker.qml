// Drop-down choice of a sound source (input or output): the button shows the current choice, a click opens the list under
// it (Up/Down, Enter, Esc). model = [{ label, value }], current = chosen value; picked(value) when the user chooses.
import QtQuick
import QtQuick.Controls.Basic
import Fili.Cassette

Rectangle {
    id: sel
    property var model: []
    property string current: ""
    property string placeholder: ""
    signal picked(string value)

    readonly property int currentIndex: model.findIndex(m => m.value === current)
    readonly property string text: currentIndex >= 0 ? model[currentIndex].label : placeholder

    implicitWidth: 320
    implicitHeight: 28
    radius: FiliTheme.radiusControl
    color: area.containsMouse || popup.opened ? FiliTheme.surfaceHover : FiliTheme.surface
    border.width: FiliTheme.borderWidth
    border.color: sel.activeFocus ? FiliTheme.accentColor : FiliTheme.border
    activeFocusOnTab: true
    Accessible.role: Accessible.ComboBox
    Accessible.name: text
    FocusRing {}

    Keys.onPressed: e => {
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space || e.key === Qt.Key_Down) {
            popup.open();
            e.accepted = true;
        }
    }

    Text {
        anchors { left: parent.left; leftMargin: FiliTheme.space3; right: arrow.left; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
        text: sel.text
        elide: Text.ElideRight
        font.family: FiliTheme.font
        font.pixelSize: FiliTheme.size
        color: sel.currentIndex >= 0 ? FiliTheme.text : FiliTheme.muted
    }
    Text {
        id: arrow
        anchors { right: parent.right; rightMargin: FiliTheme.space3; verticalCenter: parent.verticalCenter }
        text: "▾"
        font.pixelSize: FiliTheme.sizeSmall
        color: FiliTheme.muted
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: popup.opened ? popup.close() : popup.open()
    }

    Popup {
        id: popup
        y: sel.height + 2
        width: sel.width
        padding: FiliTheme.space1
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        height: Math.min(list.contentHeight + 2 * padding, 8 * 28 + 2 * padding)
        background: Rectangle {
            radius: FiliTheme.radiusControl
            color: FiliTheme.surface
            border.width: FiliTheme.borderWidth
            border.color: FiliTheme.border
        }
        contentItem: ListView {
            id: list
            clip: true
            model: sel.model
            currentIndex: sel.currentIndex
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: true
            KineticScroll {}
            delegate: Rectangle {
                id: opt
                required property var modelData
                required property int index
                width: ListView.view.width
                height: 28
                radius: FiliTheme.radiusControl
                color: optArea.containsMouse || ListView.isCurrentItem ? FiliTheme.surfaceHover : "transparent"
                Text {
                    anchors { left: parent.left; leftMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                    width: 16
                    text: opt.modelData.value === sel.current ? "✓" : ""
                    font.pixelSize: FiliTheme.sizeSmall
                    color: FiliTheme.accentColor
                }
                Text {
                    anchors { left: parent.left; leftMargin: FiliTheme.space2 + 18; right: parent.right; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                    text: opt.modelData.label
                    elide: Text.ElideRight
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.size
                    color: FiliTheme.text
                }
                MouseArea {
                    id: optArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        popup.close();
                        sel.picked(opt.modelData.value);
                    }
                }
            }
            Keys.onReturnPressed: {
                if (currentIndex >= 0) {
                    popup.close();
                    sel.picked(sel.model[currentIndex].value);
                }
            }
        }
        onOpened: list.forceActiveFocus()
    }
}
