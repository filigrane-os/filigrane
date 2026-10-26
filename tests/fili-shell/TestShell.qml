// Tests du fili-shell, chargés à la place de shell.qml par tests/fili-shell/run.sh (FILI_TEST=1: fenêtres masquées,
// commandes des clics enregistrées dans FiliTheme.ran au lieu d'être lancées). Sortie TAP: "ok N - ..." /
// "not ok N - ...", puis "# fin: X échec(s)".
// Couvre: clics de chaque module de la fili-bar, canal fili-shell (bar refresh, notification, launcher),
// fili-launcher (découpe des lignes, filtre, réponses), fili-notification (bulles, croix, historique),
// fili-tooltip et fili-info.
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

    // Commande shell de test (client fili-shell, fili-info...), sortie et code récupérés
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
                expectClick("timer", L, "bar-timer click");
                expectClick("timer", R, "bar-timer add");
                expectClick("idle", L, "bar-toggle idle");
                expectClick("night", L, "bar-toggle night");
                expectClick("backup", L, "bar-backup run");
                expectClick("tray-handle", L, "bar-tray toggle");
                expectClick("clock", L, "calendar.proton.me");
                // Ressources, son, Bluetooth, réseau, batterie: clic = fili-panel (vue ouverte, puis fermée)
                for (const [name, view] of [["cpu", "monitor"], ["temp", "monitor"], ["mem", "monitor"], ["disk", "monitor"],
                                            ["volume", "audio"], ["bluetooth", "bluetooth"], ["network", "network"], ["power", "power"]]) {
                    act(name, L);
                    ok(FiliPanel.view === view, "fili-bar " + name + ", clic -> fili-panel " + view, FiliPanel.view);
                    FiliPanel.close();
                }
                expectClick("volume", R, "wiremix --tab output");
                expectClick("keyboard", L, "switch-layout next");
                expectClick("display", L, "wdisplays");
                expectClick("display", "up", "brightnessctl -q set 5%+");
                expectClick("display", "down", "brightnessctl -q set 5%-");
                expectClick("network", R, "menu network");
                expectClick("power", R, "menu system");
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
            wait(() => t.shell('for f in menu bar-alert bar-toggle bar-news bar-update bar-timer bar-backup bar-tray bar-tui webapp focus-or-run fili-info fili-shell; do [ -x "' + t.bin + '/$f" ] || echo "$f"; done'),
                 () => t.shellOut !== null),
            () => ok(t.shellOut.out.trim() === "", "scripts appelés par la fili-bar présents dans " + t.bin, t.shellOut.out.trim()),
            // impala, bluetui, wiremix... installés
            wait(() => t.shell('for c in impala bluetui wiremix htop foot wdisplays brightnessctl niri jq; do command -v $c >/dev/null || echo $c; done'),
                 () => t.shellOut !== null),
            () => ok(t.shellOut.out.trim() === "", "programmes lancés par la fili-bar installés", t.shellOut.out.trim()),

            // ───── canal fili-shell ─────
            wait(() => t.shell(t.bin + "/fili-shell bar refresh 20 21"), () => t.refreshed.indexOf(20) >= 0 && t.refreshed.indexOf(21) >= 0),
            () => ok(true, "fili-shell bar refresh 20 21 -> signaux reçus"),
            wait(() => t.shell(t.bin + "/fili-shell notification dnd on"), () => FiliNotification.dnd === true),
            () => ok(true, "fili-shell notification dnd on"),
            wait(() => t.shell(t.bin + "/fili-shell notification dnd off"), () => FiliNotification.dnd === false),
            () => ok(true, "fili-shell notification dnd off"),

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
            wait(() => t.shell(t.bin + "/fili-shell notification dismiss 'Résumé test'"), () => FiliNotification.popups.length === 0),
            () => ok(FiliNotification.history.length === 1 && FiliNotification.history[0].summary === "Résumé test", "fili-notification fermée -> historique"),
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
                FiliNotification.dnd = false;
            },

            // ───── fili-tooltip ─────
            () => {
                const c = FiliTooltip.normalize("<tt>CPU &amp; mémoire</tt>");
                ok(c.text === "CPU & mémoire" && c.mono === true, "fili-tooltip texte Pango -> texte brut à chasse fixe", JSON.stringify(c));
                ok(FiliTooltip.empty({}) && !FiliTooltip.empty({ title: "x" }), "fili-tooltip fiche vide");
            },

            // ───── fili-info ─────
            wait(() => t.shell("for x in network power display; do " + t.bin + "/fili-info $x; done"), () => t.shellOut !== null, 10000),
            () => {
                const lines = t.shellOut.out.trim().split("\n");
                ok(lines.length === 3, "fili-info: trois fiches", t.shellOut.out);
                for (const [i, topic] of ["network", "power", "display"].entries()) {
                    let c = null;
                    try {
                        c = JSON.parse(lines[i]);
                    } catch (e) {}
                    ok(c && c.title && Array.isArray(c.rows) && c.hint, "fili-info " + topic + ": titre, lignes, aide", lines[i]);
                }
            },

            // ───── fili-panel: chaque vue se charge sans erreur, puis fili-net et fili-info monitor ─────
            () => {
                for (const v of ["network", "audio", "bluetooth", "power", "monitor"]) {
                    FiliPanel.view = v;
                    ok(FiliPanel.loaded !== null, "fili-panel " + v + ": vue chargée");
                    FiliPanel.close();
                    ok(FiliPanel.loaded === null, "fili-panel " + v + ": vue libérée à la fermeture");
                }
            },
            // Aucune fili-tooltip tant qu'un fili-panel est ouvert
            () => {
                const it = t.find(t.bar.contentItem, "volume");
                FiliPanel.summon("audio");
                FiliTooltip.show(it, { title: "x" });
                ok(FiliTooltip.target === null, "fili-tooltip: masquée quand un fili-panel est ouvert");
                FiliPanel.close();
                FiliTooltip.show(it, { title: "x" });
                ok(FiliTooltip.target === it, "fili-tooltip: de nouveau permise panneau fermé");
                FiliTooltip.hide();
            },
            // Interrupteurs à droite du titre (Wi-Fi, Bluetooth): présents, Bluetooth grisé sans adaptateur
            () => {
                for (const [v, name] of [["network", "wifi-power"], ["bluetooth", "power"]]) {
                    FiliPanel.view = v;
                    const sw = t.find(FiliPanel.loaded, name);
                    ok(sw && sw.hasOwnProperty("checked"), "fili-panel " + v + ": interrupteur à droite du titre", sw ? "" : "introuvable");
                }
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
            wait(() => t.shell(t.bin + "/fili-net list; " + t.bin + "/fili-info monitor"), () => t.shellOut !== null, 15000),
            () => {
                const lines = t.shellOut.out.trim().split("\n");
                let n = null, m = null;
                try {
                    n = JSON.parse(lines[0]);
                    m = JSON.parse(lines[1]);
                } catch (e) {}
                ok(n && typeof n.device === "string" && Array.isArray(n.networks), "fili-net list: JSON { device, networks }", lines[0]);
                ok(m && m.title && m.rows.length > 4, "fili-info monitor: fiche", lines[1]);
            },
        ];
        tick.start();
    }
}
