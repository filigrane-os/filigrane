# Plan: the assistant leaves the distribution (`fili-ai`)

Written on 2026-11-22 to resume in a clean conversation. Read `AGENTS.md`, `docs/api.md` and this file; nothing else is needed.

## Decisions already taken (by the user)

- Filigrane must work **without AI**. The assistant is an optional client of the contracts in `docs/api.md`, never wired into the shell.
- The assistant moves to its own repository, **`filigrane-os/fili-ai`** (not created yet: creating a public repository needs the user's
  explicit go). It becomes a **real Qt application**, like Casier (`~/Projects/fili-file` is the reference), not QML files of the shell.
- `fili-chat` is gone; **`fili-ai` is the one command** (`toggle | show | hide | here | ask | sessions | send | daemon | mcp`, plus the
  launcher verbs `use | pick | install | update | status | key`). The bash launcher `dotfiles/home/.local/bin/fili-ai` hands the drawer's
  verbs to the program `fili-ai-daemon` before reading anything (Mod+Y must stay quick).
- What goes with it: `fili-ai-session` (terminal sessions of the agents), the bar module `agent`, the briefs of Rob (`agents/rob/`,
  `agents/chat-prompt.md`), the agents' hooks and settings (`dotfiles/home/.claude/`, `.codex/`, `config/opencode/`).
  **`fili-incident` stays in the distribution**: collecting, notifying and preparing the GitHub issue are useful without an
  assistant; only its "Ask Rob" button comes from an incident handler (`shell/incident/<name>.toml`).
- **The assistant is named Lia** (decided on 2026-11-22; *l'IA*). Rob is retired. Only the display name changes: the program, the
  repository and the commands stay `fili-ai`, and the About card says "also known as fili-ai". The rename is done **once, at the
  extraction** (list at the end of this file).
- Skills `filigrane` and `filigrane-ui` describe the whole OS: proposed to stay here (to confirm with the user).
- **Commit only; tag everything once, at the end of the developments** (apps: no version bump, no push, no tag before the user has
  tested live; see the rules of `AGENTS.md`). The old binary `~/.local/bin/fili-chat` stays until that live test, then it is removed.

## State at the end of the session

All of this is committed locally (branch `develop`, nothing pushed); `tests/fili-shell/run.sh` passes (547 checks), and the six
applications build (`cargo check`).

| Done | Where |
|---|---|
| The Filigrane API without AI: contexts, ctl catalogs, incidents and handlers, events, assistant state; `docs/api.md` | this repository |
| `fili-api` (`list`, `show`, `apps`, `check`, `doctor`), `fili-event` (`emit`, `list`, `watch`) | `dotfiles/home/.local/bin/` |
| `fili-api-lint`: the **one** validator that defines every format (a key it does not list is refused); each application keeps a byte-identical copy `scripts/fili-api-lint`, run by its `make check` with `--app .`; `tests/fili-shell/check-api.sh` checks the copies | this repository + the six applications |
| `shell/ctl/<app_id>.json` in Casier, Aéroport, Facteur, Conversations, Baladeur, Cassette: verbs, actions (label, shortcut, arguments), action families | the six applications |
| `fili-incident` handlers: no assistant = *Report…* and *Ignore*; `dotfiles/config/filigrane/incident/rob.toml` registers Rob | `apps/fili-incident` |
| Bar modules self-contained: own `i18n/`, `group`, `uses`; `tests/fili-shell/check-module-contract.py` | `dotfiles/config/quickshell/bar/modules/` |
| `fili-chat` → `fili-ai` (command, socket, config `fili-ai.toml`, menu `fili-ai.json`, `FILI_ROB`, `fili-shell ai`, QML `FiliAi`) | everywhere, including the six applications' "Ask Rob" buttons |
| The shell reads the assistant through `AiState.qml` (`$XDG_RUNTIME_DIR/fili/ai/ui.json`, written by the drawer): the bar, the application menu and the agent panel never touch `FiliAi` | `dotfiles/config/quickshell/` |

Commits of this repository, oldest first: `ea11303` (module contract), `7708c2b` (API, fili-api, fili-event, handlers), `443856a`,
`515a90b` (formal catalog format), `4999ab0` (fili-chat removed), `ae99f56` (context and incident formats, `fili-api doctor`),
`c1d9479` (AiState). Each application has the matching `shell/ctl: …`, "Ask Rob: the assistant is driven by fili-ai" and
"scripts/fili-api-lint …" commits on `main` (local).

## What is still to do **before** the Qt application

1. ~~Decide the name~~: done, **Lia**. Do the rename while moving the files (see "The name" below), not before.
2. ~~Move the AI logic out of `bar/BarState.qml`~~: done. `modules/agent/AgentState.qml` holds it (the module and the panel each
   create one; only the module sets `watching`); the tests use a probe instance (`probeAgent`).
3. ~~How does the drawer sit on screen?~~ Settled on 2026-11-22: **keep the current behaviour (layer-shell surface with an exclusive
   zone), with no C++ at all.** The Void package `layer-shell-qt` ships a QML module `org.kde.layershell` and the Wayland shell
   integration plugin. Prototype run on the real niri (Qt 6.11 with layer-shell-qt 6.7.5): a plain Qt Quick `Window` got a layer-shell
   surface (`niri msg layers` listed it, keyboard on-demand). Recipe for the drawer process of `fili-ai`:
   - set `QT_WAYLAND_SHELL_INTEGRATION=layer-shell` before the `QGuiApplication` is created (the drawer is its own process, so no
     other window of the application is affected; a normal window such as the settings or About card is another process or goes
     without the variable);
   - in QML: `import org.kde.layershell 1.0 as LayerShell`, then on the `Window`: `LayerShell.Window.scope`, `.layer`, `.anchors`
     (top | bottom | right), `.exclusionZone` (drawer width: windows shrink beside it; 0 when it floats), `.keyboardInteractivity`
     (`KeyboardInteractivityOnDemand`);
   - the xbps package of `fili-ai` depends on `layer-shell-qt` (already installed here with `-devel`; `-devel` is not needed, remove it);
   - risk: the package is built against an older Qt than the system's; it loads today, so watch it after Qt updates (a test in the
     repository should start a window and check `niri msg layers`).
   Option (a) (normal window) and the Rust wrapper (b) are dropped; the `chatFocus` hack of `AppMenu.qml` can still go once the
   drawer is a real window of its own process with on-demand focus.

## The extraction, step by step (each step commitable and tested)

Progress (2026-11-22): steps 1 and 2 are done **locally** in `~/Projects/fili-ai` (cargo workspace `crates/fili-ai-daemon`,
`crates/fili-ai-session`, history kept through `filter-branch`, launcher `bin/fili-ai`, `Makefile`, CI, `scripts/fili-api-lint`;
`make build` and the 16 unit tests pass). No GitHub repository yet (needs the user's go), nothing removed from here yet (step 5).
The session still reads its translations from the shell catalog (`~/.config/quickshell/i18n`): move its strings to the package.

1. Create `~/Projects/fili-ai` as a clone of the layout of `~/Projects/fili-file`: `Cargo.toml` (cxx-qt), `Makefile`
   (`build`, `test`, `check`, `install`, `install-data`, `uninstall`), `.github/workflows/ci.yml` (Void container; the CI of `main`
   tags `vX.Y.Z` when the version is bumped), `CHANGELOG.md`, `scripts/fili-api-lint` (copy), `scripts/check-shell-menu.py`.
   **Ask the user before creating `filigrane-os/fili-ai` on GitHub.**
2. Move the programs with their history (`git filter-repo` on a copy): `apps/fili-ai-daemon` (the daemon and its CLI),
   `apps/fili-ai-session`. Keep the binary names `fili-ai-daemon`, `fili-ai-session`; ship the launcher `fili-ai` with the package.
3. Rob's window as a Qt Quick application following `agents/skills/filigrane-ui/references/app-window.md` (header 44, sidebar, footer
   28, menu exposed to the bar, Debug panel, settings `fili-ai.toml`, About card, theme parity with the shell). Port `FiliAi.qml`
   (1630 lines) piece by piece; the small floating field `FiliAsk.qml` (Enter sends, Shift+Enter sends without opening) must keep
   working. It publishes `ui.json` itself (the format is `fili-api-lint ai-ui`).
4. Make it a good citizen of the API: its own ctl catalog `shell/ctl/fili-ai.json` (the menu entries become
   `fili-ai ctl --pid %pid action NAME` instead of `fili-shell ai ACTION`), `shell/appmenu/fili-ai.json`,
   `shell/rob/…` brief, `shell/incident/<name>.toml` (the handler), `shell/fili-bar/agent/` (the module), its context file.
5. Remove from this repository: `apps/fili-ai-daemon`, `apps/fili-ai-session`, `FiliAi.qml`, `FiliAiAbout.qml`, `FiliAsk.qml`,
   the `ai` target of `fili-shell` and `shell.qml`, `modules/agent/`, `appmenu/fili-ai.json`, `incident/rob.toml`, the tests
   `check-fili-ai-*.py` (they move to the new repository). Add `apps/fili-ai/upstream` (url + tag), adapt `bootstrap.sh`,
   `.github/workflows/ci.yml`, `distro/` packaging and `tests/fili-shell/run.sh` (app parity + anatomy like the other applications).
   The hooks of `~/.claude/settings.json` (`fili-ai-session hook`) follow the package.
6. Live test by the user, then bump the version in `fili-ai` (the CI tags it), pin it here (`scripts/bump-app-pins.sh`).

## Tag at the end (all together, after the user's live test)

- Casier, Aéroport, Facteur, Conversations, Baladeur, Cassette: each carries a catalog, the "Ask Rob" change and the validator copy
  since their last tag (the catalogs reach the packages only with those versions). Bump the version in `Cargo.toml` and add a
  `CHANGELOG.md` section in each; the CI of `main` tags and releases; then change the pins here.
- Note version, CPU and RAM in the README of the distribution at each release (see the memory note on release tracking).
- Remove `~/.local/bin/fili-chat` (old binary, kept for the live test).

## Pitfalls met in this work

- `git add` with a pathspec that does not exist aborts the whole `add` silently: check `git show --stat` after a commit in a loop.
- `run.sh` under heavy CPU load (six Qt compilations) gives false failures (menu tests, "timed out"): run it on a quiet machine.
- A test that chains `… && git commit` commits even when the tests failed: read the result first.
- A bar module is loaded by its file; a new QML file needs `./bootstrap.sh --fili-shell` (links are made file by file).
- `bootstrap.sh --dotfiles-only` asks for sudo for the firewall: harmless without a terminal, the links are made.
- The state directory `~/.local/state/filigrane/chat/` (history of the sessions) kept its old name on purpose: do not lose the history.

## The name: Lia (decided)

Rob (robot) and Lia (*l'IA*) were both puns; Lia was chosen. The reasons, for the record:

- **"to rob" means to steal in English**, which is an unfortunate word for an assistant that can read your files and run commands.
  In French it is just a first name; the robot pun works in both languages.
- **Lia** reads as a first name, is short and soft, and *l'IA* ("the AI") is exactly how it is pronounced in French. The pun is
  French-only; for an English reader it is simply a name. It also echoes the program name (`fili-ai`) and fits the French display
  names of the applications (Casier, Aéroport, Facteur, Cassette, Baladeur, Conversations).
- Whatever the choice, the display name is an alias: the program, repository and commands stay `fili-ai`, and the "About" card says
  "also known as fili-ai" (the alias rule of `AGENTS.md`).
- Rename to do (all in places that move anyway): "Ask Rob…" → "Ask Lia…" (the default menu, six applications' `RobButton.qml`), `agents/rob/`,
  `shell/rob/<app>.md` in six repositories, the hidden prompt, the `.desktop` (`Name=Rob`), the handler label, the About card,
  the README and the docs. Do it **once, at the extraction**.
- Still to check before the public release: that no well-known product of the same kind already carries the name.
- Files to rename or rewrite: `agents/rob/` → `agents/lia/`, `shell/rob/<app>.md` → `shell/lia/<app>.md` in the six applications (and the
  loader `fili-ai` that reads them, plus `~/.config/filigrane/rob/<app>.md` → `lia/`, with a fallback to the old folder), `RobButton.qml`
  → `LiaButton.qml`, the menu label, `Name=` of the `.desktop`, the label of the incident handler, the hidden prompt, `AGENTS.md`, the
  skills and the docs. Grep for `Rob`, `rob` and `RobButton` to find them all.
