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
2. **Move the AI logic out of `bar/BarState.qml` into the `agent` module.** About 100 lines of `BarState` are the assistant's
   (`aiData`, `aiFor`, `aiChat`, `aiAsk`, `aiSeen`, `aiName`, `aiLimit`, the watcher of `fili-ai/state.json`). The module cannot ship
   in the `fili-ai` repository while its logic lives in the shell. Move them into `modules/agent/` (a small `AgentState.qml` next to
   the module, reading `AiState` and `state.json`), move their tests from `tests/fili-shell/TestShell.qml`, keep `run.sh` green.
3. **Technical question to settle with the user: how does the drawer sit on screen?** Today `FiliAi.qml` is a layer-shell surface
   with an exclusive zone (the drawer docks to the right edge and the windows shrink beside it; or it floats above them). A Qt Quick
   window cannot be a layer-shell surface without `layer-shell-qt` (C++: forbidden here, Rust only). Options: (a) a normal window in
   niri, docked as the right-hand column (niri rules) or floating, losing the exact "dock beside windows" feel; (b) a Rust wrapper
   around the layer-shell protocol (check what cxx-qt-lib offers first); (c) keep a thin layer-shell surface in the shell that only
   embeds the application's content. Measure (a) in a prototype first: it is by far the simplest and removes the `chatFocus` hack of
   `AppMenu.qml` (a real window is a real focus).

## The extraction, step by step (each step commitable and tested)

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
