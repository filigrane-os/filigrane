// Small-caps subheading of the fili-panel, preceded by a thin rule unless it is the first visible one of its view
// (the rule separates the sections from one another)
import QtQuick
import QtQuick.Layouts
import qs

Item {
    id: sec
    property alias text: label.text
    // Marker for sibling sections (see refresh)
    readonly property bool isSection: true
    property bool first: true
    // false: no rule (sections of the same block, see DisplayPanel)
    property bool divided: true
    readonly property bool ruled: divided && !first

    Layout.fillWidth: true
    implicitHeight: label.implicitHeight + (ruled ? 17 : 6)

    Rectangle {
        visible: sec.ruled
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: FiliTheme.space2 }
        height: 1
        color: FiliTheme.nuit4
    }
    Text {
        id: label
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall; letterSpacing: 1 }
    }

    // Without a rule only the first visible section stuck to the title of the view (y < 40): after a card, a
    // button or a canvas, the rule separates it from what precedes. Recomputed when a section changes visibility or
    // place (an item appears above it).
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
