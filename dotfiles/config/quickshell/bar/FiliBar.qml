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
import Quickshell.Services.Pipewire
import Quickshell.Bluetooth
import qs
import qs.bar.modules.appmenu
import qs.bar.modules.logo
import qs.bar.modules.media
import qs.bar.modules.notifications
import qs.bar.modules.status
import qs.bar.modules.tray
import qs.bar.modules.workspaces

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

    // ───────── Left: logo, workspaces, application menu ─────────
    RowLayout {
        id: leftRow
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        spacing: 0

        LogoModule { bar: bar; Layout.leftMargin: 10 }
        WorkspacesModule { bar: bar; Layout.fillHeight: true }

        // Menu of the active application (AppMenu): AT-SPI menu bar or fallback menu; replaces the window title.
        // Folded to the application name alone when the menus do not fit before the first right-hand module
        AppmenuModule {
            id: appMenu
            objectName: "appmenu"
            bar: bar
            maxWidth: Math.max(0, rightRow.x - leftRow.x - appMenu.x - FiliTheme.space3)
        }
    }

    // ───────── Right: indicators, drawer, media, resources, system, date, battery ─────────
    RowLayout {
        id: rightRow
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom; rightMargin: 6 }
        spacing: 0

        // Personal alerts: new Proton mails / imminent Proton Calendar event (hidden otherwise, see BarState), click = open and clear
        BarScript { objectName: "mail"; value: BarState.mail; color: FiliTheme.voile; click: bar.b + "/bar-alert open mail" }
        BarScript { objectName: "whatsapp"; value: BarState.whatsapp; click: bar.b + "/bar-alert open whatsapp" }
        BarScript { objectName: "cal"; value: BarState.cal; color: FiliTheme.sable; click: bar.b + "/bar-alert open cal" }
        StatusModule { bar: bar }

        TrayModule { bar: bar }

        MediaModule { bar: bar }

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
            // Agent IA (chat FiliChat et sessions des terminaux, fili-ai-session; état lu par BarState): sable et
            // clignotant quand l'agent attend une réponse (ASK), DONE quand il a fini sans être regardé; clic =
            // ouvre le panneau de l'agent (sessions, actions), Mod+clic ou clic milieu = ce qui attend (le chat, sinon la
            // session de terminal qui attend, sinon la dernière, encore: la suivante; aucune: fili-ai), clic droit = choisir l'agent
            BarScript {
                objectName: "ai"
                value: BarState.ai
                colors: ({ off: FiliTheme.ardoise, idle: FiliTheme.brume2, working: FiliTheme.brume, waiting: FiliTheme.sable, done: FiliTheme.voile })
                blinkClass: "waiting"
                rclick: bar.b + "/fili-ai pick"
                hover.onLeftClicked: hover.meta ? BarState.aiAsk() : FiliPanel.toggle(hover, "agent", bar)
                hover.onMiddleClicked: BarState.aiAsk()
                Component.onCompleted: FiliPanel.register("agent", hover, bar)
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
        }

        NotificationsModule { bar: bar }

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
            BarLabel {
                id: clockIcon
                visible: !clockItem.timing
                anchors { verticalCenter: parent.verticalCenter; right: clockText.left; rightMargin: FiliTheme.labelGap }
                text: String.fromCodePoint(0xf073)
                color: FiliTheme.ardoise
            }
            BarLabel {
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
