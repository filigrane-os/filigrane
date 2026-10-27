pragma Singleton
// fili-notification: serveur de notifications (remplace mako), bulles en haut à droite sous la fili-bar, 4 au plus,
// durée selon l'urgence (celle demandée par l'appli est ignorée), Ne pas déranger (bulles masquées).
// fili-notification-center: historique des 30 dernières (clic sur la cloche de la fili-bar, `fili-shell notification center`).
// Clic gauche sur une bulle: action par défaut puis focus sur la fenêtre de l'appli (notif-focus); croix ou clic droit: fermer.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Notifications

Singleton {
    id: notifs
    property bool dnd: false
    // Bulles affichées: { n: Notification, key }
    property var popups: []
    // Historique (copies, plus récentes en tête): { app, icon, summary, body, time }
    property var history: []
    property bool centerOpen: false
    property int serial: 0

    function timeout(n) {
        return n.urgency === NotificationUrgency.Critical ? 10000 : n.urgency === NotificationUrgency.Low ? 3000 : 5000;
    }
    function icon(n) {
        const i = n.image || n.appIcon;
        if (!i)
            return "";
        return i.startsWith("/") ? "file://" + i : i.indexOf("://") > 0 || i.startsWith("image:") ? i : Quickshell.iconPath(i, true);
    }
    // Ferme une bulle; elle passe dans l'historique (sauf captures niri: image plein écran, cf. ancien mako)
    function close(n, how) {
        if (!n)
            return;
        popups = popups.filter(p => p.n !== n);
        if (n.appName !== "niri")
            history = [{ app: n.appName, icon: n.appIcon, summary: n.summary, body: n.body, time: new Date() }].concat(history).slice(0, 30);
        if (how === "expire")
            n.expire();
        else
            n.dismiss();
    }
    function dismissAll() {
        for (const p of popups.slice())
            close(p.n, "dismiss");
    }
    function toggleCenter() {
        centerOpen = !centerOpen;
        if (centerOpen)
            FiliShell.popupOpened("center");
    }
    function activate(n) {
        const def = n.actions.find(a => a.identifier === "default");
        const app = n.appName, entry = n.desktopEntry;
        if (def)
            def.invoke();
        Quickshell.execDetached([FiliTheme.bin + "/notif-focus", app, entry]);
        close(n, "dismiss");
    }

    NotificationServer {
        keepOnReload: true
        actionsSupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        imageSupported: true
        persistenceSupported: true
        onNotification: n => {
            n.tracked = true;
            if (notifs.dnd) {
                notifs.close(n, "expire");
                return;
            }
            if (n.urgency !== NotificationUrgency.Low)
                FiliSound.notified();
            notifs.popups = notifs.popups.concat([{ n: n, key: ++notifs.serial }]);
            n.closed.connect(() => notifs.popups = notifs.popups.filter(p => p.n !== n));
        }
    }

    Connections {
        target: FiliShell
        function onPopupOpened(who) {
            if (who !== "center")
                notifs.centerOpen = false;
        }
    }
    Connections {
        target: FiliShell
        function onCommand(target, name, args) {
            if (target !== "notification")
                return;
            if (name === "dnd")
                notifs.dnd = args[0] === "on" ? true : args[0] === "off" ? false : !notifs.dnd;
            else if (name === "dismiss-all")
                notifs.dismissAll();
            else if (name === "dismiss") {
                const s = args.join(" ");
                const p = notifs.popups.find(p => p.n.summary === s);
                if (p)
                    notifs.close(p.n, "dismiss");
            } else if (name === "center")
                notifs.toggleCenter();
            else if (name === "history")
                FiliShell.reply(args[0], JSON.stringify(notifs.history.map(h => ({ app_name: h.app, app_icon: h.icon, summary: h.summary, body: h.body }))));
        }
    }

    // fili-notification: bulles
    PanelWindow {
        visible: !notifs.dnd && notifs.popups.length > 0 && !FiliTheme.testing
        anchors { top: true; right: true }
        margins { top: 12; right: 12 }
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "fili-notification"
        implicitWidth: 360
        implicitHeight: Math.max(1, stack.implicitHeight)
        color: "transparent"

        ColumnLayout {
            id: stack
            width: 360
            spacing: 8
            Repeater {
                model: notifs.popups.slice(-4).reverse()
                Card {
                    required property var modelData
                    n: modelData.n
                    Layout.fillWidth: true
                }
            }
        }
    }

    component Card: Rectangle {
        id: card
        property var n
        readonly property bool low: n.urgency === NotificationUrgency.Low
        readonly property bool critical: n.urgency === NotificationUrgency.Critical
        readonly property string img: notifs.icon(n)
        implicitHeight: Math.min(140, Math.max(row.implicitHeight + 28, 56))
        color: FiliTheme.nuit
        radius: 12
        border.width: 1
        border.color: critical ? FiliTheme.cendre : low ? FiliTheme.nuit3 : FiliTheme.nuit4
        clip: true

        Timer {
            running: !area.containsMouse && !closeBtn.hovered
            interval: notifs.timeout(card.n)
            onTriggered: notifs.close(card.n, "expire")
        }
        RowLayout {
            id: row
            anchors { fill: parent; margins: 14; rightMargin: 34 }
            spacing: 12
            IconImage {
                visible: card.img !== ""
                source: card.img
                implicitSize: 40
                Layout.alignment: Qt.AlignTop
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    text: card.n.summary
                    elide: Text.ElideRight
                    color: card.low ? FiliTheme.brume2 : FiliTheme.brume
                    font { family: FiliTheme.font; pixelSize: 15; weight: Font.Medium }
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: card.n.body
                    textFormat: Text.StyledText
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    color: card.low ? FiliTheme.brume2 : FiliTheme.brume
                    linkColor: FiliTheme.voile
                    font { family: FiliTheme.font; pixelSize: 14 }
                    onLinkActivated: l => Qt.openUrlExternally(l)
                }
                // Barre de progression (indice "value")
                Rectangle {
                    visible: card.n.hints.value !== undefined
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    implicitHeight: 4
                    radius: 2
                    color: FiliTheme.nuit3
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(100, card.n.hints.value ?? 0)) / 100
                        height: parent.height
                        radius: 2
                        color: FiliTheme.voile
                    }
                }
            }
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: m => m.button === Qt.LeftButton ? notifs.activate(card.n) : notifs.close(card.n, "dismiss")
        }
        CloseCross {
            id: closeBtn
            anchors { top: parent.top; right: parent.right; margins: 8 }
            onClicked: notifs.close(card.n, "dismiss")
        }
    }

    // Croix de fermeture (bulles et fili-notification-center): discrète, plus claire au survol
    component CloseCross: Rectangle {
        id: cross
        signal clicked
        readonly property bool hovered: crossArea.containsMouse
        width: 22
        height: 22
        radius: 6
        color: hovered ? FiliTheme.nuit3 : "transparent"
        Text {
            anchors.centerIn: parent
            text: "\u2715"
            color: cross.hovered ? FiliTheme.brume : FiliTheme.ardoise
            font { family: FiliTheme.font; pixelSize: 12 }
        }
        MouseArea {
            id: crossArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: cross.clicked()
        }
    }

    // fili-notification-center: clic = copier le texte, croix ou clic droit = retirer, Échap ou clic hors du panneau = fermer
    PanelWindow {
        visible: notifs.centerOpen && !FiliTheme.testing
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "fili-notification-center"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        color: "transparent"

        MouseArea {
            anchors.fill: parent
            onClicked: notifs.centerOpen = false
        }
        Rectangle {
            anchors { top: parent.top; right: parent.right; margins: 12 }
            width: 380
            height: Math.min(parent.height - 24, col.implicitHeight + 28)
            color: FiliTheme.nuit
            radius: 12
            border { width: 1; color: FiliTheme.nuit4 }
            focus: true
            Keys.onEscapePressed: notifs.centerOpen = false
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: col
                anchors { fill: parent; margins: 14 }
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: "Notifications" + (notifs.dnd ? "  ·  ne pas déranger" : "")
                        color: FiliTheme.voile
                        font { family: FiliTheme.font; pixelSize: 15; weight: Font.Medium }
                    }
                    Text {
                        text: notifs.dnd ? "" : ""
                        color: notifs.dnd ? FiliTheme.sable : FiliTheme.ardoise
                        font { family: FiliTheme.font; pixelSize: 15 }
                        MouseArea { anchors.fill: parent; onClicked: notifs.dnd = !notifs.dnd }
                    }
                    Text {
                        text: "Effacer"
                        visible: notifs.history.length > 0
                        color: FiliTheme.ardoise
                        font { family: FiliTheme.font; pixelSize: 13 }
                        MouseArea { anchors.fill: parent; onClicked: notifs.history = [] }
                    }
                }
                Text {
                    visible: notifs.history.length === 0
                    text: "Aucune notification"
                    color: FiliTheme.ardoise
                    font { family: FiliTheme.font; pixelSize: 13 }
                }
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    implicitHeight: contentHeight
                    clip: true
                    spacing: 6
                    model: notifs.history
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        implicitHeight: entry.implicitHeight + 16
                        radius: 9
                        color: hov.containsMouse ? FiliTheme.nuit3 : "transparent"
                        ColumnLayout {
                            id: entry
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 8; rightMargin: 32 }
                            spacing: 1
                            Text {
                                Layout.fillWidth: true
                                text: parent.parent.modelData.app + "  ·  " + Qt.formatTime(parent.parent.modelData.time, "HH:mm")
                                color: FiliTheme.ardoise
                                font { family: FiliTheme.font; pixelSize: 12 }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: parent.parent.modelData.summary
                                elide: Text.ElideRight
                                color: FiliTheme.brume
                                font { family: FiliTheme.font; pixelSize: 14; weight: Font.Medium }
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: parent.parent.modelData.body.replace(/<[^>]*>/g, "")
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                color: FiliTheme.brume2
                                font { family: FiliTheme.font; pixelSize: 13 }
                            }
                        }
                        MouseArea {
                            id: hov
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: m => {
                                const h = parent.modelData;
                                if (m.button === Qt.RightButton) {
                                    notifs.history = notifs.history.filter(x => x !== h);
                                } else {
                                    Quickshell.execDetached(["wl-copy", h.summary + (h.body ? "\n" + h.body.replace(/<[^>]*>/g, "") : "")]);
                                    notifs.centerOpen = false;
                                }
                            }
                        }
                        CloseCross {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 6 }
                            visible: hov.containsMouse || hovered
                            onClicked: notifs.history = notifs.history.filter(x => x !== parent.modelData)
                        }
                    }
                }
                // Réglages: sous les notifications, séparés d'un trait
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: FiliTheme.nuit4
                }
                // Sons (FiliSound): nouvelle notification et chargeur branché
                Repeater {
                    model: [["notify", "Son des notifications"], ["plug", "Son du chargeur branché"]]
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: parent.modelData[1]
                            color: FiliTheme.brume
                            font { family: FiliTheme.font; pixelSize: 13 }
                        }
                        PanelSwitch {
                            objectName: "sound-" + parent.modelData[0]
                            checked: parent.modelData[0] === "notify" ? FiliSound.notify : FiliSound.plug
                            onToggled: FiliSound.set(parent.modelData[0], !checked)
                        }
                    }
                }
            }
        }
    }
}
