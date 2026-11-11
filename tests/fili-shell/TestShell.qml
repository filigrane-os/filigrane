// Tests of the fili-shell, loaded in place of shell.qml by tests/fili-shell/run.sh (FILI_TEST=1: windows hidden,
// commands of the clicks recorded in FiliTheme.ran instead of being run). TAP output: "ok N - ..." /
// "not ok N - ...", then "# end: X failure(s)".
// Covers: the clicks of every fili-bar module, the fili-shell channel (bar refresh, notification, launcher),
// fili-launcher (line splitting, filter, replies), fili-notification (bubbles, cross, history),
// fili-tooltip, FiliInfo and fili-about.
//@ pragma Env QT_QUICK_BACKEND=software
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import qs
import qs.bar
import qs.bar.modules.alert
import qs.bar.modules.appmenu
import qs.bar.modules.mail

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
    Component { id: alertComp; AlertModule {} }
    Component { id: mailComp; MailModule {} }
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
    function findAll(item, name, out) {
        out = out ?? [];
        if (!item)
            return out;
        if (item.objectName === name)
            out.push(item);
        for (const c of item.children ?? [])
            findAll(c, name, out);
        return out;
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
    // Commands run by a click (button) or the wheel (up/down) on a fili-bar module
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

    // Test shell command (fili-shell client, fili-net...), output and exit code collected
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
    // French catalog of the fili-shell (FiliI18n test)
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

    // Steps: a synchronous function, or { run, until, timeout } that waits for a condition
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
                ok(false, "waiting for: " + (waitFor.name ?? "condition"), "timed out");
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
        console.log("# end: " + failures + " failure(s) out of " + count);
        Qt.callLater(() => Qt.exit(failures ? 1 : 0));
    }

    Component.onCompleted: {
        FiliNotification.dnd;
        FiliLauncher.open;
        FiliShell.fifo;
        const L = Qt.LeftButton, R = Qt.RightButton, M = Qt.MiddleButton;
        steps = [
            wait(() => {}, () => t.bar && t.find(t.bar.contentItem, "network") !== null, 5000),
            // ───── fili-bar: one click per module ─────
            () => {
                expectClick("logo", L, "/menu");
                expectClick("logo", R, "foot");
                expectClick("rec", L, "bar-toggle rec");
                expectClick("air", L, "bar-toggle air");
                expectClick("update", L, "bar-update run");
                expectClick("backup", L, "bar-backup run");
                expectClick("tray-handle", L, "bar-tray toggle");
                // Clock: the click pins the calendar, it no longer opens a calendar web app
                const clk = act("clock", L);
                ok(clk === "", "fili-bar clock, click -> no command (calendar pinned)", JSON.stringify(clk));
                act("clock", L);
                const card = t.find(t.bar.contentItem, "clock").parent.card;
                ok(card.title && card.rows.length >= 3 && card.rows.every(r => r[0] && r[1]), "horloge: fiche (date, heure, fuseau, semaine)", JSON.stringify(card));
                // Resources, sound, Bluetooth, network, battery: click = fili-panel (view open, then closed)
                for (const [name, view] of [["cpu", "monitor"], ["temp", "monitor"], ["mem", "monitor"], ["disk", "monitor"],
                                            ["volume", "audio"], ["keyboard", "keyboard"], ["display", "display"], ["bluetooth", "bluetooth"], ["network", "network"], ["power", "power"], ["ai", "agent"]]) {
                    act(name, L);
                    ok(FiliPanel.view === view, "fili-bar " + name + ", click -> fili-panel " + view, FiliPanel.view);
                    FiliPanel.close();
                }
                // Agent panel: one row per session (click = its window), message of the request, actions
                BarState.aiData = { sessions: [{ id: "a1", state: "waiting", attention: true, window: 7, message: "Bash?", cwd: "/x/proj" }, { id: "b2", state: "idle", cwd: "/x/other" }] };
                FiliPanel.view = "agent";
                const ag = FiliPanel.loaded;
                FiliTheme.ran = [];
                ok(t.findAll(ag, "agent-session").length === 2 && t.find(ag, "agent-message").visible && t.find(ag, "agent-message").text === "Bash?", "fili-panel agent: sessions and request message");
                t.findAll(ag, "agent-session")[0].press(L);
                ok(FiliTheme.ran.join("\n").indexOf("fili-ai-session focus a1") >= 0 && FiliPanel.view === "", "fili-panel agent: click on a session -> its window, panel closed", JSON.stringify(FiliTheme.ran));
                BarState.aiData = { sessions: [], limits: null };
                expectClick("volume", R, "wiremix --tab output");
                expectClick("keyboard", M, "switch-layout next");
                expectClick("display", "up", "brightnessctl -q set 3%+");
                expectClick("display", "down", "brightnessctl -q set 3%-");
                expectClick("network", R, "menu network");
                expectClick("power", R, "menu system");
                // AI agent: click = panel (above), middle and Super+click = what waits (terminal session or fili-ai), right = choose the agent
                expectClick("ai", M, "fili-ai-session focus");
                t.find(t.bar.contentItem, "ai").hover.meta = true;
                expectClick("ai", L, "fili-ai-session focus");
                t.find(t.bar.contentItem, "ai").hover.meta = false;
                expectClick("ai", R, "fili-ai pick");
                // Global theme (~/.config/filigrane/theme.toml): the mode takes precedence over [theme], invalid value ignored, # inside quotes
                const keep = FiliTheme.parsed;
                const was0 = FiliTheme.mode;
                FiliTheme.mode = "dark";
                FiliTheme.parsed = FiliTheme.parseToml("[theme]\nradius_control = 9 # px\nsize = big\ntext = \"#fff\"\n[theme.dark]\nradius_control = 3\n[theme.accents]\nsauge = [\"#111111\", \"#222222\", \"#333333\", \"#444444\"]\n");
                ok(FiliTheme.radiusControl === 3 && FiliTheme.size === 14 && FiliTheme.brume.toString() === "#ffffff" && FiliTheme.accentTones.sauge[0] === "#111111",
                   "global theme: mode wins over [theme], invalid value ignored, accents merged", FiliTheme.radiusControl + " " + FiliTheme.size + " " + FiliTheme.brume);
                FiliTheme.parsed = keep;
                FiliTheme.mode = was0;
                ok(FiliTheme.radiusControl === 6, "global theme: without a file, the defaults return");
                // Bell: click = fili-notification-center, right click = do not disturb (put back as it was)
                const was = FiliNotification.dnd;
                act("notifications", L);
                ok(FiliNotification.centerOpen, "fili-bar notifications, click -> fili-notification-center open");
                act("notifications", L);
                act("notifications", R);
                ok(FiliNotification.dnd !== was, "fili-bar notifications, right click -> do not disturb");
                FiliNotification.dnd = was;
                FiliTheme.ran = [];
            },
            // The commands of the clicks exist (scripts of the repository)
            wait(() => t.shell('for f in menu bar-alert bar-toggle bar-update bar-timer bar-backup bar-tray bar-tui webapp focus-or-run fili-shell bar-stats fili-ai fili-ai-session; do [ -x "' + t.bin + '/$f" ] || echo "$f"; done'),
                 () => t.shellOut !== null),
            () => ok(t.shellOut.out.trim() === "", "scripts called by the fili-bar present in " + t.bin, t.shellOut.out.trim()),
            // impala, bluetui, wiremix... installed
            wait(() => t.shell('for c in impala bluetui wiremix htop foot brightnessctl niri jq; do command -v $c >/dev/null || echo $c; done'),
                 () => t.shellOut !== null),
            () => ok(t.shellOut.out.trim() === "", "programs launched by the fili-bar installed", t.shellOut.out.trim()),

            // ───── fili-shell channel ─────
            wait(() => t.shell(t.bin + "/fili-shell bar refresh 20 21"), () => t.refreshed.indexOf(20) >= 0 && t.refreshed.indexOf(21) >= 0),
            () => ok(true, "fili-shell bar refresh 20 21 -> signals received"),
            wait(() => t.shell(t.bin + "/fili-shell notification dnd on"), () => FiliNotification.dnd === true),
            () => ok(true, "fili-shell notification dnd on"),
            wait(() => t.shell(t.bin + "/fili-shell notification dnd off"), () => FiliNotification.dnd === false),
            () => ok(true, "fili-shell notification dnd off"),
            // bar-stats: pipe reader and modules written without a script (stat NAME JSON)
            wait(() => {}, () => FiliShell.stats.cpu !== undefined && FiliShell.stats.net !== undefined && FiliShell.stats.air !== undefined),
            () => {
                const cpu = t.find(t.bar.contentItem, "cpu");
                ok(cpu && /^\d+%$/.test(cpu.text), "bar-stats: module cpu rempli (stat cpu)", cpu ? cpu.text : "module introuvable");
                ok(t.find(t.bar.contentItem, "network").text !== "", "bar-stats: network module filled (stat net)");
                // Niri: event stream read from the niri socket
                ok(Niri.workspaces.length > 0, "niri: workspaces received over the socket", Niri.workspaces.length);
                // Window of an MPRIS player (right click on the media)
                const mw = { 1: { id: 1, pid: 50, app_id: "chrome", title: "Autre onglet" }, 2: { id: 2, pid: 50, app_id: "chrome", title: "Chanson - YouTube" }, 4: { id: 4, pid: 70, app_id: "chrome-mail.x__-Default", title: "Mail" }, 5: { id: 5, pid: 70, app_id: "google-chrome", title: "Page" }, 3: { id: 3, pid: 60, app_id: "Spotify", title: "Spotify" } };
                ok(Niri.playerWindow(mw, "org.mpris.MediaPlayer2.chromium.instance50", "", "Chanson") === 2, "niri: browser player -> window of the pid whose title contains the track");
                ok(Niri.playerWindow(mw, "org.mpris.MediaPlayer2.chromium.instance50", "", "") === 1, "niri: browser player without a track -> first window of the pid");
                ok(Niri.playerWindow(mw, "org.mpris.MediaPlayer2.chromium.instance70", "", "Vidéo en fond") === 5, "niri: track in a background tab -> browser window, not the PWA");
                ok(Niri.playerWindow(mw, "org.mpris.MediaPlayer2.spotify", "spotify", "x") === 3, "niri: player by desktop entry");
                ok(Niri.playerWindow(mw, "org.mpris.MediaPlayer2.mpv", "mpv", "x") === null, "niri: player without a window -> null");
            },
            // AppMenu (global menu): fallback per application (pid 0 = no AT-SPI request), then simulated AT-SPI menus
            () => {
                Niri.setWindows({ 7: { id: 7, pid: 0, app_id: "foot", title: "foot" } });
                Niri.focusedId = 7;
            },
            wait(() => {}, () => AppMenu.appId === "foot" && AppMenu.source === "fallback" && AppMenu.menus.length === 5),
            () => {
                const labels = AppMenu.menus.map(m => m.label);
                ok(labels.join(",") === "Terminal,Shell,Go,Help,Window", "appmenu: foot -> application, fallback menus, Window", labels.join(","));
                ok(AppMenu.menus[0].children[0].label === "Quit %1", "appmenu: menu de l'application -> Quitter");
                const title = t.find(t.bar.contentItem, "appmenu-1");
                const host = t.find(t.bar.contentItem, "appmenu");
                ok(title && host && host.visible && host.shown, "appmenu: menu titles in the fili-bar", host ? host.visible : "not found");
                AppMenu.openAt(1, title, t.bar);
                ok(AppMenu.open && AppMenu.levels.length === 1 && AppMenu.levels[0][0].label === "New terminal", "appmenu: click on a title -> menu open");
                ok(AppMenu.levels[0][0].keys === "Super+Return", "appmenu: shortcut of a fallback entry = niri bind of the same command", AppMenu.levels[0][0].keys);
                ok(AppMenu.menus[0].children[0].keys === "Super+Q", "appmenu: Quitter -> raccourci de close-window", AppMenu.menus[0].children[0].keys);
                const pb = AppMenu.parseBinds('binds {\n    // Mod+X { nope; }\n    Mod+Ctrl+W hotkey-overlay-title="a" { spawn-sh "$HOME/.local/bin/bar-tui impala"; }\n    Mod+V       { toggle-window-floating; }\n    Mod+1 { focus-workspace 1; }\n    Mod+B { spawn "foot" "-e" "btop"; }\n}\nlayout { Mod+Z { x; } }\n');
                ok(pb["exec:bar-tui impala"] === "Super+Ctrl+W" && pb["niri:toggle-window-floating"] === "Super+V" && pb["niri:focus-workspace 1"] === "Super+1" && pb["exec:foot -e btop"] === "Super+B" && Object.keys(pb).length === 4, "appmenu: reading the niri binds (spawn, spawn-sh, actions, arguments, comments)", JSON.stringify(pb));
                FiliTheme.ran = [];
                AppMenu.activate(AppMenu.levels[0][0]);
                ok(!AppMenu.open && FiliTheme.ran.join() === "foot", "appmenu: entry -> command run, menu closed", FiliTheme.ran.join());
                AppMenu.openAt(4, title, t.bar);
                const win = AppMenu.levels[0];
                ok(win[0].label === "Close window" && win[1].kind === "sep", "appmenu: Window menu -> niri actions, separators");
                FiliTheme.ran = [];
                AppMenu.activate(win[0]);
                ok(FiliTheme.ran.join() === "niri msg action close-window", "appmenu: action niri", FiliTheme.ran.join());
                // Keyboard: fili-shell appmenu opens the first menu from the keyboard, a second call closes it
                AppMenu.summon("toggle");
                ok(AppMenu.open && AppMenu.keyboard && AppMenu.openIndex === 0 && AppMenu.sel[0] === 0, "appmenu keyboard: fili-shell appmenu -> first menu, first item selected", JSON.stringify(AppMenu.sel));
                AppMenu.summon("toggle");
                ok(!AppMenu.open && !AppMenu.keyboard, "appmenu clavier: second appel -> fermeture");
                // Other applications: fallback file by app-id, otherwise the common menus
                Niri.setWindows({ 8: { id: 8, pid: 0, app_id: "google-chrome", title: "Page" } });
                Niri.focusedId = 8;
            },
            wait(() => {}, () => AppMenu.appId === "google-chrome" && AppMenu.menus.length === 6),
            () => {
                ok(AppMenu.menus[0].label === "Chrome" && AppMenu.menus[1].children[0].exec === "google-chrome-stable --new-window", "appmenu: Chrome -> liens utiles", AppMenu.menus.map(m => m.label).join(","));
                Niri.setWindows({ 10: { id: 10, pid: 4242, app_id: "fili-file", title: "user" } });
                Niri.focusedId = 10;
            },
            wait(() => {}, () => AppMenu.appId === "fili-file" && AppMenu.menus.length === 6),
            () => {
                ok(AppMenu.source === "fallback" && AppMenu.noMenu["fili-file"] === undefined, "appmenu: a fallback file takes precedence over AT-SPI (no request)", AppMenu.source);
                ok(AppMenu.menus.map(m => m.label).join() === "Casier,File,Edit,View,Go,Window" && AppMenu.menus[1].children[0].keys === "Super+E", "appmenu: fili-file -> bar menus, shortcut from the niri bind", AppMenu.menus.map(m => m.label).join());
                const copy = AppMenu.menus[2].children[3];
                ok(copy.label === "Copy" && copy.keys === "Ctrl+C", "appmenu: fili-file -> Copy with its shortcut", copy.label + " " + copy.keys);
                ok(copy.enabled === true, "appmenu: fili-file -> Copy enabled by default");
                // The application publishes the impossible commands (nothing selected): the bar greys them out, then re-enables them
                AppMenu.onState(JSON.stringify({ disabled: ["copy", "cut", "trash"] }));
                const grey = AppMenu.menus[2].children;
                ok(grey[3].label === "Copy" && grey[3].enabled === false && grey[2].enabled === false && grey[4].label === "Paste" && grey[4].enabled === true, "appmenu: fili-file -> impossible commands greyed out (Cut, Copy), the others enabled (Paste)", grey.map(g => g.enabled).join());
                AppMenu.onState("pas du json");
                ok(AppMenu.menus[2].children[3].enabled === true, "appmenu: unreadable state -> everything enabled");
                FiliTheme.ran = [];
                AppMenu.openAt(2, t.find(t.bar.contentItem, "appmenu-2"), t.bar);
                AppMenu.activate(copy);
                ok(FiliTheme.ran.join() === "fili-file ctl --pid 4242 action copy", "appmenu: control command targeting the window process (%pid)", FiliTheme.ran.join());
                ok(AppMenu.menus[4].children[8].exec === 'fili-file ctl --pid %pid goto "$HOME/Documents"', "appmenu: fili-file -> go to a folder through fili-file ctl goto");
                // "…": the menus that do not fit in the free space go into a title, as submenus
                const h = t.find(t.bar.contentItem, "appmenu");
                h.maxWidth = 200;
                ok(h.fit >= 1 && h.fit < 6 && h.overflow && h.titleAt(h.fit) === t.find(t.bar.contentItem, "appmenu-more"), "appmenu: reduced room -> first titles and \u201c…\u201d", "fit " + h.fit);
                AppMenu.openAt(h.fit, h.titleAt(h.fit), t.bar, h);
                ok(AppMenu.more && AppMenu.levels[0].length === 6 - h.fit && AppMenu.levels[0][0].label === AppMenu.menus[h.fit].label, "appmenu: \u201c…\u201d -> list of the remaining menus", AppMenu.levels[0].length);
                AppMenu.enter(0, AppMenu.levels[0][0], 0, 0);
                ok(AppMenu.levels.length === 2 && AppMenu.levels[1] === AppMenu.menus[h.fit].children || AppMenu.levels[1].length === AppMenu.menus[h.fit].children.length, "appmenu: \u201c…\u201d -> a menu opens as a submenu");
                AppMenu.close();
                ok(!AppMenu.more, "appmenu: \u201c…\u201d closed again");
                h.maxWidth = 100000;
                ok(!h.overflow && h.fit === 6 && h.titleAt(6) === null, "appmenu: enough room -> all the titles, no \u201c…\u201d", "fit " + h.fit);
                Niri.setWindows({ 9: { id: 9, pid: 0, app_id: "org.exemple.Inconnu", title: "x" } });
                Niri.focusedId = 9;
            },
            wait(() => {}, () => AppMenu.appId === "org.exemple.Inconnu" && AppMenu.menus.length === 2),
            () => {
                ok(AppMenu.menus.map(m => m.label).join() === "Inconnu,Window", "appmenu: unknown application -> name taken from the app-id, Window menu", AppMenu.menus.map(m => m.label).join());
                // Answer of fili-appmenu: lazy GTK3 menu, AT-SPI entry
                AppMenu.pending = true;
                AppMenu.onMenu(AppMenu.gen, JSON.stringify({ items: [
                    { label: "File", kind: "sub", enabled: true, check: 0, svc: ":1.2", path: "/m/1", children: [] },
                    { label: "Edit", kind: "sub", enabled: true, check: 0, svc: ":1.2", path: "/m/2", children: [
                        { label: "Copy", kind: "item", enabled: true, check: 0, keys: "Ctrl+C", svc: ":1.2", path: "/m/3", children: [] },
                        { label: "", kind: "sep", enabled: true, check: 0, svc: ":1.2", path: "/m/4", children: [] },
                        { label: "Wrap", kind: "item", enabled: false, check: 2, svc: ":1.2", path: "/m/5", children: [] },
                        { label: "Find", kind: "sub", enabled: true, check: 0, svc: ":1.2", path: "/m/6", children: [
                            { label: "Next", kind: "item", enabled: true, check: 0, svc: ":1.2", path: "/m/7", children: [] }] }] }] }));
                ok(AppMenu.source === "atspi" && AppMenu.menus.map(m => m.label).join() === "Inconnu,File,Edit,Window", "appmenu: AT-SPI menus -> between the application menu and Window", AppMenu.menus.map(m => m.label).join());
                AppMenu.openAt(2, t.find(t.bar.contentItem, "appmenu-2"), t.bar);
                const edit = AppMenu.levels[0];
                ok(edit.length === 4 && edit[1].kind === "sep" && edit[2].check === 2 && !edit[2].enabled && edit[3].kind === "sub", "appmenu: AT-SPI menu -> separator, checked box, greyed-out entry, submenu");
                ok(edit[0].keys === "Ctrl+C" && edit[2].keys === "", "appmenu: shortcut of an AT-SPI entry kept", edit[0].keys);
                FiliTheme.ran = [];
                AppMenu.activate(edit[2]);
                ok(AppMenu.open && FiliTheme.ran.length === 0, "appmenu: greyed-out entry -> nothing");
                AppMenu.activate(edit[0]);
                ok(FiliTheme.ran.join() === FiliTheme.bin + "/fili-appmenu do :1.2 /m/3", "appmenu: AT-SPI entry -> fili-appmenu do", FiliTheme.ran.join());
                // Keyboard: ↑/↓ skips separators and greyed-out entries, → opens the submenu, ← closes it
                AppMenu.close();
                AppMenu.openAt(2, t.find(t.bar.contentItem, "appmenu-2"), t.bar);
                AppMenu.keyboard = true;
                AppMenu.keyMove(1);
                ok(AppMenu.sel[0] === 0, "appmenu keyboard: ↓ -> first entry", JSON.stringify(AppMenu.sel));
                AppMenu.keyMove(1);
                ok(AppMenu.sel[0] === 3, "appmenu keyboard: ↓ skips the separator and the greyed-out entry", JSON.stringify(AppMenu.sel));
                AppMenu.keyMove(1);
                ok(AppMenu.sel[0] === 0, "appmenu keyboard: ↓ wraps to the first entry", JSON.stringify(AppMenu.sel));
                AppMenu.keyMove(-1);
                ok(AppMenu.sel[0] === 3, "appmenu keyboard: ↑ goes back to the last entry", JSON.stringify(AppMenu.sel));
                AppMenu.keyRight();
                ok(AppMenu.levels.length === 2 && AppMenu.levels[1][0].label === "Next" && AppMenu.sel[1] === 0, "appmenu keyboard: → opens the submenu, first item selected", JSON.stringify(AppMenu.sel));
                AppMenu.keyLeft();
                ok(AppMenu.levels.length === 1 && AppMenu.openIndex === 2, "appmenu keyboard: ← closes the submenu", AppMenu.levels.length);
                AppMenu.keyLeft();
                ok(AppMenu.openIndex === 1 && AppMenu.keyboard, "appmenu keyboard: ← at the first level -> previous menu (stays in keyboard mode)", AppMenu.openIndex);
                AppMenu.keyRight();
                ok(AppMenu.openIndex === 2, "appmenu keyboard: → on a plain entry -> next menu", AppMenu.openIndex);
                AppMenu.close();
                ok(!AppMenu.open && AppMenu.levels.length === 0 && !AppMenu.keyboard, "appmenu: fermeture");
            },
            // BarState: states read from their files (agenda, timer, drawer), without a script
            () => {
                const now = 1000000;
                // AlertModule (the mail, chat and calendar plugins are instances of it)
                const mk = props => alertComp.createObject(null, props);
                const mail = mk({ kind: "mail", title: "Mail", glyph: "\uf0e0", url: "https://mail.example.org" });
                const m = mail.build("Alice\tBonjour\nBob\tSalut\n", null, now);
                ok(m.text === "\uf0e0 2" && m["class"] === "active" && m.tooltip.title === "Mail" && m.tooltip.rows[0][0] === "Alice" && m.tooltip.rows[0][1] === "Bonjour" && m.tooltip.rows[1][0] === "Bob", "AlertModule: alerte mail", JSON.stringify(m));
                const cal = mk({ kind: "cal", title: "Calendar", glyph: "\uf073", render: (rows, n) => {
                    const live = rows.filter(x => Number(x[0]) >= n - 300).sort((x, y) => Number(x[0]) - Number(y[0]));
                    return live.length ? { text: live[0][2] + " " + live[0][1], rows: live.map(x => [x[1], x[2] ?? ""]) } : null;
                } });
                const c = cal.build((now - 400) + "\t10:00\tVieux\n" + (now + 600) + "\t11:00\tRéunion\n", null, now);
                ok(c.text === "\uf073 Réunion 11:00" && JSON.stringify(c.tooltip).indexOf("Vieux") < 0, "AlertModule: render (agenda), past event ignored", JSON.stringify(c));
                ok(cal.build((now - 400) + "\t10:00\tVieux\n", null, now).text === "", "AlertModule: expired agenda hidden");
                const wa = mk({ kind: "chat", title: "Chat", glyph: "W" });
                const w = wa.build("", "3\n", now);
                ok(w.text === "W 3" && w.tooltip.title === "Chat" && w.tooltip.rows[0][1] === "3", "AlertModule: unread counter takes priority", JSON.stringify(w));
                ok(wa.build("x\ty\n", "0", now).text === "", "AlertModule: counter at 0 hides the alert");
                ok(mail.objectName === "mail" && mail.idleGlyph === "\uf0e0", "AlertModule: objectName = kind, drawer icon = icon");
                // Displayed value (BarScript.value): the alert while there is one, else nothing (drawer folded)
                const live = mk({ kind: "zzz-test", title: "Test", glyph: "T" });
                ok(live.value.text === "" && live.shown.text === "", "AlertModule: without a file, nothing to show", JSON.stringify(live.value));
                live.destroy();
                FiliTheme.ran = [];
                mail.hover.press(Qt.LeftButton);
                ok(FiliTheme.ran.join("\n").indexOf("bar-alert open mail 'https://mail.example.org'") >= 0, "AlertModule: click -> bar-alert open mail URL", JSON.stringify(FiliTheme.ran));
                mail.destroy();
                // The Facteur mail module: an alert of kind "mail" fed by `fili-mail daemon`, click opens the application
                const facteur = mailComp.createObject(null, {});
                const fm = facteur.build("Alice\tBonjour\n", "4\n", now);
                ok(facteur.objectName === "mail" && fm.text === "\uf0e0 4" && fm.tooltip.rows[1][0] === "Alice", "mail module: counter and recent messages", JSON.stringify(fm));
                FiliTheme.ran = [];
                facteur.hover.press(Qt.LeftButton);
                ok(FiliTheme.ran.join("\n").indexOf("fili-mail") >= 0, "mail module: click -> fili-mail", JSON.stringify(FiliTheme.ran));
                facteur.destroy();
                cal.destroy();
                wa.destroy();
                ok(BarState.timerFor("S", now - 65, now).text === " 01:05", "BarState: stopwatch", BarState.timerFor("S", now - 65, now).text);
                const r = BarState.timerFor("T", now + 3700, now);
                ok(r.text === " 1:01:40" && r["class"] === "active", "BarState: minuteur (heures)", r.text);
                ok(BarState.timerFor("T", now - 1, now)["class"] === "done" && BarState.timerFor("", 0, now)["class"] === "idle", "BarState: timer elapsed / idle");
                // AI agent (fili-ai-session): rest, working, question waiting, turn finished without being looked at
                ok(BarState.aiFor({ sessions: [] }, null, {})["class"] === "off", "BarState: AI agent without a session");
                const lim = { five_hour: { used_percentage: 34.4, resets_at: now + 3600 }, seven_day: { used_percentage: 12 }, seen: now };
                const busy = BarState.aiFor({ sessions: [{ id: "a", state: "working", window: 7, ctx: 42.6, cost: 1.5, model: "Opus" }], limits: lim }, null, { 7: { title: "✳ Icône IA" } }, now);
                ok(busy["class"] === "working" && busy.tooltip.rows[0][0] === "Icône IA" && busy.tooltip.rows[0][1].indexOf("context 43 %") >= 0
                   && busy.tooltip.rows.some(r => r[0] === "5-hour limit" && r[1].startsWith("34 %") && Math.abs(r[2].value - 0.344) < 1e-6 && Math.abs(r[2].mark - 0.8) < 0.01), "BarState: AI agent working, card (title, context, limits and gauges)", JSON.stringify(busy));
                const ask = BarState.aiFor({ sessions: [{ id: "a", state: "waiting", attention: true, window: 7, message: "Bash?" }] }, null, {});
                ok(ask.text.endsWith(" ASK") && ask["class"] === "waiting" && ask.tooltip.rows.some(r => r[1] === "Bash?"), "BarState: AI agent waiting (ASK)", JSON.stringify(ask));
                ok(BarState.aiFor({ sessions: [{ id: "a", state: "waiting", attention: true, window: 7 }] }, 7, {})["class"] === "idle", "BarState: AI agent looked at, no longer highlighted");
                ok(BarState.aiFor({ sessions: [{ id: "a", state: "done", attention: true, window: 7 }, { id: "b", state: "idle" }] }, null, {}).text.endsWith(" DONE"), "BarState: AI agent, turn finished (DONE)");
            },
            wait(() => t.shell('echo "S $(( $(date +%s) - 65 ))" > "$XDG_RUNTIME_DIR/bar-timer"; : > "$XDG_RUNTIME_DIR/bar-tray-open"'),
                 () => BarState.timerFile.kind === "S" && BarState.trayOpen),
            () => {
                ok(/ 01:0[5-7]$/.test(BarState.timer.text), "BarState: stopwatch read from bar-timer (FileView)", BarState.timer.text);
                const h = t.find(t.bar.contentItem, "tray-handle");
                ok(h.cls === "open", "BarState: drawer open (bar-tray-open)");
                // Text actually displayed by the module (a Text child), not only its property
                const shown = item => (item.children ?? []).some(c => (typeof c.text === "string" && c.text.indexOf("") >= 0) || shown(c));
                ok(shown(h), "BarState: drawer chevron shown by BarScript (value)");
                FiliTheme.ran = [];
            },
            wait(() => t.shell('echo "T $(( $(date +%s) - 1 ))" > "$XDG_RUNTIME_DIR/bar-timer"'), () => FiliTheme.ran.join("\n").indexOf("bar-timer expire") >= 0),
            () => ok(BarState.timer["class"] === "done", "BarState: timer elapsed -> bar-timer expires", FiliTheme.ran.join(" ")),
            wait(() => t.shell('rm -f "$XDG_RUNTIME_DIR/bar-timer" "$XDG_RUNTIME_DIR/bar-tray-open"'), () => BarState.timerFile.kind === "" && !BarState.trayOpen),
            () => ok(BarState.timer["class"] === "idle" && t.find(t.bar.contentItem, "tray-handle").cls === "", "BarState: files removed -> idle"),
            // Bluetooth: number of connected devices (or OFF / SHARE), no more ON; icon alone without an adapter (CI)
            () => {
                const bt = t.find(t.bar.contentItem, "bluetooth");
                ok(/^[^ ]+( (OFF|SHARE|\d+))?$/.test(bt.text) && (bt.adapter ? bt.text.indexOf(" ") > 0 : bt.text.indexOf(" ") < 0), "fili-bar bluetooth: number of connected devices (icon alone without an adapter)", bt.text);
            },
            // Backup running: blinks through a Timer (opacity toggled every second), not through an animation
            () => BarState.setBackup({ text: "", class: "active", tooltip: "test" }),
            wait(() => {}, () => {
                const row = t.find(t.bar.contentItem, "backup").children.find(c => c.spacing !== undefined);
                return row && row.opacity < 1;
            }, 3000),
            () => {
                const row = t.find(t.bar.contentItem, "backup").children.find(c => c.spacing !== undefined);
                ok(row.opacity === 0.35, "fili-bar backup running: blinks", row.opacity);
                BarState.setBackup({ text: "" });
            },
            wait(() => {}, () => t.find(t.bar.contentItem, "backup").children.find(c => c.spacing !== undefined).opacity === 1, 3000),
            () => ok(true, "fili-bar backup: opacity restored when the blinking stops"),

            // ───── fili-launcher ─────
            () => {
                const p = FiliLauncher.parse("  Applications ›  ‹Mod+D›");
                ok(p.glyph === "" && p.text === "Applications" && p.sub && p.key === "Mod+D", "fili-launcher splits glyph / label / submenu / key", JSON.stringify(p));
                const q = FiliLauncher.parse("Google Chrome");
                ok(q.glyph === "" && q.text === "Google Chrome" && !q.sub && q.key === "", "fili-launcher plain line", JSON.stringify(q));
                ok(FiliLauncher.match("Night light", ["nig"]) !== null && FiliLauncher.match("Night light", ["xyz"]) === null, "fili-launcher match");
                ok(FiliLauncher.match("Réglages", ["regl"]) !== null && FiliLauncher.match("Réglages", ["regl"]).hits.join() === "0,1,2,3" && FiliLauncher.fold("Éé À") === "ee a", "fili-launcher accents ignored (regl -> Réglages)");
                ok(FiliLauncher.match("Casier", ["file"], " files fichiers file ") !== null && FiliLauncher.match("Casier", ["file"], "") === null
                    && FiliLauncher.match("Rob", ["ia"], " ai assistant ia chat ") !== null && FiliLauncher.match("Rob", ["xyz"], " ai assistant ia chat ") === null, "fili-launcher keywords (Casier <- file, Rob <- ia)");
            },
            wait(() => t.shell("printf 'Alpha\\nBeta app\\nGamma › sous\\n' | " + t.bin + "/fili-shell launcher --prompt 'Style › '; echo \"rc=$?\""),
                 () => FiliLauncher.open && FiliLauncher.entries.length === 3),
            () => {
                ok(FiliLauncher.crumb === "STYLE", "fili-launcher fil d'Ariane", FiliLauncher.crumb);
                FiliLauncher.current = 1;
                FiliLauncher.accept();
            },
            wait(() => {}, () => t.shellOut !== null),
            () => ok(t.shellOut.out.trim() === "Beta app\nrc=0", "fili-launcher choice -> output and code 0", JSON.stringify(t.shellOut.out)),
            // Two requests in a row: the second keeps nothing of the first (old asynchronous read bug)
            wait(() => t.shell("printf 'Un\\nDeux\\n' | " + t.bin + "/fili-shell launcher --prompt 'Test › '; echo \"rc=$?\""),
                 () => FiliLauncher.open && FiliLauncher.entries.length === 2 && FiliLauncher.entries[0].text === "Un"),
            () => FiliLauncher.finish(10, ""),
            wait(() => {}, () => t.shellOut !== null),
            () => ok(t.shellOut.out.trim() === "rc=10", "fili-launcher Shift+Backspace -> code 10", JSON.stringify(t.shellOut.out)),
            wait(() => t.shell("printf 'X\\n' | " + t.bin + "/fili-shell launcher --prompt 'T › '; echo \"rc=$?\""), () => FiliLauncher.open),
            () => {
                FiliLauncher.query = "texte libre";
                ok(FiliLauncher.shown.length === 0, "fili-launcher filter with no result");
                FiliLauncher.accept();
            },
            wait(() => {}, () => t.shellOut !== null),
            () => ok(t.shellOut.out.trim() === "texte libre\nrc=0", "fili-launcher typed text without a match", JSON.stringify(t.shellOut.out)),
            wait(() => t.shell("printf 'X\\n' | " + t.bin + "/fili-shell launcher --prompt 'T › ' & sleep 0.5; " + t.bin + "/fili-shell launcher close; echo \"close=$?\"; wait"),
                 () => t.shellOut !== null),
            () => ok(t.shellOut.out.indexOf("close=0") >= 0 && !FiliLauncher.open, "fili-shell launcher close closes the fili-launcher", JSON.stringify(t.shellOut.out)),

            // ───── fili-notification ─────
            wait(() => t.shell("notify-send -a test 'Résumé test' 'Corps du test'"), () => FiliNotification.popups.length === 1),
            () => ok(FiliNotification.popups[0].n.summary === "Résumé test", "fili-notification bubble received"),
            () => ok(FiliTheme.ran.filter(c => c === "sound notification").length === 1, "fili-sound: one sound on the received notification", JSON.stringify(FiliTheme.ran.slice(-3))),
            wait(() => t.shell(t.bin + "/fili-shell notification dismiss 'Résumé test'"), () => FiliNotification.popups.length === 0),
            () => ok(FiliNotification.history.length === 1 && FiliNotification.history[0].summary === "Résumé test", "fili-notification closed -> history"),
            () => ok(typeof FiliNotification.history[0].icon === "string", "fili-notification history: icon kept (string, empty without an icon)"),
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
                ok(FiliNotification.popups.length === 0, "fili-notification do not disturb: no bubble, entry in the history");
                ok(FiliTheme.ran.filter(c => c === "sound notification").length <= 2, "fili-sound: no sound in do not disturb", FiliTheme.ran.filter(c => c.indexOf("sound") === 0).length);
                FiliNotification.dnd = false;
            },
            // Action buttons (notify-send -A): the answer goes back to the app, the bubble stays 60 s to leave time
            wait(() => t.shell("notify-send -a test -t 30000 -A allow=Autoriser -A deny=Refuser 'Question' 'Autoriser ?'"), () => FiliNotification.popups.length === 1),
            () => {
                const n = FiliNotification.popups[0].n;
                ok(FiliNotification.buttons(n).map(a => a.identifier).join() === "allow,deny", "fili-notification: deux boutons d'action", JSON.stringify(FiliNotification.buttons(n).map(a => a.identifier)));
                ok(FiliNotification.timeout(n) === 30000, "fili-notification: a bubble with buttons stays for the requested delay (30 s)", String(FiliNotification.timeout(n)));
                FiliNotification.answer(n, "deny");
            },
            wait(() => {}, () => t.shellOut !== null),
            () => ok(t.shellOut.out.trim() === "deny" && FiliNotification.popups.length === 0, "fili-notification: the reply goes back to notify-send and closes the bubble", JSON.stringify(t.shellOut.out)),
            // fili-sound: charger plugged in (sound only when plugged in), mute settings
            () => {
                FiliTheme.ran = [];
                FiliSound.ac = false;
                FiliSound.acEvent(true);
                ok(FiliTheme.ran.length === 1 && FiliTheme.ran[0] === "sound power-plug", "fili-sound: sound when the charger is plugged in", JSON.stringify(FiliTheme.ran));
                FiliSound.acEvent(true);
                FiliSound.acEvent(false);
                ok(FiliTheme.ran.length === 1, "fili-sound: no repeat and no sound on unplugging", JSON.stringify(FiliTheme.ran));
                FiliSound.set("plug", false);
                FiliSound.acEvent(true);
                ok(FiliTheme.ran.length === 1 && !FiliSound.plug, "fili-sound: charger sound muted", JSON.stringify(FiliTheme.ran));
                FiliSound.set("plug", true);
                FiliSound.set("notify", false);
                FiliSound.notified();
                ok(FiliTheme.ran.length === 1 && !FiliSound.notify, "fili-sound: notification sound muted", JSON.stringify(FiliTheme.ran));
                FiliSound.set("notify", true);
                FiliTheme.ran = [];
                FiliSound.notified("niri");
                ok(FiliTheme.ran.length === 0, "fili-sound: no sound for the screenshot (niri)", JSON.stringify(FiliTheme.ran));
            },

            // ───── fili-tooltip ─────
            () => {
                const c = FiliTooltip.normalize("<tt>CPU &amp; mémoire</tt>");
                ok(c.text === "CPU & mémoire" && c.mono === true, "fili-tooltip Pango text -> plain monospaced text", JSON.stringify(c));
                ok(FiliTooltip.empty({}) && !FiliTooltip.empty({ title: "x" }), "fili-tooltip fiche vide");
            },

            // ───── FiliInfo: cards requested from bar-stats (standard input) or composed (displays, niri socket) ─────
            wait(() => {
                t.cards = {};
                for (const x of ["network", "power", "display", "monitor"])
                    FiliInfo.request(x);
            }, () => ["network", "power", "display", "monitor"].every(x => t.cards[x]), 10000),
            () => {
                for (const topic of ["network", "power", "display"]) {
                    const c = t.cards[topic];
                    ok(c && c.title && Array.isArray(c.rows) && c.hint, "FiliInfo " + topic + ": title, rows, hint", JSON.stringify(c));
                }
                ok(t.cards.monitor.title === "System" && t.cards.monitor.rows.length > 4, "FiliInfo monitor: fiche", JSON.stringify(t.cards.monitor));
                ok(t.cards.display.rows.length > 0, "FiliInfo display: sorties de niri", JSON.stringify(t.cards.display));
            },

            // ───── fili-panel: every view loads without an error, then fili-net ─────
            () => {
                for (const v of ["network", "audio", "bluetooth", "power", "monitor", "keyboard", "display"]) {
                    FiliPanel.view = v;
                    ok(FiliPanel.loaded !== null, "fili-panel " + v + ": view loaded");
                    FiliPanel.close();
                    ok(FiliPanel.loaded === null, "fili-panel " + v + ": view released on close");
                }
            },
            // fili-settings display: fixture of two outputs, snapping, niri commands, confirmation and rollback
            () => {
                FiliSettings.show("display");
                const d = FiliSettings.loaded;
                const mode = (w, h, r) => ({ width: w, height: h, refresh_rate: r, is_preferred: false });
                const out = (name, x, scale, modes) => ({ name, make: "T", model: name, logical: { x, y: 0, width: Math.round(modes[0].width / scale), height: Math.round(modes[0].height / scale), scale, transform: "Normal" }, modes, current_mode: 0, vrr_supported: true, vrr_enabled: false });
                d.outputs = [out("A-1", 0, 2, [mode(2560, 1600, 60001), mode(1920, 1200, 60000), mode(1920, 1200, 120000)]), out("B-1", 1280, 1, [mode(1920, 1080, 60000)])];
                d.sel = "A-1";
                ok(d.active.length === 2 && d.resolutions.length === 2, "fili-settings display: outputs and resolutions", d.resolutions.length);
                ok(d.refreshes.length === 1, "fili-settings display: a single refresh rate, no choice", d.refreshes.length);
                const b = d.outputs[1];
                const p = d.snapPos(b, 1300, 30);
                ok(p.x === 1280 && p.y === 0, "fili-settings display: snapping to the neighbouring edge", JSON.stringify(p));
                const g = d.snapPos(b, 1400, 900);
                ok(g.x === 1400 && g.y === 800 || g.x === 1280, "fili-settings display: never a gap between two outputs (edge to edge)", JSON.stringify(g));
                FiliTheme.ran = [];
                d.setResolution(d.outputs[0], d.resolutions[1]);
                ok(FiliTheme.ran[0] === "niri msg output 'A-1' mode 1920x1200@120.000", "fili-settings display: resolution -> highest refresh rate", JSON.stringify(FiliTheme.ran));
                ok(d.snap !== null && d.secs === 15, "fili-settings display: change to confirm", d.secs);
                d.setTransform(d.outputs[0], "90");
                ok(d.snap.name === "A-1" && d.snap.current_mode === 0, "fili-settings display: the previous state stays the first one", d.snap.current_mode);
                FiliTheme.ran = [];
                d.revert();
                ok(d.snap === null && FiliTheme.ran[0].indexOf("mode 2560x1600@60.001") > 0 && FiliTheme.ran[0].indexOf("position set 0 0") > 0 && FiliTheme.ran[0].indexOf("scale 2") > 0, "fili-settings display: cancel -> previous state", JSON.stringify(FiliTheme.ran));
                FiliTheme.ran = [];
                d.move(b, 1290, 5);
                ok(FiliTheme.ran.length === 0 && !d.dirty, "fili-settings display: position already in place, nothing pending", JSON.stringify(FiliTheme.ran));
                d.move(b, 1500, 400);
                ok(FiliTheme.ran.length === 0 && d.dirty, "fili-settings display: the move is only pending", JSON.stringify(d.pending));
                d.applyLayout();
                ok(FiliTheme.ran[0] === "niri msg output 'A-1' position set 0 0; niri msg output 'B-1' position set 1280 400", "fili-settings display: Apply pins the position of every output (niri re-places the others)", JSON.stringify(FiliTheme.ran));
                ok(!d.dirty && d.snap === null, "fili-settings display: nothing pending after Apply");
                // Two outputs 67 px apart: Apply closes the gap
                d.outputs = [out("A-1", 0, 2, [mode(2560, 1600, 60001)]), out("B-1", 1347, 1, [mode(1920, 1080, 60000)])];
                ok(d.dirty && d.gapped.length === 2, "fili-settings display: gap detected, Apply enabled", JSON.stringify(d.gapped));
                FiliTheme.ran = [];
                d.applyLayout();
                ok(FiliTheme.ran[0] === "niri msg output 'A-1' position set 67 0; niri msg output 'B-1' position set 1347 0", "fili-settings display: Apply closes the gap (A-1 snaps back to B-1)", JSON.stringify(FiliTheme.ran));
                d.outputs = [out("A-1", 0, 2, [mode(2560, 1600, 60001), mode(1920, 1200, 60000), mode(1920, 1200, 120000)]), out("B-1", 1280, 1, [mode(1920, 1080, 60000)])];
                FiliTheme.ran = [];
                d.resetLayout();
                ok(FiliTheme.ran[0] === "niri msg output 'A-1' position set 0 0; niri msg output 'B-1' position set 1280 0", "fili-settings display: Reset aligns the outputs", JSON.stringify(FiliTheme.ran));
                FiliTheme.ran = [];
                d.setScale(d.outputs[0], 1.5);
                ok(FiliTheme.ran[0] === "niri msg output 'A-1' scale 1.5" && d.snap === null, "fili-settings display: scale without confirmation", JSON.stringify(FiliTheme.ran));
                d.keep();
                ok(d.snap === null, "fili-settings display: keep");
                // Connected without a niri output (no graphics pipe left): listed, and it can be turned on
                d.undetected = ["A-1", "C-9"];
                d.sel = "C-9";
                ok(d.undetectedNames.length === 1 && d.undetectedNames[0] === "C-9" && d.cur === null, "fili-settings display: a connected output without niri output is listed", JSON.stringify(d.undetectedNames));
                FiliTheme.ran = [];
                d.turnOnUndetected("C-9");
                ok(FiliTheme.ran[0] === "niri msg output 'C-9' on" && d.enabling === "C-9", "fili-settings display: an output without niri output can be turned on", JSON.stringify(FiliTheme.ran));
                d.undetected = [];
                d.enabling = "";
                FiliSettings.close();
            },
            // fili-settings workspaces: numbering across the displays (left to right), open workspaces, applications
            () => {
                FiliSettings.show("workspaces");
                const d = FiliSettings.loaded;
                const out = (name, x, serial) => ({ name, make: "T", model: "M", serial, logical: { x, y: 0, width: 1920, height: 1080, scale: 1, transform: "Normal" } });
                // B-1 is on the left: it comes first
                d.outputs = [out("A-1", 1920, "a"), out("B-1", 0, "b"), Object.assign(out("C-1", 0, "c"), { logical: null })];
                ok(d.active.map(o => o.name).join() === "B-1,A-1", "fili-settings workspaces: displays that are on, left to right", d.active.map(o => o.name).join());
                FiliTheme.ran = [];
                d.setNumbering(true);
                ok(FiliTheme.ran[0] === FiliTheme.bin + "/fili-app-output numbered 3 'T M b' 3 'T M a'", "fili-settings workspaces: numbering on, 3 per display from the left", JSON.stringify(FiliTheme.ran));
                d.conf = { apps: [], workspaces: [1, 2, 3].map(n => ({ name: String(n), output: "T M b" })).concat([4, 5, 6].map(n => ({ name: String(n), output: "T M a" }))) };
                ok(d.numberedOn && d.countOf(d.active[1]) === 3 && d.rangeOf(d.active[1]) === "4–6", "fili-settings workspaces: counts and range of a display", d.rangeOf(d.active[1]));
                FiliTheme.ran = [];
                d.setCount(d.active[0], 2);
                ok(FiliTheme.ran[0] === FiliTheme.bin + "/fili-app-output numbered 2 'T M b' 3 'T M a'", "fili-settings workspaces: count of one display", JSON.stringify(FiliTheme.ran));
                FiliTheme.ran = [];
                d.setNumbering(false);
                ok(FiliTheme.ran[0] === FiliTheme.bin + "/fili-app-output numbered", "fili-settings workspaces: numbering off", JSON.stringify(FiliTheme.ran));
                // Applications: targets, change, removal, picker of the open windows
                d.conf = { apps: [{ app: "foot", output: "T M z" }, { app: "it's", workspace: "4" }], workspaces: [{ name: "4", output: "T M a" }] };
                const tg = d.targets(d.conf.apps[0]).map(x => x.value);
                ok(tg.join() === "w:4,o:T M z" && d.targetOf(d.conf.apps[1]) === "w:4", "fili-settings workspaces: displays, named workspaces first, then the display already chosen (numbering on)", tg.join());
                // Numbering on: workspaces only (a display stays listed for an application still set on it); labels are models
                const conf0 = d.conf;
                d.conf = { apps: [{ app: "foot", output: "T M z" }, { app: "mpv", output: "T M a" }], workspaces: [{ name: "1", output: "T M b" }, { name: "2", output: "T M a" }] };
                ok(d.targets(d.conf.apps[0]).map(x => x.value).join() === "w:1,w:2,o:T M z" && d.targets(d.conf.apps[1]).map(x => x.value).join() === "w:1,w:2,o:T M a" && d.targets({ app: "x" }).map(x => x.label).join() === "Workspace 1,Workspace 2", "fili-settings workspaces: numbering on lists workspaces, not displays", d.targets({ app: "x" }).map(x => x.label).join());
                ok(d.modelLabel(d.active[0]) === "T M", "fili-settings workspaces: display labelled by its model, not the connector", d.modelLabel(d.active[0]));
                d.conf = conf0;
                // Target of an application: drop-down (PanelSelect), the current one shown, a choice applied
                const sel = t.find(d, "target-foot");
                ok(sel && sel.text === d.displayLabel("T M z") && !sel.opened, "fili-settings workspaces: target as a drop-down showing the current choice", sel ? sel.text : "none");
                sel.open();
                ok(sel.opened && sel.cursor === 1, "fili-settings workspaces: drop-down opens on the current choice", sel.cursor);
                FiliTheme.ran = [];
                sel.move(-1);
                sel.pick(sel.cursor);
                ok(!sel.opened && FiliTheme.ran[0] === FiliTheme.bin + "/fili-app-output set-workspace 'foot' '4'", "fili-settings workspaces: choice in the drop-down applied", JSON.stringify(FiliTheme.ran));
                // Placement buttons next to the drop-down; a second click on the chosen one goes back to tiled
                FiliTheme.ran = [];
                t.find(d, "layout-foot-left").click();
                d.conf = { apps: [{ app: "foot", output: "T M z", layout: "left" }, { app: "mpv", layout: "float" }], workspaces: [] };
                const lf = t.find(d, "layout-foot-left");
                lf.click();
                ok(FiliTheme.ran.join("|") === FiliTheme.bin + "/fili-app-output layout 'foot' left|" + FiliTheme.bin + "/fili-app-output layout 'foot' none" && lf.on, "fili-settings workspaces: placement buttons (left, then back to tiled)", JSON.stringify(FiliTheme.ran));
                ok(t.find(d, "target-mpv").current === "" && t.find(d, "target-mpv").text === FiliI18n.tr("Display that has the focus") && t.find(d, "layout-mpv-float").on, "fili-settings workspaces: an application with only a placement", t.find(d, "target-mpv").text);
                FiliTheme.ran = [];
                d.setTarget("it's", "o:T M a");
                d.setTarget("foot", "w:4");
                d.forget("foot");
                ok(FiliTheme.ran.join("|") === FiliTheme.bin + "/fili-app-output set 'it'\\''s' 'T M a'|" + FiliTheme.bin + "/fili-app-output set-workspace 'foot' '4'|" + FiliTheme.bin + "/fili-app-output forget 'foot'", "fili-settings workspaces: set, set-workspace, forget (quoted)", JSON.stringify(FiliTheme.ran));
                Niri.workspaces = [{ id: 1, idx: 1, name: "1", output: "B-1", is_active: true }, { id: 2, idx: 1, output: "A-1", is_active: true }];
                Niri.setWindows({ 11: { id: 11, pid: 0, app_id: "foot", title: "x", workspace_id: 2 }, 12: { id: 12, pid: 0, app_id: "zed", title: "y", workspace_id: 2 } });
                ok(d.candidates.length === 1 && d.candidates[0].app === "zed" && d.candidates[0].output === "A-1", "fili-settings workspaces: picker lists the open windows not saved yet", JSON.stringify(d.candidates));
                FiliTheme.ran = [];
                d.adding = true;
                d.add("zed", "A-1");
                ok(!d.adding && FiliTheme.ran[0] === FiliTheme.bin + "/fili-app-output set 'zed' 'T M a'", "fili-settings workspaces: added on the display of its window", JSON.stringify(FiliTheme.ran));
                // Left / right: the shell moves the column of a new focused window to the first or last place
                FiliPlacement.columns = FiliPlacement.parse("zed\tleft\nfoot\tright\nmpv\tfloat\n");
                FiliTheme.ran = [];
                FiliPlacement.place({ id: 50, app_id: "zed", is_focused: true, is_floating: false });
                FiliPlacement.place({ id: 51, app_id: "foot", is_focused: true, is_floating: false });
                FiliPlacement.place({ id: 52, app_id: "zed", is_focused: false, is_floating: false });
                FiliPlacement.place({ id: 53, app_id: "mpv", is_focused: true, is_floating: true });
                ok(FiliTheme.ran.join("|") === "niri msg action move-column-to-first|niri msg action move-column-to-last", "fili-placement: new window to the first or last column (focused, tiled only)", JSON.stringify(FiliTheme.ran));
                FiliPlacement.columns = {};
                // Add dialog: open windows first, then installed applications (hidden and saved ones left out), typed app-id last
                d.conf = { apps: [{ app: "foot", output: "T M a" }], workspaces: [] };
                const ents = [{ id: "org.gnome.Calculator", name: "Calculator", startupClass: "", noDisplay: false }, { id: "zed", name: "Zed", noDisplay: false },
                    { id: "hidden", name: "Hidden", noDisplay: true }, { id: "foot", name: "Foot", noDisplay: false }];
                ok(d.pickList("", ents).map(x => x.app).join() === "zed,org.gnome.Calculator", "fili-settings workspaces: dialog lists open windows then installed applications", JSON.stringify(d.pickList("", ents)));
                const pk = d.pickList("calc", ents);
                ok(pk.map(x => x.app).join() === "org.gnome.Calculator,calc" && pk[1].typed, "fili-settings workspaces: search by name, typed app-id offered last", JSON.stringify(pk));
                ok(d.pickList("zed", ents).length === 1, "fili-settings workspaces: no typed entry when the app-id exists");
                // Bar: numbered workspaces show their name; the empty unnamed one niri adds on each display is hidden
                // (its local index "2" clashed with workspace "2" of another display) unless active or holding a window;
                // a click acts on the display of the bar
                const so = t.bar.screen.name, wm = t.bar.contentItem;
                Niri.setWindows({ 13: { id: 13, pid: 0, app_id: "foot", title: "x", workspace_id: 92 } });
                Niri.workspaces = [{ id: 90, idx: 1, name: "2", output: so, is_active: true }, { id: 91, idx: 2, output: so, is_active: false },
                    { id: 92, idx: 3, output: so, is_active: false }, { id: 93, idx: 1, name: "1", output: "Z-9", is_active: true }];
                ok(t.find(wm, "ws-90").text === "2" && t.find(wm, "ws-91") === null && t.find(wm, "ws-92").text === "\u2022" && t.find(wm, "ws-93") === null,
                    "workspaces: numbered -> names, empty unnamed hidden, unnamed with a window = dot", JSON.stringify(Niri.workspaces));
                FiliTheme.ran = [];
                t.find(wm, "ws-90").hover.press(Qt.LeftButton);
                ok(FiliTheme.ran[0] === "niri msg action focus-monitor '" + so + "' && niri msg action focus-workspace 1", "workspaces: click -> focus the display of the bar, then its workspace", JSON.stringify(FiliTheme.ran));
                Niri.workspaces = [{ id: 94, idx: 1, output: so, is_active: true }, { id: 95, idx: 2, output: so, is_active: false }];
                ok(t.find(wm, "ws-94").text === "1" && t.find(wm, "ws-95").text === "2", "workspaces: without numbering -> index of the display, empty one shown");
                Niri.setWindows({});
                Niri.workspaces = [];
                FiliSettings.close();
            },
            // fili-settings language: the choices of fili-lang list, a choice runs fili-lang set
            () => {
                FiliSettings.show("language");
                const d = FiliSettings.loaded;
                d.languages = [{ code: "en", name: "English", available: true }, { code: "fr", name: "Français", available: false }];
                ok(t.find(d, "language").model.length === 2, "fili-settings language: choices", t.find(d, "language").model.length);
                FiliTheme.ran = [];
                d.pick("fr");
                ok(FiliTheme.ran[0] === FiliTheme.bin + "/fili-lang set fr", "fili-settings language: fili-lang set", JSON.stringify(FiliTheme.ran));
                FiliSettings.close();
            },
            // fili-settings Casier: the resident mode switch runs fili-file spare on / off
            () => {
                FiliSettings.show("files");
                const d = FiliSettings.loaded;
                ok(d !== null && d.resident === false && t.find(d, "resident") !== null, "fili-settings casier: switch, off by default", d ? d.resident : "null");
                FiliTheme.ran = [];
                d.setResident(true);
                ok(FiliTheme.ran[0] === "/usr/bin/fili-file spare on" && d.resident, "fili-settings casier: spare on", JSON.stringify(FiliTheme.ran));
                d.setResident(false);
                ok(FiliTheme.ran[1] === "/usr/bin/fili-file spare off" && !d.resident, "fili-settings casier: spare off", JSON.stringify(FiliTheme.ran));
                FiliSettings.close();
            },
            // fili-settings Bar: modules of the manifests, switch, move up / down and to the other side by fili-bar
            () => {
                FiliSettings.show("bar");
                const d = FiliSettings.loaded;
                ok(d !== null && d.entries("left").map(e => e.name).join() === "logo,workspaces,appmenu" && t.find(d, "show-logo") !== null, "fili-settings bar: left modules, in order", d ? d.entries("left").map(e => e.name).join() : "null");
                FiliTheme.ran = [];
                d.toggle("logo");
                ok(FiliTheme.ran[0] === FiliTheme.bin + "/fili-bar disable logo", "fili-settings bar: switch = fili-bar disable", JSON.stringify(FiliTheme.ran));
                FiliTheme.ran = [];
                d.shift("left", "workspaces", -1);
                ok(FiliTheme.ran[0] === FiliTheme.bin + "/fili-bar move workspaces left 10 && " + FiliTheme.bin + "/fili-bar move logo left 20", "fili-settings bar: moving up renumbers the row", JSON.stringify(FiliTheme.ran));
                FiliTheme.ran = [];
                d.shift("left", "logo", -1);
                ok(FiliTheme.ran.length === 0, "fili-settings bar: first module, moving up does nothing");
                d.flip("left", "appmenu");
                ok(FiliTheme.ran[0].indexOf("fili-bar move appmenu right ") > 0, "fili-settings bar: switch sides", JSON.stringify(FiliTheme.ran));
                FiliSettings.close();
            },
            // fili-settings About: the card of Réglages (alias), aka fili-settings
            () => {
                FiliSettings.show("about");
                const d = FiliSettings.loaded;
                ok(d !== null && d.name === "Réglages" && d.aka === "fili-settings", "fili-settings about: name Réglages, aka fili-settings", d ? d.name : "null");
                ok(d.rows[0][0] === "Also known as" && d.rows.every(r => r[1] !== ""), "fili-settings about: aka row and no empty value");
                FiliSettings.close();
            },
            // fili-settings power: idle delays, a choice writes the three delays with bar-toggle idle set
            () => {
                FiliSettings.show("power");
                const d = FiliSettings.loaded;
                ok(d !== null && d.lock === 300 && d.screenOff === 600 && d.sleep === 0, "fili-settings power: default delays", d ? [d.lock, d.screenOff, d.sleep].join(" ") : "null");
                ok(d.lockChoices.some(c => c.value === 0) && d.sleepChoices[0].value === 900, "fili-settings power: never and minutes", JSON.stringify(d.sleepChoices));
                FiliTheme.ran = [];
                d.apply(d.lock, 120, 1800);
                ok(FiliTheme.ran[0] === FiliTheme.bin + "/bar-toggle idle set 300 120 1800" && d.screenOff === 120 && d.sleep === 1800, "fili-settings power: bar-toggle idle set", JSON.stringify(FiliTheme.ran));
                FiliSettings.close();
            },
            // fili-settings login: items read from login.toml, switch, remove and add go through fili-login
            () => {
                FiliSettings.show("login");
                const d = FiliSettings.loaded;
                d.load('[items.proton-bridge]\nname = "Proton Bridge"\ncommand = "protonmail-bridge --noninteractive"\nenabled = true\n\n[items.sync]\nname = "Sync"\ncommand = "rclone mount x y"\nenabled = false\n');
                ok(d.items.length === 2 && d.items[0].id === "proton-bridge" && d.items[0].enabled && !d.items[1].enabled, "fili-settings login: items read from login.toml", JSON.stringify(d.items));
                FiliTheme.ran = [];
                d.toggle(d.items[0]);
                d.toggle(d.items[1]);
                ok(FiliTheme.ran[0] === FiliTheme.bin + "/fili-login disable proton-bridge" && FiliTheme.ran[1] === FiliTheme.bin + "/fili-login enable sync", "fili-settings login: the switch enables or disables", JSON.stringify(FiliTheme.ran));
                FiliTheme.ran = [];
                d.remove(d.items[1]);
                ok(FiliTheme.ran[0] === FiliTheme.bin + "/fili-login remove sync", "fili-settings login: remove", JSON.stringify(FiliTheme.ran));
                FiliTheme.ran = [];
                d.newName = "It's mine";
                d.newCommand = "";
                d.add();
                ok(FiliTheme.ran.length === 0 && !d.canAdd, "fili-settings login: no add without a command", JSON.stringify(FiliTheme.ran));
                d.newCommand = "echo 'a b'";
                d.add();
                ok(FiliTheme.ran[0] === FiliTheme.bin + "/fili-login add 'It'\\''s mine' 'echo '\\''a b'\\'''" && d.newName === "" && d.newCommand === "", "fili-settings login: add quotes the name and the command, form cleared", JSON.stringify(FiliTheme.ran));
                d.newName = "x";
                d.newCommand = 'echo "hi"';
                ok(d.badChars && !d.canAdd, "fili-settings login: a double quote is refused", String(d.badChars));
                d.load("");
                ok(d.items.length === 0, "fili-settings login: empty file, no item", JSON.stringify(d.items));
                FiliSettings.close();
            },
            // fili-settings: page list, page loaded on opening and freed on closing, foot of the display panel
            () => {
                FiliPanel.view = "display";
                FiliPanel.gearButton.press(Qt.LeftButton);
                ok(FiliSettings.open && !FiliPanel.open && FiliSettings.page === "display", "fili-settings: the gear of the display panel opens the Display page, panel closed", FiliSettings.page);
                ok(FiliSettings.loaded !== null && FiliSettings.pages.length > 0 && FiliSettings.pages.every(p => p.label !== ""), "fili-settings: page loaded, pages named");
                FiliSettings.show("inconnue");
                ok(FiliSettings.page === "display", "fili-settings: unknown page ignored", FiliSettings.page);
                FiliShell.popupOpened("about");
                ok(!FiliSettings.open && FiliSettings.loaded === null, "fili-settings: closed by another window, page released");
                FiliSettings.toggle("display");
                ok(FiliSettings.open, "fili-settings: toggle opens");
                FiliSettings.toggle();
                ok(!FiliSettings.open, "fili-settings: toggle closes");
            },
            // fili-panel Bluetooth, sharing: protocols greyed out if unavailable, same interface, send command
            () => {
                FiliPanel.view = "bluetooth";
                const bt = FiliPanel.loaded;
                bt.protocols = [{ id: "airdrop", label: "AirDrop", available: false, why: "omdrop non installé" },
                                { id: "bluetooth", label: "Bluetooth", available: true, why: "" },
                                { id: "localsend", label: "LocalSend", available: false, why: "non installé" }];
                bt.proto = "airdrop";
                ok(!bt.shareOk && !t.find(bt, "share-receive").switchable, "fili-panel bluetooth: protocol unavailable, receive greyed out");
                const chips = t.find(bt, "share-protocols");
                chips.pick(2);
                ok(bt.proto === "airdrop", "fili-panel bluetooth: a greyed-out protocol cannot be chosen", bt.proto);
                chips.pick(1);
                ok(bt.proto === "bluetooth" && bt.shareOk && t.find(bt, "share-receive").switchable, "fili-panel bluetooth: protocole disponible choisi", bt.proto);
                FiliTheme.ran = [];
                bt.setReceiving(true);
                ok(FiliTheme.ran[0] === FiliTheme.bin + "/fili-share receive bluetooth on", "fili-panel bluetooth: receive -> fili-share receive", JSON.stringify(FiliTheme.ran));
                FiliTheme.ran = [];
                bt.sendTo({ id: "AA:BB:CC:DD:EE:FF", name: "Tel d'Alex" });
                ok(FiliTheme.ran[0] === FiliTheme.bin + "/fili-share send bluetooth 'AA:BB:CC:DD:EE:FF' 'Tel d'\\''Alex'", "fili-panel bluetooth: send -> fili-share send (names quoted)", JSON.stringify(FiliTheme.ran));
                // Pairing a new device goes through fili-bt-pair (BlueZ agent), once at a time
                FiliPanel.view = "bluetooth";
                const bt2 = FiliPanel.loaded;
                bt2.pairDevice("AA:BB:CC:DD:EE:01");
                // Click handler on fake devices: right branch for each state, no exception
                bt2.pairing = false;
                const log = [];
                const dev = o => Object.assign({ address: "AA:BB:CC:DD:EE:02", pairing: false, state: 0, connected: false, paired: true,
                    connect: () => log.push("connect"), disconnect: () => log.push("disconnect"), forget: () => log.push("forget") }, o);
                bt2.activate(dev({}), Qt.LeftButton);
                bt2.activate(dev({ connected: true }), Qt.LeftButton);
                bt2.activate(dev({}), Qt.RightButton);
                bt2.activate(dev({ state: BluetoothDeviceState.Connecting }), Qt.LeftButton);
                ok(JSON.stringify(log) === '["connect","disconnect","forget"]', "fili-panel bluetooth: click -> connect / disconnect / forget, ignored when busy", JSON.stringify(log));
                ok(JSON.stringify(bt2.pairCommand) === JSON.stringify([FiliTheme.bin + "/fili-bt-pair", "AA:BB:CC:DD:EE:01"]), "fili-panel bluetooth: appairage -> fili-bt-pair", JSON.stringify(bt2.pairCommand));
                FiliPanel.close();
            },
            // fili-panel keyboard: viewer (keys from fili-keymap, wtype typing) and emoji (copy + typing)
            () => {
                FiliPanel.view = "keyboard";
                ok(FiliPanel.loaded && !FiliPanel.loaded.passive, "fili-panel keyboard: layouts page with focus");
                const kbd = FiliPanel.loaded;
                if (kbd.keys >= 0) {
                    FiliTheme.ran = [];
                    t.find(kbd, "keys").moved(0.5);
                    ok(FiliTheme.ran.some(c => c.indexOf("kbd_backlight' set 50%") > 0), "fili-panel keyboard: backlight slider", JSON.stringify(FiliTheme.ran));
                }
                t.find(kbd, "open-hotkeys").press(Qt.LeftButton);
                ok(FiliHotkeys.open && !FiliPanel.open, "fili-panel keyboard: Keyboard Shortcuts link -> shortcuts window, panel closed");
                FiliHotkeys.close();
                FiliPanel.view = "keyboard";
                FiliPanel.loaded.page = "viewer";
                ok(FiliPanel.loaded.passive, "fili-panel keyboard: the viewer does not take focus");
            },
            wait(() => {}, () => FiliPanel.loaded.rows.length === 4),
            () => {
                const kb = FiliPanel.loaded;
                ok(kb.rows.length === 4 && kb.rows[0].length >= 12, "fili-panel keyboard: fili-keymap, 4 rows", JSON.stringify(kb.rows).slice(0, 80));
                FiliTheme.ran = [];
                kb.typeKey("eacute");
                ok(FiliTheme.ran.indexOf("wtype -k eacute") >= 0, "fili-panel keyboard: key click -> wtype -k", JSON.stringify(FiliTheme.ran));
                kb.page = "emoji";
            },
            wait(() => {}, () => FiliPanel.loaded.emojis.length > 100),
            () => {
                const kb = FiliPanel.loaded;
                ok(kb.emojis.length > 100, "fili-panel keyboard: emoji list loaded", kb.emojis.length);
                kb.query = "grinning face";
                ok(kb.found.length > 0 && kb.found.length <= 48, "fili-panel clavier: recherche d'emoji", kb.found.length);
                FiliTheme.ran = [];
                kb.pickEmoji(kb.found[0].c);
                ok(FiliTheme.ran.some(c => c.indexOf("wl-copy") >= 0 && c.indexOf("wtype") >= 0), "fili-panel keyboard: emoji copied and typed", JSON.stringify(FiliTheme.ran));
                ok(FiliPanel.view === "", "fili-panel keyboard: choosing an emoji closes the panel");
            },
            // Icon of the audio output by type (PipeWire properties)
            () => {
                const g = p => FiliTheme.sinkGlyph(p).codePointAt(0) ?? 0;
                ok(g({ "device.icon_name": "audio-headphones", "device.profile.name": "HiFi: Headphones: sink" }) === 0xf025, "sound: wired headset");
                ok(g({ "node.name": "alsa_output.pci.analog-stereo", "device.form-factor": "headset" }) === 0xf025, "sound: USB headset");
                ok(g({ "device.api": "bluez5", "node.name": "bluez_output.AA_BB.1", "device.form-factor": "headphone" }) === 0xf0970, "sound: Bluetooth headset");
                ok(g({ "device.api": "bluez5", "node.name": "bluez_output.AA_BB.1", "device.form-factor": "speaker" }) === 0xf09a2, "sound: Bluetooth speaker");
                ok(g({ "node.name": "alsa_output.pci-0000_00_1f.3.hdmi-stereo" }) === 0xf0379, "sound: HDMI display");
                ok(g({ "node.name": "audio_effect.t2-speakers", "device.icon-name": "audio-speakers" }) === 0, "sound: speakers (graded icon)");
                ok(g(null) === 0, "sound: output missing");
            },
            // No fili-tooltip while a fili-panel is open
            () => {
                const it = t.find(t.bar.contentItem, "volume");
                FiliPanel.summon("audio");
                FiliTooltip.show(it, { title: "x" });
                ok(FiliTooltip.target === null, "fili-tooltip: hidden while a fili-panel is open");
                FiliPanel.close();
                FiliTooltip.show(it, { title: "x" });
                ok(FiliTooltip.target === null, "fili-tooltip: no card right after a panel closes");
                FiliShell.panelClosedAt = Date.now() - 5000;
                FiliTooltip.show(it, { title: "x" });
                ok(FiliTooltip.target === it, "fili-tooltip: allowed again after the grace period");
                FiliTooltip.hide();
                // Same thing with the notification center open
                FiliShell.panelClosedAt = Date.now() - 5000;
                FiliNotification.centerOpen = true;
                FiliTooltip.show(it, { title: "x" });
                ok(FiliTooltip.target === null, "fili-tooltip: hidden while the notification centre is open");
                FiliNotification.centerOpen = false;
                FiliTooltip.show(it, { title: "x" });
                ok(FiliTooltip.target === null, "fili-tooltip: grace period also after the notification centre closes");
                FiliShell.panelClosedAt = Date.now() - 5000;
                FiliTooltip.hide();
            },
            // Switches right of the title (Wi-Fi, Bluetooth): present, Bluetooth greyed out without an adapter
            () => {
                for (const [v, name] of [["network", "wifi-power"], ["bluetooth", "power"], ["display", "night"], ["power", "caffeine"]]) {
                    FiliPanel.view = v;
                    const sw = t.find(FiliPanel.loaded, name);
                    ok(sw && sw.hasOwnProperty("checked"), "fili-panel " + v + ": switch to the right of the title", sw ? "" : "not found");
                }
                FiliPanel.close();
            },
            // fili-panel displays, appearance: dark by default, "Light" turns the shell to paper and runs fili-theme
            () => {
                FiliPanel.view = "display";
                const chips = t.find(FiliPanel.loaded, "theme");
                ok(chips && chips.current === "dark" && Qt.colorEqual(FiliTheme.nuit, "#1c222b"), "fili-panel displays: dark mode by default", chips ? chips.current : "not found");
                FiliTheme.ran = [];
                chips.pick(1);
                ok(FiliTheme.light && Qt.colorEqual(FiliTheme.nuit, "#f3f1ec") && Qt.colorEqual(FiliTheme.brume, "#1c222b"), "fili-panel displays: light mode, paper background and night text", FiliTheme.mode);
                ok(FiliTheme.ran.length === 1 && /\/fili-theme light$/.test(FiliTheme.ran[0]), "fili-panel displays: fili-theme light run", JSON.stringify(FiliTheme.ran));
                chips.pick(0);
                ok(FiliTheme.mode === "dark" && /\/fili-theme dark$/.test(FiliTheme.ran[1]), "fili-panel displays: back to dark", JSON.stringify(FiliTheme.ran));
                FiliPanel.close();
            },
            // fili-settings display, accent colour: sable by default, the choice changes the accent of the shell and runs fili-theme accent
            () => {
                FiliSettings.show("display");
                const acc = t.find(FiliSettings.loaded, "accent");
                ok(acc && FiliTheme.accent === "default" && Qt.colorEqual(FiliTheme.voile, "#d2bf92"), "fili-settings display: default accent: sand in dark mode", acc ? FiliTheme.accent : "not found");
                ok(acc.names.indexOf("default") < 0 && FiliTheme.accentName === "sable" && acc.names[acc.cursor] === "sable", "fili-settings display: no Default entry, sand is the colour chosen by default", FiliTheme.accentName);
                FiliTheme.ran = [];
                acc.pick("sable");
                ok(Qt.colorEqual(FiliTheme.voile, "#d2bf92") && Qt.colorEqual(FiliTheme.voileVif, "#e0d1ab"), "fili-settings display: sand accent in the shell", String(FiliTheme.voile));
                ok(FiliTheme.ran.length === 1 && /\/fili-theme accent sable$/.test(FiliTheme.ran[0]), "fili-settings display: fili-theme accent sable run", JSON.stringify(FiliTheme.ran));
                FiliTheme.mode = "light";
                ok(Qt.colorEqual(FiliTheme.voile, "#80662b"), "accent sable en mode clair", String(FiliTheme.voile));
                FiliTheme.mode = "dark";
                FiliTheme.mode = "light";
                FiliTheme.accent = "default";
                ok(Qt.colorEqual(FiliTheme.voile, "#4f6884"), "default accent in light mode: slate", String(FiliTheme.voile));
                ok(FiliTheme.accentName === "ardoise", "default accent in light mode: slate is the chosen swatch", FiliTheme.accentName);
                FiliTheme.mode = "dark";
                FiliTheme.accent = "inconnu";
                ok(Qt.colorEqual(FiliTheme.voile, "#d2bf92"), "unknown accent: fall back to the default", String(FiliTheme.voile));
                FiliTheme.accent = "default";
                FiliSettings.close();
            },
            // Panel open: the action of a module fires on press (a single click), not twice on release
            () => {
                const logo = t.find(t.bar.contentItem, "logo");
                const area = logo.hover ?? logo;
                FiliPanel.summon("audio");
                FiliTheme.ran = [];
                area.down(Qt.LeftButton);
                ok(FiliTheme.ran.length === 1, "fili-bar: panel open, action on press", JSON.stringify(FiliTheme.ran));
                area.up(Qt.LeftButton);
                ok(FiliTheme.ran.length === 1, "fili-bar: panel open, no second trigger on release", JSON.stringify(FiliTheme.ran));
                FiliPanel.close();
                FiliTheme.ran = [];
                area.down(Qt.LeftButton);
                ok(FiliTheme.ran.length === 0, "fili-bar: panel closed, nothing on press");
                area.up(Qt.LeftButton);
                ok(FiliTheme.ran.length === 1, "fili-bar: panel closed, action on release", JSON.stringify(FiliTheme.ran));
            },
            // fili-panel network: the icon follows the signal strength (steps of 25)
            () => {
                FiliPanel.view = "network";
                const g = s => FiliPanel.loaded.signalGlyph(s).codePointAt(0);
                ok(g(100) === 0xF0928 && g(75) === 0xF0928 && g(50) === 0xF0925 && g(25) === 0xF0922 && g(0) === 0xF091F, "fili-panel network: icon according to the signal strength", [g(100), g(50), g(25), g(0)].map(x => x.toString(16)).join(","));
                FiliPanel.close();
            },
            // fili-panel: a rule separates the sections (the first visible subheading has none)
            () => FiliPanel.view = "display",
            wait(() => {}, () => FiliPanel.loaded && FiliPanel.loaded.children.filter(c => c.isSection === true && c.visible).length > 1 && FiliPanel.loaded.children.filter(c => c.isSection === true && c.first).length === 1),
            () => {
                const secs = FiliPanel.loaded.children.filter(c => c.isSection === true && c.visible);
                ok(secs.length > 1 && secs[0].first && secs.slice(1).every(s => !s.first), "fili-panel: rule between sections, not before the first", secs.map(s => s.first).join(","));
                FiliPanel.close();
            },
            // A single open panel: panel, pinned calendar and notification center close each other
            () => {
                const cal = t.find(t.bar.contentItem, "clock");
                FiliPanel.summon("audio");
                FiliNotification.toggleCenter();
                ok(FiliNotification.centerOpen && FiliPanel.view === "", "a single panel: the notification centre closes the fili-panel", FiliPanel.view);
                FiliPanel.summon("audio");
                ok(FiliPanel.view === "audio" && !FiliNotification.centerOpen, "a single panel: the fili-panel closes the notification centre");
                cal.press(Qt.RightButton);
                ok(FiliPanel.view === "", "a single panel: the pinned calendar closes the fili-panel", FiliPanel.view);
                cal.press(Qt.RightButton);
                FiliPanel.close();
            },
            // ───── keyboard navigation (Mod+A, ←/→, Enter...) ─────
            () => {
                FiliPanel.last = "monitor";
                FiliPanel.summon("toggle");
                ok(FiliPanel.view === "monitor" && FiliShell.keyNav, "keyboard: Mod+A opens the last panel, outlines active", FiliPanel.view);
                FiliPanel.step(1);
                ok(FiliPanel.view === "agent", "keyboard: → neighbouring panel (AI agent)", FiliPanel.view);
                FiliPanel.step(1);
                ok(FiliPanel.view === "audio", "keyboard: → again (sound)", FiliPanel.view);
                FiliPanel.step(-1);
                FiliPanel.step(-1);
                FiliPanel.step(-1);
                ok(FiliPanel.view === "power", "keyboard: ← from the first wraps to the last (power)", FiliPanel.view);
                FiliPanel.step(-1);
                ok(FiliPanel.view === "" && FiliNotification.centerOpen && FiliShell.keyNav, "keyboard: ← to the notification centre", FiliPanel.view);
                FiliPanel.step(-1);
                ok(FiliPanel.view === "network" && !FiliNotification.centerOpen, "keyboard: ← from the centre -> network", FiliPanel.view);
                FiliPanel.summon("toggle");
                ok(!FiliPanel.open && !FiliShell.keyNav, "keyboard: Mod+A closes, outlines forgotten");
                FiliPanel.summon("toggle");
                ok(FiliPanel.view === "network", "keyboard: Mod+A reopens the last panel (network)", FiliPanel.view);
                const m = FiliPanel.modules[Quickshell.screens[0].name] ?? {};
                ok(FiliPanel.ring().every(n => m[n]), "keyboard: every panel knows its bar module", Object.keys(m).join(","));
                FiliPanel.close();
            },
            () => FiliPanel.summon("keyboard"),
            wait(() => {}, () => FiliPanel.loaded && t.find(FiliPanel.loaded, "open-emoji")),
            () => {
                const kb = FiliPanel.loaded;
                t.find(kb, "open-emoji").key({ modifiers: 0 });
                ok(kb.page === "emoji", "keyboard: Enter on a button = click", kb.page);
                kb.page = "layouts";
                FiliPanel.close();
            },
            () => FiliSettings.show("display"),
            wait(() => {}, () => FiliSettings.loaded && t.find(FiliSettings.loaded, "scale")),
            () => {
                const chips = t.find(FiliSettings.loaded, "scale");
                const values = chips.model.filter(c => !c.off);
                if (values.length > 1) {
                    chips.cursor = chips.model.indexOf(values[0]);
                    chips.move(1);
                    FiliTheme.ran = [];
                    ok(chips.cursor === chips.model.indexOf(values[1]) && FiliTheme.ran.length === 0, "keyboard: → in a row of choices moves the cursor without applying", chips.cursor);
                }
                FiliSettings.close();
                FiliPanel.summon("display");
                const d = FiliPanel.loaded;
                const sl = t.find(d, "screen");
                if (sl.visible) {
                    FiliTheme.ran = [];
                    const e = { modifiers: Qt.ShiftModifier, accepted: true };
                    sl.nudge(e, 0.05);
                    ok(!e.accepted && FiliTheme.ran.length === 0, "keyboard: Shift+→ on a slider left to the panel (neighbour)");
                    sl.nudge({ modifiers: 0 }, 0.05);
                    ok(FiliTheme.ran.join(" ").indexOf("brightnessctl -q set") >= 0, "keyboard: → on the brightness slider = +5 %", FiliTheme.ran.join(" "));
                }
                FiliPanel.close();
                FiliTheme.ran = [];
                FiliNotification.centerOpen = true;
                FiliNotification.copy({ summary: "test copie", body: "" });
                ok(FiliTheme.ran[0] === "wl-copy test copie" && !FiliNotification.centerOpen, "keyboard: Enter on a notification of the centre = copy and close", JSON.stringify(FiliTheme.ran));
            },
            // fili-about: middle click on the logo, card read by fili-about, text copy, `about toggle` channel
            () => {
                act("logo", Qt.MiddleButton);
                ok(FiliAbout.open, "fili-bar logo, middle click -> About window");
            },
            wait(() => {}, () => FiliAbout.card.sections.length > 0, 10000),
            () => {
                const c = FiliAbout.card;
                const names = c.sections.map(s => s.name);
                ok(typeof c.host === "string" && ["System", "Machine"].every(n => names.includes(n)), "fili-about: JSON { host, sections System/Machine }", JSON.stringify(names));
                ok(c.sections.every(s => s.rows.every(r => r.length === 2 && r[1] !== "")), "fili-about: [label, value] rows not empty");
                FiliTheme.ran = [];
                FiliAbout.copy();
                ok(FiliTheme.ran[0]?.startsWith("wl-copy Filigrane · ") && FiliTheme.ran[0].indexOf("Kernel: ") > 0 && !FiliAbout.open, "fili-about: C copies the card as text and closes", JSON.stringify(FiliTheme.ran));
                FiliAbout.toggle();
                ok(FiliAbout.open, "fili-about: toggle rouvre");
                FiliShell.popupOpened("panel");
                ok(!FiliAbout.open, "fili-about: closed when another panel opens");
            },
            // fili-audio-switch: answer keeps or switches, the checkbox remembers the choice per device
            () => {
                const fake = { id: -1, name: "bluez_output.AA", description: "Test headset", properties: { "api.bluez5.address": "AA" } };
                FiliAudioSwitch.candidate = fake;
                ok(FiliAudioSwitch.open, "fili-audio-switch: a candidate output opens the modal");
                FiliAudioSwitch.remember = true;
                FiliAudioSwitch.answer(false);
                ok(!FiliAudioSwitch.open && FiliAudioSwitch.choices["AA"] === "keep", "fili-audio-switch: Keep + checkbox remembers 'keep'", JSON.stringify(FiliAudioSwitch.choices));
                FiliAudioSwitch.candidate = fake;
                FiliAudioSwitch.answer(false);
                ok(!FiliAudioSwitch.open && FiliAudioSwitch.choices["AA"] === "keep", "fili-audio-switch: without the checkbox nothing changes");
            },
            // fili-chat: drawer, sessions, daemon events (without a daemon: the requests are recorded)
            () => {
                FiliTheme.ran = [];
                FiliChat.toggle();
                ok(FiliChat.open, "fili-chat: toggle opens the drawer");
                FiliChat.send("bonjour");
                ok(FiliTheme.ran[0] === 'chat {"op":"new"}' && FiliChat.pending === "bonjour", "fili-chat: without a session, the first message creates one", JSON.stringify(FiliTheme.ran));
                FiliChat.receive({ ev: "sessions", sessions: [] });
                FiliChat.receive({ ev: "created", id: "s1" });
                ok(FiliTheme.ran[1] === 'chat {"op":"send","id":"s1","text":"bonjour"}' && FiliChat.current === "s1" && FiliChat.pending === "", "fili-chat: the created session receives the pending message", JSON.stringify(FiliTheme.ran));
                FiliChat.receive({ ev: "msg", id: "s1", role: "user", text: "bonjour" });
                FiliChat.receive({ ev: "state", id: "s1", state: "working" });
                FiliChat.receive({ ev: "delta", id: "s1", text: "sal" });
                FiliChat.receive({ ev: "delta", id: "s1", text: "ut" });
                ok(FiliChat.working && FiliChat.busy && FiliChat.live === "salut", "fili-chat: text in progress and working state", FiliChat.live);
                FiliTheme.ran = [];
                FiliChat.send("encore");
                ok(FiliTheme.ran.length === 1 && FiliTheme.ran[0] === 'chat {"op":"send","id":"s1","text":"encore"}', "fili-chat: message typed during a turn: sent to the daemon, which queues it", JSON.stringify(FiliTheme.ran));
                FiliChat.receive({ ev: "queue", id: "s1", items: ["encore"] });
                ok(FiliChat.queuedNow.length === 1, "fili-chat: queue shown");
                FiliChat.receive({ ev: "queue", id: "s1", items: [] });
                FiliChat.receive({ ev: "tool", id: "s1", name: "Bash", summary: "sv status iwd" });
                FiliChat.receive({ ev: "msg", id: "s1", role: "assistant", text: "Salut." });
                FiliChat.receive({ ev: "state", id: "s1", state: "idle" });
                ok(FiliChat.log.map(i => i.kind).join() === "user,tool,assistant" && FiliChat.live === "" && !FiliChat.working && !FiliChat.busy, "fili-chat: thread (message, tool, reply) and end of the turn", FiliChat.log.map(i => i.kind).join());
                FiliChat.receive({ ev: "sessions", sessions: [{ id: "s2", title: "Wi-Fi", state: "idle", updated: 2 }, { id: "s1", title: "bonjour", state: "idle", updated: 1 }] });
                ok(FiliChat.current === "s1" && FiliChat.title === "bonjour", "fili-chat: title of the current session", FiliChat.title);
                FiliTheme.ran = [];
                FiliChat.openSession("s2");
                ok(FiliChat.current === "s2" && FiliTheme.ran[0] === 'chat {"op":"open","id":"s2"}', "fili-chat: switching session asks for its history", JSON.stringify(FiliTheme.ran));
                FiliChat.receive({ ev: "history", id: "s2", items: [{ ev: "msg", id: "s2", role: "assistant", text: "Avant" }] });
                ok(FiliChat.log.length === 1 && FiliChat.items["s1"].length === 3, "fili-chat: history per session");
                // Permission asked: card in the thread, "waiting" state, ASK dot, answer
                FiliChat.openSession("s1");
                FiliChat.receive({ ev: "state", id: "s1", state: "working" });
                FiliChat.receive({ ev: "ask", id: "s1", rid: "r1", tool: "Bash", summary: "sudo sv restart iwd", status: "pending" });
                FiliChat.receive({ ev: "state", id: "s1", state: "waiting" });
                ok(FiliChat.log[FiliChat.log.length - 1].kind === "ask" && FiliChat.attention === "waiting" && FiliChat.working, "fili-chat: permission requested (card, waiting, ASK)", FiliChat.attention);
                ok(BarState.aiChat(BarState.aiFor({ sessions: [] }, null, {}), FiliChat.attention, FiliChat.busy).text.endsWith(" ASK"), "fili-chat: pastille IA ASK");
                FiliTheme.ran = [];
                FiliChat.answerFirst(true);
                ok(FiliTheme.ran[0] === 'chat {"op":"answer","rid":"r1","allow":true}', "fili-chat: Ctrl+Enter allows the first request", JSON.stringify(FiliTheme.ran));
                FiliChat.receive({ ev: "ask", id: "s1", rid: "r1", tool: "Bash", summary: "sudo sv restart iwd", status: "allowed" });
                ok(FiliChat.log.filter(i => i.kind === "ask").length === 1 && FiliChat.log[FiliChat.log.length - 1].status === "allowed", "fili-chat: the decided request replaces the card");
                // Permission asked while the drawer is hidden: notification with Allow / Deny answered through the drawer
                FiliChat.hide();
                FiliTheme.ran = [];
                FiliChat.receive({ ev: "ask", id: "s1", rid: "r2", tool: "Bash", summary: "ls", status: "pending" });
                ok(FiliTheme.ran[0] === "notify-ask s1 r2", "fili-chat: permission out of sight: notification with buttons", JSON.stringify(FiliTheme.ran));
                FiliChat.act("answer", ["r2:no"]);
                ok(FiliTheme.ran[1] === 'chat {"op":"answer","rid":"r2","allow":false}', "fili-chat: Deny of the notification answers the request", JSON.stringify(FiliTheme.ran));
                FiliChat.receive({ ev: "ask", id: "s1", rid: "r2", tool: "Bash", summary: "ls", status: "denied" });
                ok(FiliTheme.ran[2] === "notify-close r2", "fili-chat: settled request closes its notification", JSON.stringify(FiliTheme.ran));
                FiliChat.show();
                FiliChat.openSession("s1");
                // Answer finished while the drawer is hidden: DONE until it opens
                FiliChat.hide();
                FiliChat.receive({ ev: "state", id: "s1", state: "working" });
                FiliChat.receive({ ev: "state", id: "s1", state: "idle" });
                ok(FiliChat.attention === "done" && BarState.aiChat(BarState.aiFor({ sessions: [] }, null, {}), FiliChat.attention, FiliChat.busy).text.endsWith(" DONE"), "fili-chat: unread reply (DONE)", FiliChat.attention);
                // Tabs: red (waiting) and green (finished, unread) are read from states / unread of each session
                ok(FiliChat.unread["s1"] === true && FiliChat.tabsOpen, "fili-chat: tab of s1 green (finished, unread)");
                FiliChat.act("sessions");
                ok(!FiliChat.tabsOpen && FiliChat.open, "fili-chat: Sessions… hides the tabs");
                FiliChat.act("sessions");
                ok(FiliChat.tabsOpen, "fili-chat: Sessions… shows them again");
                // Deletion confirmed; the deleted ones stay in the full list
                FiliChat.receive({ ev: "sessions", sessions: [{ id: "s1", title: "A", state: "idle", link: "" }, { id: "s2", title: "B", state: "idle", link: "", archived: true }] });
                ok(FiliChat.sessions.length === 1 && FiliChat.allSessions.length === 2, "fili-chat: deleted ones are out of the tabs but in the full list");
                FiliChat.askArchive("s1");
                ok(FiliChat.confirmId === "s1", "fili-chat: supprimer demande confirmation");
                FiliChat.confirmArchive(false);
                ok(FiliChat.confirmId === "" && FiliChat.sessions.length === 1, "fili-chat: cancel keeps the session");
                FiliChat.receive({ ev: "sessions", sessions: [{ id: "s1", title: "A", state: "idle", link: "", icon: 0xF2001 }] });
                ok(FiliChat.sessions[0].icon === 0xF2001, "fili-chat: the topic icon chosen by the AI arrives with the session");
                FiliChat.receive({ ev: "agent", ok: false });
                ok(!FiliChat.agentOk, "fili-chat: without an AI agent, the install banner is shown");
                FiliChat.receive({ ev: "agent", ok: true });
                ok(FiliChat.agentOk, "fili-chat: agent installed, banner removed");
                FiliChat.receive({ ev: "sessions", sessions: [{ id: "s1", title: "A", state: "idle", link: "" }, { id: "s2", title: "B", state: "idle", link: "", archived: true }] });
                // 20 tabs at most, the older ones stay in the full list; the current one keeps its tab
                FiliChat.receive({ ev: "sessions", sessions: Array.from({ length: 25 }, (_, i) => ({ id: "t" + i, title: "T" + i, state: "idle", link: "", updated: 100 - i })) });
                ok(FiliChat.tabSessions.length === 20 && FiliChat.allSessions.length === 25, "fili-chat: at most 20 tabs, all the sessions in the list");
                FiliChat.current = "t24";
                ok(FiliChat.tabSessions.length === 20 && FiliChat.tabSessions.some(x => x.id === "t24"), "fili-chat: a session opened from the list keeps its tab");
                FiliChat.receive({ ev: "sessions", sessions: [{ id: "s1", title: "A", state: "idle", link: "" }, { id: "s2", title: "B", state: "idle", link: "", archived: true }] });
                FiliChat.askArchive("s2");
                ok(FiliChat.confirmId === "", "fili-chat: no confirmation for an already deleted session");
                // Context (Mod+Y): attached once to the message
                FiliChat.show();
                ok(FiliChat.attention === "", "fili-chat: opening the drawer reads the reply");
                FiliChat.ctx = { window: { app_id: "foot", title: "~" } };
                FiliChat.ctxOn = true;
                ok(FiliChat.ctxLabel === "foot · ~", "fili-chat: context chip", FiliChat.ctxLabel);
                FiliTheme.ran = [];
                FiliChat.send("ceci");
                ok(FiliTheme.ran[0] === 'chat {"op":"link","id":"s1","key":"foot"}' && FiliTheme.ran[1] === 'chat {"op":"send","id":"s1","text":"ceci","context":true}' && !FiliChat.ctxOn, "fili-chat: the context goes with the message, once (and links the session)", JSON.stringify(FiliTheme.ran));
                FiliChat.setMode("float");
                FiliShell.popupOpened("panel");
                ok(!FiliChat.open, "fili-chat: floating, closed when a bar panel opens");
                FiliChat.setMode("dock");
            },
            // fili-chat: layout (floating / docked), width, renaming
            () => {
                FiliTheme.ran = [];
                ok(FiliChat.mode === "dock" && FiliChat.dock && FiliChat.viewWidth === 440, "fili-chat: docked, 440 px by default", FiliChat.mode);
                FiliChat.show();
                FiliShell.popupOpened("panel");
                ok(FiliChat.open, "fili-chat: docked, a bar panel does not close it");
                FiliChat.act("width-wide");
                ok(FiliChat.viewWidth === 560 && FiliChat.dock && FiliTheme.ran[0] === "chat-view dock 560", "fili-chat: largeur large", JSON.stringify(FiliTheme.ran));
                FiliChat.act("float");
                ok(!FiliChat.dock && FiliChat.viewWidth === 560 && FiliTheme.ran[1] === "chat-view float 560", "fili-chat: View menu > floating, choice kept", JSON.stringify(FiliTheme.ran));
                FiliChat.setWidth(5000);
                ok(FiliChat.viewWidth === 900, "fili-chat: dragged width clamped to 900", FiliChat.viewWidth);
                FiliChat.setWidth(100);
                ok(FiliChat.viewWidth === 300, "fili-chat: dragged width clamped to 300", FiliChat.viewWidth);
                FiliChat.act("width-medium");
                FiliShell.popupOpened("panel");
                ok(!FiliChat.open, "fili-chat: floating, a bar panel closes it");
                FiliChat.act("dock");
                ok(FiliChat.dock, "fili-chat: View menu > docked");
                FiliChat.receive({ ev: "sessions", sessions: [{ id: "s1", title: "bonjour", state: "idle", updated: 1 }] });
                FiliChat.current = "s1";
                FiliTheme.ran = [];
                FiliChat.act("rename");
                ok(FiliChat.open && FiliChat.renaming, "fili-chat: Rename opens the title field");
                FiliChat.commitRename("  Wi-Fi  ");
                ok(!FiliChat.renaming && FiliTheme.ran[0] === 'chat {"op":"rename","id":"s1","title":"Wi-Fi"}', "fili-chat: rename sent to the daemon", JSON.stringify(FiliTheme.ran));
                FiliChat.hide();
                FiliChat.act("toggle");
                ok(FiliChat.open, "fili-chat: act toggle");
                FiliChat.act("close");
            },
            // fili-chat: sessions linked to applications (follow = "app"): resumed on opening, link on sending, new linked session
            () => {
                FiliChat.hide();
                FiliChat.receive({ ev: "sessions", sessions: [{ id: "a1", title: "Chrome", state: "idle", updated: 3, link: "google-chrome" }, { id: "a2", title: "Terminal", state: "idle", updated: 2, link: "foot" }, { id: "a3", title: "libre", state: "idle", updated: 1, link: "" }] });
                FiliChat.current = "a3";
                FiliChat.items = Object.assign({}, FiliChat.items, { a1: [], a2: [], a3: [] });
                ok(FiliChat.follow === "app" && FiliChat.linkKey({ window: { app_id: "foot", title: "~" } }) === "foot", "fili-chat: follow = app by default, key = app_id", FiliChat.follow);
                // Opening: the context (active application) and the list are there -> the linked session is resumed
                FiliTheme.ran = [];
                FiliChat.show();
                FiliChat.ctx = { window: { app_id: "google-chrome", title: "Toyota" } };
                FiliChat.ctxReady = true;
                FiliChat.sessionsFresh = true;
                FiliChat.tryFollow();
                ok(FiliChat.current === "a1", "fili-chat: opening resumes the session linked to the active application", FiliChat.current);
                // No resuming while the drawer is open (window change), nor if the turn is working
                FiliChat.ctx = { window: { app_id: "foot", title: "~" } };
                FiliChat.tryFollow();
                ok(FiliChat.current === "a1", "fili-chat: a window change with the drawer open does not change the session");
                FiliChat.hide();
                FiliChat.receive({ ev: "state", id: "a1", state: "working" });
                FiliChat.show();
                FiliChat.ctx = { window: { app_id: "foot", title: "~" } };
                FiliChat.ctxReady = true;
                FiliChat.sessionsFresh = true;
                FiliChat.tryFollow();
                ok(FiliChat.current === "a1", "fili-chat: no resume during a turn in progress");
                FiliChat.receive({ ev: "state", id: "a1", state: "idle" });
                // Application without a linked session: the current session stays
                FiliChat.hide();
                FiliChat.show();
                FiliChat.ctx = { window: { app_id: "niri-inconnu", title: "" } };
                FiliChat.ctxReady = true;
                FiliChat.sessionsFresh = true;
                FiliChat.tryFollow();
                ok(FiliChat.current === "a1", "fili-chat: application without a linked session, the last one stays");
                // Link on sending: session without a link + context chip
                FiliChat.openSession("a3");
                FiliChat.ctx = { window: { app_id: "foot", title: "~" } };
                FiliChat.ctxOn = true;
                FiliTheme.ran = [];
                FiliChat.send("bonjour");
                ok(FiliTheme.ran[0] === 'chat {"op":"link","id":"a3","key":"foot"}' && FiliTheme.ran[1].includes('"op":"send"'), "fili-chat: sending with the context chip links the session", JSON.stringify(FiliTheme.ran));
                FiliChat.receive({ ev: "state", id: "a3", state: "working" });
                FiliChat.receive({ ev: "state", id: "a3", state: "idle" });
                // Already linked: no second link; chip removed: no link
                FiliChat.receive({ ev: "sessions", sessions: [{ id: "a1", title: "Chrome", state: "idle", updated: 3, link: "google-chrome" }, { id: "a3", title: "libre", state: "idle", updated: 1, link: "foot" }] });
                FiliChat.ctxOn = true;
                FiliTheme.ran = [];
                FiliChat.send("encore");
                ok(FiliTheme.ran.length === 1 && FiliTheme.ran[0].includes('"op":"send"'), "fili-chat: an already linked session is not linked again", JSON.stringify(FiliTheme.ran));
                // New session for this application
                FiliChat.receive({ ev: "state", id: "a3", state: "working" });
                FiliChat.receive({ ev: "state", id: "a3", state: "idle" });
                FiliChat.ctx = { window: { app_id: "fili-file", title: "Casier" } };
                FiliTheme.ran = [];
                FiliChat.act("new-here");
                ok(FiliTheme.ran[0] === 'chat {"op":"new"}' && FiliChat.pendingLink === "fili-file", "fili-chat: New session for this application", JSON.stringify(FiliTheme.ran));
                FiliChat.receive({ ev: "created", id: "a4" });
                ok(FiliTheme.ran[1] === 'chat {"op":"link","id":"a4","key":"fili-file"}' && FiliChat.pendingLink === "", "fili-chat: the created session is linked", JSON.stringify(FiliTheme.ran));
                FiliTheme.ran = [];
                FiliChat.act("unlink");
                ok(FiliTheme.ran[0] === 'chat {"op":"link","id":"a4","key":""}', "fili-chat: Unlink removes the link", JSON.stringify(FiliTheme.ran));
                FiliChat.hide();
            },
            // fili-chat: its menu replaces that of the window when the drawer has the keyboard focus (without the niri Quit/Window menus)
            wait(() => { FiliChat.show(); FiliChat.focused = true; }, () => AppMenu.appName === "Rob" && AppMenu.menus.length > 0, 5000),
            () => {
                const labels = AppMenu.menus.map(m => m.label);
                ok(labels.join() === "Rob,Session,View", "fili-chat: fili-bar menu = Rob, Session, View (no Window or Quit)", labels.join());
                ok(AppMenu.menus[0].children.some(c => c.label === "About Rob" && c.exec === "fili-shell chat about"), "fili-chat: menu Rob > About Rob");
                const session = AppMenu.menus.find(m => m.label === "Session");
                ok(session && session.children.some(c => c.label === "Rename Session…" && c.keys === "F2" && c.exec === "fili-shell chat rename"), "fili-chat: Session > Rename Session… (F2)");
                // Press on a title of the bar: niri gives the focus back to the previous window, the chat menu stays
                AppMenu.pressTitle();
                FiliChat.focused = false;
                ok(AppMenu.chatFocus && AppMenu.appId === "fili-chat", "fili-chat: the menu stays during a press on a title (focus given back to the window)");
            },
            wait(() => {}, () => !AppMenu.chatFocus, 5000),
            () => {
                ok(AppMenu.appId !== "fili-chat", "fili-chat: without focus or an open menu, the bar goes back to the active window");
                FiliChat.hide();
            },
            // fili-chat: "About Rob" card (robot icon, name Rob), closed by another panel
            () => {
                FiliChat.hide();
                FiliChat.act("about");
                ok(FiliChatAbout.open && FiliChatAbout.name === "Rob" && FiliChatAbout.icon.codePointAt(0) === 0xf06a9, "fili-chat: About Rob (robot icon, name Rob)");
                const labels = FiliChatAbout.rows.map(r => r[0]);
                ok(["Also known as", "Part of", "Agent", "Model", "Sessions", "View", "Follow", "Settings"].every(l => labels.includes(l)) && FiliChatAbout.rows.every(r => r[1] !== ""), "fili-chat: card = aka, membership, agent, model, sessions, view, follow, settings", labels.join());
                ok(FiliChatAbout.rows[0][0] === "Also known as" && FiliChatAbout.rows[0][1] === "fili-chat", "fili-chat: the card says aka fili-chat");
                ok(!FiliChat.open, "fili-chat: the card does not open the drawer");
                FiliShell.popupOpened("panel");
                ok(!FiliChatAbout.open, "fili-chat: card closed by another panel");
                FiliChatAbout.toggle();
                ok(FiliChatAbout.open, "fili-chat: the card reopens");
                FiliChatAbout.close();
            },
            // FiliI18n: tests in English (LANG=C.UTF-8, run.sh); French catalog loaded by hand
            () => {
                ok(FiliI18n.lang === "en" && FiliI18n.tr("Workspace %1", 3) === "Workspace 3" && FiliI18n.num(1.5, 1) === "1.5", "FiliI18n: English without a catalogue, %1 replaced", FiliI18n.lang);
                const saved = FiliI18n.catalog;
                FiliI18n.catalog = t.frCatalog;
                ok(FiliI18n.tr("Workspace %1", 3) === "Espace 3" && FiliI18n.num(1.5, 1) === "1,5" && FiliI18n.tr("not in catalog") === "not in catalog", "FiliI18n: fr.json catalogue (translation, decimal separator, English fallback)", FiliI18n.tr("Workspace %1", 3));
                FiliI18n.catalog = saved;
            },
            // fili-lang: live language change (state in $XDG_STATE_HOME, niri locale.kdl in a test folder)
            wait(() => t.shell('XDG_CONFIG_HOME="$XDG_STATE_HOME/cfg" "$0" set fr && cat "$XDG_STATE_HOME/filigrane/locale" "$XDG_STATE_HOME/cfg/niri/locale.kdl"'.replace('"$0"', t.bin + "/fili-lang")), () => t.shellOut !== null),
            () => ok(t.shellOut.code === 0 && t.shellOut.out.indexOf("fr_") >= 0 && t.shellOut.out.indexOf("Généré par fili-lang") >= 0, "fili-lang set fr: choice saved, niri's locale.kdl written", t.shellOut.out),
            wait(() => {}, () => FiliI18n.lang === "fr", 5000),
            () => ok(FiliI18n.lang === "fr" && FiliI18n.tr("Workspace %1", 3) === "Espace 3", "FiliI18n: suit fili-lang en direct (fr)", FiliI18n.lang),
            wait(() => t.shell(t.bin + "/fili-lang list"), () => t.shellOut !== null),
            () => {
                let l = [];
                try {
                    l = JSON.parse(t.shellOut.out);
                } catch (e) {}
                ok(l.some(x => x.code === "en") && l.some(x => x.code === "fr" && x.current && x.name === "Français"), "fili-lang list: en and fr, fr current", t.shellOut.out);
            },
            wait(() => t.shell('XDG_CONFIG_HOME="$XDG_STATE_HOME/cfg" ' + t.bin + "/fili-lang set system"), () => t.shellOut !== null),
            wait(() => {}, () => FiliI18n.lang === "en", 5000),
            () => ok(FiliI18n.lang === "en" && FiliI18n.tr("Workspace %1", 3) === "Workspace 3", "fili-lang set system: back to the system language (en)", FiliI18n.lang),
            wait(() => t.shell(t.bin + "/fili-net list"), () => t.shellOut !== null, 15000),
            () => {
                let n = null;
                try {
                    n = JSON.parse(t.shellOut.out.trim().split("\n")[0]);
                } catch (e) {}
                ok(n && typeof n.device === "string" && Array.isArray(n.networks), "fili-net list: JSON { device, networks }", t.shellOut.out);
            },
            // fili-bar layout (module.toml manifests, ~/.config/filigrane/fili-bar.toml optional)
            wait(() => {}, () => BarLayout.ready, 5000),
            () => {
                const p = FiliTheme.parseToml('[modules]\nleft = ["logo",\n    "workspaces", # comment\n]\nright = ["power", "clock"]\n');
                ok(JSON.stringify(p.modules.left) === '["logo","workspaces"]' && JSON.stringify(p.modules.right) === '["power","clock"]', "FiliTheme.parseToml: array over several lines", JSON.stringify(p));
                ok(BarLayout.ready && BarLayout.left.join() === "logo,workspaces,appmenu" && BarLayout.right.indexOf("clock") > 0, "BarLayout: without a file, default modules (manifests)", BarLayout.left.join());
                BarLayout.parsed = FiliTheme.parseToml('[modules.clock]\nside = "left"\norder = 5\n[modules.power]\nenabled = false\n');
                ok(BarLayout.left.join() === "clock,logo,workspaces,appmenu", "BarLayout: [modules.<name>] changes side and order", BarLayout.left.join());
                ok(BarLayout.right.indexOf("clock") < 0 && BarLayout.right.indexOf("power") < 0, "BarLayout: enabled = false removes the module", BarLayout.right.join());
                BarLayout.parsed = ({});
                BarLayout.parsed = FiliTheme.parseToml('[modules]\nright = ["my-thing", "..."]\n');
                ok(BarLayout.right.join() === "my-thing," + BarLayout.defaultRight.join(), "BarLayout: ... = the default modules", BarLayout.right.join());
                BarLayout.parsed = FiliTheme.parseToml('[modules]\nleft = ["logo", "logo"]\nright = ["power", "clock", "../etc", "Nope", "ghost"]\n');
                ok(BarLayout.left.join() === "logo" && BarLayout.right.join() === "power,clock,ghost", "BarLayout: invalid names and duplicates ignored", BarLayout.right.join());
            },
            wait(() => {}, () => t.find(t.bar.contentItem, "network") === null && t.find(t.bar.contentItem, "clock") !== null, 5000),
            () => {
                ok(t.find(t.bar.contentItem, "appmenu") === null && t.find(t.bar.contentItem, "power") !== null, "fili-bar: only the modules of the file (menu absent)");
                ok(FiliPanel.ring().join() === "power", "fili-bar: the panel of a removed module is unregistered", FiliPanel.ring().join());
                BarLayout.parsed = ({});
            },
            wait(() => {}, () => t.find(t.bar.contentItem, "network") !== null && t.find(t.bar.contentItem, "appmenu") !== null, 5000),
            () => ok(FiliPanel.ring().length === 9 && FiliPanel.ring().indexOf("status") < 0, "fili-bar: default modules back, panels registered again (status panel only while an indicator is active)", FiliPanel.ring().join()),
            () => {
                const r = t.find(t.bar.contentItem, "rec");
                ok(r && r.display === "both" && r.trayMode === "never" && r.inDrawer, "fili-bar: default display/tray (both, never)", r ? r.display + "/" + r.trayMode : "absent");
                BarLayout.parsed = FiliTheme.parseToml('[modules.status]\ndisplay = "icon"\ntray = "always"\n[modules.bogus]\ndisplay = "x"\n');
            },
            wait(() => {}, () => t.find(t.bar.contentItem, "rec")?.display === "icon", 3000),
            () => {
                const r = t.find(t.bar.contentItem, "rec");
                ok(r && r.display === "icon" && r.trayMode === "always" && !r.inDrawer, "fili-bar: display and tray of a module followed by its items (collapsed drawer = hidden)", r ? r.display + "/" + r.trayMode + "/" + r.inDrawer : "absent");
                ok(BarLayout.choice("bogus", "display", ["both", "icon", "value"], "both") === "both", "BarLayout.choice: invalid value = fallback");
                BarLayout.parsed = ({});
            },
            // Squeezed bar: levels go up one step at a time while the right row does not fit, and come back with room to spare
            () => {
                const seen = [];
                ok(BarLayout.nextLevel(0, 800, 700, seen) === 0, "bar squeeze: fits -> level unchanged");
                ok(BarLayout.nextLevel(0, 600, 700, seen) === 1 && BarLayout.nextLevel(3, 600, 700, seen) === 4, "bar squeeze: overflow -> next level");
                ok(BarLayout.nextLevel(4, 100, 700, seen) === 4, "bar squeeze: last level holds");
                ok(BarLayout.nextLevel(2, 650, 560, [700, 640]) === 2 && BarLayout.nextLevel(2, 660, 560, [700, 640]) === 1, "bar squeeze: back down only when the lower level fits with room to spare");
                ok(BarLayout.nextLevel(1, 900, 500, []) === 1, "bar squeeze: unknown lower width = no step down");
                ok(BarLayout.level("media", "compact_at") === 1 && BarLayout.level("clock", "compact_at") === 2 && BarLayout.level("resources", "drawer_at") === 3 && BarLayout.level("logo", "compact_at") === 0, "bar squeeze: levels of the manifests (media 1, clock 2, resources drawer 3)");
                t.bar.level = 1;
            },
            wait(() => {}, () => t.find(t.bar.contentItem, "media")?.display === "icon", 3000),
            () => {
                const clk = t.find(t.bar.contentItem, "clock").parent;
                ok(!clk.compact && t.find(t.bar.contentItem, "cpu").trayMode === "never", "bar squeeze 1: media icon alone, clock and resources untouched");
                t.bar.level = 2;
            },
            wait(() => {}, () => t.find(t.bar.contentItem, "clock")?.parent.compact === true, 3000),
            () => {
                ok(t.find(t.bar.contentItem, "clock").parent.compact, "bar squeeze 2: clock without the date");
                t.bar.level = 3;
            },
            wait(() => {}, () => t.find(t.bar.contentItem, "cpu")?.trayMode === "always", 3000),
            () => {
                ok(t.find(t.bar.contentItem, "cpu").trayMode === "always" && !t.find(t.bar.contentItem, "cpu").inDrawer, "bar squeeze 3: resources go into the drawer (hidden while it is folded)");
                BarLayout.parsed = FiliTheme.parseToml('[modules.media]\ndisplay = "value"\n[modules.resources]\ntray = "idle"\n');
            },
            wait(() => {}, () => t.find(t.bar.contentItem, "cpu")?.trayMode === "idle", 3000),
            () => {
                ok(t.find(t.bar.contentItem, "media").display === "value", "bar squeeze: what the user chose (display, tray) wins over the squeeze");
                BarLayout.parsed = ({});
                t.bar.level = 0;
            },
            wait(() => {}, () => t.find(t.bar.contentItem, "cpu")?.trayMode === "never" && t.find(t.bar.contentItem, "media")?.display === "both", 3000),
            // Status indicators merged into one icon: one row per active indicator in the panel
            () => {
                const st = t.find(t.bar.contentItem, "status");
                ok(st && !st.visible, "bar status: nothing active, no icon");
                const rec = t.find(t.bar.contentItem, "rec"), air = t.find(t.bar.contentItem, "air");
                rec.apply({ text: String.fromCodePoint(0xf111) + " REC", "class": "recording" });
                air.apply({ text: String.fromCodePoint(0xf072), "class": "" });
            },
            wait(() => {}, () => BarState.statusRows.length === 2, 3000),
            () => {
                const st = t.find(t.bar.contentItem, "status");
                ok(FiliPanel.ring().indexOf("status") >= 0, "bar status: panel in the keyboard ring while an indicator is active");
                ok(st.visible && FiliTheme.value(st.text) === "2" && st.cls === "rec", "bar status: two indicators = one icon with the count, the recording first", st.text + "/" + st.cls);
                act("status", L);
                ok(FiliPanel.view === "status", "bar status: click -> status panel", FiliPanel.view);
                const rows = t.findAll(FiliPanel.loaded, "status-rec").concat(t.findAll(FiliPanel.loaded, "status-air"));
                ok(rows.length === 2, "fili-panel status: a row per active indicator", rows.length);
                FiliTheme.ran = [];
                rows[0].press(L);
                ok(FiliTheme.ran.join("\n").indexOf("bar-toggle rec") >= 0 && FiliPanel.view === "", "fili-panel status: click on a row runs its action and closes the panel", JSON.stringify(FiliTheme.ran));
                t.find(t.bar.contentItem, "rec").apply({ text: "" });
                t.find(t.bar.contentItem, "air").apply({ text: "" });
            },
            // Edge of the bar: [bar] edge, a column on the left and the right
            () => {
                BarLayout.parsed = FiliTheme.parseToml('[bar]\nedge = "left"\n');
                const a = t.bar.anchors;
                ok(FiliTheme.barEdge === "left" && FiliTheme.barVertical && a.left && a.top && a.bottom && !a.right, "fili-bar: edge = left -> column anchored on the left", FiliTheme.barEdge);
                BarLayout.parsed = FiliTheme.parseToml('[bar]\nedge = "bottom"\n');
                ok(FiliTheme.barEdge === "bottom" && !FiliTheme.barVertical && a.bottom && a.left && a.right && !a.top, "fili-bar: edge = bottom -> row at the bottom", FiliTheme.barEdge);
                BarLayout.parsed = FiliTheme.parseToml('[bar]\nedge = "nope"\n');
                ok(FiliTheme.barEdge === "top" && a.top, "fili-bar: invalid edge -> top", FiliTheme.barEdge);
                // Screens: all by default, a list picks them, a list that matches nothing gives every screen (never no bar)
                const n = Quickshell.screens.length, first = Quickshell.screens[0].name;
                BarLayout.parsed = ({});
                ok(BarLayout.barScreens.length === n && BarLayout.screensChoice === "all", "fili-bar: default screens = all", BarLayout.barScreens.length + "/" + n);
                BarLayout.parsed = FiliTheme.parseToml('[bar]\nscreens = ["' + first + '"]\n');
                ok(BarLayout.barScreens.length === 1 && BarLayout.barScreens[0].name === first, "fili-bar: screens = [name] -> that output only", BarLayout.barScreens.length);
                BarLayout.parsed = FiliTheme.parseToml('[bar]\nscreens = ["no-such-output"]\n');
                ok(BarLayout.barScreens.length === n, "fili-bar: screens without a known output -> all (never without a bar)", BarLayout.barScreens.length);
                BarLayout.parsed = FiliTheme.parseToml('[bar]\nscreens = "all"\n');
                ok(BarLayout.barScreens.length === n, "fili-bar: screens = \"all\"", BarLayout.barScreens.length);
                BarLayout.parsed = ({});
            },
            // Right click on the bar background: position of the bar and shortcut to the settings
            wait(() => FiliPanel.openBarMenu(t.bar, 100, 10), () => FiliPanel.loaded !== null && t.find(FiliPanel.loaded, "bar-edge") !== null, 5000),
            () => {
                ok(FiliPanel.view === "barmenu" && FiliPanel.gearButton.visible && FiliPanel.gearButton.page === "bar" && t.find(FiliPanel.loaded, "bar-screens") !== null, "fili-bar: right click -> position panel, bar outputs + settings");
                FiliPanel.close();
            },
            // Script plugin: a manifest with a cmd, no QML
            () => {
                const m = Object.assign({}, BarLayout.manifests);
                m.hello = { cmd: "printf '{\"text\":\"hi\",\"tooltip\":\"tip\"}\\n'", side: "right", order: "1", title: "Hello", click: "true", signal: "40" };
                BarLayout.manifests = m;
            },
            wait(() => {}, () => t.find(t.bar.contentItem, "hello")?.text === "hi", 5000),
            () => {
                const h = t.find(t.bar.contentItem, "hello");
                ok(h && h.text === "hi" && h.title === "Hello" && h.signal === 40 && h.click.indexOf("true") > 0 && BarLayout.right[0] === "hello", "fili-bar: script plugin (manifest with cmd, no QML)", h ? h.text + "/" + h.title + "/" + h.signal : "absent");
                ok(h && h.cmd.indexOf("FILI_BAR_OPTIONS='") >= 0 && h.cmd.indexOf("/filigrane/bar/hello.toml") > 0, "fili-bar: plugin script, FILI_BAR_OPTIONS = ~/.config/filigrane/bar/<name>.toml", h ? h.cmd : "absent");
                FiliI18n.catalog = { "Open instantly": "Ouvrir" };
                FiliI18n.pluginCatalog = { "Plugin zzz": "Plugin en français", "Open instantly": "autre" };
                ok(FiliI18n.tr("Plugin zzz") === "Plugin en français" && FiliI18n.tr("Nothing here") === "Nothing here" && FiliI18n.tr("Open instantly") === "Ouvrir", "FiliI18n: a plugin's catalogue, the shell's one wins", FiliI18n.tr("Open instantly"));
                FiliI18n.catalog = ({});
                FiliI18n.pluginCatalog = ({});
                const m = Object.assign({}, BarLayout.manifests);
                delete m.hello;
                BarLayout.manifests = m;
            },
            wait(() => {}, () => t.find(t.bar.contentItem, "hello") === null, 5000),
            () => ok(BarLayout.right.indexOf("hello") < 0, "fili-bar: script plugin removed"),
        ];
        tick.start();
    }
}
