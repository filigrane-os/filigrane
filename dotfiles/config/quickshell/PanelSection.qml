// Intertitre en petites capitales des fili-panel, précédé d'un filet fin sauf s'il est le premier visible de sa vue
// (le filet sépare les sections entre elles)
import QtQuick
import QtQuick.Layouts

Item {
    id: sec
    property alias text: label.text
    // Repère pour les sections sœurs (voir refresh)
    readonly property bool isSection: true
    property bool first: true
    readonly property bool ruled: !first

    Layout.fillWidth: true
    implicitHeight: label.implicitHeight + (ruled ? 17 : 6)

    Rectangle {
        visible: sec.ruled
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 8 }
        height: 1
        color: FiliTheme.nuit4
    }
    Text {
        id: label
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: 11; letterSpacing: 1 }
    }

    // Sans filet seulement la première section visible et collée au titre de la vue (y < 40): après une fiche, un
    // bouton ou un canvas, le filet la sépare de ce qui précède. Recalculé quand une section change de visibilité ou
    // de place (un élément apparaît au-dessus).
    function refresh() {
        let seen = false;
        for (const c of parent.children) {
            if (c.isSection !== true)
                continue;
            c.first = c.visible && !seen && c.y < 40;
            seen = seen || c.visible;
        }
    }
    onVisibleChanged: Qt.callLater(refresh)
    onYChanged: Qt.callLater(refresh)
    Component.onCompleted: Qt.callLater(refresh)
}
