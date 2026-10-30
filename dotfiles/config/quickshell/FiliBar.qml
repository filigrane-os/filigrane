// fili-bar: barre du haut, une par écran: mêmes modules et interactions que l'ancienne Waybar (inspirée de la barre Omarchy
// Quattro). Clic: action principale; clic droit/milieu/molette: voir chaque module. Les TUI s'ouvrent via bar-tui.
// Scripts réutilisés (BarScript.qml); natifs: niri, horloge, audio (PipeWire), MPRIS, Bluetooth, tray, batterie.
// Survol: fili-tooltip (fiche inspirée des panneaux d'Omarchy: état détaillé + rappel des clics); réseau, alimentation
// et écran lus au survol seulement (FiliInfo).
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

    // Filet fin sous la barre
    Rectangle {
        z: -1
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1
        color: FiliTheme.nuit3
    }

    // ───────── Gauche: logo, espaces de travail, fenêtre ─────────
    RowLayout {
        id: leftRow
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        spacing: 0

        // Logo Filigrane (brand/, lié dans ~/.local/share/filigrane par bootstrap.sh): ouvre le menu, clic milieu: À propos
        Item {
            Layout.leftMargin: 10
            implicitWidth: 44
            implicitHeight: FiliTheme.barHeight
            Image {
                anchors.centerIn: parent
                source: "file://" + Quickshell.env("HOME") + "/.local/share/filigrane/filigrane-" + (FiliTheme.light ? "couleur" : "sombre") + ".svg"
                sourceSize.width: 44
                fillMode: Image.PreserveAspectFit
            }
            BarHover {
                objectName: "logo"
                anchors.fill: parent
                tip: ({ title: "Filigrane", hint: FiliI18n.tr("click: menu · right click: terminal · middle click: about") })
                click: "setsid -f " + bar.b + "/menu"
                rclick: "setsid -f foot"
                onMiddleClicked: FiliAbout.show()
            }
        }

        // Clic = aller au workspace, molette = précédent/suivant (sans boucler)
        Row {
            Layout.fillHeight: true
            Repeater {
                model: Niri.workspaces.filter(w => w.output === bar.screen.name)
                Rectangle {
                    required property var modelData
                    implicitWidth: ws.implicitWidth + 2 * FiliTheme.pad
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
                                title: FiliI18n.tr("Workspace %1", parent.modelData.idx),
                                rows: wins.length ? wins.map(w => [w.app_id ?? "", w.title ?? ""]) : [["", FiliI18n.tr("no window")]],
                                hint: FiliI18n.tr("click: go there · wheel: previous / next")
                            };
                        }
                        onLeftClicked: Niri.action("focus-workspace", String(parent.modelData.idx))
                        onWheelUp: Niri.action("focus-workspace-up")
                        onWheelDown: Niri.action("focus-workspace-down")
                    }
                }
            }
        }

        // Clic milieu ou droit = fermer la fenêtre. Titre tronqué (…) avant d'atteindre le premier module de droite:
        // largeur max = place libre entre la fin des espaces de travail et rightRow, moins l'écart entre deux textes
        BarItem {
            id: windowItem
            objectName: "window"
            maxWidth: Math.min(420, Math.max(0, rightRow.x - leftRow.x - windowItem.x - 2 * FiliTheme.pad))
            text: Niri.focused?.title ?? ""
            color: FiliTheme.brume2
            tip: Niri.focused ? { title: Niri.focused.app_id, text: Niri.focused.title, hint: FiliI18n.tr("right or middle click: close the window") } : ""
            hover.onRightClicked: Niri.action("close-window")
            hover.onMiddleClicked: Niri.action("close-window")
        }
    }

    // ───────── Droite: indicateurs, tiroir, média, ressources, système, date, batterie ─────────
    RowLayout {
        id: rightRow
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom; rightMargin: 6 }
        spacing: 0

        // Indicateurs et bascules: mails, WhatsApp, agenda, enregistrement, SSH, avion, VPN, veille, MAJ
        Row {
            // Nouveaux mails Proton / événement Proton Calendar imminent (masqués sinon, voir BarState), clic = ouvrir et effacer
            BarScript { objectName: "mail"; value: BarState.mail; color: FiliTheme.voile; click: bar.b + "/bar-alert open mail" }
            BarScript { objectName: "whatsapp"; value: BarState.whatsapp; click: bar.b + "/bar-alert open whatsapp" }
            BarScript { objectName: "cal"; value: BarState.cal; color: FiliTheme.sable; click: bar.b + "/bar-alert open cal" }
            // Enregistrement d'écran: visible seulement en cours, clic = arrêter (démarrage: menu › Capture)
            BarScript { objectName: "rec"; title: FiliI18n.tr("Recording"); cmd: bar.b + "/bar-status rec"; signal: 11; color: FiliTheme.cendre; click: bar.b + "/bar-toggle rec" }
            // Session SSH entrante, mode avion (clic = désactiver), VPN: écrits par bar-stats quand l'état change
            BarScript { objectName: "remote"; title: "SSH"; stat: "remote"; color: FiliTheme.cendre }
            BarScript { objectName: "air"; title: FiliI18n.tr("Airplane mode"); stat: "air"; color: FiliTheme.sable; click: bar.b + "/bar-toggle air" }
            BarScript { objectName: "vpn"; title: "VPN"; stat: "vpn" }
            // Rapports de veille non lus, clic = les lire
            BarScript { objectName: "news"; title: FiliI18n.tr("News"); cmd: bar.b + "/bar-news"; interval: 3600; signal: 15; color: FiliTheme.brume2; click: bar.b + "/bar-news open" }
            // Mises à jour xbps (masqué s'il n'y en a pas), clic = mettre à jour dans un terminal flottant
            BarScript { objectName: "update"; title: FiliI18n.tr("Updates"); cmd: bar.b + "/bar-update"; interval: 3600; signal: 16; color: FiliTheme.sable; click: bar.b + "/bar-update run" }
        }

        // Tiroir (BarState, bar-tray toggle): replié, seuls les indicateurs en cours d'usage restent visibles; clic sur le chevron = tout afficher
        Row {
            Repeater {
                model: SystemTray.items
                Item {
                    id: trayItem
                    required property var modelData
                    implicitWidth: FiliTheme.iconCell
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
            // Mail, WhatsApp, agenda au repos: rangés dans le tiroir (visibles tiroir ouvert), ils sortent dans la barre quand il y a une alerte
            BarScript { objectName: "mail-idle"; value: BarState.mailIdle; color: FiliTheme.ardoise; click: bar.b + "/bar-alert open mail" }
            BarScript { objectName: "whatsapp-idle"; value: BarState.whatsappIdle; color: FiliTheme.ardoise; click: bar.b + "/bar-alert open whatsapp" }
            BarScript { objectName: "cal-idle"; value: BarState.calIdle; color: FiliTheme.ardoise; click: bar.b + "/bar-alert open cal" }
            // Sauvegarde restic: gris au repos, clignotant en cours, rouge en échec; clic = sauvegarder maintenant
            BarScript {
                objectName: "backup"
                title: FiliI18n.tr("Backup")
                value: BarState.backup
                colors: ({ idle: FiliTheme.ardoise, active: FiliTheme.brume, failed: FiliTheme.cendre }); blinkClass: "active"
                click: bar.b + "/bar-backup run"
            }
            // Chevron du tiroir: clic = afficher / replier
            BarScript { objectName: "tray-handle"; value: BarState.trayHandle; hideEmpty: false; colors: ({ "": FiliTheme.ardoise, open: FiliTheme.brume2 }); click: bar.b + "/bar-tray toggle" }
        }

        // Clic = lecture/pause, clic droit = fenêtre du lecteur, clic milieu = suivant, molette haut/bas = précédent/suivant
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
                rows: [[FiliI18n.tr("Title"), player.trackTitle], [FiliI18n.tr("Artist"), player.trackArtist], [FiliI18n.tr("Album"), player.trackAlbum],
                       [FiliI18n.tr("State"), player.isPlaying ? FiliI18n.tr("playing") : FiliI18n.tr("paused")],
                       [FiliI18n.tr("Position"), player.lengthSupported && player.length > 0 ? mmss(player.position) + " / " + mmss(player.length) : ""]].filter(r => r[1]),
                hint: FiliI18n.tr("click: play/pause · right click: player window · middle click: next · wheel: previous / next")
            }
            hover.onLeftClicked: player.togglePlaying()
            hover.onMiddleClicked: player.next()
            hover.onRightClicked: {
                const id = player ? Niri.playerWindow(Niri.windows, player.dbusName, player.desktopEntry, player.trackTitle) : null;
                if (id !== null)
                    Niri.action("focus-window", "--id", String(id));
            }
            hover.onWheelUp: player.previous()
            hover.onWheelDown: player.next()
        }

        // Ressources: CPU et mémoire (top 5 en infobulle); température (dès 50 °C) et disque (dès 90 %) seulement quand ils
        // sont très hauts (bar-stats les vide sinon); clic = moniteur
        Row {
            BarScript { objectName: "cpu"; tag: "CPU"; stat: "cpu"; color: FiliTheme.brume2; hover.onLeftClicked: FiliPanel.toggle(hover, "monitor", bar); hint: FiliI18n.tr("click: monitor")
                Component.onCompleted: FiliPanel.register("monitor", hover, bar) }
            BarScript { objectName: "temp"; stat: "temp"; colors: ({ "": FiliTheme.sable, critical: FiliTheme.cendre }); hover.onLeftClicked: FiliPanel.toggle(hover, "monitor", bar); hint: FiliI18n.tr("click: monitor") }
            BarScript { objectName: "mem"; tag: "RAM"; stat: "mem"; color: FiliTheme.brume2; hover.onLeftClicked: FiliPanel.toggle(hover, "monitor", bar); hint: FiliI18n.tr("click: monitor") }
            BarScript {
                objectName: "disk"
                stat: "disk"; hint: FiliI18n.tr("click: monitor")
                colors: ({ "": FiliTheme.sable, critical: FiliTheme.cendre })
                hover.onLeftClicked: FiliPanel.toggle(hover, "monitor", bar)
            }
        }

        // Système: sortie audio, clavier, écrans, Bluetooth, réseau, notifications
        Row {
            // Agent IA (fili-ai-session, état lu par BarState): sable et clignotant quand une session attend une réponse,
            // DONE quand elle a fini sans être regardée; clic = la session qui attend, sinon la dernière (encore: la
            // suivante), aucune: fili-ai comme Mod+Y; clic milieu = nouvelle session, clic droit = choisir l'agent
            BarScript {
                objectName: "ai"
                value: BarState.ai
                colors: ({ off: FiliTheme.ardoise, idle: FiliTheme.brume2, working: FiliTheme.brume, waiting: FiliTheme.sable, done: FiliTheme.voile })
                blinkClass: "waiting"
                click: bar.b + "/fili-ai-session focus"
                mclick: bar.b + "/fili-ai-session new"
                rclick: bar.b + "/fili-ai pick"
            }
            // Sortie audio: clic = muet, molette = volume, clic droit = mixeur (wiremix), clic milieu = sound-tune
            BarItem {
                objectName: "volume"
                readonly property var audio: bar.sink?.audio ?? null
                readonly property int vol: audio ? Math.round(audio.volume * 100) : 0
                readonly property string kind: FiliTheme.sinkGlyph(bar.sink?.properties)
                text: !audio ? "" : (kind || (audio.muted ? "" : vol < 34 ? "" : vol < 67 ? "" : ""))
                    + (audio.muted ? " " + FiliI18n.tr("muted") : " " + vol + "%")
                color: audio?.muted ? FiliTheme.ardoise : FiliTheme.brume
                tip: !audio ? "" : {
                    title: audio.muted ? FiliI18n.tr("Sound muted") : FiliI18n.tr("Sound"),
                    rows: [[FiliI18n.tr("Output"), bar.sink.description || bar.sink.nickname || bar.sink.name], [FiliI18n.tr("Volume"), vol + " %"],
                           [FiliI18n.tr("Input"), bar.source ? (bar.source.description || bar.source.name) : ""]].filter(r => r[1]),
                    hint: FiliI18n.tr("click: sound panel · middle click: mute · wheel: volume · right click: mixer")
                }
                hover.onLeftClicked: FiliPanel.toggle(hover, "audio", bar)
                Component.onCompleted: FiliPanel.register("audio", hover, bar)
                hover.onMiddleClicked: audio.muted = !audio.muted
                hover.onWheelUp: audio.volume = Math.min(1, audio.volume + 0.03)
                hover.onWheelDown: audio.volume = Math.max(0, audio.volume - 0.03)
                hover.rclick: bar.b + "/bar-tui wiremix --tab output"
            }
            // Disposition clavier (bépo / qwerty australien): clic = panneau, clic milieu = disposition suivante
            BarItem {
                objectName: "keyboard"
                readonly property string name: Niri.layouts[Niri.layout] ?? ""
                text: name ? " " + Niri.shortName(name) : ""
                tip: ({
                    title: FiliI18n.tr("Keyboard"),
                    rows: Niri.layouts.map((l, i) => [i === Niri.layout ? "●" : "", l]),
                    hint: FiliI18n.tr("click: keyboard panel · middle click: next layout")
                })
                hover.onLeftClicked: FiliPanel.toggle(hover, "keyboard", bar)
                Component.onCompleted: FiliPanel.register("keyboard", hover, bar)
                hover.onMiddleClicked: Niri.action("switch-layout", "next")
            }
            // Écrans: clic = panneau (disposition, définition, échelle, rotation), molette = luminosité
            BarScript {
                objectName: "display"
                stat: "display"; hideEmpty: false
                tipInfo: "display"
                hover.onLeftClicked: FiliPanel.toggle(hover, "display", bar)
                Component.onCompleted: FiliPanel.register("display", hover, bar)
                scrollUp: "brightnessctl -q set 3%+; " + bar.b + "/fili-shell bar refresh 23"
                scrollDown: "brightnessctl -q set 3%-; " + bar.b + "/fili-shell bar refresh 23"
            }
            // Bluetooth (toujours visible, grisé sans adaptateur): clic = panneau (activer, appairer, connecter, oublier)
            BarItem {
                objectName: "bluetooth"
                id: btItem
                readonly property var adapter: Bluetooth.defaultAdapter
                readonly property var connected: adapter ? adapter.devices.values.filter(d => d.connected) : []
                // Réception de fichiers active (fili-share, un des protocoles): SHARE quand aucun appareil n'est connecté
                property bool sharing: false
                Process {
                    id: shareProc
                    command: [bar.b + "/fili-share", "receive", "any", "status"]
                    stdout: SplitParser { onRead: line => btItem.sharing = line.trim() === "on" }
                }
                Connections {
                    target: FiliShell
                    function onRefresh(n) {
                        if (n === 24 && !shareProc.running)
                            shareProc.running = true;
                    }
                }
                Component.onCompleted: {
                    shareProc.running = true;
                    FiliPanel.register("bluetooth", hover, bar);
                }
                text: {
                    if (!adapter)
                        return "";
                    if (!adapter.enabled)
                        return " OFF";
                    // Appareils connectés: leur nombre (noms et batteries dans la fiche); aucun et réception active: SHARE
                    if (connected.length === 0 && sharing)
                        return " SHARE";
                    return " " + connected.length;
                }
                color: !adapter ? FiliTheme.ardoise : FiliTheme.brume
                tip: !adapter ? { title: "Bluetooth", rows: [[FiliI18n.tr("State"), FiliI18n.tr("no adapter found")]], hint: FiliI18n.tr("click: Bluetooth panel") } : {
                    title: "Bluetooth",
                    rows: [[adapter.name, adapter.enabled ? FiliI18n.tr("on") : FiliI18n.tr("off")]].concat(
                        adapter.devices.values.filter(d => d.paired || d.connected).map(d => [d.name,
                            (d.connected ? FiliI18n.tr("connected") : FiliI18n.tr("paired")) + (d.connected && d.batteryAvailable ? ", " + Math.round(d.battery * 100) + " %" : "")])),
                    hint: FiliI18n.tr("click: Bluetooth panel (pair, connect, forget)")
                }
                hover.onLeftClicked: FiliPanel.toggle(hover, "bluetooth", bar)
            }
            // Wi-Fi: clic = impala (SSID, connexion), clic droit = menu réseau (IP, ping, débit)
            BarScript {
                objectName: "network"
                stat: "net"; hideEmpty: false
                colors: ({ disconnected: FiliTheme.cendre })
                hover.onLeftClicked: FiliPanel.toggle(hover, "network", bar)
                Component.onCompleted: FiliPanel.register("network", hover, bar)
                rclick: "setsid -f " + bar.b + "/menu network"
                tipInfo: "network"
            }
            // Notifications: clic = historique, clic droit = Ne pas déranger
            BarItem {
                objectName: "notifications"
                text: FiliNotification.dnd ? " MUTE" : (FiliNotification.history.length + FiliNotification.popups.length > 0 ? "" : "") + " " + (FiliNotification.history.length + FiliNotification.popups.length)
                color: FiliNotification.dnd ? FiliTheme.sable : FiliTheme.brume
                tip: ({
                    title: FiliNotification.dnd ? FiliI18n.tr("Do not disturb") : FiliI18n.tr("Notifications"),
                    rows: [[FiliI18n.tr("Pop-ups"), FiliNotification.dnd ? FiliI18n.tr("hidden") : FiliI18n.tr("shown")], [FiliI18n.tr("History"), FiliI18n.tr("%1 notification(s)", FiliNotification.history.length)]],
                    hint: FiliI18n.tr("click: fili-notification-center · right click: do not disturb")
                })
                hover.onLeftClicked: FiliNotification.toggleCenter()
                Component.onCompleted: FiliPanel.register("center", hover, bar)
                hover.onRightClicked: FiliNotification.dnd = !FiliNotification.dnd
            }
        }

        // Survol = fiche (date, fuseau, prochains événements), clic (gauche ou droit) = calendrier épinglé comme panneau (molette: mois précédent/suivant, clic milieu: mois courant)
        Item {
            id: clockItem
            implicitWidth: clockText.implicitWidth + (clockIcon.visible ? clockIcon.implicitWidth + FiliTheme.labelGap : 0) + 2 * FiliTheme.pad
            implicitHeight: FiliTheme.barHeight
            SystemClock { id: clock; precision: SystemClock.Minutes }
            // Minuteur ou chronomètre en cours (bar-timer, état lu par BarState): remplace la date
            readonly property var timerState: BarState.timer
            readonly property bool timing: timerState["class"] !== "idle"
            // Fiche du survol: date, heure, fuseau, semaine puis prochains événements de l'agenda (BarState.agenda)
            readonly property var card: {
                const d = clock.date;
                const off = -d.getTimezoneOffset();
                const hm = n => String(n).padStart(2, "0");
                const utc = "UTC" + (off < 0 ? "−" : "+") + hm(Math.floor(Math.abs(off) / 60)) + ":" + hm(Math.abs(off) % 60);
                const day = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()) - new Date(d.getFullYear(), 0, 0)) / 864e5);
                // Semaine ISO: celle du jeudi de la semaine
                const thu = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 3 - (d.getDay() + 6) % 7);
                const week = Math.floor((thu - new Date(thu.getFullYear(), 0, 1)) / 864e5 / 7) + 1;
                const rows = [
                    [FiliI18n.tr("Local time"), FiliI18n.locale.toString(d, "HH:mm")],
                    [FiliI18n.tr("Time zone"), Qt.formatDateTime(d, "tttt") + " (" + Qt.formatDateTime(d, "t") + ", " + utc + ")"],
                    [FiliI18n.tr("Week"), FiliI18n.tr("%1 · day %2 of the year", week, day)]
                ];
                if (timing)
                    rows.push([FiliI18n.tr("Timer"), timerState.text.trim()]);
                const today = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
                const ev = BarState.agenda;
                if (ev === null)
                    return { title: FiliI18n.locale.toString(d, "dddd d MMMM yyyy"), rows: rows, hint: FiliI18n.tr("click: calendar") };
                if (ev.length === 0)
                    rows.push([FiliI18n.tr("Agenda"), FiliI18n.tr("no upcoming event")]);
                for (const e of ev) {
                    const s = new Date(e.start * 1000);
                    const n = Math.round((new Date(s.getFullYear(), s.getMonth(), s.getDate()).getTime() - today) / 864e5);
                    const when = n === 0 ? FiliI18n.tr("Today") : n === 1 ? FiliI18n.tr("Tomorrow") : FiliI18n.locale.toString(s, "ddd d MMM");
                    rows.push([when + " " + FiliI18n.locale.toString(s, "HH:mm"), e.title + (e.place ? "  ·  " + e.place : "")]);
                }
                return { title: FiliI18n.locale.toString(d, "dddd d MMMM yyyy"), rows: rows, hint: FiliI18n.tr("click: calendar") };
            }
            onCardChanged: if (clockMouse.containsMouse) FiliTooltip.update(clockMouse, card)
            // Icône agenda devant la date, comme les autres modules (le minuteur porte la sienne)
            Label {
                id: clockIcon
                visible: !clockItem.timing
                anchors { verticalCenter: parent.verticalCenter; right: clockText.left; rightMargin: FiliTheme.labelGap }
                text: String.fromCodePoint(0xf073)
                color: FiliTheme.ardoise
            }
            Label {
                id: clockText
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: clockIcon.visible ? (clockIcon.implicitWidth + FiliTheme.labelGap) / 2 : 0
                text: clockItem.timing ? clockItem.timerState.text : FiliI18n.locale.toString(clock.date, "ddd dd MMM  HH:mm")
                color: !clockItem.timing ? FiliTheme.brume : clockItem.timerState["class"] === "done" ? FiliTheme.cendre : FiliTheme.sable
                // Chiffres de largeur fixe: l'horloge ne bouge pas à chaque seconde
                font.family: clockItem.timing ? FiliTheme.mono : FiliTheme.font
                font.weight: Font.Normal
            }
            MouseArea {
                id: clockMouse
                objectName: "clock"
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                onContainsMouseChanged: if (containsMouse) FiliTooltip.show(this, clockItem.card); else FiliTooltip.hide(this)
                onClicked: m => press(m.button)
                // Clic (appelé aussi par les tests)
                function press(button) {
                    FiliTooltip.hide();
                    if (button === Qt.MiddleButton) {
                        cal.shift = 0;
                    } else {
                        cal.pinned = !cal.pinned;
                        if (cal.pinned) {
                            cal.shift = 0;
                            cal.show();
                        } else {
                            cal.visible = false;
                        }
                    }
                }
                onWheel: w => cal.shift += w.angleDelta.y > 0 ? -1 : 1
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

        // Batterie: clic = menu système (verrouiller, veille, quitter...)
        BarPower {
            objectName: "power"
            tipInfo: "power"
            hover.onLeftClicked: FiliPanel.toggle(hover, "power", bar)
                Component.onCompleted: FiliPanel.register("power", hover, bar)
            hover.rclick: "setsid -f " + bar.b + "/menu system"
        }
    }
}
