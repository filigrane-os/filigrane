# Installing apps, plugins and web apps: `fili`

`fili` installs what extends Filigrane from an **index**: one command and one list for three different things.

| Kind | What it is | How it is installed |
|---|---|---|
| `app` | A program with its own window (Casier, Rob), compiled and signed | An xbps package of the Filigrane repository: `sudo xbps-install` |
| `plugin` | A module of the bar: QML or scripts, its dependencies, a setup | A git repository: `fili-bar install` (manifest shown, `packages`, `install.sh`, see [bar.md](bar.md)) |
| `webapp` | A web application in the launcher | `webapp-add` |

An app stays a package, never a plugin: a plugin is text run with your rights, an app is a binary that needs updates, a signature and a clean removal, which is what xbps is for.

```
fili list [app|plugin|webapp] [--installed]   what the index offers, and the state of each entry
fili search TEXT
fili info NAME
fili install NAME [--yes]    shows the plan (size, packages, manifest); --yes does it
fili remove NAME [--yes]
fili update                  fetch the published index (filigrane-os/fili-index)
fili sync                    on a new machine: the apps of ~/.config/filigrane/apps.toml, then the pinned plugins
```

Nothing is changed without `--yes`: the first call only says what would happen (exit code 2). A heavy entry (`weight = "heavy"`) says so; measure with `budget save` before and `budget diff` after, as for any installation. `fili install` records an app in `~/.config/filigrane/apps.toml` (like `bar-plugins.toml` for the plugins), so `fili sync` brings the same machine back.

## The index

The index has three sources, from the strongest to the weakest for a given name:

1. the files of a user layer in `~/.config/filigrane/index.d/` (`users/<login>/dotfiles/config/filigrane/index.d/*.toml`): your own entries, or a replacement of an official one;
2. the **published index**, the repository [`filigrane-os/fili-index`](https://github.com/filigrane-os/fili-index), cloned into `~/.local/share/filigrane/index/` by `fili update` (new official apps and plugins arrive without a release of the distribution; `FILI_INDEX_URL` points elsewhere);
3. `00-core.toml` of the distribution, the offline default.

An entry is a section named like the command argument (lowercase letters, digits, hyphens). The index is data: nothing in it runs by itself, and `fili install` still shows the plan (for a plugin, its manifest, packages and `install.sh`) before anything is installed.

```toml
[fili-file]
kind = "app"
title = "Casier"              # the name shown to the user
description = "File manager"  # one line, searched by `fili search`
package = "fili-file"         # app: the xbps package
weight = "heavy"              # optional: warns before installing

[whatsapp]
kind = "plugin"
title = "WhatsApp"
url = "https://github.com/filigrane-os/fili-bar-whatsapp"   # plugin: the git repository

[proton-mail-web]
kind = "webapp"
title = "Proton Mail Web"
url = "https://mail.proton.me"   # webapp: the page
icon = "web-browser"             # optional: icon theme name or file
```

## Words

*Plugin* is what extends the bar. *App* is a program. *Entry* is a line of the index, whatever its kind.
