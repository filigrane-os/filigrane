// Menu of the active application in the fili-bar (see AppMenu): the application name in bold, then its menus, as many as
// the free space (maxWidth, set by BarSlot) shows. The menus that no longer fit move into a "…" title whose list opens
// them as submenus. Click = open or close a menu; with a menu open, moving over another title opens it.
import QtQuick
import qs
import qs.bar

BarModule {
    id: root
    objectName: "appmenu"
    // Free space in the bar
    property real maxWidth: Infinity
    readonly property int count: AppMenu.menus.length
    readonly property bool shown: count > 0

    // Titles shown (at least the first) and width used. Everything fits: no "…". Otherwise "…" takes the place of the
    // last titles that no longer fit with it. The width of a title does not depend on its visibility.
    readonly property var layout: {
        void rep.count;
        const n = count;
        const w = [];
        for (let i = 0; i < n; i++)
            w.push(rep.itemAt(i)?.implicitWidth ?? 0);
        let sum = 0;
        let k = 0;
        while (k < n && sum + w[k] <= maxWidth) {
            sum += w[k];
            k++;
        }
        if (k === n)
            return { fit: n, width: sum };
        while (k > 1 && sum + moreTitle.implicitWidth > maxWidth) {
            k--;
            sum -= w[k];
        }
        k = Math.max(1, k);
        if (k === 1)
            sum = w[0];
        return { fit: k, width: sum + moreTitle.implicitWidth };
    }
    readonly property int fit: layout.fit
    readonly property bool overflow: fit < count
    visible: shown
    implicitWidth: shown ? layout.width : 0
    implicitHeight: FiliTheme.barHeight

    // Title i; index fit is the "…"
    function titleAt(i) {
        return i < fit ? rep.itemAt(i) : (overflow && i === fit ? moreTitle : null);
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
            onPressed: AppMenu.pressTitle()
            onClicked: title.clicked()
            onEntered: title.entered()
        }
    }

    Row {
        Repeater {
            id: rep
            model: AppMenu.menus
            Title {
                id: t
                required property var modelData
                required property int index
                objectName: "appmenu-" + index
                visible: index < root.fit
                text: FiliI18n.tr(modelData.label, AppMenu.appName)
                bold: index === 0
                current: AppMenu.open && AppMenu.openIndex === index
                onClicked: AppMenu.toggle(index, t, root.bar, root)
                onEntered: AppMenu.hoverTitle(index, t, root.bar, root)
            }
        }
        // Menus that no longer fit in the bar
        Title {
            id: moreTitle
            objectName: "appmenu-more"
            visible: root.overflow
            text: "…"
            current: AppMenu.open && AppMenu.more
            onClicked: AppMenu.toggle(root.fit, moreTitle, root.bar, root)
            onEntered: AppMenu.hoverTitle(root.fit, moreTitle, root.bar, root)
        }
    }
}
