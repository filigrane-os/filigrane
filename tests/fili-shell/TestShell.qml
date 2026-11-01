// Tests du fili-shell, chargés à la place de shell.qml par tests/fili-shell/run.sh (FILI_TEST=1: fenêtres masquées,
// commandes des clics enregistrées dans FiliTheme.ran au lieu d'être lancées). Sortie TAP: "ok N - ..." /
// "not ok N - ...", puis "# fin: X échec(s)".
// Couvre: clics de chaque module de la fili-bar, canal fili-shell (bar refresh, notification, launcher),
// fili-launcher (découpe des lignes, filtre, réponses), fili-notification (bulles, croix, historique),
// fili-tooltip, FiliInfo et fili-about.
//@ pragma Env QT_QUICK_BACKEND=software
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: t
    property int count: 0
    property int failures: 0
    property var steps: []
    property int stepIndex: 0
    property var waitFor: null
    property real waitUntil: 0
    property var refreshed: []
    readonly property var bar: bars.instances[0] ?? null
    readonly property string bin: FiliTheme.bin

    function ok(cond, name, detail) {
        count++;
        if (cond)
            console.log("ok " + count + " - " + name);
        else {
            failures++;
            console.log("not ok " + count + " - " + name + (detail !== undefined ? " # " + detail : ""));
        }
    }
    function find(item, name) {
        if (!item)
            return null;
        if (item.objectName === name)
            return item;
        for (const c of item.children ?? []) {
            const r = find(c, name);
            if (r)
                return r;
        }
        return null;
    }
    // Commandes lancées par un clic (bouton) ou la molette (up/down) sur un module de la fili-bar
    function act(name, how) {
        FiliTheme.ran = [];
        const it = find(bar.contentItem, name);
        if (!it)
            return null;
        const h = it.hover ?? it;
        if (how === "up" || how === "down")
            h.roll(how === "up");
        else
            h.press(how);
        return FiliTheme.ran.join("\n");
    }
    function expectClick(name, how, needle) {
        const r = act(name, how);
        const label = { [Qt.LeftButton]: "clic", [Qt.RightButton]: "clic droit", [Qt.MiddleButton]: "clic milieu", up: "molette haut", down: "molette bas" }[how];
        ok(r !== null && r.indexOf(needle) >= 0, "fili-bar " + name + ", " + label + " -> " + needle, r === null ? "module introuvable" : JSON.stringify(r));
    }

    // Commande shell de test (client fili-shell, fili-net...), sortie et code récupérés
    property var shellOut: null
    Process {
        id: sh
        property string out: ""
        stdout: StdioCollector { onStreamFinished: sh.out = text }
        onExited: code => t.shellOut = { code: code, out: sh.out }
    }
    function shell(cmd) {
        shellOut = null;
        sh.out = "";
        sh.command = ["sh", "-c", cmd];
        sh.running = true;
    }

    Variants {
        id: bars
        model: [Quickshell.screens[0]]
        FiliBar {}
    }
    property var cards: ({})
    // Catalogue français du fili-shell (test de FiliI18n)
    property var frCatalog: ({})
    FileView {
        path: Quickshell.shellDir + "/i18n/fr.json"
        blockLoading: true
        onLoaded: t.frCatalog = JSON.parse(text())
    }
    Connections {
        target: FiliInfo
        function onReady(topic, card) {
            t.cards[topic] = card;
        }
    }
    Connections {
        target: FiliShell
        function onRefresh(n) {
            t.refreshed = t.refreshed.concat([n]);
        }
    }

    // Étapes: fonction synchrone, ou { run, until, timeout } qui attend une condition
    function wait(run, until, timeout) {
        return { run: run, until: until, timeout: timeout ?? 5000 };
    }
    Timer {
        id: tick
        interval: 50
        repeat: true
        onTriggered: t.advance()
    }
    function advance() {
        if (waitFor) {
            if (!waitFor.until() && Date.now() < waitUntil)
                return;
            if (!waitFor.until())
                ok(false, "attente: " + (waitFor.name ?? "condition"), "délai dépassé");
            if (waitFor.after)
                waitFor.after();
            waitFor = null;
        }
        while (stepIndex < steps.length) {
            const s = steps[stepIndex++];
            if (typeof s === "function") {
                try {
                    s();
                } catch (e) {
                    ok(false, "exception", e + " " + (e.stack ?? ""));
                }
            } else {
                s.run();
                waitFor = s;
                waitUntil = Date.now() + s.timeout;
                return;
            }
        }
        tick.stop();
        console.log("# fin: " + failures + " échec(s) sur " + count);
        Qt.callLater(() => Qt.exit(failures ? 1 : 0));
    }

    Component.onCompleted: {
        FiliNotification.dnd;
        FiliLauncher.open;
        FiliShell.fifo;
        const L = Qt.LeftButton, R = Qt.RightButton, M = Qt.MiddleButton;
        steps = [
            wait(() => {}, () => t.bar && t.find(t.bar.contentItem, "network") !== null, 5000),
            // ───── fili-bar: un clic par module ─────
            () => {
                expectClick("logo", L, "/menu");
                expectClick("logo", R, "foot");
                expectClick("mail", L, "bar-alert open mail");
                expectClick("whatsapp", L, "bar-alert open whatsapp");
                expectClick("cal", L, "bar-alert open cal");
                expectClick("rec", L, "bar-toggle rec");
                expectClick("air", L, "bar-toggle air");
                expectClick("news", L, "bar-news open");
                expectClick("update", L, "bar-update run");
                expectClick("backup", L, "bar-backup run");
                expectClick("tray-handle", L, "bar-tray toggle");
                // Horloge: le clic épingle le calendrier, il n'ouvre plus Proton Calendar
                const clk = act("clock", L);
                ok(clk === "", "fili-bar clock, clic -> aucune commande (calendrier épinglé)", JSON.stringify(clk));
                act("clock", L);
                const card = t.find(t.bar.contentItem, "clock").parent.card;
                ok(card.title && card.rows.length >= 3 && card.rows.every(r => r[0] && r[1]), "horloge: fiche (date, heure, fuseau, semaine)", JSON.stringify(card));
                // Ressources, son, Bluetooth, réseau, batterie: clic = fili-panel (vue ouverte, puis fermée)
                for (const [name, view] of [["cpu", "monitor"], ["temp", "monitor"], ["mem", "monitor"], ["disk", "monitor"],
                                            ["volume", "audio"], ["keyboard", "keyboard"], ["display", "display"], ["bluetooth", "bluetooth"], ["network", "network"], ["power", "power"]]) {
                    act(name, L);
                    ok(FiliPanel.view === view, "fili-bar " + name + ", clic -> fili-panel " + view, FiliPanel.view);
                    FiliPanel.close();
                }
                expectClick("volume", R, "wiremix --tab output");
                expectClick("keyboard", M, "switch-layout next");
                expectClick("display", "up", "brightnessctl -q set 3%+");
                expectClick("display", "down", "brightnessctl -q set 3%-");
                expectClick("network", R, "menu network");
                expectClick("power", R, "menu system");
                // Agent IA: clic = tiroir du chat, milieu = session de terminal qui attend (ou fili-ai), droit = choix de l'agent
                expectClick("ai", L, "fili-chat toggle");
                expectClick("ai", M, "fili-ai-session focus");
                expectClick("ai", R, "fili-ai pick");
                // Cloche: clic = fili-notification-center, clic droit = ne pas déranger (remis en l'état)
                const was = FiliNotification.dnd;
                act("notifications", L);
                ok(FiliNotification.centerOpen, "fili-bar notifications, clic -> fili-notification-center ouvert");
                act("notifications", L);
                act("notifications", R);
                ok(FiliNotification.dnd !== was, "fili-bar notifications, clic droit -> ne pas déranger");
                FiliNotification.dnd = was;
                FiliTheme.ran = [];
            },
            // Les commandes des clics existent (scripts du dépôt)
            wait(() => t.shell('for f in menu bar-alert bar-toggle bar-news bar-update bar-timer bar-backup bar-tray bar-tui webapp focus-or-run fili-shell bar-stats fili-ai fili-ai-session; do [ -x "' + t.bin + '/$f" ] || echo "$f"; done'),
                 () => t.shellOut !== null),
            () => ok(t.shellOut.out.trim() === "", "scripts appelés par la fili-bar présents dans " + t.bin, t.shellOut.out.trim()),
            // impala, bluetui, wiremix... installés
            wait(() => t.shell('for c in impala bluetui wiremix htop foot brightnessctl niri jq; do command -v $c >/dev/null || echo $c; done'),
                 () => t.shellOut !== null),
            () => ok(t.shellOut.out.trim() === "", "programmes lancés par la fili-bar installés", t.shellOut.out.trim()),

            // ───── canal fili-shell ─────
            wait(() => t.shell(t.bin + "/fili-shell bar refresh 20 21"), () => t.refreshed.indexOf(20) >= 0 && t.refreshed.indexOf(21) >= 0),
            () => ok(true, "fili-shell bar refresh 20 21 -> signaux reçus"),
            wait(() => t.shell(t.bin + "/fili-shell notification dnd on"), () => FiliNotification.dnd === true),
            () => ok(true, "fili-shell notification dnd on"),
            wait(() => t.shell(t.bin + "/fili-shell notification dnd off"), () => FiliNotification.dnd === false),
            () => ok(true, "fili-shell notification dnd off"),
            // bar-stats: lecteur du tuyau et modules écrits sans script (stat NOM JSON)
            wait(() => {}, () => FiliShell.stats.cpu !== undefined && FiliShell.stats.net !== undefined && FiliShell.stats.air !== undefined),
            () => {
                const cpu = t.find(t.bar.contentItem, "cpu");
                ok(cpu && /^\d+%$/.test(cpu.text), "bar-stats: module cpu rempli (stat cpu)", cpu ? cpu.text : "module introuvable");
                ok(t.find(t.bar.contentItem, "network").text !== "", "bar-stats: module réseau rempli (stat net)");
                // Niri: flux d'événements lu sur le socket de niri
                ok(Niri.workspaces.length > 0, "niri: espaces de travail reçus par le socket", Niri.workspaces.length);
                // Fenêtre d'un lecteur MPRIS (clic droit sur le média)
                const mw = { 1: { id: 1, pid: 50, app_id: "chrome", title: "Autre onglet" }, 2: { id: 2, pid: 50, app_id: "chrome", title: "Chanson - YouTube" }, 4: { id: 4, pid: 70, app_id: "chrome-mail.x__-Default", title: "Mail" }, 5: { id: 5, pid: 70, app_id: "google-chrome", title: "Page" }, 3: { id: 3, pid: 60, app_id: "Spotify", title: "Spotify" } };
                ok(Niri.playerWindow(mw, "org.mpris.MediaPlayer2.chromium.instance50", "", "Chanson") === 2, "niri: lecteur navigateur -> fenêtre du pid dont le titre contient la piste");
                ok(Niri.playerWindow(mw, "org.mpris.MediaPlayer2.chromium.instance50", "", "") === 1, "niri: lecteur navigateur sans piste -> première fenêtre du pid");
                ok(Niri.playerWindow(mw, "org.mpris.MediaPlayer2.chromium.instance70", "", "Vidéo en fond") === 5, "niri: piste dans un onglet de fond -> fenêtre du navigateur, pas la PWA");
                ok(Niri.playerWindow(mw, "org.mpris.MediaPlayer2.spotify", "spotify", "x") === 3, "niri: lecteur par entrée de bureau");
                ok(Niri.playerWindow(mw, "org.mpris.MediaPlayer2.mpv", "mpv", "x") === null, "niri: lecteur sans fenêtre -> null");
            },
            // AppMenu (menu global): repli par application (pid 0 = pas de requête AT-SPI), puis menus AT-SPI simulés
            () => {
                Niri.setWindows({ 7: { id: 7, pid: 0, app_id: "foot", title: "foot" } });
                Niri.focusedId = 7;
            },
            wait(() => {}, () => AppMenu.appId === "foot" && AppMenu.source === "fallback" && AppMenu.menus.length === 5),
            () => {
                const labels = AppMenu.menus.map(m => m.label);
                ok(labels.join(",") === "Terminal,Shell,Go,Help,Window", "appmenu: foot -> application, menus de repli, Fenêtre", labels.join(","));
                ok(AppMenu.menus[0].children[0].label === "Quit %1", "appmenu: menu de l'application -> Quitter");
                const title = t.find(t.bar.contentItem, "appmenu-1");
                const host = t.find(t.bar.contentItem, "appmenu");
                ok(title && host && host.visible && host.shown, "appmenu: titres des menus dans la fili-bar", host ? host.visible : "introuvable");
                AppMenu.openAt(1, title, t.bar);
                ok(AppMenu.open && AppMenu.levels.length === 1 && AppMenu.levels[0][0].label === "New terminal", "appmenu: clic sur un titre -> menu ouvert");
                ok(AppMenu.levels[0][0].keys === "Super+Return", "appmenu: raccourci d'une entrée de repli = bind niri de la même commande", AppMenu.levels[0][0].keys);
                ok(AppMenu.menus[0].children[0].keys === "Super+Q", "appmenu: Quitter -> raccourci de close-window", AppMenu.menus[0].children[0].keys);
                const pb = AppMenu.parseBinds('binds {\n    // Mod+X { nope; }\n    Mod+Ctrl+W hotkey-overlay-title="a" { spawn-sh "$HOME/.local/bin/bar-tui impala"; }\n    Mod+V       { toggle-window-floating; }\n    Mod+1 { focus-workspace 1; }\n    Mod+B { spawn "foot" "-e" "btop"; }\n}\nlayout { Mod+Z { x; } }\n');
                ok(pb["exec:bar-tui impala"] === "Super+Ctrl+W" && pb["niri:toggle-window-floating"] === "Super+V" && pb["niri:focus-workspace 1"] === "Super+1" && pb["exec:foot -e btop"] === "Super+B" && Object.keys(pb).length === 4, "appmenu: lecture des binds niri (spawn, spawn-sh, actions, arguments, commentaires)", JSON.stringify(pb));
                FiliTheme.ran = [];
                AppMenu.activate(AppMenu.levels[0][0]);
                ok(!AppMenu.open && FiliTheme.ran.join() === "foot", "appmenu: entrée -> commande lancée, menu fermé", FiliTheme.ran.join());
                AppMenu.openAt(4, title, t.bar);
                const win = AppMenu.levels[0];
                ok(win[0].label === "Close window" && win[1].kind === "sep", "appmenu: menu Fenêtre -> actions niri, séparateurs");
                FiliTheme.ran = [];
                AppMenu.activate(win[0]);
                ok(FiliTheme.ran.join() === "niri msg action close-window", "appmenu: action niri", FiliTheme.ran.join());
                // Clavier: fili-shell appmenu ouvre le premier menu au clavier, un second appel le ferme
                AppMenu.summon("toggle");
                ok(AppMenu.open && AppMenu.keyboard && AppMenu.openIndex === 0 && AppMenu.sel[0] === 0, "appmenu clavier: fili-shell appmenu -> premier menu, premier élément choisi", JSON.stringify(AppMenu.sel));
                AppMenu.summon("toggle");
                ok(!AppMenu.open && !AppMenu.keyboard, "appmenu clavier: second appel -> fermeture");
                // Autres applications: fichier de repli par app-id, sinon menus communs
                Niri.setWindows({ 8: { id: 8, pid: 0, app_id: "google-chrome", title: "Page" } });
                Niri.focusedId = 8;
            },
            wait(() => {}, () => AppMenu.appId === "google-chrome" && AppMenu.menus.length === 6),
            () => {
                ok(AppMenu.menus[0].label === "Chrome" && AppMenu.menus[1].children[0].exec === "google-chrome-stable --new-window", "appmenu: Chrome -> liens utiles", AppMenu.menus.map(m => m.label).join(","));
                Niri.setWindows({ 10: { id: 10, pid: 4242, app_id: "fili-file", title: "thomas" } });
                Niri.focusedId = 10;
            },
            wait(() => {}, () => AppMenu.appId === "fili-file" && AppMenu.menus.length === 6),
            () => {
                ok(AppMenu.source === "fallback" && AppMenu.noMenu["fili-file"] === undefined, "appmenu: un fichier de repli passe devant AT-SPI (aucune requête)", AppMenu.source);
                ok(AppMenu.menus.map(m => m.label).join() === "Casier,File,Edit,View,Go,Window" && AppMenu.menus[1].children[0].keys === "Super+E", "appmenu: fili-file -> menus de la barre, raccourci du bind niri", AppMenu.menus.map(m => m.label).join());
                const copy = AppMenu.menus[2].children[3];
                ok(copy.label === "Copy" && copy.keys === "Ctrl+C", "appmenu: fili-file -> Copier avec son raccourci", copy.label + " " + copy.keys);
                FiliTheme.ran = [];
                AppMenu.openAt(2, t.find(t.bar.contentItem, "appmenu-2"), t.bar);
                AppMenu.activate(copy);
                ok(FiliTheme.ran.join() === "fili-file ctl --pid 4242 action copy", "appmenu: commande de contrôle visant le processus de la fenêtre (%pid)", FiliTheme.ran.join());
                ok(AppMenu.menus[4].children[8].exec === 'fili-file ctl --pid %pid goto "$HOME/Documents"', "appmenu: fili-file -> aller à un dossier par fili-file ctl goto");
                // «…»: les menus qui ne tiennent pas dans la place libre passent dans un titre, en sous-menus
                const h = t.find(t.bar.contentItem, "appmenu");
                h.maxWidth = 200;
                ok(h.fit >= 1 && h.fit < 6 && h.overflow && h.titleAt(h.fit) === t.find(t.bar.contentItem, "appmenu-more"), "appmenu: place réduite -> premiers titres et «…»", "fit " + h.fit);
                AppMenu.openAt(h.fit, h.titleAt(h.fit), t.bar, h);
                ok(AppMenu.more && AppMenu.levels[0].length === 6 - h.fit && AppMenu.levels[0][0].label === AppMenu.menus[h.fit].label, "appmenu: «…» -> liste des menus restants", AppMenu.levels[0].length);
                AppMenu.enter(0, AppMenu.levels[0][0], 0, 0);
                ok(AppMenu.levels.length === 2 && AppMenu.levels[1] === AppMenu.menus[h.fit].children || AppMenu.levels[1].length === AppMenu.menus[h.fit].children.length, "appmenu: «…» -> un menu s'ouvre en sous-menu");
                AppMenu.close();
                ok(!AppMenu.more, "appmenu: «…» refermé");
                h.maxWidth = 100000;
                ok(!h.overflow && h.fit === 6 && h.titleAt(6) === null, "appmenu: place suffisante -> tous les titres, pas de «…»", "fit " + h.fit);
                Niri.setWindows({ 9: { id: 9, pid: 0, app_id: "org.exemple.Inconnu", title: "x" } });
                Niri.focusedId = 9;
            },
            wait(() => {}, () => AppMenu.appId === "org.exemple.Inconnu" && AppMenu.menus.length === 2),
            () => {
                ok(AppMenu.menus.map(m => m.label).join() === "Inconnu,Window", "appmenu: application inconnue -> nom tiré de l'app-id, menu Fenêtre", AppMenu.menus.map(m => m.label).join());
                // Réponse de fili-appmenu: menu GTK3 paresseux, entrée AT-SPI
                AppMenu.pending = true;
                AppMenu.onMenu(AppMenu.gen, JSON.stringify({ items: [
                    { label: "File", kind: "sub", enabled: true, check: 0, svc: ":1.2", path: "/m/1", children: [] },
                    { label: "Edit", kind: "sub", enabled: true, check: 0, svc: ":1.2", path: "/m/2", children: [
                        { label: "Copy", kind: "item", enabled: true, check: 0, keys: "Ctrl+C", svc: ":1.2", path: "/m/3", children: [] },
                        { label: "", kind: "sep", enabled: true, check: 0, svc: ":1.2", path: "/m/4", children: [] },
                        { label: "Wrap", kind: "item", enabled: false, check: 2, svc: ":1.2", path: "/m/5", children: [] },
                        { label: "Find", kind: "sub", enabled: true, check: 0, svc: ":1.2", path: "/m/6", children: [
                            { label: "Next", kind: "item", enabled: true, check: 0, svc: ":1.2", path: "/m/7", children: [] }] }] }] }));
                ok(AppMenu.source === "atspi" && AppMenu.menus.map(m => m.label).join() === "Inconnu,File,Edit,Window", "appmenu: menus AT-SPI -> entre le menu de l'application et Fenêtre", AppMenu.menus.map(m => m.label).join());
                AppMenu.openAt(2, t.find(t.bar.contentItem, "appmenu-2"), t.bar);
                const edit = AppMenu.levels[0];
                ok(edit.length === 4 && edit[1].kind === "sep" && edit[2].check === 2 && !edit[2].enabled && edit[3].kind === "sub", "appmenu: menu AT-SPI -> séparateur, case cochée, entrée grisée, sous-menu");
                ok(edit[0].keys === "Ctrl+C" && edit[2].keys === "", "appmenu: raccourci d\x27une entrée AT-SPI conservé", edit[0].keys);
                FiliTheme.ran = [];
                AppMenu.activate(edit[2]);
                ok(AppMenu.open && FiliTheme.ran.length === 0, "appmenu: entrée grisée -> rien");
                AppMenu.activate(edit[0]);
                ok(FiliTheme.ran.join() === FiliTheme.bin + "/fili-appmenu do :1.2 /m/3", "appmenu: entrée AT-SPI -> fili-appmenu do", FiliTheme.ran.join());
                // Clavier: ↑/↓ saute séparateurs et entrées grisées, → ouvre le sous-menu, ← le referme
                AppMenu.close();
                AppMenu.openAt(2, t.find(t.bar.contentItem, "appmenu-2"), t.bar);
                AppMenu.keyboard = true;
                AppMenu.keyMove(1);
                ok(AppMenu.sel[0] === 0, "appmenu clavier: ↓ -> première entrée", JSON.stringify(AppMenu.sel));
                AppMenu.keyMove(1);
                ok(AppMenu.sel[0] === 3, "appmenu clavier: ↓ saute le séparateur et l\x27entrée grisée", JSON.stringify(AppMenu.sel));
                AppMenu.keyMove(1);
                ok(AppMenu.sel[0] === 0, "appmenu clavier: ↓ boucle sur la première entrée", JSON.stringify(AppMenu.sel));
                AppMenu.keyMove(-1);
                ok(AppMenu.sel[0] === 3, "appmenu clavier: ↑ revient à la dernière entrée", JSON.stringify(AppMenu.sel));
                AppMenu.keyRight();
                ok(AppMenu.levels.length === 2 && AppMenu.levels[1][0].label === "Next" && AppMenu.sel[1] === 0, "appmenu clavier: → ouvre le sous-menu, premier élément choisi", JSON.stringify(AppMenu.sel));
                AppMenu.keyLeft();
                ok(AppMenu.levels.length === 1 && AppMenu.openIndex === 2, "appmenu clavier: ← referme le sous-menu", AppMenu.levels.length);
                AppMenu.keyLeft();
                ok(AppMenu.openIndex === 1 && AppMenu.keyboard, "appmenu clavier: ← au premier niveau -> menu précédent (resté au clavier)", AppMenu.openIndex);
                AppMenu.keyRight();
                ok(AppMenu.openIndex === 2, "appmenu clavier: → sur une entrée simple -> menu suivant", AppMenu.openIndex);
                AppMenu.close();
                ok(!AppMenu.open && AppMenu.levels.length === 0 && !AppMenu.keyboard, "appmenu: fermeture");
            },
            // BarState: états lus dans leurs fichiers (alertes, agenda, minuteur, tiroir), sans script
            () => {
                const now = 1000000;
                const m = BarState.alert("mail", "Alice\tBonjour\nBob\tSalut\n", null, now);
                ok(m.text === " 2" && m["class"] === "active" && m.tooltip.title === "Proton Mail" && m.tooltip.rows[0][0] === "Alice" && m.tooltip.rows[0][1] === "Bonjour" && m.tooltip.rows[1][0] === "Bob", "BarState: alerte mail", JSON.stringify(m));
                const c = BarState.alert("cal", (now - 400) + "\t10:00\tVieux\n" + (now + 600) + "\t11:00\tRéunion\n", null, now);
                ok(c.text === " Réunion 11:00" && JSON.stringify(c.tooltip).indexOf("Vieux") < 0, "BarState: agenda, événement passé ignoré", JSON.stringify(c));
                ok(BarState.alert("cal", (now - 400) + "\t10:00\tVieux\n", null, now).text === "", "BarState: agenda expiré masqué");
                const w = BarState.alert("whatsapp", "", "3\n", now);
                ok(w.text.endsWith(" 3") && w.tooltip.title === "WhatsApp" && w.tooltip.rows[0][1] === "3", "BarState: compteur de non-lus prioritaire", JSON.stringify(w));
                ok(BarState.alert("whatsapp", "x\ty\n", "0", now).text === "", "BarState: compteur à 0 masque l'alerte");
                ok(BarState.timerFor("S", now - 65, now).text === " 01:05", "BarState: chronomètre", BarState.timerFor("S", now - 65, now).text);
                const r = BarState.timerFor("T", now + 3700, now);
                ok(r.text === " 1:01:40" && r["class"] === "active", "BarState: minuteur (heures)", r.text);
                ok(BarState.timerFor("T", now - 1, now)["class"] === "done" && BarState.timerFor("", 0, now)["class"] === "idle", "BarState: minuteur écoulé / au repos");
                // Agent IA (fili-ai-session): repos, au travail, question en attente, tour fini sans être regardé
                ok(BarState.aiFor({ sessions: [] }, null, {})["class"] === "off", "BarState: agent IA sans session");
                const lim = { five_hour: { used_percentage: 34.4, resets_at: now + 3600 }, seven_day: { used_percentage: 12 }, seen: now };
                const busy = BarState.aiFor({ sessions: [{ id: "a", state: "working", window: 7, ctx: 42.6, cost: 1.5, model: "Opus" }], limits: lim }, null, { 7: { title: "✳ Icône IA" } }, now);
                ok(busy["class"] === "working" && busy.tooltip.rows[0][0] === "Icône IA" && busy.tooltip.rows[0][1].indexOf("context 43 %") >= 0
                   && busy.tooltip.rows.some(r => r[0] === "5-hour limit" && r[1].startsWith("34 %") && Math.abs(r[2].value - 0.344) < 1e-6 && Math.abs(r[2].mark - 0.8) < 0.01), "BarState: agent IA au travail, fiche (titre, contexte, limites et jauges)", JSON.stringify(busy));
                const ask = BarState.aiFor({ sessions: [{ id: "a", state: "waiting", attention: true, window: 7, message: "Bash?" }] }, null, {});
                ok(ask.text.endsWith(" ASK") && ask["class"] === "waiting" && ask.tooltip.rows.some(r => r[1] === "Bash?"), "BarState: agent IA en attente (ASK)", JSON.stringify(ask));
                ok(BarState.aiFor({ sessions: [{ id: "a", state: "waiting", attention: true, window: 7 }] }, 7, {})["class"] === "idle", "BarState: agent IA regardé, plus mis en avant");
                ok(BarState.aiFor({ sessions: [{ id: "a", state: "done", attention: true, window: 7 }, { id: "b", state: "idle" }] }, null, {}).text.endsWith(" DONE"), "BarState: agent IA, tour fini (DONE)");
            },
            wait(() => t.shell('echo "S $(( $(date +%s) - 65 ))" > "$XDG_RUNTIME_DIR/bar-timer"; : > "$XDG_RUNTIME_DIR/bar-tray-open"'),
                 () => BarState.timerFile.kind === "S" && BarState.trayOpen),
            () => {
                ok(/ 01:0[5-7]$/.test(BarState.timer.text), "BarState: chronomètre lu dans bar-timer (FileView)", BarState.timer.text);
                const h = t.find(t.bar.contentItem, "tray-handle");
                ok(h.cls === "open", "BarState: tiroir ouvert (bar-tray-open)");
                // Texte réellement affiché par le module (un enfant Text), pas seulement sa propriété
                const shown = item => (item.children ?? []).some(c => (typeof c.text === "string" && c.text.indexOf("") >= 0) || shown(c));
                ok(shown(h), "BarState: chevron du tiroir affiché par BarScript (value)");
                FiliTheme.ran = [];
            },
            wait(() => t.shell('echo "T $(( $(date +%s) - 1 ))" > "$XDG_RUNTIME_DIR/bar-timer"'), () => FiliTheme.ran.join("\n").indexOf("bar-timer expire") >= 0),
            () => ok(BarState.timer["class"] === "done", "BarState: minuteur écoulé -> bar-timer expire", FiliTheme.ran.join(" ")),
            wait(() => t.shell('rm -f "$XDG_RUNTIME_DIR/bar-timer" "$XDG_RUNTIME_DIR/bar-tray-open"'), () => BarState.timerFile.kind === "" && !BarState.trayOpen),
            () => ok(BarState.timer["class"] === "idle" && t.find(t.bar.contentItem, "tray-handle").cls === "", "BarState: fichiers supprimés -> repos"),
            // Bluetooth: nombre d'appareils connectés (ou OFF / SHARE), plus de ON; icône seule sans adaptateur (CI)
            () => {
                const bt = t.find(t.bar.contentItem, "bluetooth");
                ok(/^[^ ]+( (OFF|SHARE|\d+))?$/.test(bt.text) && (bt.adapter ? bt.text.indexOf(" ") > 0 : bt.text.indexOf(" ") < 0), "fili-bar bluetooth: nombre d'appareils connectés (icône seule sans adaptateur)", bt.text);
            },
            // Sauvegarde en cours: clignote par un Timer (opacité basculée chaque seconde), pas par une animation
            () => BarState.setBackup({ text: "", class: "active", tooltip: "test" }),
            wait(() => {}, () => {
                const row = t.find(t.bar.contentItem, "backup").children.find(c => c.spacing !== undefined);
                return row && row.opacity < 1;
            }, 3000),
            () => {
                const row = t.find(t.bar.contentItem, "backup").children.find(c => c.spacing !== undefined);
                ok(row.opacity === 0.35, "fili-bar sauvegarde en cours: clignote", row.opacity);
                BarState.setBackup({ text: "" });
            },
            wait(() => {}, () => t.find(t.bar.contentItem, "backup").children.find(c => c.spacing !== undefined).opacity === 1, 3000),
            () => ok(true, "fili-bar sauvegarde: opacité rétablie à l'arrêt du clignotement"),

            // ───── fili-launcher ─────
            () => {
                const p = FiliLauncher.parse("  Applications ›  ‹Mod+D›");
                ok(p.glyph === "" && p.text === "Applications" && p.sub && p.key === "Mod+D", "fili-launcher découpe glyphe / libellé / sous-menu / touche", JSON.stringify(p));
                const q = FiliLauncher.parse("Google Chrome");
                ok(q.glyph === "" && q.text === "Google Chrome" && !q.sub && q.key === "", "fili-launcher ligne simple", JSON.stringify(q));
                ok(FiliLauncher.match("Night light", ["nig"]) !== null && FiliLauncher.match("Night light", ["xyz"]) === null, "fili-launcher correspondance");
                ok(FiliLauncher.match("Casier", ["file"], " files fichiers file ") !== null && FiliLauncher.match("Casier", ["file"], "") === null
                    && FiliLauncher.match("Rob", ["ia"], " ai assistant ia chat ") !== null && FiliLauncher.match("Rob", ["xyz"], " ai assistant ia chat ") === null, "fili-launcher mots-clés (Casier <- file, Rob <- ia)");
            },
            wait(() => t.shell("printf 'Alpha\\nBeta app\\nGamma › sous\\n' | " + t.bin + "/fili-shell launcher --prompt 'Style › '; echo \"rc=$?\""),
                 () => FiliLauncher.open && FiliLauncher.entries.length === 3),
            () => {
                ok(FiliLauncher.crumb === "STYLE", "fili-launcher fil d'Ariane", FiliLauncher.crumb);
                FiliLauncher.current = 1;
                FiliLauncher.accept();
            },
            wait(() => {}, () => t.shellOut !== null),
            () => ok(t.shellOut.out.trim() === "Beta app\nrc=0", "fili-launcher choix -> sortie et code 0", JSON.stringify(t.shellOut.out)),
            // Deux requêtes à la suite: la seconde ne garde rien de la première (ancien défaut de lecture asynchrone)
            wait(() => t.shell("printf 'Un\\nDeux\\n' | " + t.bin + "/fili-shell launcher --prompt 'Test › '; echo \"rc=$?\""),
                 () => FiliLauncher.open && FiliLauncher.entries.length === 2 && FiliLauncher.entries[0].text === "Un"),
            () => FiliLauncher.finish(10, ""),
            wait(() => {}, () => t.shellOut !== null),
            () => ok(t.shellOut.out.trim() === "rc=10", "fili-launcher Maj+Retour arrière -> code 10", JSON.stringify(t.shellOut.out)),
            wait(() => t.shell("printf 'X\\n' | " + t.bin + "/fili-shell launcher --prompt 'T › '; echo \"rc=$?\""), () => FiliLauncher.open),
            () => {
                FiliLauncher.query = "texte libre";
                ok(FiliLauncher.shown.length === 0, "fili-launcher filtre sans résultat");
                FiliLauncher.accept();
            },
            wait(() => {}, () => t.shellOut !== null),
            () => ok(t.shellOut.out.trim() === "texte libre\nrc=0", "fili-launcher texte saisi sans correspondance", JSON.stringify(t.shellOut.out)),
            wait(() => t.shell("printf 'X\\n' | " + t.bin + "/fili-shell launcher --prompt 'T › ' & sleep 0.5; " + t.bin + "/fili-shell launcher close; echo \"close=$?\"; wait"),
                 () => t.shellOut !== null),
            () => ok(t.shellOut.out.indexOf("close=0") >= 0 && !FiliLauncher.open, "fili-shell launcher close ferme le fili-launcher", JSON.stringify(t.shellOut.out)),

            // ───── fili-notification ─────
            wait(() => t.shell("notify-send -a test 'Résumé test' 'Corps du test'"), () => FiliNotification.popups.length === 1),
            () => ok(FiliNotification.popups[0].n.summary === "Résumé test", "fili-notification bulle reçue"),
            () => ok(FiliTheme.ran.filter(c => c === "sound notification").length === 1, "fili-sound: un son à la notification reçue", JSON.stringify(FiliTheme.ran.slice(-3))),
            wait(() => t.shell(t.bin + "/fili-shell notification dismiss 'Résumé test'"), () => FiliNotification.popups.length === 0),
            () => ok(FiliNotification.history.length === 1 && FiliNotification.history[0].summary === "Résumé test", "fili-notification fermée -> historique"),
            () => ok(typeof FiliNotification.history[0].icon === "string", "fili-notification historique: icône gardée (chaîne, vide sans icône)"),
            wait(() => t.shell(t.bin + "/fili-shell notification history"), () => t.shellOut !== null),
            () => {
                let h = [];
                try {
                    h = JSON.parse(t.shellOut.out);
                } catch (e) {}
                ok(h.length === 1 && h[0].summary === "Résumé test", "fili-shell notification history (JSON)", t.shellOut.out);
            },
            wait(() => t.shell("notify-send -a test 'Deux' 'b'; notify-send -a test 'Trois' 'c'"), () => FiliNotification.popups.length === 2),
            wait(() => t.shell(t.bin + "/fili-shell notification dismiss-all"), () => FiliNotification.popups.length === 0),
            () => ok(FiliNotification.history.length === 3, "fili-shell notification dismiss-all"),
            wait(() => {
                FiliNotification.dnd = true;
                t.shell("notify-send -a test 'Silence' 'd'");
            }, () => t.shellOut !== null && FiliNotification.history.length === 4),
            () => {
                ok(FiliNotification.popups.length === 0, "fili-notification ne pas déranger: pas de bulle, entrée dans l'historique");
                ok(FiliTheme.ran.filter(c => c === "sound notification").length <= 2, "fili-sound: pas de son en ne pas déranger", FiliTheme.ran.filter(c => c.indexOf("sound") === 0).length);
                FiliNotification.dnd = false;
            },
            // Boutons d'action (notify-send -A): la réponse revient à l'appli, la bulle reste 60 s pour laisser le temps
            wait(() => t.shell("notify-send -a test -t 30000 -A allow=Autoriser -A deny=Refuser 'Question' 'Autoriser ?'"), () => FiliNotification.popups.length === 1),
            () => {
                const n = FiliNotification.popups[0].n;
                ok(FiliNotification.buttons(n).map(a => a.identifier).join() === "allow,deny", "fili-notification: deux boutons d'action", JSON.stringify(FiliNotification.buttons(n).map(a => a.identifier)));
                ok(FiliNotification.timeout(n) === 30000, "fili-notification: une bulle à boutons reste le délai demandé (30 s)", String(FiliNotification.timeout(n)));
                FiliNotification.answer(n, "deny");
            },
            wait(() => {}, () => t.shellOut !== null),
            () => ok(t.shellOut.out.trim() === "deny" && FiliNotification.popups.length === 0, "fili-notification: la réponse revient à notify-send et ferme la bulle", JSON.stringify(t.shellOut.out)),
            // fili-sound: chargeur branché (son au branchement seulement), réglages de coupure
            () => {
                FiliTheme.ran = [];
                FiliSound.ac = false;
                FiliSound.acEvent(true);
                ok(FiliTheme.ran.length === 1 && FiliTheme.ran[0] === "sound power-plug", "fili-sound: son au branchement du chargeur", JSON.stringify(FiliTheme.ran));
                FiliSound.acEvent(true);
                FiliSound.acEvent(false);
                ok(FiliTheme.ran.length === 1, "fili-sound: ni redite ni son au débranchement", JSON.stringify(FiliTheme.ran));
                FiliSound.set("plug", false);
                FiliSound.acEvent(true);
                ok(FiliTheme.ran.length === 1 && !FiliSound.plug, "fili-sound: son du chargeur coupé", JSON.stringify(FiliTheme.ran));
                FiliSound.set("plug", true);
                FiliSound.set("notify", false);
                FiliSound.notified();
                ok(FiliTheme.ran.length === 1 && !FiliSound.notify, "fili-sound: son des notifications coupé", JSON.stringify(FiliTheme.ran));
                FiliSound.set("notify", true);
                FiliTheme.ran = [];
                FiliSound.notified("niri");
                ok(FiliTheme.ran.length === 0, "fili-sound: pas de son pour la capture d'écran (niri)", JSON.stringify(FiliTheme.ran));
            },

            // ───── fili-tooltip ─────
            () => {
                const c = FiliTooltip.normalize("<tt>CPU &amp; mémoire</tt>");
                ok(c.text === "CPU & mémoire" && c.mono === true, "fili-tooltip texte Pango -> texte brut à chasse fixe", JSON.stringify(c));
                ok(FiliTooltip.empty({}) && !FiliTooltip.empty({ title: "x" }), "fili-tooltip fiche vide");
            },

            // ───── FiliInfo: fiches demandées à bar-stats (entrée standard) ou composées (écrans, socket niri) ─────
            wait(() => {
                t.cards = {};
                for (const x of ["network", "power", "display", "monitor"])
                    FiliInfo.request(x);
            }, () => ["network", "power", "display", "monitor"].every(x => t.cards[x]), 10000),
            () => {
                for (const topic of ["network", "power", "display"]) {
                    const c = t.cards[topic];
                    ok(c && c.title && Array.isArray(c.rows) && c.hint, "FiliInfo " + topic + ": titre, lignes, aide", JSON.stringify(c));
                }
                ok(t.cards.monitor.title === "System" && t.cards.monitor.rows.length > 4, "FiliInfo monitor: fiche", JSON.stringify(t.cards.monitor));
                ok(t.cards.display.rows.length > 0, "FiliInfo display: sorties de niri", JSON.stringify(t.cards.display));
            },

            // ───── fili-panel: chaque vue se charge sans erreur, puis fili-net ─────
            () => {
                for (const v of ["network", "audio", "bluetooth", "power", "monitor", "keyboard", "display"]) {
                    FiliPanel.view = v;
                    ok(FiliPanel.loaded !== null, "fili-panel " + v + ": vue chargée");
                    FiliPanel.close();
                    ok(FiliPanel.loaded === null, "fili-panel " + v + ": vue libérée à la fermeture");
                }
            },
            // fili-panel écrans: fixture de deux sorties, aimantation, commandes niri, confirmation et retour en arrière
            () => {
                FiliPanel.view = "display";
                const d = FiliPanel.loaded;
                const mode = (w, h, r) => ({ width: w, height: h, refresh_rate: r, is_preferred: false });
                const out = (name, x, scale, modes) => ({ name, make: "T", model: name, logical: { x, y: 0, width: Math.round(modes[0].width / scale), height: Math.round(modes[0].height / scale), scale, transform: "Normal" }, modes, current_mode: 0, vrr_supported: true, vrr_enabled: false });
                d.outputs = [out("A-1", 0, 2, [mode(2560, 1600, 60001), mode(1920, 1200, 60000), mode(1920, 1200, 120000)]), out("B-1", 1280, 1, [mode(1920, 1080, 60000)])];
                d.sel = "A-1";
                ok(d.active.length === 2 && d.resolutions.length === 2, "fili-panel écrans: sorties et définitions", d.resolutions.length);
                ok(d.refreshes.length === 1, "fili-panel écrans: une seule fréquence, pas de choix", d.refreshes.length);
                const b = d.outputs[1];
                const p = d.snapPos(b, 1300, 30);
                ok(p.x === 1280 && p.y === 0, "fili-panel écrans: aimantation au bord voisin", JSON.stringify(p));
                FiliTheme.ran = [];
                d.setResolution(d.outputs[0], d.resolutions[1]);
                ok(FiliTheme.ran[0] === "niri msg output 'A-1' mode 1920x1200@120.000", "fili-panel écrans: définition -> plus haute fréquence", JSON.stringify(FiliTheme.ran));
                ok(d.snap !== null && d.secs === 15, "fili-panel écrans: changement à confirmer", d.secs);
                d.setTransform(d.outputs[0], "90");
                ok(d.snap.name === "A-1" && d.snap.current_mode === 0, "fili-panel écrans: l'état d'avant reste le premier", d.snap.current_mode);
                FiliTheme.ran = [];
                d.revert();
                ok(d.snap === null && FiliTheme.ran[0].indexOf("mode 2560x1600@60.001") > 0 && FiliTheme.ran[0].indexOf("position set 0 0") > 0 && FiliTheme.ran[0].indexOf("scale 2") > 0, "fili-panel écrans: annuler -> état d'avant", JSON.stringify(FiliTheme.ran));
                FiliTheme.ran = [];
                d.move(b, 1290, 5);
                ok(FiliTheme.ran[0] === "niri msg output 'B-1' position set 1280 0" && d.snap === null, "fili-panel écrans: déplacement sans confirmation", JSON.stringify(FiliTheme.ran));
                FiliTheme.ran = [];
                d.setScale(d.outputs[0], 1.5);
                ok(FiliTheme.ran[0] === "niri msg output 'A-1' scale 1.5" && d.snap === null, "fili-panel écrans: échelle sans confirmation", JSON.stringify(FiliTheme.ran));
                d.keep();
                ok(d.snap === null, "fili-panel écrans: garder");
                FiliPanel.close();
            },
            // fili-panel Bluetooth, partage de fichiers: protocoles grisés si indisponibles, même interface, commande d'envoi
            () => {
                FiliPanel.view = "bluetooth";
                const bt = FiliPanel.loaded;
                bt.protocols = [{ id: "airdrop", label: "AirDrop", available: false, why: "omdrop non installé" },
                                { id: "bluetooth", label: "Bluetooth", available: true, why: "" },
                                { id: "localsend", label: "LocalSend", available: false, why: "non installé" }];
                bt.proto = "airdrop";
                ok(!bt.shareOk && !t.find(bt, "share-receive").switchable, "fili-panel bluetooth: protocole indisponible, réception grisée");
                const chips = t.find(bt, "share-protocols");
                chips.pick(2);
                ok(bt.proto === "airdrop", "fili-panel bluetooth: un protocole grisé ne se choisit pas", bt.proto);
                chips.pick(1);
                ok(bt.proto === "bluetooth" && bt.shareOk && t.find(bt, "share-receive").switchable, "fili-panel bluetooth: protocole disponible choisi", bt.proto);
                FiliTheme.ran = [];
                bt.setReceiving(true);
                ok(FiliTheme.ran[0] === FiliTheme.bin + "/fili-share receive bluetooth on", "fili-panel bluetooth: réception -> fili-share receive", JSON.stringify(FiliTheme.ran));
                FiliTheme.ran = [];
                bt.sendTo({ id: "AA:BB:CC:DD:EE:FF", name: "Tel d'Alex" });
                ok(FiliTheme.ran[0] === FiliTheme.bin + "/fili-share send bluetooth 'AA:BB:CC:DD:EE:FF' 'Tel d'\\''Alex'", "fili-panel bluetooth: envoi -> fili-share send (noms quotés)", JSON.stringify(FiliTheme.ran));
                FiliPanel.close();
            },
            // fili-panel clavier: visualiseur (touches de fili-keymap, frappe wtype) et emoji (copie + frappe)
            () => {
                FiliPanel.view = "keyboard";
                ok(FiliPanel.loaded && !FiliPanel.loaded.passive, "fili-panel clavier: page des dispositions avec focus");
                const kbd = FiliPanel.loaded;
                if (kbd.keys >= 0) {
                    FiliTheme.ran = [];
                    t.find(kbd, "keys").moved(0.5);
                    ok(FiliTheme.ran.some(c => c.indexOf("kbd_backlight' set 50%") > 0), "fili-panel clavier: curseur du rétroéclairage", JSON.stringify(FiliTheme.ran));
                }
                t.find(kbd, "open-hotkeys").press(Qt.LeftButton);
                ok(FiliHotkeys.open && !FiliPanel.open, "fili-panel clavier: lien Raccourcis clavier -> fenêtre des raccourcis, panneau fermé");
                FiliHotkeys.close();
                FiliPanel.view = "keyboard";
                FiliPanel.loaded.page = "viewer";
                ok(FiliPanel.loaded.passive, "fili-panel clavier: le visualiseur ne prend pas le focus");
            },
            wait(() => {}, () => FiliPanel.loaded.rows.length === 4),
            () => {
                const kb = FiliPanel.loaded;
                ok(kb.rows.length === 4 && kb.rows[0].length >= 12, "fili-panel clavier: fili-keymap, 4 rangées", JSON.stringify(kb.rows).slice(0, 80));
                FiliTheme.ran = [];
                kb.typeKey("eacute");
                ok(FiliTheme.ran.indexOf("wtype -k eacute") >= 0, "fili-panel clavier: clic touche -> wtype -k", JSON.stringify(FiliTheme.ran));
                kb.page = "emoji";
            },
            wait(() => {}, () => FiliPanel.loaded.emojis.length > 100),
            () => {
                const kb = FiliPanel.loaded;
                ok(kb.emojis.length > 100, "fili-panel clavier: liste des emoji chargée", kb.emojis.length);
                kb.query = "grinning face";
                ok(kb.found.length > 0 && kb.found.length <= 48, "fili-panel clavier: recherche d'emoji", kb.found.length);
                FiliTheme.ran = [];
                kb.pickEmoji(kb.found[0].c);
                ok(FiliTheme.ran.some(c => c.indexOf("wl-copy") >= 0 && c.indexOf("wtype") >= 0), "fili-panel clavier: emoji copié et tapé", JSON.stringify(FiliTheme.ran));
                ok(FiliPanel.view === "", "fili-panel clavier: choisir un emoji ferme le panneau");
            },
            // Icône de la sortie audio selon son type (propriétés PipeWire)
            () => {
                const g = p => FiliTheme.sinkGlyph(p).codePointAt(0) ?? 0;
                ok(g({ "device.icon_name": "audio-headphones", "device.profile.name": "HiFi: Headphones: sink" }) === 0xf025, "son: casque filaire");
                ok(g({ "node.name": "alsa_output.pci.analog-stereo", "device.form-factor": "headset" }) === 0xf025, "son: casque-micro USB");
                ok(g({ "device.api": "bluez5", "node.name": "bluez_output.AA_BB.1", "device.form-factor": "headphone" }) === 0xf0970, "son: casque Bluetooth");
                ok(g({ "device.api": "bluez5", "node.name": "bluez_output.AA_BB.1", "device.form-factor": "speaker" }) === 0xf09a2, "son: enceinte Bluetooth");
                ok(g({ "node.name": "alsa_output.pci-0000_00_1f.3.hdmi-stereo" }) === 0xf0379, "son: écran HDMI");
                ok(g({ "node.name": "audio_effect.t2-speakers", "device.icon-name": "audio-speakers" }) === 0, "son: haut-parleurs (icône graduée)");
                ok(g(null) === 0, "son: sortie absente");
            },
            // Aucune fili-tooltip tant qu'un fili-panel est ouvert
            () => {
                const it = t.find(t.bar.contentItem, "volume");
                FiliPanel.summon("audio");
                FiliTooltip.show(it, { title: "x" });
                ok(FiliTooltip.target === null, "fili-tooltip: masquée quand un fili-panel est ouvert");
                FiliPanel.close();
                FiliTooltip.show(it, { title: "x" });
                ok(FiliTooltip.target === null, "fili-tooltip: aucune fiche juste après la fermeture d'un panneau");
                FiliShell.panelClosedAt = Date.now() - 5000;
                FiliTooltip.show(it, { title: "x" });
                ok(FiliTooltip.target === it, "fili-tooltip: de nouveau permise après le répit");
                FiliTooltip.hide();
                // Même chose avec le centre de notifications ouvert
                FiliShell.panelClosedAt = Date.now() - 5000;
                FiliNotification.centerOpen = true;
                FiliTooltip.show(it, { title: "x" });
                ok(FiliTooltip.target === null, "fili-tooltip: masquée quand le centre de notifications est ouvert");
                FiliNotification.centerOpen = false;
                FiliTooltip.show(it, { title: "x" });
                ok(FiliTooltip.target === null, "fili-tooltip: répit aussi après la fermeture du centre de notifications");
                FiliShell.panelClosedAt = Date.now() - 5000;
                FiliTooltip.hide();
            },
            // Interrupteurs à droite du titre (Wi-Fi, Bluetooth): présents, Bluetooth grisé sans adaptateur
            () => {
                for (const [v, name] of [["network", "wifi-power"], ["bluetooth", "power"], ["display", "night"], ["power", "caffeine"]]) {
                    FiliPanel.view = v;
                    const sw = t.find(FiliPanel.loaded, name);
                    ok(sw && sw.hasOwnProperty("checked"), "fili-panel " + v + ": interrupteur à droite du titre", sw ? "" : "introuvable");
                }
                FiliPanel.close();
            },
            // fili-panel écrans, apparence: sombre par défaut, « Clair » passe le shell en papier et lance fili-theme
            () => {
                FiliPanel.view = "display";
                const chips = t.find(FiliPanel.loaded, "theme");
                ok(chips && chips.current === "dark" && Qt.colorEqual(FiliTheme.nuit, "#1c222b"), "fili-panel écrans: mode sombre par défaut", chips ? chips.current : "introuvable");
                FiliTheme.ran = [];
                chips.pick(1);
                ok(FiliTheme.light && Qt.colorEqual(FiliTheme.nuit, "#f3f1ec") && Qt.colorEqual(FiliTheme.brume, "#1c222b"), "fili-panel écrans: mode clair, fond papier et texte nuit", FiliTheme.mode);
                ok(FiliTheme.ran.length === 1 && /\/fili-theme light$/.test(FiliTheme.ran[0]), "fili-panel écrans: fili-theme light lancé", JSON.stringify(FiliTheme.ran));
                chips.pick(0);
                ok(FiliTheme.mode === "dark" && /\/fili-theme dark$/.test(FiliTheme.ran[1]), "fili-panel écrans: retour au sombre", JSON.stringify(FiliTheme.ran));
                FiliPanel.close();
            },
            // fili-panel écrans, couleur d'accentuation: voile par défaut, le choix change l'accent du shell et lance fili-theme accent
            () => {
                FiliPanel.view = "display";
                const acc = t.find(FiliPanel.loaded, "accent");
                ok(acc && FiliTheme.accent === "default" && Qt.colorEqual(FiliTheme.voile, "#dbe7f4"), "fili-panel écrans: accent par défaut: brume en sombre", acc ? FiliTheme.accent : "introuvable");
                FiliTheme.ran = [];
                acc.pick("sable");
                ok(Qt.colorEqual(FiliTheme.voile, "#d2bf92") && Qt.colorEqual(FiliTheme.voileVif, "#e0d1ab"), "fili-panel écrans: accent sable dans le shell", String(FiliTheme.voile));
                ok(FiliTheme.ran.length === 1 && /\/fili-theme accent sable$/.test(FiliTheme.ran[0]), "fili-panel écrans: fili-theme accent sable lancé", JSON.stringify(FiliTheme.ran));
                FiliTheme.mode = "light";
                ok(Qt.colorEqual(FiliTheme.voile, "#80662b"), "accent sable en mode clair", String(FiliTheme.voile));
                FiliTheme.mode = "dark";
                FiliTheme.mode = "light";
                FiliTheme.accent = "default";
                ok(Qt.colorEqual(FiliTheme.voile, "#1c222b"), "accent par défaut en mode clair: noir", String(FiliTheme.voile));
                FiliTheme.mode = "dark";
                FiliTheme.accent = "inconnu";
                ok(Qt.colorEqual(FiliTheme.voile, "#dbe7f4"), "accent inconnu: repli sur le défaut", String(FiliTheme.voile));
                FiliTheme.accent = "default";
                FiliPanel.close();
            },
            // Panneau ouvert: l'action d'un module part à l'appui (un seul clic), pas deux fois au relâchement
            () => {
                const logo = t.find(t.bar.contentItem, "logo");
                const area = logo.hover ?? logo;
                FiliPanel.summon("audio");
                FiliTheme.ran = [];
                area.down(Qt.LeftButton);
                ok(FiliTheme.ran.length === 1, "fili-bar: panneau ouvert, action à l'appui", JSON.stringify(FiliTheme.ran));
                area.up(Qt.LeftButton);
                ok(FiliTheme.ran.length === 1, "fili-bar: panneau ouvert, pas de second déclenchement au relâchement", JSON.stringify(FiliTheme.ran));
                FiliPanel.close();
                FiliTheme.ran = [];
                area.down(Qt.LeftButton);
                ok(FiliTheme.ran.length === 0, "fili-bar: panneau fermé, rien à l'appui");
                area.up(Qt.LeftButton);
                ok(FiliTheme.ran.length === 1, "fili-bar: panneau fermé, action au relâchement", JSON.stringify(FiliTheme.ran));
            },
            // fili-panel réseau: l'icône suit la force du signal (paliers de 25)
            () => {
                FiliPanel.view = "network";
                const g = s => FiliPanel.loaded.signalGlyph(s).codePointAt(0);
                ok(g(100) === 0xF0928 && g(75) === 0xF0928 && g(50) === 0xF0925 && g(25) === 0xF0922 && g(0) === 0xF091F, "fili-panel réseau: icône selon la force du signal", [g(100), g(50), g(25), g(0)].map(x => x.toString(16)).join(","));
                FiliPanel.close();
            },
            // fili-panel: un filet sépare les sections (le premier intertitre visible n'en a pas)
            () => FiliPanel.view = "display",
            wait(() => {}, () => FiliPanel.loaded && FiliPanel.loaded.children.filter(c => c.isSection === true && c.visible).length > 1 && FiliPanel.loaded.children.filter(c => c.isSection === true && c.first).length === 1),
            () => {
                const secs = FiliPanel.loaded.children.filter(c => c.isSection === true && c.visible);
                ok(secs.length > 1 && secs[0].first && secs.slice(1).every(s => !s.first), "fili-panel: filet entre les sections, pas avant la première", secs.map(s => s.first).join(","));
                FiliPanel.close();
            },
            // Un seul panneau ouvert: panneau, calendrier épinglé et centre de notifications se ferment l'un l'autre
            () => {
                const cal = t.find(t.bar.contentItem, "clock");
                FiliPanel.summon("audio");
                FiliNotification.toggleCenter();
                ok(FiliNotification.centerOpen && FiliPanel.view === "", "un seul panneau: le centre de notifications ferme le fili-panel", FiliPanel.view);
                FiliPanel.summon("audio");
                ok(FiliPanel.view === "audio" && !FiliNotification.centerOpen, "un seul panneau: le fili-panel ferme le centre de notifications");
                cal.press(Qt.RightButton);
                ok(FiliPanel.view === "", "un seul panneau: le calendrier épinglé ferme le fili-panel", FiliPanel.view);
                cal.press(Qt.RightButton);
                FiliPanel.close();
            },
            // ───── navigation au clavier (Mod+A, ←/→, Entrée...) ─────
            () => {
                FiliPanel.last = "monitor";
                FiliPanel.summon("toggle");
                ok(FiliPanel.view === "monitor" && FiliShell.keyNav, "clavier: Mod+A ouvre le dernier panneau, contours actifs", FiliPanel.view);
                FiliPanel.step(1);
                ok(FiliPanel.view === "audio", "clavier: → panneau voisin (son)", FiliPanel.view);
                FiliPanel.step(-1);
                FiliPanel.step(-1);
                ok(FiliPanel.view === "power", "clavier: ← depuis le premier boucle sur le dernier (alimentation)", FiliPanel.view);
                FiliPanel.step(-1);
                ok(FiliPanel.view === "" && FiliNotification.centerOpen && FiliShell.keyNav, "clavier: ← vers le centre de notifications", FiliPanel.view);
                FiliPanel.step(-1);
                ok(FiliPanel.view === "network" && !FiliNotification.centerOpen, "clavier: ← depuis le centre -> réseau", FiliPanel.view);
                FiliPanel.summon("toggle");
                ok(!FiliPanel.open && !FiliShell.keyNav, "clavier: Mod+A ferme, contours oubliés");
                FiliPanel.summon("toggle");
                ok(FiliPanel.view === "network", "clavier: Mod+A rouvre le dernier panneau (réseau)", FiliPanel.view);
                const m = FiliPanel.modules[Quickshell.screens[0].name] ?? {};
                ok(FiliPanel.ring.every(n => m[n]), "clavier: chaque panneau connaît son module de la barre", Object.keys(m).join(","));
                FiliPanel.close();
            },
            () => FiliPanel.summon("keyboard"),
            wait(() => {}, () => FiliPanel.loaded && t.find(FiliPanel.loaded, "open-emoji")),
            () => {
                const kb = FiliPanel.loaded;
                t.find(kb, "open-emoji").key({ modifiers: 0 });
                ok(kb.page === "emoji", "clavier: Entrée sur un bouton = clic", kb.page);
                kb.page = "layouts";
                FiliPanel.close();
            },
            () => FiliPanel.summon("display"),
            wait(() => {}, () => FiliPanel.loaded && t.find(FiliPanel.loaded, "scale")),
            () => {
                const d = FiliPanel.loaded;
                const chips = t.find(d, "scale");
                const values = chips.model.filter(c => !c.off);
                if (values.length > 1) {
                    chips.cursor = chips.model.indexOf(values[0]);
                    chips.move(1);
                    FiliTheme.ran = [];
                    ok(chips.cursor === chips.model.indexOf(values[1]) && FiliTheme.ran.length === 0, "clavier: → dans une rangée de choix déplace le curseur sans appliquer", chips.cursor);
                }
                const sl = t.find(d, "screen");
                if (sl.visible) {
                    FiliTheme.ran = [];
                    const e = { modifiers: Qt.ShiftModifier, accepted: true };
                    sl.nudge(e, 0.05);
                    ok(!e.accepted && FiliTheme.ran.length === 0, "clavier: Maj+→ sur un curseur laissé au panneau (voisin)");
                    sl.nudge({ modifiers: 0 }, 0.05);
                    ok(FiliTheme.ran.join(" ").indexOf("brightnessctl -q set") >= 0, "clavier: → sur le curseur de luminosité = +5 %", FiliTheme.ran.join(" "));
                }
                FiliPanel.close();
                FiliTheme.ran = [];
                FiliNotification.centerOpen = true;
                FiliNotification.copy({ summary: "test copie", body: "" });
                ok(FiliTheme.ran[0] === "wl-copy test copie" && !FiliNotification.centerOpen, "clavier: Entrée sur une notification du centre = copie et fermeture", JSON.stringify(FiliTheme.ran));
            },
            // fili-about: clic milieu du logo, fiche lue par fili-about, copie en texte, canal `about toggle`
            () => {
                act("logo", Qt.MiddleButton);
                ok(FiliAbout.open, "fili-bar logo, clic milieu -> fenêtre À propos");
            },
            wait(() => {}, () => FiliAbout.card.sections.length > 0, 10000),
            () => {
                const c = FiliAbout.card;
                const names = c.sections.map(s => s.name);
                ok(typeof c.host === "string" && ["Filigrane", "System", "Machine"].every(n => names.includes(n)), "fili-about: JSON { host, sections Filigrane/System/Machine }", JSON.stringify(names));
                ok(c.sections.every(s => s.rows.every(r => r.length === 2 && r[1] !== "")), "fili-about: lignes [libellé, valeur] non vides");
                FiliTheme.ran = [];
                FiliAbout.copy();
                ok(FiliTheme.ran[0]?.startsWith("wl-copy Filigrane · ") && FiliTheme.ran[0].indexOf("Kernel: ") > 0 && !FiliAbout.open, "fili-about: C copie la fiche en texte et ferme", JSON.stringify(FiliTheme.ran));
                FiliAbout.toggle();
                ok(FiliAbout.open, "fili-about: toggle rouvre");
                FiliShell.popupOpened("panel");
                ok(!FiliAbout.open, "fili-about: fermée quand un autre panneau s'ouvre");
            },
            // fili-chat: tiroir, sessions, événements du démon (sans démon: les requêtes sont enregistrées)
            () => {
                FiliTheme.ran = [];
                FiliChat.toggle();
                ok(FiliChat.open, "fili-chat: toggle ouvre le tiroir");
                FiliChat.send("bonjour");
                ok(FiliTheme.ran[0] === 'chat {"op":"new"}' && FiliChat.pending === "bonjour", "fili-chat: sans session, le premier message en crée une", JSON.stringify(FiliTheme.ran));
                FiliChat.receive({ ev: "sessions", sessions: [] });
                FiliChat.receive({ ev: "created", id: "s1" });
                ok(FiliTheme.ran[1] === 'chat {"op":"send","id":"s1","text":"bonjour"}' && FiliChat.current === "s1" && FiliChat.pending === "", "fili-chat: la session créée reçoit le message en attente", JSON.stringify(FiliTheme.ran));
                FiliChat.receive({ ev: "msg", id: "s1", role: "user", text: "bonjour" });
                FiliChat.receive({ ev: "state", id: "s1", state: "working" });
                FiliChat.receive({ ev: "delta", id: "s1", text: "sal" });
                FiliChat.receive({ ev: "delta", id: "s1", text: "ut" });
                ok(FiliChat.working && FiliChat.busy && FiliChat.live === "salut", "fili-chat: texte en cours et état « travaille »", FiliChat.live);
                FiliTheme.ran = [];
                FiliChat.send("encore");
                ok(FiliTheme.ran.length === 1 && FiliTheme.ran[0] === 'chat {"op":"send","id":"s1","text":"encore"}', "fili-chat: message écrit pendant un tour: envoyé au démon, qui le met en file", JSON.stringify(FiliTheme.ran));
                FiliChat.receive({ ev: "queue", id: "s1", items: ["encore"] });
                ok(FiliChat.queuedNow.length === 1, "fili-chat: file d'attente affichée");
                FiliChat.receive({ ev: "queue", id: "s1", items: [] });
                FiliChat.receive({ ev: "tool", id: "s1", name: "Bash", summary: "sv status iwd" });
                FiliChat.receive({ ev: "msg", id: "s1", role: "assistant", text: "Salut." });
                FiliChat.receive({ ev: "state", id: "s1", state: "idle" });
                ok(FiliChat.log.map(i => i.kind).join() === "user,tool,assistant" && FiliChat.live === "" && !FiliChat.working && !FiliChat.busy, "fili-chat: fil (message, outil, réponse) et fin du tour", FiliChat.log.map(i => i.kind).join());
                FiliChat.receive({ ev: "sessions", sessions: [{ id: "s2", title: "Wi-Fi", state: "idle", updated: 2 }, { id: "s1", title: "bonjour", state: "idle", updated: 1 }] });
                ok(FiliChat.current === "s1" && FiliChat.title === "bonjour", "fili-chat: titre de la session courante", FiliChat.title);
                FiliTheme.ran = [];
                FiliChat.openSession("s2");
                ok(FiliChat.current === "s2" && FiliTheme.ran[0] === 'chat {"op":"open","id":"s2"}', "fili-chat: changer de session demande son historique", JSON.stringify(FiliTheme.ran));
                FiliChat.receive({ ev: "history", id: "s2", items: [{ ev: "msg", id: "s2", role: "assistant", text: "Avant" }] });
                ok(FiliChat.log.length === 1 && FiliChat.items["s1"].length === 3, "fili-chat: historique par session");
                // Permission demandée: carte dans le fil, état « attend », pastille ASK, réponse
                FiliChat.openSession("s1");
                FiliChat.receive({ ev: "state", id: "s1", state: "working" });
                FiliChat.receive({ ev: "ask", id: "s1", rid: "r1", tool: "Bash", summary: "sudo sv restart iwd", status: "pending" });
                FiliChat.receive({ ev: "state", id: "s1", state: "waiting" });
                ok(FiliChat.log[FiliChat.log.length - 1].kind === "ask" && FiliChat.attention === "waiting" && FiliChat.working, "fili-chat: permission demandée (carte, attend, ASK)", FiliChat.attention);
                ok(BarState.aiChat(BarState.aiFor({ sessions: [] }, null, {}), FiliChat.attention, FiliChat.busy).text.endsWith(" ASK"), "fili-chat: pastille IA ASK");
                FiliTheme.ran = [];
                FiliChat.answerFirst(true);
                ok(FiliTheme.ran[0] === 'chat {"op":"answer","rid":"r1","allow":true}', "fili-chat: Ctrl+Retour autorise la première demande", JSON.stringify(FiliTheme.ran));
                FiliChat.receive({ ev: "ask", id: "s1", rid: "r1", tool: "Bash", summary: "sudo sv restart iwd", status: "allowed" });
                ok(FiliChat.log.filter(i => i.kind === "ask").length === 1 && FiliChat.log[FiliChat.log.length - 1].status === "allowed", "fili-chat: la demande tranchée remplace la carte");
                // Réponse finie pendant que le tiroir est caché: DONE jusqu'à l'ouverture
                FiliChat.hide();
                FiliChat.receive({ ev: "state", id: "s1", state: "working" });
                FiliChat.receive({ ev: "state", id: "s1", state: "idle" });
                ok(FiliChat.attention === "done" && BarState.aiChat(BarState.aiFor({ sessions: [] }, null, {}), FiliChat.attention, FiliChat.busy).text.endsWith(" DONE"), "fili-chat: réponse non lue (DONE)", FiliChat.attention);
                // Onglets: rouge (attend) et vert (fini, non lu) se lisent dans states / unread de chaque session
                ok(FiliChat.unread["s1"] === true && FiliChat.tabsOpen, "fili-chat: onglet de s1 vert (fini, non lu)");
                FiliChat.act("sessions");
                ok(!FiliChat.tabsOpen && FiliChat.open, "fili-chat: Sessions… cache les onglets");
                FiliChat.act("sessions");
                ok(FiliChat.tabsOpen, "fili-chat: Sessions… les remontre");
                // Suppression confirmée; les supprimées restent dans la liste complète
                FiliChat.receive({ ev: "sessions", sessions: [{ id: "s1", title: "A", state: "idle", link: "" }, { id: "s2", title: "B", state: "idle", link: "", archived: true }] });
                ok(FiliChat.sessions.length === 1 && FiliChat.allSessions.length === 2, "fili-chat: les supprimées sont hors des onglets mais dans la liste complète");
                FiliChat.askArchive("s1");
                ok(FiliChat.confirmId === "s1", "fili-chat: supprimer demande confirmation");
                FiliChat.confirmArchive(false);
                ok(FiliChat.confirmId === "" && FiliChat.sessions.length === 1, "fili-chat: annuler garde la session");
                FiliChat.receive({ ev: "sessions", sessions: [{ id: "s1", title: "A", state: "idle", link: "", icon: 0xF2001 }] });
                ok(FiliChat.sessions[0].icon === 0xF2001, "fili-chat: l'icône de sujet choisie par l'IA arrive avec la session");
                FiliChat.receive({ ev: "agent", ok: false });
                ok(!FiliChat.agentOk, "fili-chat: sans agent IA, la bannière d'installation s'affiche");
                FiliChat.receive({ ev: "agent", ok: true });
                ok(FiliChat.agentOk, "fili-chat: agent installé, bannière retirée");
                FiliChat.receive({ ev: "sessions", sessions: [{ id: "s1", title: "A", state: "idle", link: "" }, { id: "s2", title: "B", state: "idle", link: "", archived: true }] });
                // 20 onglets au plus, les plus anciennes restent dans la liste complète; la courante garde son onglet
                FiliChat.receive({ ev: "sessions", sessions: Array.from({ length: 25 }, (_, i) => ({ id: "t" + i, title: "T" + i, state: "idle", link: "", updated: 100 - i })) });
                ok(FiliChat.tabSessions.length === 20 && FiliChat.allSessions.length === 25, "fili-chat: 20 onglets au plus, toutes les sessions dans la liste");
                FiliChat.current = "t24";
                ok(FiliChat.tabSessions.length === 20 && FiliChat.tabSessions.some(x => x.id === "t24"), "fili-chat: la session ouverte depuis la liste garde son onglet");
                FiliChat.receive({ ev: "sessions", sessions: [{ id: "s1", title: "A", state: "idle", link: "" }, { id: "s2", title: "B", state: "idle", link: "", archived: true }] });
                FiliChat.askArchive("s2");
                ok(FiliChat.confirmId === "", "fili-chat: pas de confirmation pour une session déjà supprimée");
                // Contexte (Mod+Y): joint une fois au message
                FiliChat.show();
                ok(FiliChat.attention === "", "fili-chat: ouvrir le tiroir lit la réponse");
                FiliChat.ctx = { window: { app_id: "foot", title: "~" } };
                FiliChat.ctxOn = true;
                ok(FiliChat.ctxLabel === "foot · ~", "fili-chat: puce de contexte", FiliChat.ctxLabel);
                FiliTheme.ran = [];
                FiliChat.send("ceci");
                ok(FiliTheme.ran[0] === 'chat {"op":"link","id":"s1","key":"foot"}' && FiliTheme.ran[1] === 'chat {"op":"send","id":"s1","text":"ceci","context":true}' && !FiliChat.ctxOn, "fili-chat: le contexte part avec le message, une fois (et lie la session)", JSON.stringify(FiliTheme.ran));
                FiliChat.setMode("float");
                FiliShell.popupOpened("panel");
                ok(!FiliChat.open, "fili-chat: flottant, fermé quand un panneau de la barre s'ouvre");
                FiliChat.setMode("dock");
            },
            // fili-chat: présentation (flottant / ancré), largeur, renommage
            () => {
                FiliTheme.ran = [];
                ok(FiliChat.mode === "dock" && FiliChat.dock && FiliChat.viewWidth === 440, "fili-chat: ancré, 440 px par défaut", FiliChat.mode);
                FiliChat.show();
                FiliShell.popupOpened("panel");
                ok(FiliChat.open, "fili-chat: ancré, un panneau de la barre ne le ferme pas");
                FiliChat.act("width-wide");
                ok(FiliChat.viewWidth === 560 && FiliChat.dock && FiliTheme.ran[0] === "chat-view dock 560", "fili-chat: largeur large", JSON.stringify(FiliTheme.ran));
                FiliChat.act("float");
                ok(!FiliChat.dock && FiliChat.viewWidth === 560 && FiliTheme.ran[1] === "chat-view float 560", "fili-chat: menu View > flottant, choix gardé", JSON.stringify(FiliTheme.ran));
                FiliChat.act("width-medium");
                FiliShell.popupOpened("panel");
                ok(!FiliChat.open, "fili-chat: flottant, un panneau de la barre le ferme");
                FiliChat.act("dock");
                ok(FiliChat.dock, "fili-chat: menu View > ancré");
                FiliChat.receive({ ev: "sessions", sessions: [{ id: "s1", title: "bonjour", state: "idle", updated: 1 }] });
                FiliChat.current = "s1";
                FiliTheme.ran = [];
                FiliChat.act("rename");
                ok(FiliChat.open && FiliChat.renaming, "fili-chat: Renommer ouvre le champ de titre");
                FiliChat.commitRename("  Wi-Fi  ");
                ok(!FiliChat.renaming && FiliTheme.ran[0] === 'chat {"op":"rename","id":"s1","title":"Wi-Fi"}', "fili-chat: renommage envoyé au démon", JSON.stringify(FiliTheme.ran));
                FiliChat.hide();
                FiliChat.act("toggle");
                ok(FiliChat.open, "fili-chat: act toggle");
                FiliChat.act("close");
            },
            // fili-chat: sessions liées aux applications (follow = "app"): reprise à l'ouverture, lien à l'envoi, nouvelle session liée
            () => {
                FiliChat.hide();
                FiliChat.receive({ ev: "sessions", sessions: [{ id: "a1", title: "Chrome", state: "idle", updated: 3, link: "google-chrome" }, { id: "a2", title: "Terminal", state: "idle", updated: 2, link: "foot" }, { id: "a3", title: "libre", state: "idle", updated: 1, link: "" }] });
                FiliChat.current = "a3";
                FiliChat.items = Object.assign({}, FiliChat.items, { a1: [], a2: [], a3: [] });
                ok(FiliChat.follow === "app" && FiliChat.linkKey({ window: { app_id: "foot", title: "~" } }) === "foot", "fili-chat: follow = app par défaut, clé = app_id", FiliChat.follow);
                // Ouverture: le contexte (application active) et la liste sont là -> la session liée est reprise
                FiliTheme.ran = [];
                FiliChat.show();
                FiliChat.ctx = { window: { app_id: "google-chrome", title: "Toyota" } };
                FiliChat.ctxReady = true;
                FiliChat.sessionsFresh = true;
                FiliChat.tryFollow();
                ok(FiliChat.current === "a1", "fili-chat: l'ouverture reprend la session liée à l'application active", FiliChat.current);
                // Pas de reprise pendant que le tiroir est ouvert (changement de fenêtre), ni si le tour travaille
                FiliChat.ctx = { window: { app_id: "foot", title: "~" } };
                FiliChat.tryFollow();
                ok(FiliChat.current === "a1", "fili-chat: un changement de fenêtre tiroir ouvert ne change pas de session");
                FiliChat.hide();
                FiliChat.receive({ ev: "state", id: "a1", state: "working" });
                FiliChat.show();
                FiliChat.ctx = { window: { app_id: "foot", title: "~" } };
                FiliChat.ctxReady = true;
                FiliChat.sessionsFresh = true;
                FiliChat.tryFollow();
                ok(FiliChat.current === "a1", "fili-chat: pas de reprise pendant un tour en cours");
                FiliChat.receive({ ev: "state", id: "a1", state: "idle" });
                // Application sans session liée: la session courante reste
                FiliChat.hide();
                FiliChat.show();
                FiliChat.ctx = { window: { app_id: "niri-inconnu", title: "" } };
                FiliChat.ctxReady = true;
                FiliChat.sessionsFresh = true;
                FiliChat.tryFollow();
                ok(FiliChat.current === "a1", "fili-chat: application sans session liée, la dernière reste");
                // Lien à l'envoi: session sans lien + puce de contexte
                FiliChat.openSession("a3");
                FiliChat.ctx = { window: { app_id: "foot", title: "~" } };
                FiliChat.ctxOn = true;
                FiliTheme.ran = [];
                FiliChat.send("bonjour");
                ok(FiliTheme.ran[0] === 'chat {"op":"link","id":"a3","key":"foot"}' && FiliTheme.ran[1].includes('"op":"send"'), "fili-chat: envoyer avec la puce de contexte lie la session", JSON.stringify(FiliTheme.ran));
                FiliChat.receive({ ev: "state", id: "a3", state: "working" });
                FiliChat.receive({ ev: "state", id: "a3", state: "idle" });
                // Déjà liée: pas de second lien; puce retirée: pas de lien
                FiliChat.receive({ ev: "sessions", sessions: [{ id: "a1", title: "Chrome", state: "idle", updated: 3, link: "google-chrome" }, { id: "a3", title: "libre", state: "idle", updated: 1, link: "foot" }] });
                FiliChat.ctxOn = true;
                FiliTheme.ran = [];
                FiliChat.send("encore");
                ok(FiliTheme.ran.length === 1 && FiliTheme.ran[0].includes('"op":"send"'), "fili-chat: une session déjà liée ne se relie pas", JSON.stringify(FiliTheme.ran));
                // Nouvelle session pour cette application
                FiliChat.receive({ ev: "state", id: "a3", state: "working" });
                FiliChat.receive({ ev: "state", id: "a3", state: "idle" });
                FiliChat.ctx = { window: { app_id: "fili-file", title: "Casier" } };
                FiliTheme.ran = [];
                FiliChat.act("new-here");
                ok(FiliTheme.ran[0] === 'chat {"op":"new"}' && FiliChat.pendingLink === "fili-file", "fili-chat: Nouvelle session pour cette application", JSON.stringify(FiliTheme.ran));
                FiliChat.receive({ ev: "created", id: "a4" });
                ok(FiliTheme.ran[1] === 'chat {"op":"link","id":"a4","key":"fili-file"}' && FiliChat.pendingLink === "", "fili-chat: la session créée est liée", JSON.stringify(FiliTheme.ran));
                FiliTheme.ran = [];
                FiliChat.act("unlink");
                ok(FiliTheme.ran[0] === 'chat {"op":"link","id":"a4","key":""}', "fili-chat: Unlink retire le lien", JSON.stringify(FiliTheme.ran));
                FiliChat.hide();
            },
            // fili-chat: son menu remplace celui de la fenêtre quand le tiroir a le focus clavier (sans menus Quitter/Fenêtre de niri)
            wait(() => { FiliChat.show(); FiliChat.focused = true; }, () => AppMenu.appName === "Rob" && AppMenu.menus.length > 0, 5000),
            () => {
                const labels = AppMenu.menus.map(m => m.label);
                ok(labels.join() === "Rob,Session,View", "fili-chat: menu de la fili-bar = Rob, Session, View (ni Fenêtre ni Quitter)", labels.join());
                ok(AppMenu.menus[0].children.some(c => c.label === "About Rob" && c.exec === "fili-shell chat about"), "fili-chat: menu Rob > About Rob");
                const session = AppMenu.menus.find(m => m.label === "Session");
                ok(session && session.children.some(c => c.label === "Rename Session…" && c.keys === "F2" && c.exec === "fili-shell chat rename"), "fili-chat: Session > Rename Session… (F2)");
                // Appui sur un titre de la barre: niri rend le focus à la fenêtre précédente, le menu du chat reste
                AppMenu.pressTitle();
                FiliChat.focused = false;
                ok(AppMenu.chatFocus && AppMenu.appId === "fili-chat", "fili-chat: le menu reste pendant l'appui sur un titre (focus rendu à la fenêtre)");
            },
            wait(() => {}, () => !AppMenu.chatFocus, 5000),
            () => {
                ok(AppMenu.appId !== "fili-chat", "fili-chat: sans focus ni menu ouvert, la barre revient à la fenêtre active");
                FiliChat.hide();
            },
            // fili-chat: fiche « À propos de Rob » (icône robot, nom Rob), fermée par un autre panneau
            () => {
                FiliChat.hide();
                FiliChat.act("about");
                ok(FiliChatAbout.open && FiliChatAbout.name === "Rob" && FiliChatAbout.icon.codePointAt(0) === 0xf06a9, "fili-chat: À propos de Rob (icône robot, nom Rob)");
                const labels = FiliChatAbout.rows.map(r => r[0]);
                ok(["Also known as", "Part of", "Agent", "Model", "Sessions", "View", "Follow", "Settings"].every(l => labels.includes(l)) && FiliChatAbout.rows.every(r => r[1] !== ""), "fili-chat: fiche = aka, appartenance, agent, modèle, sessions, présentation, lien, réglages", labels.join());
                ok(FiliChatAbout.rows[0][0] === "Also known as" && FiliChatAbout.rows[0][1] === "fili-chat", "fili-chat: la fiche dit « aka fili-chat »");
                ok(!FiliChat.open, "fili-chat: la fiche n'ouvre pas le tiroir");
                FiliShell.popupOpened("panel");
                ok(!FiliChatAbout.open, "fili-chat: fiche fermée par un autre panneau");
                FiliChatAbout.toggle();
                ok(FiliChatAbout.open, "fili-chat: la fiche se rouvre");
                FiliChatAbout.close();
            },
            // FiliI18n: tests en anglais (LANG=C.UTF-8, run.sh); catalogue français chargé à la main
            () => {
                ok(FiliI18n.lang === "en" && FiliI18n.tr("Workspace %1", 3) === "Workspace 3" && FiliI18n.num(1.5, 1) === "1.5", "FiliI18n: anglais sans catalogue, %1 remplacé", FiliI18n.lang);
                const saved = FiliI18n.catalog;
                FiliI18n.catalog = t.frCatalog;
                ok(FiliI18n.tr("Workspace %1", 3) === "Espace 3" && FiliI18n.num(1.5, 1) === "1,5" && FiliI18n.tr("not in catalog") === "not in catalog", "FiliI18n: catalogue fr.json (traduction, séparateur décimal, repli anglais)", FiliI18n.tr("Workspace %1", 3));
                FiliI18n.catalog = saved;
            },
            // fili-lang: changement de langue en direct (état dans $XDG_STATE_HOME, locale.kdl de niri dans un dossier de test)
            wait(() => t.shell('XDG_CONFIG_HOME="$XDG_STATE_HOME/cfg" "$0" set fr && cat "$XDG_STATE_HOME/filigrane/locale" "$XDG_STATE_HOME/cfg/niri/locale.kdl"'.replace('"$0"', t.bin + "/fili-lang")), () => t.shellOut !== null),
            () => ok(t.shellOut.code === 0 && t.shellOut.out.indexOf("fr_") >= 0 && t.shellOut.out.indexOf("Généré par fili-lang") >= 0, "fili-lang set fr: choix enregistré, locale.kdl de niri écrit", t.shellOut.out),
            wait(() => {}, () => FiliI18n.lang === "fr", 5000),
            () => ok(FiliI18n.lang === "fr" && FiliI18n.tr("Workspace %1", 3) === "Espace 3", "FiliI18n: suit fili-lang en direct (fr)", FiliI18n.lang),
            wait(() => t.shell(t.bin + "/fili-lang list"), () => t.shellOut !== null),
            () => {
                let l = [];
                try {
                    l = JSON.parse(t.shellOut.out);
                } catch (e) {}
                ok(l.some(x => x.code === "en") && l.some(x => x.code === "fr" && x.current && x.name === "Français"), "fili-lang list: en et fr, fr en cours", t.shellOut.out);
            },
            wait(() => t.shell('XDG_CONFIG_HOME="$XDG_STATE_HOME/cfg" ' + t.bin + "/fili-lang set system"), () => t.shellOut !== null),
            wait(() => {}, () => FiliI18n.lang === "en", 5000),
            () => ok(FiliI18n.lang === "en" && FiliI18n.tr("Workspace %1", 3) === "Workspace 3", "fili-lang set system: retour à la langue du système (en)", FiliI18n.lang),
            wait(() => t.shell(t.bin + "/fili-net list"), () => t.shellOut !== null, 15000),
            () => {
                let n = null;
                try {
                    n = JSON.parse(t.shellOut.out.trim().split("\n")[0]);
                } catch (e) {}
                ok(n && typeof n.device === "string" && Array.isArray(n.networks), "fili-net list: JSON { device, networks }", t.shellOut.out);
            },
        ];
        tick.start();
    }
}
