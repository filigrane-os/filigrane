# The bar (fili-bar)

The bar is the thin line at the top of every screen. In the interface it is simply called **Barre**; `fili-bar` is its name in the repository, the code and the commands. It is part of the *fili-shell* (Quickshell, QML) and is made of **modules**: small independent items, each one a folder.

Idle, a module shows little or nothing: indicators such as alerts, the timer or the recording mark only appear when they have something to say.

## Default layout

Left, from the edge: `logo`, `workspaces`, `appmenu`. Right, in reading order: `status`, `tray`, `media`, `resources`, `agent`, `audio`, `keyboard`, `display`, `bluetooth`, `network`, `notifications`, `clock`, `power`.

| Module | Shows | Click |
|---|---|---|
| `logo` | Filigrane logo | menu; middle click: About |
| `workspaces` | workspaces of the screen | go to one; wheel: previous / next |
| `appmenu` | name and menus of the active application | open a menu (see below) |
| `status` | screen recording, incoming SSH, airplane mode, VPN, pending updates (each hidden when idle) | recording: stop; airplane: turn off; updates: run them |
| `tray` | system tray icons and the drawer chevron | chevron: show or fold the drawer |
| `media` | current player | play / pause; middle: next; wheel: previous / next |
| `resources` | CPU and memory; temperature and disk only when high | monitor panel |
| `agent` | the AI agent (waiting, done) | sessions panel |
| `audio` | output volume | sound panel; middle: mute; wheel: volume; right: mixer |
| `keyboard` | layout | panel; middle: next layout |
| `display` | screens | panel; wheel: brightness |
| `bluetooth` | adapter and devices | panel |
| `network` | Wi-Fi | panel; right: network menu |
| `notifications` | notification count | history; right: do not disturb |
| `clock` | date and time | pinned calendar |
| `power` | battery | panel; right: system menu |

A click that opens a panel opens a **fili-panel** under the item. `Esc`, a click elsewhere or another click closes it. `Mod+A` opens the panels from the keyboard, and the arrows move from one module to the next, in the order of the bar.

### The drawer

The `tray` module folds the indicators that are not in use. Folded, only the ones that have something to show stay visible; the chevron unfolds all of them. `bar-tray toggle` does the same from a script.

### The application menu

`appmenu` is the global menu: the name of the active application in bold, then its menus, like the classic Mac OS X menu bar. It reads the application's menu bar through AT-SPI (GTK, Qt) or, for applications that export none, a hand-written fallback in `dotfiles/config/filigrane/appmenu/<app_id>.json` (personal ones in `users/<login>/dotfiles/config/filigrane/appmenu/`). Menus that do not fit move into a `…` title. `Mod+F10` gives the menu the keyboard focus.

## Choosing and ordering modules

Every module folder has a manifest, `module.toml`:

```toml
title = "Clock"
description = "Date, time and calendar"
side = "right"   # "left" or "right" (default)
order = 120      # position in the row, smaller = more to the left (default 50)
```

The default rows are the manifests of each side sorted by `order`. A module with a manifest joins its row by itself, so a personal module needs nothing else: `order = 1` puts it first of the right row. The manifests are read once when the shell starts.

To change the defaults, create `~/.config/filigrane/fili-bar.toml` (re-read as soon as it changes):

```toml
[modules]
left  = ["logo", "workspaces", "appmenu"]
right = ["mail", "...", "clock", "power"]

[modules.clock]      # overrides the manifest of one module
side = "left"
order = 5
enabled = false
```

- A name is a folder of `bar/modules/`: `my-thing` loads `my-thing/MyThingModule.qml`.
- An explicit `left` / `right` list is the exact order of the bar, left to right, and wins over `order`.
- `"..."` stands for the default modules of that row that are not listed yet.
- `[modules.<name>]` overrides `side`, `order` and `enabled` (`false` removes the module, in the lists too).
- Names that are invalid (anything but lowercase letters, digits and hyphens) and duplicates are ignored. A module that does not exist leaves a loading error in the log and no gap in the bar.

Your own `fili-bar.toml` belongs to the [personal layer](configuration.md): `users/<login>/dotfiles/config/filigrane/fili-bar.toml`.

## Writing a module

A module is a folder `bar/modules/<name>/` with `<Name>Module.qml` and, if it opens a panel, `<Name>Panel.qml` next to it. Add a `module.toml` (see above) so it is placed without a `fili-bar.toml`. A personal module (an account, a third-party service) goes in `users/<login>/dotfiles/config/quickshell/bar/modules/<name>/`, never in the distribution. After adding a file, run `./bootstrap.sh --fili-shell` (files are linked one by one, a new one is not seen before) and restart Quickshell if it is already running.

The root of the module is one of:

- **`BarModule`**: the base. A bar window and an optional panel (`panel: "name"`, `panelSource: Qt.resolvedUrl("<Name>Panel.qml")`, `togglePanel()` on click).
- **`BarItem`**: a glyph and a value, in the standard look: slate icon or label, then the value in mist. A state colours the whole module.
- **`BarScript`**: an item fed by a script. The script prints one JSON line `{"text": "...", "class": "...", "tooltip": "..."}` (the protocol of the custom Waybar modules); an empty `text` hides the module.

`BarScript` properties:

| Property | Role |
|---|---|
| `cmd` | script to run; its output is the state |
| `interval` | seconds between two runs; `0` once (then on signal); `-1` resident, one line per update |
| `signal` | refreshed by `fili-shell bar refresh N` |
| `stat` | no script: state written by `bar-stats` (`stat NAME JSON`) |
| `value` | no script: state bound to a `{text, class, tooltip}` object |
| `colors`, `color` | colour per `class`, default colour |
| `click`, `rclick`, `mclick`, `scrollUp`, `scrollDown` | commands run on each gesture |
| `title`, `hint`, `tipCmd` | tooltip title, hint line, command run on hover only |

Give the module an `objectName`: the tests find it by that name. Prefer `bar refresh N` over a short `interval`: nothing runs until something changes.

Example, a module of a personal layer (unread watch reports):

```qml
import QtQuick
import qs
import qs.bar

BarScript {
    objectName: "news"
    title: FiliI18n.tr("News")
    cmd: FiliTheme.bin + "/bar-news"
    interval: 3600
    signal: 15
    color: FiliTheme.brume2
    click: FiliTheme.bin + "/bar-news open"
}
```

### Alerts

An alert (new mail, unread messages, next event) is an `AlertModule` of a few lines. It reads `~/.local/state/alerts/<kind>` (one line per item, fields separated by a tab; added with `bar-alert push`) and optionally `<kind>.count`, the real number of unread items, which wins. It shows in the bar while there is something to read and, at rest, only in the open drawer. A click runs `bar-alert open <kind> [URL]`.

```qml
import QtQuick
import qs
import qs.bar.modules.alert

AlertModule {
    kind: "mail"
    title: "My Mail"
    url: "https://mail.example.org"
    glyph: ""
    accent: FiliTheme.voile
}
```

`render: (rows, now) => ({ text, rows })` gives a kind its own format and expiry (the calendar uses it); returning `null` means nothing is left.

### Pitfalls

- A module is loaded **by its file**. It sees the other files of its folder only if `BarLayout.qml` imports that folder; a module with helpers next to it (`appmenu`, `audio`, `clock`, `alert`) needs a line there. Otherwise rely on `qs`, `qs.bar` and `qs.controls` only.
- Text is in English in the code; translations go in `dotfiles/config/quickshell/i18n/<language>.json` and `FiliI18n.tr("...")`.
- Colours, sizes and fonts come from `FiliTheme`, never hard-coded. The interface rules are in the `filigrane-ui` skill (`agents/skills/filigrane-ui/`).
- The bar must stay light: no resident process per module, no polling when a signal will do. Measure with `tests/fili-shell/bench.sh`.

## Testing

After any change to the fili-shell, `tests/fili-shell/run.sh` must pass. It starts the shell in an isolated instance and clicks every module (`expectClick("name", Qt.LeftButton, "command")` in `tests/fili-shell/TestShell.qml`). The test workflow is described in [development.md](development.md).
