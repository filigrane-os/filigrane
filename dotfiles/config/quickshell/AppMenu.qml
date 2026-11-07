pragma Singleton
// fili-appmenu: menu de l'application qui a le focus, dans la fili-bar (menu global à la Mac OS X).
//
// Source des menus, dans l'ordre:
//   1. la barre de menus de l'application, lue par AT-SPI avec ~/.local/bin/fili-appmenu (apps/fili-appmenu): GTK3,
//      Qt, Firefox... Seules les applications qui exportent leur accessibilité en ont une; chaque menu GTK3 ne se remplit
//      qu'à l'ouverture (`expand`);
//   2. sinon un menu de repli, écrit à la main: ~/.config/filigrane/appmenu/APP_ID.json (dotfiles/config/filigrane/appmenu/,
//      couche personnelle comprise), qui complète _default.json.
// Dans les deux cas: menu de l'application (nom en gras, « Quitter »), menus propres, menu Fenêtre (niri). Ils remplacent
// le titre de la fenêtre dans la fili-bar (BarAppMenu): tous affichés, ou seulement le nom de l'application quand ils ne
// tiennent pas (le reste passe dans un titre «…»). Souris, ou clavier: `fili-shell appmenu` (Mod+F10).
//
// Fichier de repli: { "name": "Chrome", "app": [ENTRÉE], "menus": [ { "label": "File", "children": [ENTRÉE] } ] }
//   ENTRÉE = { "label", "exec": "commande shell" } ou { "label", "niri": ["action", "argument"] } ou { "sep": true }
//            ou { "label", "children": [ENTRÉE] } (sous-menu). Textes en anglais, traduits par FiliI18n; %1 = nom de l'appli.
// Aucun processus ne reste: fili-appmenu est lancé au changement de fenêtre active, une seule fois par application
// sans menu (la réponse « rien » est retenue une minute).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.bar

Singleton {
    id: am

    // Fenêtre dont on montre le menu: la fenêtre active de niri, gardée tant que le menu est ouvert. Un menu pris au
    // clavier reçoit le focus et niri n'annonce alors plus de fenêtre active (null): ce n'est pas un changement d'application.
    readonly property var niriWin: Niri.focused
    property var win: null
    onNiriWinChanged: {
        if (niriWin || !open)
            win = niriWin;
    }
    Component.onCompleted: win = niriWin
    // Le tiroir fili-chat a le focus clavier: son menu (appmenu/fili-chat.json) remplace celui de la fenêtre. Gardé tant
    // qu'un menu est ouvert (un menu pris au clavier reçoit le focus à sa place) et pendant un appui sur un titre de la
    // barre: la barre ne prend pas le clavier, niri rend alors le focus à la fenêtre précédente, et le menu changerait
    // sous la souris avant la fin du clic
    property bool chatFocus: false
    property bool holdChat: false
    readonly property bool chatNow: FiliChat.focused
    onChatNowChanged: {
        if (chatNow || !(open || holdChat))
            chatFocus = chatNow;
    }
    onOpenChanged: {
        if (!open && !holdChat && !chatNow)
            chatFocus = false;
    }
    function pressTitle() {
        if (chatFocus) {
            holdChat = true;
            holdTimer.restart();
        }
    }
    Timer {
        id: holdTimer
        interval: 1500
        onTriggered: {
            am.holdChat = false;
            if (!am.open && !am.chatNow)
                am.chatFocus = false;
        }
    }
    readonly property var winId: chatFocus ? "fili-chat" : (win ? win.id : null)
    readonly property string appId: chatFocus ? "fili-chat" : (win?.app_id ?? "")
    readonly property string dir: Quickshell.env("FILI_APPMENU_DIR") || Quickshell.env("HOME") + "/.config/filigrane/appmenu"
    readonly property string key: appId.replace(/[^A-Za-z0-9._-]/g, "_")

    // Menus affichés dans la barre (ENTRÉE normalisées, voir norm) et leur origine: "atspi", "fallback" ou ""
    property var menus: []
    property string source: ""
    // Réponse de fili-appmenu attendue: rien d'affiché en attendant
    property bool pending: false
    property var appMenus: []
    property var spec: ({})
    property var generic: ({})
    property var noMenu: ({})
    property int gen: 0
    readonly property string appName: spec.name ?? prettyName(appId)

    // Menu ouvert (index dans menus, -1 = fermé), colonnes de menus ouvertes, entrée choisie et ordonnée du haut de
    // chaque colonne
    property int openIndex: -1
    property var levels: []
    property var sel: []
    property var levelY: []
    property real anchorX: 0
    property var screen: null
    readonly property bool open: openIndex >= 0
    // Menu ouvert au clavier (fili-shell appmenu): il prend le focus clavier, sinon l'application garde le sien
    property bool keyboard: false
    // Menu ouvert depuis «…» (les menus qui ne tiennent plus dans la barre): la première colonne les liste
    property bool more: false
    // Un widget BarAppMenu par barre (écran): titres affichés (fit), titre «…» (overflow)
    property var hosts: ({})
    function register(host) {
        hosts[host.bar?.screen?.name ?? ""] = host;
    }

    function prettyName(id) {
        if (!id)
            return "";
        const n = id.split(".").pop().replace(/^chrome-/, "").replace(/__.*$/, "");
        return n.charAt(0).toUpperCase() + n.slice(1);
    }

    function parse(text) {
        try {
            return JSON.parse(text) ?? {};
        } catch (e) {
            return {};
        }
    }

    // Raccourcis des binds de niri (config.kdl, puis local.kdl qui complète ou remplace): une entrée de repli qui lance
    // la même commande ou la même action que un bind affiche sa touche, sans qu'on la recopie (elle ne peut pas dériver).
    // Clé: "niri:ACTION ARGS" ou "exec:COMMANDE" (spawn et spawn-sh, sans $HOME/.local/bin/ ni /usr/bin/); valeur: "Super+Q".
    readonly property string niriDir: Quickshell.env("FILI_NIRI_DIR") || (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/niri"
    property var bindsMain: ({})
    property var bindsLocal: ({})
    readonly property var binds: Object.assign({}, bindsMain, bindsLocal)
    onBindsChanged: rebuild()
    function parseBinds(text) {
        const out = {};
        let inBinds = false;
        for (const line of text.split("\n")) {
            if (/^binds\s*\{/.test(line)) {
                inBinds = true;
                continue;
            }
            if (inBinds && /^\}/.test(line)) {
                inBinds = false;
                continue;
            }
            if (!inBinds || /^\s*\/\//.test(line))
                continue;
            const m = /^\s*([A-Za-z0-9_+]+)\s[^{]*\{\s*([a-z0-9-]+)((?:\s+(?:"[^"]*"|[^\s";}]+))*)\s*;/.exec(line);
            if (!m)
                continue;
            const args = (m[3].match(/"[^"]*"|[^\s"]+/g) ?? []).map(a => a.replace(/^"|"$/g, ""));
            let id;
            if (m[2] === "spawn")
                id = "exec:" + args.join(" ");
            else if (m[2] === "spawn-sh")
                id = "exec:" + (args[0] ?? "").replace("$HOME/.local/bin/", "").replace(/^\/usr\/bin\//, "");
            else
                id = "niri:" + [m[2]].concat(args).join(" ");
            if (!(id in out))
                out[id] = m[1].replace(/^Mod\+/, "Super+").replace(/\+Mod\+/g, "+Super+");
        }
        return out;
    }
    FileView {
        path: am.niriDir + "/config.kdl"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: am.bindsMain = am.parseBinds(text())
        onLoadFailed: am.bindsMain = ({})
    }
    FileView {
        path: am.niriDir + "/local.kdl"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: am.bindsLocal = am.parseBinds(text())
        onLoadFailed: am.bindsLocal = ({})
    }
    // Touche d'une entrée de repli (champ "keys" du fichier, sinon le bind niri de la même action ou commande)
    function bindKey(e) {
        if (e.niri)
            return binds["niri:" + e.niri.join(" ")] ?? "";
        if (e.exec)
            return binds["exec:" + e.exec] ?? "";
        return "";
    }

    // Commandes de l'application impossibles maintenant: champ « disabled » de son fichier de contexte
    // ($XDG_RUNTIME_DIR/fili/context/PID.json, voir le skill filigrane-ui), relu à l'ouverture du menu. Une entrée de repli
    // « ... ctl --pid %pid action NOM » est grisée quand NOM y figure.
    property var disabled: []
    onDisabledChanged: rebuild()
    function cmdDisabled(exec) {
        const m = /\bctl\b.*\baction ([a-z-]+)/.exec(exec ?? "");
        return m !== null && disabled.indexOf(m[1]) >= 0;
    }
    function onState(text) {
        let list = [];
        try {
            list = JSON.parse(text).disabled ?? [];
        } catch (e) {
            list = [];
        }
        // Rien ne change quand la liste est la même (évite de reconstruire les menus à chaque ouverture)
        if (list.join(",") !== disabled.join(","))
            disabled = list;
    }
    function readState() {
        if (!win || !win.pid || source !== "fallback" || JSON.stringify(spec).indexOf("%pid") < 0) {
            if (disabled.length > 0)
                disabled = [];
            return;
        }
        stateReader.command = ["cat", (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/fili/context/" + win.pid + ".json"];
        stateReader.running = false;
        stateReader.running = true;
    }
    Process {
        id: stateReader
        stdout: StdioCollector {
            onStreamFinished: am.onState(text)
        }
    }

    // Entrée normalisée, qu'elle vienne d'AT-SPI ou d'un fichier de repli
    function norm(e) {
        if (e.sep || e.kind === "sep")
            return { label: "", kind: "sep", enabled: false, check: 0, keys: "", svc: "", path: "", exec: "", niri: null, children: [] };
        const kids = (e.children ?? []).map(c => norm(c)).filter(c => c.kind === "sep" || c.label !== "");
        return {
            label: e.label ?? "",
            kind: e.kind ?? (kids.length > 0 ? "sub" : "item"),
            enabled: e.enabled ?? !cmdDisabled(e.exec),
            check: e.check ?? 0,
            keys: e.keys ?? bindKey(e),
            svc: e.svc ?? "",
            path: e.path ?? "",
            exec: e.exec ?? "",
            niri: e.niri ?? null,
            children: kids
        };
    }

    // Menus de la barre: menu de l'application, menus propres (AT-SPI ou repli), menu Fenêtre
    function rebuild() {
        if ((!win && !chatFocus) || pending) {
            menus = [];
            return;
        }
        const own = source === "atspi" ? appMenus : (spec.menus ?? []).map(m => norm(m));
        // Nom recalculé ici: appName (liaison) n'est pas encore à jour quand spec vient de changer
        // Les menus communs (Quitter, Fenêtre) agissent sur la fenêtre active de niri: pas pour le tiroir
        const app = norm({ label: spec.name ?? prettyName(appId), kind: "sub", children: [].concat(spec.app ?? [], chatFocus ? [] : generic.app ?? []) });
        // Menu Fenêtre commun, suivi des entrées de l'application (clé "window" de son fichier de menu)
        const own_w = spec.window ?? [];
        const w = generic.window && !chatFocus ? [norm({ label: "Window", children: [].concat(generic.window, own_w.length > 0 ? [{ sep: true }] : [], own_w) })] : [];
        menus = [].concat(app.children.length > 0 ? [app] : [], own, w);
    }
    onSpecChanged: rebuild()
    onGenericChanged: rebuild()

    // Fenêtre active changée: menu fermé, menus relus (une fois la rafale d'événements niri passée)
    onWinIdChanged: debounce.restart()
    Timer {
        id: debounce
        interval: 100
        onTriggered: am.refresh()
    }
    function refresh() {
        gen++;
        query.running = false;
        expander.running = false;
        close();
        appMenus = [];
        source = "";
        pending = false;
        disabled = [];
        const w = chatFocus ? null : win;
        // Un fichier de repli de l'application est un choix délibéré: il passe devant AT-SPI (la MenuBar de Qt Quick
        // Controls y figure sans aucune entrée, ses menus ne sont pas exportés)
        if (w && w.pid && (spec.menus ?? []).length === 0 && Date.now() - (noMenu[w.app_id] ?? 0) > 60000) {
            pending = true;
            query.queryGen = gen;
            query.command = [FiliTheme.bin + "/fili-appmenu", "menu", String(w.pid), w.title ?? ""];
            query.running = true;
        } else {
            source = "fallback";
        }
        rebuild();
    }
    Process {
        id: query
        property int queryGen: -1
        stdout: StdioCollector {
            onStreamFinished: am.onMenu(query.queryGen, text)
        }
    }
    function onMenu(g, text) {
        if (g !== gen)
            return;
        const d = parse(text);
        pending = false;
        if (d.items && d.items.length > 0) {
            appMenus = d.items.map(i => norm(i)).filter(i => i.label !== "");
            source = "atspi";
        } else {
            noMenu[appId] = Date.now();
            source = "fallback";
        }
        rebuild();
    }

    // Menus de repli de l'application et menus communs, relus quand le fichier change
    FileView {
        path: am.key !== "" ? am.dir + "/" + am.key + ".json" : ""
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: am.spec = am.parse(text())
        onLoadFailed: am.spec = ({})
    }
    FileView {
        path: am.dir + "/_default.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: am.generic = am.parse(text())
        onLoadFailed: am.generic = ({})
    }

    // ───────── Ouverture, navigation, action ─────────
    // Clic sur un titre (host: le BarAppMenu de la barre). Le titre d'index host.fit est «…» quand des menus débordent
    function toggle(index, item, bar, host) {
        if (openIndex === index)
            close();
        else
            openAt(index, item, bar, host);
    }
    // Menu ouvert à la souris: passer sur un autre titre l'ouvre à son tour
    function hoverTitle(index, item, bar, host) {
        if (open && !keyboard && openIndex !== index)
            openAt(index, item, bar, host);
    }
    function openAt(index, item, bar, host) {
        const m = menus[index];
        if (!m)
            return;
        FiliTooltip.hide();
        FiliShell.popupOpened("appmenu");
        readState();
        anchorX = item.mapToItem(null, 0, 0).x;
        screen = bar?.screen ?? null;
        more = host ? host.overflow && index === host.fit : false;
        openIndex = index;
        // «…»: la première colonne est la liste des menus restants, chacun ouvre sa colonne
        levels = [more ? menus.slice(host.fit) : m.children];
        sel = [-1];
        levelY = [0];
        if (!more)
            fillIfLazy(0, m);
    }
    function close() {
        openIndex = -1;
        levels = [];
        sel = [];
        levelY = [];
        keyboard = false;
        more = false;
    }

    // ───────── Clavier (fili-shell appmenu, Mod+F10): ↑/↓ entrée, → sous-menu ou menu suivant, ← retour ou menu précédent,
    // Entrée ou Espace agir, Échap fermer ─────────
    // Commande `fili-shell appmenu [toggle|close]`: ouvre le premier menu de la barre de l'écran courant, au clavier
    function summon(action) {
        if (action === "close" || open) {
            close();
            return;
        }
        const host = hosts[Quickshell.screens[0]?.name ?? ""] ?? Object.values(hosts)[0];
        if (!host || menus.length === 0)
            return;
        const first = host.titleAt(0);
        if (!first)
            return;
        openAt(0, first, host.bar, host);
        keyboard = true;
        selectFirst(0);
    }
    // Premier élément choisissable d'une colonne (ni séparateur, ni grisé), -1 s'il n'y en a pas
    function firstEnabled(entries) {
        return entries.findIndex(e => e.kind !== "sep" && e.enabled);
    }
    function selectFirst(level) {
        sel = sel.slice(0, level).concat([firstEnabled(levels[level] ?? [])]);
    }
    // Entrée suivante (d = 1) ou précédente (-1) de la dernière colonne, en bouclant
    function keyMove(d) {
        const level = levels.length - 1;
        const es = levels[level] ?? [];
        let i = sel[level] ?? -1;
        if (i < 0)
            i = d > 0 ? -1 : 0;
        for (let n = 0; n < es.length; n++) {
            i = (i + d + es.length) % es.length;
            if (es[i].kind !== "sep" && es[i].enabled) {
                sel = sel.slice(0, level).concat([i]);
                return;
            }
        }
    }
    // Ordonnée de la ligne i de la colonne level (la colonne la calcule: défilement compris)
    function rowY(level, i) {
        return repeater.itemAt(level)?.rowY(i) ?? 0;
    }
    function keyRight() {
        const level = levels.length - 1;
        const e = (levels[level] ?? [])[sel[level]];
        if (e && e.kind === "sub" && e.enabled) {
            enter(level, e, sel[level], rowY(level, sel[level]));
            selectFirst(level + 1);
        } else {
            switchMenu(1);
        }
    }
    function keyLeft() {
        const level = levels.length - 1;
        if (level > 0) {
            levels = levels.slice(0, level);
            levelY = levelY.slice(0, level);
            sel = sel.slice(0, level);
        } else {
            switchMenu(-1);
        }
    }
    function keyActivate() {
        const level = levels.length - 1;
        const e = (levels[level] ?? [])[sel[level]];
        if (!e)
            return;
        if (e.kind === "sub")
            keyRight();
        else
            activate(e);
    }
    // Titre voisin de la barre (d = ±1, «…» compris, en boucle)
    function switchMenu(d) {
        const host = hosts[screen?.name ?? ""] ?? Object.values(hosts)[0];
        const n = host ? host.fit + (host.overflow ? 1 : 0) : 0;
        if (n < 2)
            return;
        const index = (openIndex + d + n) % n;
        const title = host?.titleAt(index);
        if (!title)
            return;
        const kb = keyboard;
        openAt(index, title, host.bar, host);
        keyboard = kb;
        selectFirst(0);
    }
    // Survol ou clic d'une entrée: son sous-menu s'ouvre à droite, aligné sur elle, les colonnes suivantes se ferment
    function enter(level, entry, index, y) {
        sel = sel.slice(0, level).concat([index]);
        if (entry.kind === "sub") {
            levels = levels.slice(0, level + 1).concat([entry.children]);
            levelY = levelY.slice(0, level + 1).concat([y]);
            sel = sel.concat([-1]);
            fillIfLazy(level + 1, entry);
        } else {
            levels = levels.slice(0, level + 1);
            levelY = levelY.slice(0, level + 1);
        }
    }
    function activate(e) {
        if (!e.enabled || e.kind !== "item")
            return;
        close();
        if (e.exec) {
            // %pid: processus de la fenêtre dont on montre le menu (l'application visée par ses commandes de contrôle)
            FiliTheme.run(e.exec.replace(/%pid/g, win ? String(win.pid ?? "") : ""));
        } else if (e.niri) {
            Niri.action(...e.niri);
        } else if (e.svc) {
            const cmd = [FiliTheme.bin + "/fili-appmenu", "do", e.svc, e.path];
            if (FiliTheme.testing)
                FiliTheme.ran = FiliTheme.ran.concat([cmd.join(" ")]);
            else
                Quickshell.execDetached(cmd);
        }
    }

    // Sous-menu AT-SPI vide (GTK3, Firefox le remplissent à l'ouverture): demandé à fili-appmenu, colonne mise à jour
    function fillIfLazy(depth, entry) {
        if (source !== "atspi" || entry.children.length > 0 || entry.svc === "")
            return;
        expander.running = false;
        expander.target = entry;
        expander.depth = depth;
        expander.expandGen = gen;
        expander.command = [FiliTheme.bin + "/fili-appmenu", "expand", entry.svc, entry.path];
        expander.running = true;
    }
    Process {
        id: expander
        property var target: null
        property int depth: 0
        property int expandGen: -1
        stdout: StdioCollector {
            onStreamFinished: {
                if (expander.expandGen !== am.gen || !expander.target)
                    return;
                const d = am.parse(text);
                const items = Array.isArray(d) ? d.map(i => am.norm(i)).filter(i => i.kind === "sep" || i.label !== "") : [];
                expander.target.children = items;
                // La colonne attend toujours ce sous-menu: elle prend son contenu
                if (am.open && am.levels.length === expander.depth + 1) {
                    am.levels = am.levels.slice(0, expander.depth).concat([items]);
                    // Ouvert au clavier: le premier élément se choisit dès que le menu est rempli
                    if (am.keyboard && (am.sel[expander.depth] ?? -1) < 0)
                        am.selectFirst(expander.depth);
                }
            }
        }
    }

    Connections {
        target: FiliShell
        function onPopupOpened(who) {
            if (who !== "appmenu")
                am.close();
        }
    }

    // ───────── Fenêtres: rattrapage des clics à côté, puis les colonnes de menus ─────────
    // Pas de focus clavier: l'application garde le sien (une action qui vise le champ actif, Coller par exemple, doit
    // l'atteindre). Un clic en dehors du menu ferme, la barre reste cliquable (le rattrapage commence sous elle).
    PanelWindow {
        visible: am.open && !FiliTheme.testing
        screen: am.screen
        anchors { top: true; left: true; right: true; bottom: true }
        margins.top: FiliTheme.barHeight
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "fili-appmenu-catcher"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: am.close()
        }
    }

    PanelWindow {
        id: menuWin
        visible: am.open && !FiliTheme.testing
        screen: am.screen
        anchors { top: true; left: true }
        margins.top: FiliTheme.barHeight + 2
        margins.left: Math.max(4, Math.min((am.screen?.width ?? 0) - implicitWidth - 4, am.anchorX))
        implicitWidth: Math.max(1, cards.width)
        implicitHeight: Math.max(1, cards.height)
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "fili-appmenu"
        // Ouvert à la souris: pas de focus, l'application garde le sien. Au clavier: focus à la demande
        WlrLayershell.keyboardFocus: am.open && am.keyboard ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        Item {
            id: cards
            focus: true
            Keys.onEscapePressed: am.close()
            Keys.onUpPressed: am.keyMove(-1)
            Keys.onDownPressed: am.keyMove(1)
            Keys.onLeftPressed: am.keyLeft()
            Keys.onRightPressed: am.keyRight()
            Keys.onReturnPressed: am.keyActivate()
            Keys.onEnterPressed: am.keyActivate()
            Keys.onSpacePressed: am.keyActivate()
            // Focus reçu à l'ouverture puis perdu (clic sur une fenêtre): fermeture
            property bool held: false
            Window.onActiveChanged: {
                if (Window.active)
                    held = true;
                else if (held && am.keyboard)
                    am.close();
            }
            Connections {
                target: am
                function onOpenChanged() {
                    cards.held = false;
                }
            }
            readonly property int cardWidth: 290
            width: Math.max(0, am.levels.length - 1) * (cardWidth - 4) + cardWidth
            height: {
                let h = 0;
                for (let i = 0; i < repeater.count; i++) {
                    const c = repeater.itemAt(i);
                    if (c)
                        h = Math.max(h, c.y + c.height);
                }
                return h;
            }
            Repeater {
                id: repeater
                model: am.levels.length
                Rectangle {
                    id: card
                    required property int index
                    readonly property var entries: am.levels[index] ?? []
                    x: index * (cards.cardWidth - 4)
                    y: am.levelY[index] ?? 0
                    width: cards.cardWidth
                    height: Math.min(list.contentHeight, (am.screen?.height ?? 800) - FiliTheme.barHeight - 40 - y) + 8
                    color: FiliTheme.nuit
                    border.color: FiliTheme.border
                    border.width: FiliTheme.borderWidth
                    radius: FiliTheme.radiusControl
                    // Ordonnée (dans la fenêtre) de la ligne i: le sous-menu s'aligne dessus
                    function rowY(i) {
                        const it = list.itemAtIndex(i);
                        return card.y + 4 + (it ? it.y - list.contentY : 0);
                    }
                    // Choix au clavier: la ligne reste visible dans une longue liste
                    Connections {
                        target: am
                        function onSelChanged() {
                            const i = am.sel[card.index] ?? -1;
                            if (i >= 0 && am.keyboard)
                                list.positionViewAtIndex(i, ListView.Contain);
                        }
                    }
                    ListView {
                        id: list
                        anchors { fill: parent; margins: 4 }
                        model: card.entries
                        clip: true
                        interactive: contentHeight > height
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: Item {
                            id: row
                            required property var modelData
                            required property int index
                            readonly property bool sep: modelData.kind === "sep"
                            readonly property bool lit: !sep && modelData.enabled && (hover.hovered || am.sel[card.index] === index)
                            width: list.width
                            height: sep ? 9 : 22
                            Rectangle {
                                visible: row.sep
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 8; rightMargin: 8 }
                                height: 1
                                color: FiliTheme.nuit4
                            }
                            Rectangle {
                                visible: !row.sep
                                anchors.fill: parent
                                radius: FiliTheme.radiusMark
                                color: row.lit ? FiliTheme.nuit3 : "transparent"
                            }
                            Text {
                                visible: !row.sep && row.modelData.check === 2
                                x: 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: "✓"
                                color: FiliTheme.voile
                                font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList }
                            }
                            // Raccourci clavier, aligné à droite (une flèche remplace la touche d'un sous-menu)
                            Text {
                                id: keysText
                                visible: !row.sep && row.modelData.kind !== "sub" && row.modelData.keys !== ""
                                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                text: row.modelData.keys
                                color: FiliTheme.ardoise
                                font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList }
                            }
                            Text {
                                visible: !row.sep
                                x: 22
                                width: parent.width - 22 - (keysText.visible ? keysText.implicitWidth + 24 : 22)
                                anchors.verticalCenter: parent.verticalCenter
                                text: FiliI18n.tr(row.modelData.label, am.appName)
                                elide: Text.ElideRight
                                color: !row.modelData.enabled ? FiliTheme.ardoise : row.lit ? FiliTheme.voileVif : FiliTheme.brume
                                font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList }
                            }
                            Text {
                                visible: row.modelData.kind === "sub"
                                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                text: "›"
                                color: FiliTheme.ardoise
                                font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                            }
                            HoverHandler {
                                id: hover
                                enabled: !row.sep
                                onHoveredChanged: if (hovered) am.enter(card.index, row.modelData, row.index, card.y + 4 + row.y - list.contentY)
                            }
                            TapHandler {
                                enabled: !row.sep
                                onTapped: {
                                    if (row.modelData.kind === "sub")
                                        am.enter(card.index, row.modelData, row.index, card.y + 4 + row.y - list.contentY);
                                    else
                                        am.activate(row.modelData);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
