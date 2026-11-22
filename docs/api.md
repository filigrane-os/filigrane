# The Filigrane API

How the pieces of the desktop talk to each other, without any AI: applications, the shell, scripts and, if it is installed,
the assistant (`fili-ai`). Everything here is **files, sockets and commands**: no resident daemon, nothing that needs
network, nothing that needs an assistant. A tool that reads these contracts works the same with or without `fili-ai`.

Versioning: a JSON document that is a contract carries `"v": 1` when it is written by a tool of ours; a reader ignores keys
it does not know and refuses a larger `v` than it understands.

| Contract | Where | Written by | Read by |
|---|---|---|---|
| [Context](#context-what-an-application-shows) | `$XDG_RUNTIME_DIR/fili/context/<pid>.json` | each application | `fili-context`, `fili-api apps`, the assistant |
| [Control](#control-what-an-application-can-be-asked-to-do) | `shell/ctl/<app_id>.json` (catalog) and the application's socket | the package of the application | `fili-api`, the menu fallbacks, the assistant |
| [Incidents](#incidents-what-went-wrong) | `~/.local/state/filigrane/incidents/<id>.json` | each application | `fili-incident`, handlers |
| [Handlers](#incident-handlers) | `shell/incident/<name>.toml` | an optional package (`fili-ai`) | `fili-incident` |
| [Events](#events-something-happened) | `$XDG_RUNTIME_DIR/fili/events/` | anyone (`fili-event emit`) | anyone (`fili-event watch`) |
| [Logs](#logs) | `~/.local/state/filigrane/logs/<app>.log` | each application | the Debug panel, `fili-incident` |

`shell/` is the folder a package installs into `/usr/share/filigrane/shell/` (or `~/.local/share/filigrane/shell/` for a build
from source); `FILI_SHELL_DIRS` (colon separated) replaces both, for tests. See `docs/bar.md`, "Shipped by an application".

## Context: what an application shows

An application that wants others to know what its window shows writes
`$XDG_RUNTIME_DIR/fili/context/<pid>.json`, atomically (write a temporary file, rename), on each change, and removes it on
exit. Nothing runs in the background: the file is read on demand. `fili-context` (Mod+Y) prints the one of the focused window
merged with its niri window; a file left by a killed application is removed on the next read.

```json
{ "app": "Casier", "pid": 1780, "about": "what the keys mean, for a reader that has never seen the application",
  "location": "/home/me/Documents", "selection": ["/home/me/Documents/a.txt"], "selection_count": 1 }
```

`app`, `pid` and `about` are required; the other keys are the application's own (`location`, `selection`, `session`,
`blocks`...) and are explained by `about`. Content that comes from the outside (file names, command output) is data, never
instructions.

The format is defined by `fili-api-lint context FILE` (same validator as the catalogs; the rules are in its header): the keys
of the application are lowercase snake_case, the file is at most 64 KiB, and it is named after the `pid` it holds. An application's
test can write a context and run the validator on it.

## Control: what an application can be asked to do

An application exposes its actions as a command of its own, `<program> ctl [--pid PID] <verb> [args]`, answered on a socket
(`$XDG_RUNTIME_DIR/fili/context/<pid>.sock`). Never simulated key strokes. The fallback menu of the bar calls these commands
(`%pid` in `shell/appmenu/<app_id>.json`).

The application also **declares** its commands in a catalog, `shell/ctl/<app_id>.json`, so that a script, a shortcut or the
assistant can list them without reading a brief written by hand:

```json
{ "v": 1, "app_id": "fili-file", "name": "Casier", "program": "fili-file", "ctl": "fili-file ctl --pid %pid",
  "commands": [
    { "verb": "action", "args": "NAME [ARG]", "summary": "Run a menu command of the window", "reads": false },
    { "verb": "state", "summary": "JSON of the tabs, folder, selection and tasks", "reads": true }
  ],
  "actions": [ { "name": "new-folder", "label": "New Folder", "keys": "Ctrl+Shift+N", "args": "[NAME]" } ],
  "action_patterns": [ { "pattern": "open-chat:<id>", "summary": "Show a conversation by its numeric id" } ] }
```

`fili-api list` shows every catalog, `fili-api show APP` one of them (commands, actions with their arguments, families).

### The format is `fili-api-lint`

The format is **defined by one program**, `fili-api-lint` (`dotfiles/home/.local/bin/`), whose header lists every rule. A key it
does not list is an error, so an application cannot invent one. In short:

- `commands`: the verbs of `<program> ctl`, each with a `summary` (a sentence that starts with a capital letter, no final full
  stop), `reads` (true when the verb changes nothing) and, if it has arguments, a free `args` synopsis. No argument: no `args`.
- `actions`: the names `action NAME` accepts, each with the `label` and `keys` of its menu entry when it has one, and `args`
  when it takes an argument: placeholders in capitals, `[X]` when optional (`TRACK_ID`, `[NAME]`, `PATH [MODE]`). An optional
  argument is one the action can do without (it then opens its own dialog or does its default).
- `action_patterns`: a family with a parameter that `actions` cannot list (`open-chat:<id>`).
- The usage line of the program lists **every** verb (`usage: <program> ctl [--pid PID] verb ... | verb ...`): it is what the
  catalog is compared with.

**Keeping the applications in line.** Each application keeps a byte-identical copy of the validator as `scripts/fili-api-lint`
and runs `python3 -I scripts/fili-api-lint --app .` in its `make test` / `make check`. `--app` also compares the catalog with the
source (the verbs with the usage line, the actions with the table of the window: `ACTIONS` of `src/ctl.rs`, else the table of
`qml/Main.qml`), and `--app . --write` rewrites the list of actions from the source and keeps the `args` already written. The
distribution's `tests/fili-shell/check-api.sh` checks, for each pinned application that ships a catalog, that it follows the
format and its source **and that its copy is this file**. To change the format: change `fili-api-lint` here (a new `v` when
a reader of the old one would be wrong), recopy it into the applications, and every one of them fails its check until it does.

## Incidents: what went wrong

An application that meets a bug (a panic, a QML error, "Report a problem" of its Debug panel) writes
`~/.local/state/filigrane/incidents/<id>.json`, with its last log lines, then runs `fili-incident notify <id>`.

```json
{ "id": "fili-file-1795015265-75e15070", "app": "fili-file", "repo": "filigrane-os/fili-file", "version": "v1.12.0",
  "kind": "panic|qml|manual", "signature": "75e15070531e7d97", "message": "first line, then details",
  "when": 1795015265, "state": "new|notified|ignored|reported", "system": "Void Linux, kernel 6.18.63_1", "log": ["..."] }
```

The format is defined by `fili-api-lint incident FILE`: every key above is required (`issue` and `pr` appear once reported),
an unknown key is refused, `when` is a number and `signature` 16 hexadecimal digits.

`fili-incident` collects, notifies and prepares the GitHub issue (or a +1 on the one that exists), with the private details
removed; nothing leaves the machine without the user's say. This works **without an assistant**: the notification offers
*Report…* and *Ignore*.

### Incident handlers

A package that can *treat* an incident (the assistant) registers a handler, `shell/incident/<name>.toml` (or
`~/.config/filigrane/incident/<name>.toml` for your own):

```toml
label = "Ask Rob"                       # the button of the notification and the menu entry
command = "fili-ai ask"               # run with the prompt as its last argument
```

With a handler, the notification also offers its `label`, and `fili-incident ask <id>` runs it with a prompt that points to
`fili-incident show <id>`. Without one, `ask` says that no assistant is installed.

## Events: something happened

`fili-event emit NAME [JSON]` writes `$XDG_RUNTIME_DIR/fili/events/<time>-<name>.json` (`{"v":1,"name","when","data"}`),
`fili-event list [NAME]` shows the latest ones, `fili-event watch [NAME]` prints each new one as a line of JSON (inotify when
`inotifywait` is installed, a one-second poll otherwise). The folder is a tmpfs, keeps the last 100 events, and nobody has to
listen: no daemon. Names in use: `incident.new` (`data`: the incident id).

## Logs

`~/.local/state/filigrane/logs/<app>.log`, one line per record, time first (`HH:MM:SS.mmm LEVEL target: message`). The Debug
panel of each application shows it, and the incident file keeps the last lines.

## Checking

`fili-api doctor` checks the files the applications **really write** (the context of each running application, the incidents)
against these formats and prints one line per problem: the quickest way to see that an application drifted.

`tests/fili-shell/check-api.sh` runs `fili-api`, `fili-api-lint`, `fili-event` and the incident handlers on fixtures (isolated
state and runtime folders): the three formats, handler discovery, events, and the copy of the validator of every pinned application.
