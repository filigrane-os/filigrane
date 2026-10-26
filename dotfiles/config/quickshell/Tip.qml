// Infobulle unique de la barre, sous l'élément survolé. Le balisage Pango des scripts (<tt>, <b>...) est retiré;
// <tt> passe le texte en police à chasse fixe (tableaux des top CPU/RAM).
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: tip
    property Item target: null
    property string text: ""
    property bool mono: false

    function show(item, t, m) {
        if (!t) {
            hide(item);
            return;
        }
        target = item;
        text = t.replace(/<[^>]*>/g, "").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">");
        mono = m;
        delay.restart();
    }
    function hide(item) {
        if (item && item !== target)
            return;
        delay.stop();
        popup.visible = false;
    }

    Timer {
        id: delay
        interval: 400
        onTriggered: if (tip.target) popup.visible = true
    }

    PopupWindow {
        id: popup
        visible: false
        anchor.item: tip.target
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 4
        implicitWidth: body.implicitWidth + 20
        implicitHeight: body.implicitHeight + 14
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            color: Theme.nuit
            border.color: Theme.nuit4
            border.width: 1
            radius: 10
            Text {
                id: body
                anchors.centerIn: parent
                text: tip.text
                color: Theme.brume
                font.family: tip.mono ? Theme.mono : Theme.font
                font.pixelSize: tip.mono ? 12 : Theme.size
            }
        }
    }
}
