// fili-bar: barre du haut, une par écran: mêmes modules et interactions que l'ancienne Waybar (inspirée de la barre Omarchy
// Quattro). Clic: action principale; clic droit/milieu/molette: voir chaque module. Les TUI s'ouvrent via bar-tui.
// Scripts réutilisés (BarScript.qml); natifs: niri, horloge, audio (PipeWire), MPRIS, Bluetooth, tray, batterie.
// Survol: fili-tooltip (fiche inspirée des panneaux d'Omarchy: état détaillé + rappel des clics); réseau, alimentation
// et écran lus au survol seulement (fili-info).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Bluetooth

PanelWindow {
    id: bar
    required property var modelData
    screen: modelData
    anchors { top: true; left: true; right: true }
    implicitHeight: FiliTheme.barHeight
    color: FiliTheme.nuit
    visible: !FiliTheme.testing
    WlrLayershell.namespace: "fili-bar"

    readonly property string b: FiliTheme.bin
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    PwObjectTracker { objects: [bar.sink, bar.source] }

    component Label: Text {
        color: FiliTheme.brume
        font.family: FiliTheme.font
        font.pixelSize: FiliTheme.size
        verticalAlignment: Text.AlignVCenter
    }

    // Clic sur le fond de la barre (hors modules): ferme fili-panel, calendrier épinglé et centre de notifications
    MouseArea {
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.AllButtons
        onPressed: FiliShell.popupOpened("")
    }

    // ───────── Gauche: logo, espaces de travail, fenêtre ─────────
    RowLayout {
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        spacing: 12

        // Logo Filigrane (brand/, lié dans ~/.local/share/filigrane par bootstrap.sh): ouvre le menu
        Item {
            Layout.leftMargin: 10
            implicitWidth: 44
            implicitHeight: FiliTheme.barHeight
            Image {
                anchors.centerIn: parent
                source: "file://" + Quickshell.env("HOME") + "/.local/share/filigrane/filigrane-sombre.svg"
                sourceSize.width: 44
                fillMode: Image.PreserveAspectFit
            }
            BarHover {
                objectName: "logo"
                anchors.fill: parent
                tip: ({ title: "Filigrane", hint: "clic: menu · clic droit: terminal" })
                click: "setsid -f " + bar.b + "/menu"
                rclick: "setsid -f foot"
            }
        }

        // Clic = aller au workspace, molette = précédent/suivant (sans boucler)
        Row {
            Layout.fillHeight: true
            Repeater {
                model: Niri.workspaces.filter(w => w.output === bar.screen.name)
                Rectangle {
                    required property var modelData
                    implicitWidth: ws.implicitWidth + 12
                    implicitHeight: FiliTheme.barHeight
                    color: modelData.is_active || wsHover.containsMouse ? FiliTheme.nuit3 : "transparent"
                    Label {
                        id: ws
                        anchors.centerIn: parent
                        text: parent.modelData.idx
                        color: parent.modelData.is_active || wsHover.containsMouse ? FiliTheme.brume : FiliTheme.ardoise
                    }
                    Rectangle {
                        visible: parent.modelData.is_active
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: 2
                        color: FiliTheme.voile
                    }
                    BarHover {
                        id: wsHover
                        anchors.fill: parent
                        // Fenêtres de l'espace (app, titre)
                        tip: {
                            const id = parent.modelData.id;
                            const wins = Object.values(Niri.windows).filter(w => w.workspace_id === id);
                            return {
                                title: "Espace " + parent.modelData.idx,
                                rows: wins.length ? wins.map(w => [w.app_id ?? "", w.title ?? ""]) : [["", "aucune fenêtre"]],
                                hint: "clic: y aller · molette: précédent / suivant"
                            };
                        }
                        onLeftClicked: Niri.action("focus-workspace", String(parent.modelData.idx))
                        onWheelUp: Niri.action("focus-workspace-up")
                        onWheelDown: Niri.action("focus-workspace-down")
                    }
                }
            }
        }

        // Clic milieu ou droit = fermer la fenêtre
        BarItem {
            objectName: "window"
            Layout.maximumWidth: 420
            text: {
                const t = Niri.focused?.title ?? "";
                return t.length > 60 ? t.slice(0, 59) + "…" : t;
            }
            color: FiliTheme.brume2
            tip: Niri.focused ? { title: Niri.focused.app_id, text: Niri.focused.title, hint: "clic droit ou milieu: fermer la fenêtre" } : ""
            hover.onRightClicked: Niri.action("close-window")
            hover.onMiddleClicked: Niri.action("close-window")
        }
    }

    // ───────── Centre: indicateurs, tiroir, horloge ─────────
    RowLayout {
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; bottom: parent.bottom }
        spacing: 12

        // Indicateurs et bascules: mails, WhatsApp, agenda, enregistrement, SSH, avion, VPN, veille, MAJ
        Row {
            // Nouveaux mails Proton / événement Proton Calendar imminent (masqués sinon, voir bar-alert), clic = ouvrir et effacer
            BarScript { objectName: "mail"; cmd: bar.b + "/bar-alert mail"; signal: 16; color: FiliTheme.voile; click: bar.b + "/bar-alert open mail" }
            BarScript { objectName: "whatsapp"; cmd: bar.b + "/bar-alert whatsapp"; signal: 19; click: bar.b + "/bar-alert open whatsapp" }
            BarScript { objectName: "cal"; cmd: bar.b + "/bar-alert cal"; signal: 17; color: FiliTheme.sable; click: bar.b + "/bar-alert open cal" }
            // Enregistrement d'écran: visible seulement en cours, clic = arrêter (démarrage: menu › Capture)
            BarScript { objectName: "rec"; cmd: bar.b + "/bar-status rec"; signal: 11; color: FiliTheme.cendre; click: bar.b + "/bar-toggle rec" }
            // Session SSH entrante, mode avion (clic = désactiver), VPN: réveillés par bar-stats watch
            BarScript { objectName: "remote"; cmd: bar.b + "/bar-status remote"; signal: 21; color: FiliTheme.cendre }
            BarScript { objectName: "air"; cmd: bar.b + "/bar-status air"; signal: 14; color: FiliTheme.sable; click: bar.b + "/bar-toggle air" }
            BarScript { objectName: "vpn"; cmd: bar.b + "/bar-status vpn"; signal: 22 }
            // Rapports de veille non lus, clic = les lire
            BarScript { objectName: "news"; cmd: bar.b + "/bar-news"; interval: 3600; signal: 15; color: FiliTheme.brume2; click: bar.b + "/bar-news open" }
            // Mises à jour xbps (masqué s'il n'y en a pas), clic = mettre à jour dans un terminal flottant
            BarScript { objectName: "update"; cmd: bar.b + "/bar-update"; interval: 3600; signal: 16; color: FiliTheme.sable; click: bar.b + "/bar-update run" }
        }

        // Tiroir (bar-tray): replié, seuls les indicateurs en cours d'usage restent visibles; clic sur le chevron = tout afficher
        Row {
            Repeater {
                model: SystemTray.items
                Item {
                    id: trayItem
                    required property var modelData
                    implicitWidth: 24
                    implicitHeight: FiliTheme.barHeight
                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: 16
                        source: parent.modelData.icon
                    }
                    BarHover {
                        anchors.fill: parent
                        tip: parent.modelData.tooltipTitle || parent.modelData.title
                        onLeftClicked: parent.modelData.onlyMenu ? menuAnchor.open() : parent.modelData.activate()
                        onRightClicked: if (parent.modelData.hasMenu) menuAnchor.open()
                        onMiddleClicked: parent.modelData.secondaryActivate()
                        onWheelUp: parent.modelData.scroll(1, false)
                        onWheelDown: parent.modelData.scroll(-1, false)
                    }
                    QsMenuAnchor {
                        id: menuAnchor
                        menu: trayItem.modelData.menu
                        anchor.item: trayItem
                        anchor.edges: Edges.Bottom
                        anchor.gravity: Edges.Bottom
                    }
                }
            }
            // Sauvegarde restic: gris au repos, clignotant en cours, rouge en échec; clic = sauvegarder maintenant
            BarScript {
                objectName: "backup"
                cmd: bar.b + "/bar-tray backup"; interval: 3600; signal: 18
                colors: ({ idle: FiliTheme.ardoise, active: FiliTheme.brume, failed: FiliTheme.cendre }); blinkClass: "active"
                click: bar.b + "/bar-backup run"
            }
            // Chevron du tiroir: clic = afficher / replier
            BarScript { objectName: "tray-handle"; cmd: bar.b + "/bar-tray handle"; signal: 20; hideEmpty: false; colors: ({ "": FiliTheme.ardoise, open: FiliTheme.brume2 }); click: bar.b + "/bar-tray toggle" }
        }

        // Clic = Proton Calendar, survol = calendrier (molette: mois précédent/suivant, clic milieu: mois courant)
        Item {
            id: clockItem
            implicitWidth: clockText.implicitWidth + 12
            implicitHeight: FiliTheme.barHeight
            SystemClock { id: clock; precision: SystemClock.Minutes }
            // Minuteur ou chronomètre en cours (bar-timer, rafraîchi chaque seconde par son ticker): remplace la date
            BarScript { id: timerState; visible: false; cmd: bar.b + "/bar-timer"; signal: 12 }
            readonly property bool timing: timerState.text !== "" && timerState.cls !== "idle"
            Label {
                id: clockText
                anchors.centerIn: parent
                text: clockItem.timing ? timerState.text : Qt.locale("C").toString(clock.date, "ddd dd MMM  HH:mm")
                color: !clockItem.timing ? FiliTheme.brume : timerState.cls === "done" ? FiliTheme.cendre : FiliTheme.sable
                // Chiffres de largeur fixe: l'horloge ne bouge pas à chaque seconde
                font.family: clockItem.timing ? FiliTheme.mono : FiliTheme.font
                font.weight: Font.Medium
            }
            MouseArea {
                objectName: "clock"
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                onContainsMouseChanged: if (containsMouse) { closeCal.stop(); cal.shift = 0; cal.show(); } else if (!cal.pinned) closeCal.restart()
                onClicked: m => press(m.button)
                // Clic (appelé aussi par les tests)
                function press(button) {
                    if (button === Qt.LeftButton) {
                        FiliTheme.run(bar.b + "/webapp https://calendar.proton.me");
                    } else if (button === Qt.MiddleButton) {
                        cal.shift = 0;
                    } else {
                        cal.pinned = !cal.pinned;
                        if (cal.pinned)
                            cal.show();
                        else
                            cal.visible = false;
                    }
                }
                onWheel: w => cal.shift += w.angleDelta.y > 0 ? -1 : 1
            }
            // Laisse le temps d'aller de l'horloge au calendrier (minuteur cliquable)
            Timer {
                id: closeCal
                interval: 250
                onTriggered: if (!cal.pinned && !cal.hovered) cal.visible = false
            }
            // Calendrier épinglé: un clic ailleurs sur l'écran le ferme. Fenêtre transparente sous la barre, percée à
            // l'emplacement du calendrier (centré sous l'horloge, 4 px sous la barre) pour que ses boutons restent cliquables.
            PanelWindow {
                id: dismiss
                visible: cal.pinned && cal.visible && !FiliTheme.testing
                screen: bar.screen
                anchors { top: true; bottom: true; left: true; right: true }
                margins.top: FiliTheme.barHeight
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.namespace: "fili-calendar-dismiss"
                color: "transparent"
                mask: Region {
                    width: dismiss.width
                    height: dismiss.height
                    Region {
                        x: Math.max(0, clockItem.mapToItem(null, clockItem.width / 2, 0).x - cal.implicitWidth / 2)
                        y: 4
                        width: cal.implicitWidth
                        height: cal.implicitHeight
                        intersection: Intersection.Subtract
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    onPressed: FiliShell.popupOpened("")
                }
            }
            FiliCalendar {
                id: cal
                anchor.item: clockItem
                today: clock.date
            }
        }
    }

    // ───────── Droite: média, ressources, système, batterie ─────────
    RowLayout {
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom; rightMargin: 6 }
        spacing: 12

        // Clic = lecture/pause, clic milieu = suivant, molette haut/bas = précédent/suivant
        BarItem {
            objectName: "media"
            readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
            text: {
                if (!player || !player.trackTitle)
                    return "";
                const t = player.isPlaying ? " " + player.trackTitle + (player.trackArtist ? "  ·  " + player.trackArtist : "") : " " + player.trackTitle;
                return t.length > 40 ? t.slice(0, 39) + "…" : t;
            }
            color: FiliTheme.brume2
            function mmss(s) {
                s = Math.max(0, Math.round(s));
                return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
            }
            tip: !player ? "" : {
                title: player.identity,
                rows: [["Titre", player.trackTitle], ["Artiste", player.trackArtist], ["Album", player.trackAlbum],
                       ["État", player.isPlaying ? "lecture" : "pause"],
                       ["Position", player.lengthSupported && player.length > 0 ? mmss(player.position) + " / " + mmss(player.length) : ""]].filter(r => r[1]),
                hint: "clic: lecture/pause · clic milieu: suivant · molette: précédent / suivant"
            }
            hover.onLeftClicked: player.togglePlaying()
            hover.onMiddleClicked: player.next()
            hover.onWheelUp: player.previous()
            hover.onWheelDown: player.next()
        }

        // Ressources: CPU et mémoire (top 5 en infobulle); température (dès 85 °C) et disque (dès 90 %) seulement quand ils
        // sont très hauts (bar-stats les vide sinon); clic = moniteur
        Row {
            BarScript { objectName: "cpu"; cmd: "exec " + bar.b + "/bar-stats cpu"; interval: -1; color: FiliTheme.brume2; hover.onLeftClicked: FiliPanel.toggle(hover, "monitor", bar); hint: "clic: moniteur" }
            BarScript { objectName: "temp"; cmd: "exec " + bar.b + "/bar-stats temp"; interval: -1; colors: ({ "": FiliTheme.sable, critical: FiliTheme.cendre }); hover.onLeftClicked: FiliPanel.toggle(hover, "monitor", bar); hint: "clic: moniteur" }
            BarScript { objectName: "mem"; cmd: "exec " + bar.b + "/bar-stats mem"; interval: -1; color: FiliTheme.brume2; hover.onLeftClicked: FiliPanel.toggle(hover, "monitor", bar); hint: "clic: moniteur" }
            BarScript {
                objectName: "disk"
                cmd: "exec " + bar.b + "/bar-stats disk"; interval: -1; hint: "clic: moniteur"
                colors: ({ "": FiliTheme.sable, critical: FiliTheme.cendre })
                hover.onLeftClicked: FiliPanel.toggle(hover, "monitor", bar)
            }
        }

        // Système: sortie audio, clavier, écrans, Bluetooth, réseau, notifications
        Row {
            // Sortie audio: clic = muet, molette = volume, clic droit = mixeur (wiremix), clic milieu = sound-tune
            BarItem {
                objectName: "volume"
                readonly property var audio: bar.sink?.audio ?? null
                readonly property int vol: audio ? Math.round(audio.volume * 100) : 0
                text: !audio ? "" : audio.muted ? " muet" : (vol < 34 ? "" : vol < 67 ? "" : "") + " " + vol + "%"
                color: audio?.muted ? FiliTheme.ardoise : FiliTheme.brume
                tip: !audio ? "" : {
                    title: audio.muted ? "Son coupé" : "Son",
                    rows: [["Sortie", bar.sink.description || bar.sink.nickname || bar.sink.name], ["Volume", vol + " %"],
                           ["Entrée", bar.source ? (bar.source.description || bar.source.name) : ""]].filter(r => r[1]),
                    hint: "clic: panneau son · clic milieu: muet · molette: volume · clic droit: mixeur"
                }
                hover.onLeftClicked: FiliPanel.toggle(hover, "audio", bar)
                hover.onMiddleClicked: audio.muted = !audio.muted
                hover.onWheelUp: audio.volume = Math.min(1, audio.volume + 0.05)
                hover.onWheelDown: audio.volume = Math.max(0, audio.volume - 0.05)
                hover.rclick: bar.b + "/bar-tui wiremix --tab output"
            }
            // Disposition clavier (bépo / qwerty australien): clic = panneau, clic milieu = disposition suivante
            BarItem {
                objectName: "keyboard"
                readonly property string name: Niri.layouts[Niri.layout] ?? ""
                text: name ? " " + Niri.shortName(name) : ""
                tip: ({
                    title: "Clavier",
                    rows: Niri.layouts.map((l, i) => [i === Niri.layout ? "●" : "", l]),
                    hint: "clic: panneau clavier · clic milieu: disposition suivante"
                })
                hover.onLeftClicked: FiliPanel.toggle(hover, "keyboard", bar)
                hover.onMiddleClicked: Niri.action("switch-layout", "next")
            }
            // Écrans: clic = panneau (disposition, définition, échelle, rotation), molette = luminosité
            BarItem {
                objectName: "display"
                text: ""
                tipCmd: bar.b + "/fili-info display"
                hover.onLeftClicked: FiliPanel.toggle(hover, "display", bar)
                hover.scrollUp: "brightnessctl -q set 5%+"
                hover.scrollDown: "brightnessctl -q set 5%-"
            }
            // Bluetooth (toujours visible, grisé sans adaptateur): clic = panneau (activer, appairer, connecter, oublier)
            BarItem {
                objectName: "bluetooth"
                readonly property var adapter: Bluetooth.defaultAdapter
                readonly property var connected: adapter ? adapter.devices.values.filter(d => d.connected) : []
                text: {
                    if (!adapter)
                        return "";
                    if (!adapter.enabled)
                        return " off";
                    const d = connected[0];
                    if (!d)
                        return " on";
                    return " " + d.name + (d.batteryAvailable ? " " + Math.round(d.battery * 100) + "%" : "");
                }
                color: !adapter ? FiliTheme.ardoise : FiliTheme.brume
                tip: !adapter ? { title: "Bluetooth", rows: [["État", "aucun adaptateur détecté"]], hint: "clic: panneau Bluetooth" } : {
                    title: "Bluetooth",
                    rows: [[adapter.name, adapter.enabled ? "activé" : "désactivé"]].concat(
                        adapter.devices.values.filter(d => d.paired || d.connected).map(d => [d.name,
                            (d.connected ? "connecté" : "appairé") + (d.connected && d.batteryAvailable ? ", " + Math.round(d.battery * 100) + " %" : "")])),
                    hint: "clic: panneau Bluetooth (appairer, connecter, oublier)"
                }
                hover.onLeftClicked: FiliPanel.toggle(hover, "bluetooth", bar)
            }
            // Wi-Fi: clic = impala (SSID, connexion), clic droit = menu réseau (IP, ping, débit)
            BarScript {
                objectName: "network"
                cmd: "exec " + bar.b + "/bar-stats net"; interval: -1; hideEmpty: false
                colors: ({ disconnected: FiliTheme.cendre })
                hover.onLeftClicked: FiliPanel.toggle(hover, "network", bar)
                rclick: "setsid -f " + bar.b + "/menu network"
                tipCmd: bar.b + "/fili-info network"
            }
            // Notifications: clic = historique, clic droit = Ne pas déranger
            BarItem {
                objectName: "notifications"
                text: FiliNotification.dnd ? "" : ""
                color: FiliNotification.dnd ? FiliTheme.sable : FiliTheme.ardoise
                tip: ({
                    title: FiliNotification.dnd ? "Ne pas déranger" : "Notifications",
                    rows: [["Bulles", FiliNotification.dnd ? "masquées" : "affichées"], ["Historique", FiliNotification.history.length + " notification(s)"]],
                    hint: "clic: fili-notification-center · clic droit: ne pas déranger"
                })
                hover.onLeftClicked: FiliNotification.toggleCenter()
                hover.onRightClicked: FiliNotification.dnd = !FiliNotification.dnd
            }
        }

        // Batterie: clic = menu système (verrouiller, veille, quitter...)
        BarPower {
            objectName: "power"
            tipCmd: bar.b + "/fili-info power"
            hover.onLeftClicked: FiliPanel.toggle(hover, "power", bar)
            hover.rclick: "setsid -f " + bar.b + "/menu system"
        }

        // Invisible: surveille SSH entrant, mode avion, VPN, veilleuse, sauvegarde, agenda et batterie faible
        // (bar-stats watch) et réveille par `bar refresh N` le module dont l'état a changé
        BarScript { objectName: "watch"; cmd: "exec " + bar.b + "/bar-stats watch"; interval: -1 }
    }
}
