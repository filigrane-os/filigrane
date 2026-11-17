// First launch: how a double click behaves (play, or add with Alt), and where to change it. Shown once (ui state "welcomed").
import QtQuick
import Fili.Baladeur

Rectangle {
    id: dlg
    signal closed()
    anchors.fill: parent
    z: 310
    color: FiliTheme.alpha(FiliTheme.background, 0.6)
    focus: visible
    function dismiss() {
        visible = false;
        Fili.setUiState("welcomed", "1");
        dlg.closed();
    }
    onVisibleChanged: if (visible)
        forceActiveFocus()
    Keys.onEscapePressed: dismiss()
    Keys.onReturnPressed: dismiss()
    MouseArea { anchors.fill: parent }
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(480, parent.width - 2 * FiliTheme.margin)
        height: column.implicitHeight + 2 * FiliTheme.space6
        radius: FiliTheme.radiusWindow
        color: FiliTheme.surface
        border.width: FiliTheme.borderWidth
        border.color: FiliTheme.border
        Column {
            id: column
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: FiliTheme.space6 }
            spacing: FiliTheme.space3
            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 72
                height: 72
                source: "qrc:/qt/qml/Fili/Baladeur/icons/fili-music.svg"
                sourceSize: Qt.size(144, 144)
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Fili.tr("Welcome to Baladeur")
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeTitle + 4
                font.weight: Font.Light
                color: FiliTheme.text
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: Fili.tr("Here's how playback works in Baladeur.")
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.size
                color: FiliTheme.textSecondary
            }
            Repeater {
                model: [
                    { title: Fili.tr("Double-click a track"), text: Fili.tr("Plays it immediately, jumping the queue.") },
                    { title: Fili.tr("Alt + double-click"), text: Fili.tr("Adds it to the queue without interrupting what's playing.") },
                    { title: Fili.tr("Want it the other way around?"), text: Fili.tr("Set invert_queue in the settings (File → Settings…).") }
                ]
                Rectangle {
                    id: item
                    required property var modelData
                    width: column.width
                    height: body.implicitHeight + 2 * FiliTheme.space3
                    radius: FiliTheme.radiusControl + 2
                    color: FiliTheme.alpha(FiliTheme.surfaceHover, 0.5)
                    Column {
                        id: body
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: FiliTheme.space3 }
                        spacing: 2
                        Text {
                            width: parent.width
                            text: item.modelData.title
                            font.family: FiliTheme.font
                            font.pixelSize: FiliTheme.size
                            font.weight: FiliTheme.weightAccent
                            color: FiliTheme.text
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: item.modelData.text
                            font.family: FiliTheme.font
                            font.pixelSize: FiliTheme.sizeSmall
                            color: FiliTheme.textSecondary
                        }
                    }
                }
            }
            Item { width: 1; height: FiliTheme.space1 }
            TextButton {
                anchors.horizontalCenter: parent.horizontalCenter
                label: Fili.tr("Get started")
                primary: true
                onClicked: dlg.dismiss()
            }
        }
    }
}
