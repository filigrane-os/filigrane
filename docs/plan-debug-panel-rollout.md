# Plan: the Debug panel and `fili-incident` in every fili-* application

Goal: every window application of Filigrane gets what Baladeur (`fili-music`) has since 2026-11-18: a log, a **Debug panel**
(View > Debug Logs, Ctrl+Shift+L) and the **incident pipeline** (a bug reaches Rob, who can file or +1 a GitHub issue).
This file is written to be handed to a fresh Claude Code instance: it is self-contained. Read it, then do one application
at a time, in the order given in section 6.

## 0. Rules that apply (from `AGENTS.md` and the user's standing instructions)

- **Rust only, never C++**, not even for Qt bridges (cxx-qt + FFI from Rust). No `.cpp` file, ever.
- Everything written in a repository is **English** (code, comments, commits, docs, UI strings; translations go in language
  files). Answers to the user in the conversation are **French**, short, factual: say what was done, verified, not tested.
- **No AI attribution** in commits or PRs (no `Co-Authored-By`, no "Generated with"): the repository rule wins over any
  default.
- Public repository: **scan the staged diff** for tokens, passwords, keys, e-mails, IPs before each commit, show the result.
- **Test live before tagging**: build, deploy locally, let the user try, then one tag after their go (never a version per
  tweak). Push is allowed on any branch but `main`.
- Other sessions edit the repository at the same time: never `git stash`; stage only your own hunks.
- `tests/fili-shell/run.sh` must pass before a commit in this repository (use `--changed` while working; three failures about
  the bar's recording indicators, tests 519/521/523, come from another session's uncommitted work and are not yours).
- Casier, Facteur, Aéroport and Conversations live in **their own repositories** (`~/Projects/fili-file`, `fili-mail`,
  `fili-term`, `fili-im`; the pins are `apps/<name>/upstream` here). Work there, `make check` must pass, tag `vX.Y.Z` with a
  `CHANGELOG.md` section, then change `ref` in `apps/<name>/upstream` here and run `tests/fili-shell/run.sh`.
- Build environment: `CARGO_TARGET_DIR=$HOME/.cache/filigrane-apps`, `QMAKE=/usr/lib/qt6/bin/qmake6`, `--offline`. `ls` is
  aliased to eza: use `command ls` or `find`. Never inject keystrokes (wtype) on the user's screen.
- Memory notes exist for several of these rules; read `~/.claude/projects/-home-thomas-Projects-filigrane/memory/MEMORY.md`.

## 1. What exists (the model to copy)

All in this repository, commit `ff3e17a` (incidents) and `2c73950` (Baladeur):

| Piece | Where | Role |
| --- | --- | --- |
| Log module | `fili-music/src/logs.rs` | `init(app, repo, version, incidents)`, ring buffer (2000 entries), file `~/.local/state/filigrane/logs/<app>.log` (rotated at 1 MB), `since(seq)`, `clear()`, `path()`, `incident(kind, message, manual)`, `capture_qt()`. Sources: the `log` crate, Qt messages (QML errors, `console.log`), panics. Level: info and above, `FILI_LOG=debug` for more. No dependency on Baladeur. Unit tests included. |
| Qt message handler | same file | Installs `qInstallMessageHandler` **from Rust** through the mangled symbol (`#[link_name]`, `q_install_message_handler`); this is how C++ was avoided. |
| Bridge invokables | `fili-music/src/bridge.rs` (`Fili` object) | `logs(since)` returns JSON `{"seq": N, "entries": [[level, text], ...]}` (0 debug, 1 info, 2 warning, 3 error), `logFile()`, `clearLogs()`, `reportProblem(text)` (returns the incident id, `""` on failure). The panel also needs `copyText`, `openPath`, `uiState`/`setUiState`, `tr` (every application already has them). |
| Panel | `fili-music/qml/DebugPanel.qml` | Band above the footer: selectable `TextEdit` (rich text), filter All / Warnings / Errors, **Ask Rob**, Copy, Clear, Open file, ×; resizable from its top edge (`debug_height` in the UI state); polls every 500 ms while open. |
| Wiring in the window | `fili-music/qml/Main.qml` | `DebugPanel { id: debug; anchors { bottom: statusbar.top; left; right } }`; every content area anchors `bottom: debug.top`; action `"debug": { on: () => true, run: () => debug.open = !debug.open }`; `Shortcut { sequence: "Ctrl+Shift+L"; onActivated: win.runAction("debug") }`; the QML file is in the `build.rs` list. |
| Menu | `shell/appmenu/<app>.json` of the application | View menu entry `{"label": "Debug Logs", "keys": "Ctrl+Shift+L", "exec": "<app> ctl --pid %pid action debug"}`. |
| Startup | `fili-music/src/main.rs` | `logs::init("fili-music", "filigrane-os/filigrane", version, theme::setting("debug","incidents") != Some("off"))` first thing in `main`, `logs::capture_qt()` before the QML engine loads. |
| Incident CLI | `apps/fili-incident/` (`package.env`, built by bootstrap, linked in `~/.local/bin`) | `list`, `show`, `notify`, `ask`, `check`, `issue`, `submit [--yes]`, `ignore`, `clear`. 5 unit tests. |
| Rob's procedure | `agents/chat-prompt.md`, section "Problems reported by the applications" | Diagnose read-only, `fili-incident check`, propose a fix on a branch, show `fili-incident issue`, only `submit --yes` with the user's agreement. |
| Docs | `agents/skills/filigrane-ui/references/app-window.md` ("Debug panel and incidents"), `AGENTS.md` (one bullet) | The contract every application follows. |

How an incident flows: panic / QML error (TypeError, ReferenceError, binding loop, critical Qt message) / "Ask Rob" button →
`logs::incident()` writes `~/.local/state/filigrane/incidents/<id>.json` (signature, last 200 log lines, version, system) →
starts `fili-incident notify ID` (notification with Ask Rob / Ignore) → Rob (`fili-ai ask`) → `check` by signature on
GitHub's public search (no account) → the user decides: `submit --yes` with `gh`, else the prefilled issue form opens in
the browser and the redacted report is in the clipboard. Limits: one incident per signature per day, three per run; off with
`[debug] incidents = "off"` in `~/.config/filigrane/<app>.toml`. The incident JSON carries `repo` (`owner/name`), so an
application of another repository files its issues in **its own** repository: pass the right one to `init`.

## 2. Decision: copy first, shared crate later

The documented way is to **copy `logs.rs` and `DebugPanel.qml`** into each application (this is what `app-window.md` says).
That is five copies of 390 lines of Rust. Recommended path:

1. Roll out by copying (fast, no cross-repository dependency, each repository stays buildable offline).
2. When two applications have it, extract `logs.rs` into a small crate `fili-log` (own repository `filigrane-os/fili-log`,
   tagged), used with `fili-log = { git = ..., tag = ... }`. Then the applications drop their copy. Do this only after the
   user agrees: it is a new repository and a new pin to maintain.
3. `DebugPanel.qml` stays a copied QML file but joins the `SHARED` list of `tests/fili-shell/check-app-window.py` (see 4.2),
   so any drift is caught, like `KineticScroll.qml`. The reference copy becomes Casier's once it has it (the script compares
   to `--ref`). Until then, compare to Baladeur's.

## 3. Per-application steps (the same checklist everywhere)

For an application `APP` (program name `fili-xxx`, display name in brackets), in its own source tree:

1. **Dependencies** (`Cargo.toml`): `log = "0.4"`, `env_logger = "0.11"`, `serde_json = "1"` (probably present), cxx-qt-lib
   with `qt_gui` (already there). If the application already uses `env_logger` or its own logging, merge: `logs::init`
   installs the `log` backend (`set_boxed_logger`), so remove the existing `env_logger::init()`.
2. **Copy `logs.rs`**, change only the header comment if needed. Check the module compiles with the application's
   `cxx_qt_lib` version (Baladeur uses 0.10). Keep the tests.
3. **Start-up** (`main.rs`): `logs::init(APP, "<owner>/<repo>", version, incidents_enabled)` before anything logs;
   `logs::capture_qt()` before the engine loads QML. `incidents_enabled` reads `[debug] incidents` from the application's
   settings file the way the app already reads its settings (Baladeur: `theme::setting("debug", "incidents")`).
4. **Bridge**: add the four invokables (`logs`, `logFile`, `clearLogs`, `reportProblem`) to the object QML already uses
   (`Fili` in Baladeur; use the name the application has). Copy the four small functions of `bridge.rs`
   (`crate::logs::since`, `path`, `clear`, `incident("manual", ..., true)`). `copyText` and `openPath` exist; if not, add them.
5. **Panel**: copy `DebugPanel.qml`, register it in `build.rs`/the QML module list, import path as in the app
   (`import Fili.<Name>`), instantiate it above the footer, make every content area anchor `bottom: debug.top`. Where the
   footer is optional (`fili-theme footer off`), the panel anchors to the window bottom instead; it must stay reachable when
   the footer is hidden. Use the application's own `FiliTheme`/`TextButton`/`FiliScrollBar` (Casier's tokens: space/margin
   values, no literals; read `agents/skills/filigrane-ui/references/tokens.md` first).
6. **Action + shortcut + menu**: action `debug` in the window's action table (and in the `ctl ... action` command handler,
   so the bar's menu can call it), `Shortcut Ctrl+Shift+L`, View > Debug Logs in the fallback menu JSON. For Casier the menu
   file here must stay identical to the application's (`scripts/check-shell-menu.py` of Casier): change both.
7. **Translations**: the new strings (`Debug logs`, `All`, `Warnings`, `Errors`, `entries`, `Ask Rob`, `Copy`, `Clear`,
   `Open file`, `Rob was asked to look at it`, `Could not record the problem`) go in the application's language files
   (French at least). Baladeur's are in `dotfiles/config/quickshell/i18n/fr.json`.
8. **Tests**: keep the `logs.rs` unit tests; add a QML/menu check if the repository has one; run the application's
   `make check` (external repositories) or `tests/fili-shell/run.sh --changed` (here).
9. **Live check** (ask the user): launch the app, Ctrl+Shift+L shows the panel, text is selectable, the filter works, Ask Rob
   gives a notification and a Rob session; force a bug to see the incident (for instance a deliberate `console.error` of a
   TypeError via the QML console, never left in the code).
10. **Docs**: add the application to the "Debug panel" list in `app-window.md`; changelog line; README version/CPU/RAM
    note when a release is tagged (see the memory note on README measurements).

## 4. Work in this repository (done once, before or with the first rollout)

### 4.1 `fili-incident`
- It already works for any `app` and `repo` in the incident file. Verify it is **packaged**: `apps/fili-incident/package.env`
  exists; check that the xbps package list (`packages/`, `distro/`) installs the binary for users, not only the
  `~/.local/bin` symlink of this machine. If missing, add it to the same package as the other `apps/*` tools.
- Not yet tested live: the notification buttons (`notify-send --wait` with actions in the user's Quickshell) and the Rob
  session opened by `fili-incident ask`. Test with a **fake incident** the user knows about (tell them first: a
  notification will appear), never silently.
- Optional, only with the user's agreement: a **relay** for people with no GitHub account (a small service creating the issue
  with an organisation token; needs hosting and abuse protection). Today those users get the clipboard + the prefilled form.

### 4.2 `tests/fili-shell/check-app-window.py`
Add, for every application source tree it checks: `logs.rs` present and `logs::init` called; `DebugPanel.qml` present (add it
to `SHARED` once two applications have it); the fallback menu has a `Debug Logs` entry with `Ctrl+Shift+L`; `capture_qt` is
called. Add the check to `run.sh` with `want`. Update the "Check" paragraph of `app-window.md`.

### 4.3 Daemons and CLIs without a Qt window
Aéroport (`fili-term`), Conversations (`fili-im`) and Facteur (`fili-mail`) each have a **daemon** next to the window. The
daemon has no QML: give it the log (file + panic hook + incidents) but not the Qt handler or the panel. Make `capture_qt()`
and the `cxx-qt-lib` import optional (a cargo feature `qt`, on by default for the GUI binary), as `fili-mail` and `fili-im`
already split their `cxx-qt` dependencies behind a feature. The window's panel can then also show the daemon's log: read
`~/.local/state/filigrane/logs/<app>-daemon.log` (a second tab or a source filter in the panel) once the basics work.
`fili-ai` (Rob, `apps/fili-ai-daemon`) is a thin client: log file only, no panel.

## 5. Per-application notes

| Application | Program, repository | Stack | Notes |
| --- | --- | --- | --- |
| Baladeur | `fili-music`, `filigrane-os/filigrane` (here) | Rust + cxx-qt, QML `Fili.Baladeur` | Done. Reference. Core patch commits (`55c81b4`, `8bc5957`, `b01f7cc`) in `~/Projects/tornade-core-ffi` are local, not pushed: needs the user's OK. |
| Casier | `fili-file`, `filigrane-os/fili-file` (`~/Projects/fili-file`) | Rust + cxx-qt, `Main.qml` 156 KB | The **reference** for the app-window anatomy: do it first so `DebugPanel.qml` can join `SHARED`. Menu fallback must stay identical to the app's (`check-fili-file-menu.py`). `make check`, tag `vX.Y.Z` + `CHANGELOG.md`, then bump `apps/fili-file/upstream`. |
| Cassette | `fili-recorder`, here (`apps/fili-recorder`) | Rust + cxx-qt | Has uncommitted work from another session (`codec.rs`, `recorder.rs`): stage only your hunks, or wait. Easy: same layout as Baladeur. |
| Facteur | `fili-mail`, `filigrane-os/fili-mail` | cxx-qt behind a feature, daemon + window | Daemon log: see 4.3. Issues must go to its own repository. |
| Aéroport | `fili-term`, `filigrane-os/fili-term` | Rust daemon + Qt Quick window (`ctl.rs`, `proto.rs`) | It is a terminal: the panel must not steal key input from the shell; Ctrl+Shift+L may conflict with terminal shortcuts, check its keymap first and pick another chord if needed (and record it in the contract). |
| Conversations | `fili-im`, `filigrane-os/fili-im` | daemon + cxx-qt GUI behind a feature | Messages can be private: **never log message bodies**; the redaction in `fili-incident` removes paths, e-mails, IPs and MACs but not chat text. Check what the application logs before enabling the panel's copy/Ask Rob. Live test of P1 still pending (see `~/Projects/fili-im/docs/next.md`). |
| Rob | `fili-ai`, here | small Rust client | Log file only. |

Privacy rule for every application: nothing sensitive in log lines (tokens, passwords, message or mail bodies, file contents).
Review the existing `log::` calls of each application before turning the panel on, and lower or remove any that print
private data. The incident text is redacted before it leaves, but redaction is a net, not a licence.

## 6. Order of work

1. This repository: 4.1 (packaging check, live notification test) and 4.2 (check script), so each rollout is checked.
2. **Casier** (reference for the shared QML files), then add `DebugPanel.qml` to `SHARED`.
3. **Cassette** (same repository as the plan, no extra repository).
4. **Facteur**, **Conversations**, **Aéroport** (daemon split first: 4.3).
5. Extract `fili-log` (section 2, step 2) if the user agrees; otherwise leave the copies.
6. Update `app-window.md`, `AGENTS.md`, the todo note of each application (`fili-apps-todo` in memory), and report to the user in
   French: what was done, what was verified, what is not tested.

## 7. Done when

- Every window application has the panel (View > Debug Logs, Ctrl+Shift+L, or its documented alternative) and writes
  `~/.local/state/filigrane/logs/<app>.log`.
- A forced bug in each application produces an incident, a notification, and a Rob session that can `show`, `check` and
  `issue` it; the issue goes to the right repository.
- `check-app-window.py` fails when an application loses its panel, its menu entry or its `logs::init`.
- The user has tested at least one application live (notification buttons included) and agreed before any tag.
