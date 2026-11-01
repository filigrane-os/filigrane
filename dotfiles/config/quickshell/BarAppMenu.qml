// Menu de l'application active dans la fili-bar (voir AppMenu): le nom de l'application en gras, puis ses menus, tous
// visibles (accès direct). Clic = ouvre ou ferme un menu; menu ouvert, passer sur un autre titre l'ouvre.
// Quand les titres ne tiennent pas dans la place libre (maxWidth, posée par la barre), seul le nom de l'application
// reste: il ouvre la liste des menus (mode compact), pour ne pas déborder sur les indicateurs de droite.
import QtQuick

Item {
    id: root
    // Fenêtre de la fili-bar qui porte ce menu (son écran reçoit le menu déroulé)
    property var bar
    // Place libre dans la barre
    property real maxWidth: Infinity
    readonly property bool shown: AppMenu.menus.length > 0
    readonly property bool compact: inline.implicitWidth > maxWidth
    visible: shown
    implicitWidth: shown ? (compact ? compactTitle.implicitWidth : inline.implicitWidth) : 0
    implicitHeight: FiliTheme.barHeight

    // Titre i (le seul, en mode compact)
    function titleAt(i) {
        return compact ? compactTitle : rep.itemAt(i);
    }
    Component.onCompleted: AppMenu.register(root)

    component Title: Item {
        id: title
        property string text
        property bool bold: false
        property bool current: false
        signal clicked
        signal entered
        implicitWidth: label.implicitWidth + 2 * FiliTheme.pad
        implicitHeight: FiliTheme.barHeight
        Rectangle {
            anchors.fill: parent
            color: title.current || area.containsMouse ? FiliTheme.nuit3 : "transparent"
        }
        Text {
            id: label
            anchors.centerIn: parent
            text: title.text
            color: title.current || area.containsMouse ? FiliTheme.brume : FiliTheme.brume2
            font {
                family: FiliTheme.font
                pixelSize: FiliTheme.size
                weight: title.bold ? FiliTheme.weightAccent : Font.Normal
            }
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: title.clicked()
            onEntered: title.entered()
        }
    }

    Row {
        id: inline
        visible: !root.compact
        Repeater {
            id: rep
            model: AppMenu.menus
            Title {
                id: t
                required property var modelData
                required property int index
                objectName: "appmenu-" + index
                text: FiliI18n.tr(modelData.label, AppMenu.appName)
                bold: index === 0
                current: AppMenu.open && AppMenu.openIndex === index
                onClicked: AppMenu.toggle(index, t, root.bar, root)
                onEntered: AppMenu.hoverTitle(index, t, root.bar, root)
            }
        }
    }
    // Mode compact: nom de l'application seul
    Title {
        id: compactTitle
        objectName: "appmenu-compact"
        visible: root.compact
        text: root.shown ? FiliI18n.tr(AppMenu.menus[0].label, AppMenu.appName) : ""
        bold: true
        current: AppMenu.open
        onClicked: AppMenu.toggle(0, compactTitle, root.bar, root)
    }
}
