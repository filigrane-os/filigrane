// Barre du haut, une par écran: mêmes modules et interactions que l'ancienne Waybar (inspirée de la barre Omarchy
// Quattro). Clic: action principale; clic droit/milieu/molette: voir chaque module. Les TUI s'ouvrent via bar-tui.
// Scripts réutilisés (Mod.qml); natifs: niri, horloge, audio (PipeWire), MPRIS, Bluetooth, tray, batterie.
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
    implicitHeight: Theme.barHeight
    color: Theme.nuit
    WlrLayershell.namespace: "filigrane-bar"

    readonly property string b: Theme.bin
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    PwObjectTracker { objects: [bar.sink, bar.source] }

    component Label: Text {
        color: Theme.brume
        font.family: Theme.font
        font.pixelSize: Theme.size
        verticalAlignment: Text.AlignVCenter
    }

    // ───────── Gauche: logo, espaces de travail, fenêtre ─────────
    RowLayout {
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        spacing: 12

        // Logo Filigrane (brand/, lié dans ~/.local/share/filigrane par bootstrap.sh): ouvre le menu
        Item {
            Layout.leftMargin: 10
            implicitWidth: 44
            implicitHeight: Theme.barHeight
            Image {
                anchors.centerIn: parent
                source: "file://" + Quickshell.env("HOME") + "/.local/share/filigrane/filigrane-sombre.svg"
                sourceSize.width: 44
                fillMode: Image.PreserveAspectFit
            }
            Hover {
                anchors.fill: parent
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
                    implicitHeight: Theme.barHeight
                    color: modelData.is_active || wsHover.containsMouse ? Theme.nuit3 : "transparent"
                    Label {
                        id: ws
                        anchors.centerIn: parent
                        text: parent.modelData.idx
                        color: parent.modelData.is_active || wsHover.containsMouse ? Theme.brume : Theme.ardoise
                    }
                    Rectangle {
                        visible: parent.modelData.is_active
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: 2
                        color: Theme.voile
                    }
                    Hover {
                        id: wsHover
                        anchors.fill: parent
                        onLeftClicked: Niri.action("focus-workspace", String(parent.modelData.idx))
                        onWheelUp: Niri.action("focus-workspace-up")
                        onWheelDown: Niri.action("focus-workspace-down")
                    }
                }
            }
        }

        // Clic milieu ou droit = fermer la fenêtre
        Native {
            Layout.maximumWidth: 420
            text: {
                const t = Niri.focused?.title ?? "";
                return t.length > 60 ? t.slice(0, 59) + "…" : t;
            }
            color: Theme.brume2
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
            Mod { cmd: bar.b + "/bar-alert mail"; signal: 16; color: Theme.voile; click: bar.b + "/bar-alert open mail" }
            Mod { cmd: bar.b + "/bar-alert whatsapp"; signal: 19; click: bar.b + "/bar-alert open whatsapp" }
            Mod { cmd: bar.b + "/bar-alert cal"; signal: 17; color: Theme.sable; click: bar.b + "/bar-alert open cal" }
            // Enregistrement d'écran: visible seulement en cours, clic = arrêter (démarrage: menu › Capture)
            Mod { cmd: bar.b + "/bar-status rec"; signal: 11; color: Theme.cendre; click: bar.b + "/bar-toggle rec" }
            // Session SSH entrante, mode avion (clic = désactiver), VPN: réveillés par bar-stats watch
            Mod { cmd: bar.b + "/bar-status remote"; signal: 21; color: Theme.cendre }
            Mod { cmd: bar.b + "/bar-status air"; signal: 14; color: Theme.sable; click: bar.b + "/bar-toggle air" }
            Mod { cmd: bar.b + "/bar-status vpn"; signal: 22 }
            // Rapports de veille non lus, clic = les lire
            Mod { cmd: bar.b + "/bar-news"; interval: 3600; signal: 15; color: Theme.brume2; click: bar.b + "/bar-news open" }
            // Mises à jour xbps (masqué s'il n'y en a pas), clic = mettre à jour dans un terminal flottant
            Mod { cmd: bar.b + "/bar-update"; interval: 3600; signal: 16; color: Theme.sable; click: bar.b + "/bar-update run" }
        }

        // Tiroir (bar-tray): replié, seuls les indicateurs en cours d'usage restent visibles; clic sur le chevron = tout afficher
        Row {
            Repeater {
                model: SystemTray.items
                Item {
                    id: trayItem
                    required property var modelData
                    implicitWidth: 24
                    implicitHeight: Theme.barHeight
                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: 16
                        source: parent.modelData.icon
                    }
                    Hover {
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
            // Minuteur / chronomètre: clic = choisir (ou arrêter), clic droit = +5 min; notification à la fin
            Mod { cmd: bar.b + "/bar-tray timer"; signal: 12; click: bar.b + "/bar-timer click"; rclick: bar.b + "/bar-timer add" }
            // Caféine: tasse jaune = verrouillage auto coupé, grise = actif; clic = bascule
            Mod { cmd: bar.b + "/bar-tray idle"; signal: 13; colors: ({ idle: Theme.ardoise, active: Theme.sable }); click: bar.b + "/bar-toggle idle" }
            // Veilleuse (wlsunset, 4500 K la nuit), clic = coupe/force
            Mod { cmd: bar.b + "/bar-tray night"; signal: 10; colors: ({ idle: Theme.ardoise, active: Theme.sable }); click: bar.b + "/bar-toggle night" }
            // Sauvegarde restic: gris au repos, clignotant en cours, rouge en échec; clic = sauvegarder maintenant
            Mod {
                cmd: bar.b + "/bar-tray backup"; interval: 3600; signal: 18
                colors: ({ idle: Theme.ardoise, active: Theme.brume, failed: Theme.cendre }); blinkClass: "active"
                click: bar.b + "/bar-backup run"
            }
            // Chevron du tiroir: clic = afficher / replier
            Mod { cmd: bar.b + "/bar-tray handle"; signal: 20; hideEmpty: false; colors: ({ "": Theme.ardoise, open: Theme.brume2 }); click: bar.b + "/bar-tray toggle" }
        }

        // Clic = Proton Calendar, survol = calendrier (molette: mois précédent/suivant, clic milieu: mois courant)
        Item {
            id: clockItem
            implicitWidth: clockText.implicitWidth + 12
            implicitHeight: Theme.barHeight
            SystemClock { id: clock; precision: SystemClock.Minutes }
            Label {
                id: clockText
                anchors.centerIn: parent
                text: Qt.locale("C").toString(clock.date, "ddd dd MMM  HH:mm")
                font.weight: Font.Medium
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                onContainsMouseChanged: if (containsMouse) { cal.shift = 0; cal.visible = true; } else if (!cal.pinned) cal.visible = false
                onClicked: m => {
                    if (m.button === Qt.LeftButton) {
                        Theme.run(bar.b + "/webapp https://calendar.proton.me");
                    } else if (m.button === Qt.MiddleButton) {
                        cal.shift = 0;
                    } else {
                        cal.pinned = !cal.pinned;
                        cal.visible = cal.pinned;
                    }
                }
                onWheel: w => cal.shift += w.angleDelta.y > 0 ? -1 : 1
            }
            Calendar {
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
        Native {
            readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
            text: {
                if (!player || !player.trackTitle)
                    return "";
                const t = player.isPlaying ? " " + player.trackTitle + (player.trackArtist ? "  ·  " + player.trackArtist : "") : " " + player.trackTitle;
                return t.length > 40 ? t.slice(0, 39) + "…" : t;
            }
            color: Theme.brume2
            tip: player ? player.identity + ": " + player.trackTitle + "\n" + player.trackArtist + " · " + player.trackAlbum : ""
            hover.onLeftClicked: player.togglePlaying()
            hover.onMiddleClicked: player.next()
            hover.onWheelUp: player.previous()
            hover.onWheelDown: player.next()
        }

        // Ressources: CPU (top 5 en infobulle), température, mémoire, disque; clic = htop
        Row {
            Mod { cmd: "exec " + bar.b + "/bar-stats cpu"; interval: -1; color: Theme.brume2; click: bar.b + "/bar-tui htop" }
            Mod { cmd: "exec " + bar.b + "/bar-stats temp"; interval: -1; click: bar.b + "/bar-tui htop" }
            Mod { cmd: "exec " + bar.b + "/bar-stats mem"; interval: -1; color: Theme.brume2; click: bar.b + "/bar-tui htop" }
            Mod {
                cmd: "exec " + bar.b + "/bar-stats disk"; interval: -1
                click: bar.b + "/bar-tui sh -c 'df -h; echo; du -xh --max-depth=1 ~ 2>/dev/null | sort -h | tail -15; read _'"
            }
        }

        // Système: micro, sortie audio, clavier, écrans, Bluetooth, réseau, notifications
        Row {
            // Micro: clic = couper/activer, molette = volume, clic droit ou milieu = mixeur (onglet entrées)
            Native {
                readonly property var audio: bar.source?.audio ?? null
                text: audio ? (audio.muted ? "" : "") : ""
                color: audio?.muted ? Theme.cendre : Theme.brume
                tip: audio ? (audio.muted ? "Micro coupé" : "Micro actif: " + Math.round(audio.volume * 100) + "%") : ""
                hover.onLeftClicked: audio.muted = !audio.muted
                hover.onWheelUp: audio.volume = Math.min(1, audio.volume + 0.05)
                hover.onWheelDown: audio.volume = Math.max(0, audio.volume - 0.05)
                hover.rclick: bar.b + "/bar-tui wiremix --tab input"
                hover.mclick: bar.b + "/bar-tui wiremix --tab input"
            }
            // Sortie audio: clic = muet, molette = volume, clic droit = mixeur (wiremix), clic milieu = sound-tune
            Native {
                readonly property var audio: bar.sink?.audio ?? null
                readonly property int vol: audio ? Math.round(audio.volume * 100) : 0
                text: !audio ? "" : audio.muted ? " muet" : (vol < 34 ? "" : vol < 67 ? "" : "") + " " + vol + "%"
                color: audio?.muted ? Theme.ardoise : Theme.brume
                tip: bar.sink ? (bar.sink.description || bar.sink.name) : ""
                hover.onLeftClicked: audio.muted = !audio.muted
                hover.onWheelUp: audio.volume = Math.min(1, audio.volume + 0.05)
                hover.onWheelDown: audio.volume = Math.max(0, audio.volume - 0.05)
                hover.rclick: bar.b + "/bar-tui wiremix --tab output"
                hover.mclick: bar.b + "/bar-tui sound-tune"
            }
            // Disposition clavier (bépo / qwerty australien): clic = bascule
            Native {
                readonly property string name: Niri.layouts[Niri.layout] ?? ""
                readonly property string short: {
                    const m = name.match(/\((Australian|US|UK)/);
                    if (m)
                        return { Australian: "au", US: "us", UK: "gb" }[m[1]];
                    return name.slice(0, 2).toLowerCase();
                }
                text: name ? " " + short : ""
                tip: "Clavier: " + name + " (clic: changer)"
                hover.onLeftClicked: Niri.action("switch-layout", "next")
            }
            // Écrans: clic = wdisplays
            Native {
                text: ""
                tip: "Écrans (clic: wdisplays)"
                hover.click: bar.b + "/focus-or-run wdisplays wdisplays"
            }
            // Bluetooth (masqué sans adaptateur): clic = bluetui (appairage, connexion, oubli)
            Native {
                readonly property var adapter: Bluetooth.defaultAdapter
                readonly property var connected: adapter ? adapter.devices.values.filter(d => d.connected) : []
                text: {
                    if (!adapter)
                        return "";
                    if (!adapter.enabled)
                        return " off";
                    const d = connected[0];
                    if (!d)
                        return " on";
                    return " " + d.name + (d.batteryAvailable ? " " + Math.round(d.battery * 100) + "%" : "");
                }
                tip: adapter ? adapter.name + "\n" + connected.length + " connecté(s)" + (connected.length ? "\n\n" + connected.map(d => d.name).join("\n") : "") : ""
                hover.click: bar.b + "/bar-tui bluetui"
            }
            // Wi-Fi: clic = impala (SSID, connexion), clic droit = menu réseau (IP, ping, débit)
            Mod {
                cmd: "exec " + bar.b + "/bar-stats net"; interval: -1; hideEmpty: false
                colors: ({ disconnected: Theme.cendre })
                click: bar.b + "/bar-tui impala"
                rclick: "setsid -f " + bar.b + "/menu network"
            }
            // Notifications: clic = historique, clic droit = Ne pas déranger
            Native {
                text: Notifs.dnd ? "" : ""
                color: Notifs.dnd ? Theme.sable : Theme.ardoise
                tip: Notifs.dnd ? "Ne pas déranger (clic: historique, clic droit: réactiver)" : "Notifications actives (clic: historique, clic droit: les couper)"
                hover.onLeftClicked: Notifs.toggleHistory()
                hover.onRightClicked: Notifs.dnd = !Notifs.dnd
            }
        }

        // Batterie: clic = menu système (verrouiller, veille, quitter...)
        Battery {
            hover.click: "setsid -f " + bar.b + "/menu system"
        }

        // Invisible: surveille SSH entrant, mode avion, VPN, veilleuse, sauvegarde, agenda et batterie faible
        // (bar-stats watch) et réveille par `signal` le module dont l'état a changé
        Mod { cmd: "exec " + bar.b + "/bar-stats watch"; interval: -1 }
    }
}
