// Menu de l'application active dans la fili-bar (voir AppMenu): le nom de l'application en gras, puis ses menus, autant
// que la place libre (maxWidth, posée par la barre) en laisse voir. Les menus qui ne tiennent plus passent dans un
// titre « More », dont la liste les ouvre en sous-menus. Clic = ouvre ou ferme un menu; menu ouvert, passer sur un autre
// titre l'ouvre.
import QtQuick

Item {
    id: root
    // Fenêtre de la fili-bar qui porte ce menu (son écran reçoit le menu déroulé)
    property var bar
    // Place libre dans la barre
    property real maxWidth: Infinity
    readonly property int count: AppMenu.menus.length
    readonly property bool shown: count > 0

    // Titres affichés (au moins le premier) et largeur utilisée. Tout tient: aucun « More ». Sinon « More » prend la place
    // des derniers titres qui ne tiennent plus avec lui. La largeur d'un titre ne dépend pas de sa visibilité.
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

    // Titre i; l'index fit est « More »
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
        // Menus qui ne tiennent plus dans la barre
        Title {
            id: moreTitle
            objectName: "appmenu-more"
            visible: root.overflow
            text: FiliI18n.tr("More")
            current: AppMenu.open && AppMenu.more
            onClicked: AppMenu.toggle(root.fit, moreTitle, root.bar, root)
            onEntered: AppMenu.hoverTitle(root.fit, moreTitle, root.bar, root)
        }
    }
}
