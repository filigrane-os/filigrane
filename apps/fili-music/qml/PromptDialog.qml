// A small modal: a title, optionally a list to choose from (existing playlists), a text field and the two buttons.
// open(title, text, choices, confirmLabel); accepted(text, choiceId) with choiceId -1 when nothing was chosen.
import QtQuick
import Fili.Baladeur

Rectangle {
    id: dlg
    property string title
    property string confirmLabel
    property string fieldLabel
    property var choices: []
    property int choice: -1
    signal accepted(string text, int choiceId)

    visible: false
    anchors.fill: parent
    z: 250
    color: FiliTheme.alpha(FiliTheme.background, 0.6)

    function open(titleText, initial, list, confirm, label) {
        title = titleText;
        choices = list || [];
        choice = -1;
        confirmLabel = confirm || Fili.tr("OK");
        fieldLabel = label || "";
        input.text = initial || "";
        visible = true;
        input.forceActiveFocus();
        input.selectAll();
    }
    function close() {
        visible = false;
    }
    function accept() {
        const t = input.text.trim();
        if (choice < 0 && t === "")
            return;
        close();
        accepted(t, choice);
    }
    MouseArea { anchors.fill: parent; onClicked: dlg.close() }
    Keys.onEscapePressed: close()

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(400, parent.width - 2 * FiliTheme.margin)
        height: col.implicitHeight + 2 * FiliTheme.space5
        radius: FiliTheme.radiusWindow
        color: FiliTheme.surface
        border.width: FiliTheme.borderWidth
        border.color: FiliTheme.border
        MouseArea { anchors.fill: parent }
        Column {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: FiliTheme.space5 }
            spacing: FiliTheme.space3
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: dlg.title
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.size
                font.weight: FiliTheme.weightAccent
                color: FiliTheme.text
            }
            Repeater {
                model: dlg.choices
                Rectangle {
                    id: ch
                    required property var modelData
                    width: col.width
                    height: 26
                    radius: FiliTheme.radiusControl
                    color: dlg.choice === modelData.id ? FiliTheme.surfaceActive : chArea.containsMouse ? FiliTheme.surfaceHover : "transparent"
                    Text {
                        anchors { fill: parent; leftMargin: FiliTheme.space2; rightMargin: FiliTheme.space2 }
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: ch.modelData.label
                        font.family: FiliTheme.font
                        font.pixelSize: FiliTheme.sizeList
                        color: FiliTheme.text
                    }
                    MouseArea { id: chArea; anchors.fill: parent; hoverEnabled: true; onClicked: dlg.choice = dlg.choice === ch.modelData.id ? -1 : ch.modelData.id }
                }
            }
            Text {
                visible: dlg.fieldLabel !== ""
                text: dlg.fieldLabel
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeSmall
                color: FiliTheme.muted
            }
            Rectangle {
                width: parent.width
                height: 28
                radius: FiliTheme.radiusControl
                color: FiliTheme.background
                border.width: FiliTheme.borderWidth
                border.color: input.activeFocus ? FiliTheme.accentColor : FiliTheme.border
                TextInput {
                    id: input
                    anchors { fill: parent; leftMargin: FiliTheme.space2; rightMargin: FiliTheme.space2 }
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.size
                    color: FiliTheme.text
                    selectionColor: FiliTheme.surfaceActive
                    selectedTextColor: FiliTheme.text
                    onTextChanged: if (text !== "")
                        dlg.choice = -1
                    Keys.onReturnPressed: dlg.accept()
                    Keys.onEscapePressed: dlg.close()
                }
            }
            Row {
                anchors.right: parent.right
                spacing: FiliTheme.space2
                TextButton { label: Fili.tr("Cancel"); onClicked: dlg.close() }
                TextButton { label: dlg.confirmLabel; primary: true; onClicked: dlg.accept() }
            }
        }
    }
}
