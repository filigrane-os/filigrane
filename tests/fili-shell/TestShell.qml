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
                expectClick("window", R, "close-window");
                expectClick("window", M, "close-window");
                expectClick("mail", L, "bar-alert open mail");
                expectClick("whatsapp", L, "bar-alert open whatsapp");
                expectClick("cal", L, "bar-alert open cal");
                expectClick("rec", L, "bar-toggle rec");
                expectClick("air", L, "bar-toggle air");
                expectClick("news", L, "bar-news open");
                expectClick("update", L, "bar-update run");
                expectClick("backup", L, "bar-backup run");
                expectClick("tray-handle", L, "bar-tray toggle");
                expectClick("clock", L, "calendar.proton.me");
                // Ressources, son, Bluetooth, réseau, batterie: clic = fili-panel (vue ouverte, puis fermée)
                for (const [name, view] of [["cpu", "monitor"], ["temp", "monitor"], ["mem", "monitor"], ["disk", "monitor"],
                                            ["volume", "audio"], ["keyboard", "keyboard"], ["display", "display"], ["bluetooth", "bluetooth"], ["network", "network"], ["power", "power"]]) {
                    act(name, L);
                    ok(FiliPanel.view === view, "fili-bar " + name + ", clic -> fili-panel " + view, FiliPanel.view);
                    FiliPanel.close();
                }
                expectClick("volume", R, "wiremix --tab output");
                expectClick("keyboard", M, "switch-layout next");
                expectClick("display", "up", "brightnessctl -q set 5%+");
                expectClick("display", "down", "brightnessctl -q set 5%-");
                expectClick("network", R, "menu network");
                expectClick("power", R, "menu system");
                // Agent IA: clic = session qui attend (ou fili-ai), milieu = nouvelle session, droit = choix de l'agent
                expectClick("ai", L, "fili-ai-session focus");
                expectClick("ai", M, "fili-ai-session new");
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
            },
            // BarState: états lus dans leurs fichiers (alertes, agenda, minuteur, tiroir), sans script
            () => {
                const now = 1000000;
                const m = BarState.alert("mail", "Alice\tBonjour\nBob\tSalut\n", null, now);
                ok(m.text === " 2" && m["class"] === "active" && m.tooltip.startsWith("Alice: Bonjour\nBob: Salut"), "BarState: alerte mail", JSON.stringify(m));
                const c = BarState.alert("cal", (now - 400) + "\t10:00\tVieux\n" + (now + 600) + "\t11:00\tRéunion\n", null, now);
                ok(c.text === " Réunion 11:00" && c.tooltip.indexOf("Vieux") < 0, "BarState: agenda, événement passé ignoré", JSON.stringify(c));
                ok(BarState.alert("cal", (now - 400) + "\t10:00\tVieux\n", null, now).text === "", "BarState: agenda expiré masqué");
                const w = BarState.alert("whatsapp", "", "3\n", now);
                ok(w.text.endsWith(" 3") && w.tooltip.indexOf("3 unread") >= 0, "BarState: compteur de non-lus prioritaire", JSON.stringify(w));
                ok(BarState.alert("whatsapp", "x\ty\n", "0", now).text === "", "BarState: compteur à 0 masque l'alerte");
                ok(BarState.timerFor("S", now - 65, now).text === " 01:05", "BarState: chronomètre", BarState.timerFor("S", now - 65, now).text);
                const r = BarState.timerFor("T", now + 3700, now);
                ok(r.text === " 1:01:40" && r["class"] === "active", "BarState: minuteur (heures)", r.text);
                ok(BarState.timerFor("T", now - 1, now)["class"] === "done" && BarState.timerFor("", 0, now)["class"] === "idle", "BarState: minuteur écoulé / au repos");
                // Agent IA (fili-ai-session): repos, au travail, question en attente, tour fini sans être regardé
                ok(BarState.aiFor({ sessions: [] }, null, {})["class"] === "off", "BarState: agent IA sans session");
                const lim = { five_hour: { used_percentage: 34.4, resets_at: now + 3600 }, seven_day: { used_percentage: 12 }, seen: Date.now() / 1000 };
                const busy = BarState.aiFor({ sessions: [{ id: "a", state: "working", window: 7, ctx: 42.6, cost: 1.5, model: "Opus" }], limits: lim }, null, { 7: { title: "✳ Icône IA" } });
                ok(busy["class"] === "working" && busy.tooltip.rows[0][0] === "Icône IA" && busy.tooltip.rows[0][1].indexOf("context 43 %") >= 0
                   && busy.tooltip.rows.some(r => r[0] === "5-hour limit" && r[1].startsWith("34 %")), "BarState: agent IA au travail, fiche (titre, contexte, limites)", JSON.stringify(busy));
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
                d.setScale(d.outputs[0], 1.5);
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
