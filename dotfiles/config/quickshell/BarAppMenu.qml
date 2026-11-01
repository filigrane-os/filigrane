// Titres du menu de l'application active dans la fili-bar (voir AppMenu): le nom de l'application en gras, puis ses menus.
// Clic = ouvre ou ferme le menu; menu ouvert, passer sur un autre titre l'ouvre.
import QtQuick

Row {
    id: root
    // Fenêtre de la fili-bar qui porte ce menu (son écran reçoit le menu déroulé)
    property var bar
    visible: AppMenu.menus.length > 0

    Repeater {
        model: AppMenu.menus
        Item {
            id: title
            required property var modelData
            required property int index
            readonly property bool current: AppMenu.open && AppMenu.openIndex === index
            objectName: "appmenu-" + index
            implicitWidth: label.implicitWidth + 2 * FiliTheme.pad
            implicitHeight: FiliTheme.barHeight
            Rectangle {
                anchors.fill: parent
                color: title.current || area.containsMouse ? FiliTheme.nuit3 : "transparent"
            }
            Text {
                id: label
                anchors.centerIn: parent
                text: FiliI18n.tr(title.modelData.label, AppMenu.appName)
                color: title.current || area.containsMouse ? FiliTheme.brume : FiliTheme.brume2
                font {
                    family: FiliTheme.font
                    pixelSize: FiliTheme.size
                    weight: title.index === 0 ? FiliTheme.weightAccent : Font.Normal
                }
            }
            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: AppMenu.toggle(title.index, title, root.bar)
                onEntered: AppMenu.hoverTitle(title.index, title, root.bar)
            }
        }
    }
}
