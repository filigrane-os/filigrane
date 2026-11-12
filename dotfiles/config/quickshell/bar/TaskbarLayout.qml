pragma Singleton
// fili-taskbar: which windows the taskbar (FiliTaskbar.qml) lists, and how it squeezes. One bar per screen, listing the
// windows of that screen grouped by workspace, in the order niri lays them out. Settings: [taskbar] of fili-bar.toml
// (dotfiles/config/filigrane/fili-bar.toml lists them):
//   [taskbar]
//   enabled = true         # false: no taskbar
//   edge = "bottom"        # "bottom" (default) | "top" | "left" | "right"; the edge of the fili-bar is never shared (the taskbar takes the opposite one)
//   screens = "all"        # "all" (default) or a list of output names, like [bar] screens
//   autohide = false       # true: hidden until the pointer touches the edge, takes no room
//   background = "solid"   # "solid" (default) | "translucent" | "transparent"
import QtQuick
import Quickshell
import qs

Singleton {
    id: taskbar
    readonly property var conf: BarLayout.parsed.taskbar ?? ({})
    readonly property bool enabled: String(conf.enabled ?? "true") !== "false"
    // Edge of the screen: the one asked for ("top", "bottom" (default), "left" or "right"), unless the fili-bar sits there (then the opposite one)
    readonly property string edge: {
        const want = ["top", "bottom", "left", "right"].indexOf(conf.edge) >= 0 ? conf.edge : "bottom";
        return want === FiliTheme.barEdge ? ({ top: "bottom", bottom: "top", left: "right", right: "left" })[want] : want;
    }
    // On the left or the right the Quai is a narrow column: one icon over its number per window, no titles
    readonly property bool vertical: edge === "left" || edge === "right"
    // Hidden until the pointer touches its edge ([taskbar] autohide = true); it then takes no room: the windows use the whole screen
    readonly property bool autohide: String(conf.autohide ?? "false") === "true"
    // Background, like the fili-bar: "solid" (default) | "translucent" | "transparent"
    readonly property string background: BarLayout.backgrounds[conf.background] !== undefined ? conf.background : "solid"
    readonly property real alpha: BarLayout.backgrounds[taskbar.background]
    Binding { target: FiliTheme; property: "taskbarTone"; value: BarLayout.toneFor(taskbar.edge, taskbar.alpha) }
    Binding { target: FiliTheme; property: "taskbarEdge"; value: taskbar.enabled && !taskbar.autohide ? taskbar.edge : "" }

    // Screens that get a taskbar (a list that matches no connected screen gives all of them, like the fili-bar)
    readonly property var screens: {
        if (!enabled)
            return [];
        const v = conf.screens;
        const list = Array.isArray(v) ? v : (v ? [v] : []);
        const all = Quickshell.screens;
        const some = list.indexOf("all") >= 0 ? [] : all.filter(s => list.indexOf(s.name) >= 0);
        return some.length > 0 ? some : all;
    }

    // Squeeze levels (the bar goes up one step at a time while its row does not fit, down again when it does):
    // 0 icon and title of every window; 1 the title of the focused window only; 2 the windows of one application in
    // a workspace merge into one icon with a count; 3 the workspaces that are not shown on their screen fold into a label
    // and a count. Click on a merged icon or a folded workspace opens the list of its windows.
    readonly property int maxLevel: 3
    function nextLevel(level, avail, row, seen) {
        return BarLayout.nextLevel(level, avail, row, seen, maxLevel);
    }

    // Place of a window in its workspace: niri's columns left to right, then the tiles of a column, floating ones last
    function order(a, b) {
        const pa = a.layout?.pos_in_scrolling_layout, pb = b.layout?.pos_in_scrolling_layout;
        if (pa && pb)
            return pa[0] - pb[0] || pa[1] - pb[1];
        if (pa || pb)
            return pa ? -1 : 1;
        return a.id - b.id;
    }
    // Natural order of two names: "2" before "10", "a" before "b" (case ignored)
    function naturalCompare(a, b) {
        const pa = String(a).toLowerCase().match(/\d+|\D+/g) ?? [], pb = String(b).toLowerCase().match(/\d+|\D+/g) ?? [];
        for (let i = 0; i < Math.min(pa.length, pb.length); i++) {
            const x = pa[i], y = pb[i];
            if (x === y)
                continue;
            const nx = /^\d/.test(x), ny = /^\d/.test(y);
            if (nx && ny)
                return Number(x) - Number(y) || x.length - y.length;
            return x < y ? -1 : 1;
        }
        return pa.length - pb.length;
    }
    // Order of the workspaces of a screen, left to right: the named ones in alphanumeric order, then the unnamed ones as niri has
    // them (a workspace keeps its place whatever niri's order, which moves with every workspace that opens or closes)
    function wsOrder(a, b) {
        const na = a.name ?? "", nb = b.name ?? "";
        if (na && nb)
            return naturalCompare(na, nb);
        if (na || nb)
            return na ? -1 : 1;
        return a.idx - b.idx;
    }
    // Label of a workspace in the bar: its name, else its index on the display, else a dot (numbered workspaces, like the
    // workspaces module of the fili-bar)
    function label(ws, numbered) {
        return ws.name ?? (numbered ? "•" : String(ws.idx));
    }
    // The groups of one screen: workspaces left to right (those with a window, and the active one), each
    //   { id, label, active, urgent, count, folded, wins: [window...], entries: [entry...] }
    // entry = { key, app_id, wins: [window...], nums: [number...], focused, urgent, title }: one window, or from level 2 all the windows of
    // one application of the workspace (title = the title to show, "" for the icon alone).
    function groups(output, workspaces, windows, focusedId, level) {
        const all = Object.values(windows);
        const numbered = workspaces.some(w => /^[0-9]+$/.test(w.name ?? ""));
        const out = [];
        for (const ws of workspaces.filter(w => w.output === output).sort(wsOrder)) {
            const wins = all.filter(w => w.workspace_id === ws.id).sort(order);
            if (wins.length === 0 && !ws.is_active)
                continue;
            const focusedHere = wins.some(w => w.id === focusedId);
            const entries = [];
            for (const w of wins) {
                const prev = level >= 2 ? entries.find(e => e.app_id === (w.app_id ?? "")) : undefined;
                if (prev)
                    prev.wins.push(w);
                else
                    entries.push({ key: (level >= 2 ? "a" + ws.id + "/" + (w.app_id ?? "") : "w" + w.id), app_id: w.app_id ?? "", wins: [w] });
            }
            for (const e of entries) {
                e.nums = e.wins.map(w => TaskbarNumbers.numberOf(w.id));
                e.focused = e.wins.some(w => w.id === focusedId);
                e.urgent = e.wins.some(w => w.is_urgent);
                // Title: every window at level 0, then the focused one (not a merged icon)
                e.title = e.wins.length === 1 && (level === 0 || (level >= 1 && e.focused)) ? (e.wins[0].title ?? "") : "";
            }
            out.push({
                id: ws.id,
                label: label(ws, numbered),
                active: ws.is_active,
                urgent: wins.some(w => w.is_urgent),
                count: wins.length,
                folded: level >= 3 && !ws.is_active && !focusedHere,
                wins: wins,
                entries: entries
            });
        }
        return out;
    }

    // Name of an application for the card and the list: its desktop entry, else its app_id
    function appName(appId) {
        const e = appId ? DesktopEntries.heuristicLookup(appId) : null;
        return e?.name || appId || "";
    }
    // Theme icon of an application (path), "" when it has none
    function appIcon(appId) {
        const e = appId ? DesktopEntries.heuristicLookup(appId) : null;
        return e?.icon ? Quickshell.iconPath(e.icon, true) : "";
    }
}
