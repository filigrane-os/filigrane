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

To change the defaults, create `~/.config/filigrane/fili-bar.toml` (re-read as soon as it changes). `dotfiles/config/filigrane/fili-bar.toml` lists every option with its comment, all commented out at their defaults:

```toml
[bar]
edge = "top"         # "top" (default), "bottom", "left" or "right": on the left and the right the bar is a narrow column
screens = "all"      # "all" (default) or a list of output names, e.g. ["eDP-1", "DP-6"]

[modules]
left  = ["logo", "workspaces", "appmenu"]
right = ["mail", "...", "clock", "power"]

[modules.clock]      # overrides the manifest of one module
side = "left"
order = 5
enabled = false
display = "icon"     # "both" (default), "icon" or "value"
tray = "idle"        # "never" (default), "idle" or "always"
show = "always"      # "active" (hidden while empty) or "always"
```

- `edge` puts the bar on one edge of the screen; a column stacks the modules, folds the application menu into one button and shows the clock as time over date. `screens` limits the bar to some outputs (names as in `niri msg outputs`); a list that matches no connected screen gives every screen a bar, so the bar never disappears.
- A name is a folder of `bar/modules/`: `my-thing` loads `my-thing/MyThingModule.qml`.
- An explicit `left` / `right` list is the exact order of the bar, left to right, and wins over `order`.
- `"..."` stands for the default modules of that row that are not listed yet.
- `[modules.<name>]` overrides `side`, `order` and `enabled` (`false` removes the module, in the lists too).
- `display`: the icon alone or the value alone (a module without icon always shows its value). `tray`: `idle` keeps the module in the drawer at rest and in the bar while it has something to say, `always` shows it only in the open drawer. `show`: `always` keeps a module that is empty in the bar (when its code allows it). These three also work in a `module.toml`, and apply to `BarItem` and `BarScript` modules.
- Names that are invalid (anything but lowercase letters, digits and hyphens) and duplicates are ignored. A module that does not exist leaves a loading error in the log and no gap in the bar.

Your own `fili-bar.toml` belongs to the [personal layer](configuration.md): `users/<login>/dotfiles/config/filigrane/fili-bar.toml`.

## The `fili-bar` command

```
fili-bar list                          modules: name, side, order, state, kind, title
fili-bar enable NAME | disable NAME    show or hide a module
fili-bar move NAME left|right [ORDER]  side and position
fili-bar edge [top|bottom|left|right]   edge of the screen the bar sits on
fili-bar screens [all|NAME...]         screens that get a bar
fili-bar new NAME [--qml]              skeleton of a plugin (script, or QML module)
fili-bar check DIR|NAME                check a manifest and its script
fili-bar install URL [--commit REV]    clone a plugin (a repository `fili-bar-NAME` installs as `NAME`); shows its manifest, then --yes
fili-bar setup NAME                    run the install.sh of a plugin again
fili-bar remove NAME                   remove a plugin (to the trash)
fili-bar sync                          clone the pinned plugins of bar-plugins.toml (new machine)
```

`enable`, `disable` and `move` write `[modules.<name>]` in `~/.config/filigrane/fili-bar.toml`, which the bar re-reads at once. Plugins you add live in `~/.local/share/filigrane/bar/plugins/<name>/`, never in the repository, and are linked into `~/.config/quickshell/bar/modules/<name>`. `install` records `name = "url@commit"` in `~/.config/filigrane/bar-plugins.toml`, so `sync` brings the same commits back on another machine. A manifest with an `api` newer than the bar's is refused. A plugin is code with your rights, without a sandbox: read what `install` shows, and the script, before saying `--yes`. A new plugin shows after the shell restarts.

### Settings > Barre

A right click on the bar background opens a panel with the edge and the screens (also `fili-bar edge` and `fili-bar screens`), and a shortcut to **Settings › Barre**. The same choices are in **Settings › Barre** (`fili-shell settings bar`, or the foot of a panel): a switch to show or hide each module, arrows to move it up or down its row and to the other side. The page runs `fili-bar`, so it writes the same `fili-bar.toml`. An explicit `left` / `right` list in that file wins over the order of the page, and the page says so.

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

### A script plugin, without QML

The simplest module is a folder with a `module.toml` and a script, no QML. A manifest with a `cmd` is loaded by the generic `ScriptModule`:

```toml
# bar/modules/uptime/module.toml
title = "Uptime"
side = "right"
order = 35
cmd = "./uptime.sh"
interval = 60
click = "foot -e htop"
```

```sh
#!/bin/sh
# uptime.sh: one JSON line per run
printf '{"text": " %s", "tooltip": "%s"}\n' "$(uptime -p | sed 's/up //')" "$(uptime -s)"
```

| Key | Role |
|---|---|
| `cmd` | command that prints the state (run in the folder of the module) |
| `interval` | seconds between two runs; `0` (default): once, then on signal; `-1`: resident, one line per update |
| `signal` | refreshed by `fili-shell signal N` |
| `click`, `rclick`, `mclick`, `scroll_up`, `scroll_down` | commands run by the mouse |
| `title`, `hint` | name and help line of the tooltip |

The output protocol is the one of `BarScript` above (`text`, `class`, `tooltip`); an empty `text` hides the module. `side`, `order`, `display`, `tray` and `show` work as for any module. A plugin runs with your rights: read its script before adding it.

### `install.sh`: first-run setup

A plugin may ship an optional `install.sh` at its root: the steps that make it work (build a daemon, store a credential in the keyring, copy `config.example.toml` to the options file, run `rclone config`). `fili-bar install` shows it with the manifest, runs it with `--yes` once the plugin is in place, and `fili-bar sync` runs it for every plugin it clones on a new machine. `fili-bar setup NAME` runs it again.

- It runs with `sh`, in the folder of the plugin, with `FILI_BAR_PLUGIN` (the name) and `FILI_BAR_OPTIONS` (the options file) in the environment.
- It must be idempotent: running it twice changes nothing.
- It never writes a secret in the plugin folder (credentials go to the keyring or to a file under `~/.config`), and never calls `sudo` without saying so on screen.
- A failure is reported and the plugin stays installed; fix it, then `fili-bar setup NAME`.

### Translations and options of a plugin

- **Translations**: write the plugin in English. To translate it, add `i18n/<language>.json` in its folder (`{"English text": "translation"}`, `%1`, `%2` for arguments, same format as the catalogs of the shell). The shell merges them with its own catalog, which wins on a clash; the bar reads them when it starts and when the language changes. In a QML module, texts go through `FiliI18n.tr("...")`.
- **Options**: the user's options for a plugin are in `~/.config/filigrane/bar/<name>.toml` (optional; the plugin documents its keys). A script plugin finds the path in `FILI_BAR_OPTIONS`; a QML module reads it with a `FileView` on `BarLayout.options("<name>")` and `FiliTheme.parseToml`.

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

## Status of the plugin interface

The interface is `api = 1` (the manifest keys, `BarModule` / `BarItem` / `BarScript`, `FiliTheme`, `FiliI18n`, `qs.controls`). It lives in this repository with the bar and is tested with it (`tests/fili-shell/run.sh`). It is not frozen yet: a change that breaks plugins raises the `api` number and is written in the changelog.

The bar stays in this repository, like the rest of the fili-shell, until three things are true: the interface has stayed at `api = 1` for a while, at least one plugin lives outside this repository, and this guide is complete. Then the bar can move to its own repository pinned here (as Casier is) and an index of plugin URLs (`filigrane-os/fili-bar-plugins`) can list the plugins that are worth installing. Until then, a plugin is shared as its own git repository (a folder with a `module.toml`) that `fili-bar install` clones.

## Testing

After any change to the fili-shell, `tests/fili-shell/run.sh` must pass. It starts the shell in an isolated instance and clicks every module (`expectClick("name", Qt.LeftButton, "command")` in `tests/fili-shell/TestShell.qml`). The test workflow is described in [development.md](development.md).
