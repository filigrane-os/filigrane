// A labelled text field of the tag editor, with suggestions (artists, albums, genres already in the library) that drop down
// while typing. `text` is read and set directly; `mixed` shows "Mixed" as a placeholder (several tracks with different values).
import QtQuick
import Fili.Baladeur

Item {
    id: field
    property string label
    property var suggestions: []
    property bool mixed: false
    property alias text: input.text
    property alias input: input
    signal submitted()
    signal edited()

    width: parent ? parent.width : 300
    height: 28
    readonly property var matches: {
        const t = input.text.trim().toLowerCase();
        if (!input.activeFocus || t === "")
            return [];
        return suggestions.filter(s => s.toLowerCase().includes(t) && s.toLowerCase() !== t).slice(0, 6);
    }

    Text {
        id: caption
        width: 96
        height: parent.height
        verticalAlignment: Text.AlignVCenter
        text: field.label
        font.family: FiliTheme.font
        font.pixelSize: FiliTheme.size
        color: FiliTheme.muted
    }
    Rectangle {
        anchors { left: caption.right; right: parent.right; top: parent.top; bottom: parent.bottom }
        radius: FiliTheme.radiusControl
        color: FiliTheme.background
        border.width: FiliTheme.borderWidth
        border.color: input.activeFocus ? FiliTheme.accentColor : FiliTheme.border
        Text {
            anchors { left: parent.left; leftMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
            visible: input.text === "" && field.mixed
            text: Fili.tr("Mixed")
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.size
            font.italic: true
            color: FiliTheme.muted
        }
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
            onTextEdited: field.edited()
            Keys.onReturnPressed: field.submitted()
            Accessible.name: field.label
        }
    }
    // Suggestions: in front of what follows the field
    Rectangle {
        visible: field.matches.length > 0
        z: 20
        x: caption.width
        y: field.height + 2
        width: field.width - caption.width
        height: field.matches.length * 24 + 2
        radius: FiliTheme.radiusControl
        color: FiliTheme.surface
        border.width: FiliTheme.borderWidth
        border.color: FiliTheme.border
        Column {
            anchors { fill: parent; margins: 1 }
            Repeater {
                model: field.matches
                Rectangle {
                    id: sg
                    required property string modelData
                    width: parent.width
                    height: 24
                    radius: FiliTheme.radiusControl
                    color: sgArea.containsMouse ? FiliTheme.surfaceHover : "transparent"
                    Text {
                        anchors { fill: parent; leftMargin: FiliTheme.space2; rightMargin: FiliTheme.space2 }
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: sg.modelData
                        font.family: FiliTheme.font
                        font.pixelSize: FiliTheme.sizeList
                        color: FiliTheme.text
                    }
                    MouseArea {
                        id: sgArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            input.text = sg.modelData;
                            field.edited();
                        }
                    }
                }
            }
        }
    }
}
