pragma Singleton
// État de niri (espaces de travail, fenêtres, disposition clavier) depuis son flux d'événements (socket $NIRI_SOCKET):
// Quickshell n'a pas de module niri, le flux d'événements donne tout sans interroger.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: niri
    property var workspaces: []
    property var windows: ({})
    property var focusedId: null
    property var layouts: []
    property int layout: 0
    // Disposition utilisée avant l'actuelle (bascule « précédente », comme Ctrl+Espace du sélecteur d'Omarchy)
    property int previousLayout: -1

    readonly property var focused: focusedId !== null ? windows[focusedId] ?? null : null

    function action(...args) {
        if (FiliTheme.testing)
            FiliTheme.ran = FiliTheme.ran.concat(["niri msg action " + args.join(" ")]);
        else
            Quickshell.execDetached(["niri", "msg", "action", ...args]);
    }

    // Fenêtre d'un lecteur MPRIS (id niri, ou null): les navigateurs publient "…instance<pid>" (le pid de la fenêtre),
    // les autres lecteurs se retrouvent par leur entrée de bureau (desktopEntry = app_id); s'il reste plusieurs
    // fenêtres (onglets, PWA), celle dont le titre contient la piste; sinon (la piste joue dans un onglet de fond,
    // dont le titre n'apparaît pas) une fenêtre du navigateur plutôt qu'une PWA (app_id "chrome-site__-Default")
    function playerWindow(wins, dbusName, desktopEntry, track) {
        const pid = /\.instance(\d+)$/.exec(dbusName ?? "");
        const entry = (desktopEntry ?? "").toLowerCase();
        let c = Object.values(wins).filter(w => pid ? w.pid === Number(pid[1]) : entry !== "" && (w.app_id ?? "").toLowerCase() === entry);
        if (c.length > 1 && track) {
            const t = c.filter(w => (w.title ?? "").indexOf(track) >= 0);
            const nonPwa = c.filter(w => (w.app_id ?? "").indexOf("__") < 0);
            c = t.length > 0 ? t : nonPwa.length > 0 ? nonPwa : c;
        }
        return c.length > 0 ? c[0].id : null;
    }

    // Code court d'une disposition pour la barre: « French (BEPO, AFNOR) » -> fr, « English (Australia) » -> au
    function shortName(name) {
        const m = name.match(/\((Australian|Australia|US|UK)/);
        if (m)
            return { Australian: "au", Australia: "au", US: "us", UK: "gb" }[m[1]];
        return name.slice(0, 2).toLowerCase();
    }
    function setLayout(i) {
        if (i !== layout) {
            previousLayout = layout;
            layout = i;
        }
    }
    function selectLayout(i) {
        action("switch-layout", String(i));
    }

    function setWindows(m) {
        windows = m;
    }
    // Champs d'une fenêtre lus par la barre: niri renvoie la fenêtre entière à chaque déplacement ou redimensionnement
    // (layout), sans rien changer de ce qui est affiché
    function same(a, b) {
        return a && a.title === b.title && a.app_id === b.app_id && a.workspace_id === b.workspace_id;
    }

    // Flux d'événements lu directement sur le socket de niri (requête "EventStream"), sans processus `niri msg`
    Socket {
        id: stream
        path: Quickshell.env("NIRI_SOCKET") ?? ""
        connected: path !== ""
        onConnectedChanged: {
            if (connected) {
                write('"EventStream"\n');
                flush();
            } else {
                // niri relancé ou flux coupé: on se reconnecte
                restart.start();
            }
        }
        parser: SplitParser {
            onRead: line => {
                let ev;
                try {
                    ev = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (ev.WorkspacesChanged) {
                    niri.workspaces = ev.WorkspacesChanged.workspaces.slice().sort((a, b) => a.output === b.output ? a.idx - b.idx : a.output.localeCompare(b.output));
                } else if (ev.WorkspaceActivated) {
                    const id = ev.WorkspaceActivated.id;
                    const out = (niri.workspaces.find(w => w.id === id) || {}).output;
                    niri.workspaces = niri.workspaces.map(w => w.output === out ? Object.assign({}, w, { is_active: w.id === id }) : w);
                } else if (ev.WindowsChanged) {
                    const m = {};
                    for (const w of ev.WindowsChanged.windows) {
                        m[w.id] = w;
                        if (w.is_focused)
                            niri.focusedId = w.id;
                    }
                    niri.setWindows(m);
                } else if (ev.WindowOpenedOrChanged) {
                    const w = ev.WindowOpenedOrChanged.window;
                    if (niri.same(niri.windows[w.id], w)) {
                        niri.windows[w.id] = w;
                    } else {
                        const m = Object.assign({}, niri.windows);
                        m[w.id] = w;
                        niri.setWindows(m);
                    }
                    if (w.is_focused)
                        niri.focusedId = w.id;
                } else if (ev.WindowClosed) {
                    const m = Object.assign({}, niri.windows);
                    delete m[ev.WindowClosed.id];
                    niri.setWindows(m);
                } else if (ev.WindowFocusChanged) {
                    niri.focusedId = ev.WindowFocusChanged.id;
                } else if (ev.KeyboardLayoutsChanged) {
                    niri.layouts = ev.KeyboardLayoutsChanged.keyboard_layouts.names;
                    niri.layout = ev.KeyboardLayoutsChanged.keyboard_layouts.current_idx;
                    niri.previousLayout = -1;
                } else if (ev.KeyboardLayoutSwitched) {
                    niri.setLayout(ev.KeyboardLayoutSwitched.idx);
                }
            }
        }
    }
    Timer {
        id: restart
        interval: 1000
        onTriggered: stream.connected = stream.path !== ""
    }

    // Requête ponctuelle (ex. "Outputs") sur une seconde connexion: rappel avec la réponse (champ Ok, ou null en
    // erreur); les requêtes partent une à une, la connexion se ferme quand il n'y en a plus
    property var pending: []
    function request(name, done) {
        pending = pending.concat([{ name: name, done: done }]);
        if (!req.connected)
            req.connected = req.path !== "";
        else if (pending.length === 1)
            req.send();
    }
    Socket {
        id: req
        path: stream.path
        function send() {
            write(JSON.stringify(niri.pending[0].name) + "\n");
            flush();
        }
        onConnectedChanged: if (connected && niri.pending.length) send()
        parser: SplitParser {
            onRead: line => {
                const p = niri.pending[0];
                niri.pending = niri.pending.slice(1);
                let r = null;
                try {
                    r = JSON.parse(line).Ok ?? null;
                } catch (e) {}
                // Un rappel en erreur (demandeur détruit entre-temps) ne bloque pas la file
                try {
                    if (p)
                        p.done(r ? r[p.name] ?? r : null);
                } catch (e) {}
                if (niri.pending.length)
                    req.send();
                else
                    req.connected = false;
            }
        }
    }
}
