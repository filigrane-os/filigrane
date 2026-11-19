# Plan: the "Ask Rob" header button in every fili-* application

Goal: every window application of Filigrane gets what Casier (`fili-file`) has since 2026-11-19: a speech-bubble button in
the header that shows Rob's small floating field for **that application** (`fili-chat here`). Rob answers in a new session
linked to the application and scoped to it, with the hidden brief `agents/rob/<app_id>.md`.
This file is written to be handed to a fresh Claude Code instance: it is self-contained. Read it, then do one application
at a time, in the order given in section 6.

## 0. Rules that apply (from `AGENTS.md` and the user's standing instructions)

- **Rust only, never C++**, not even for Qt bridges (cxx-qt + FFI from Rust). No `.cpp` file, ever.
- Everything written in a repository is **English** (code, comments, commits, docs, UI strings; translations go in language
  files). Answers to the user in the conversation are **French**, short, factual: say what was done, verified, not tested.
- **No AI attribution** in commits or PRs (no `Co-Authored-By`, no "Generated with").
- The Filigrane repository is public: scan the staged diff for tokens, passwords, keys, e-mails, IPs before every commit and
  show the result. Never push to `main` (nor force-push) without an explicit request; pushing another branch is allowed.
- **Test live before publishing.** Build and deploy locally, let the user try it, then one tag per application (not one per
  retouch). A tag needs its section in `CHANGELOG.md`; then change `ref` in `apps/<app>/upstream` here and run
  `tests/fili-shell/run.sh`. Compile first and let the user test; long test suites come after, or in the background.
- Applications live in their own repositories (clone in `~/Projects/<app>`, pin in `apps/<app>/upstream`). Work on a
  **branch of its own** (`feat/ask-rob-button`), created from `main`: other branches of that repository may hold unrelated
  work. Never `git stash` (other sessions edit in parallel).
- Never inject keystrokes (`wtype`, `ydotool`) to test: they land in the user's terminal. Look at the screen with niri's own
  screenshot (`niri msg action screenshot-screen`, files in `~/Screenshots/`).
- QML follows the `filigrane-ui` skill (`agents/skills/filigrane-ui/references/app-window.md`): sizes are tokens of the
  application's `FiliTheme.qml`, never literals; text never overflows (elide).

## 1. What exists (the model to copy)

Reference application: **Casier**, repository `filigrane-os/fili-file`, branch `feat/ask-rob-button` merged into `main`
(commit `3587bf3`, merge `d3be62f`; not tagged yet when this plan was written: check `git tag` there).

- **`qml/RobButton.qml`** (about 55 lines): a `Rectangle` 28 × 24, `radiusControl`, hover `surfaceHover`, pressed
  `surfaceActive`; a 16 × 16 `Canvas` draws the speech bubble in the colour `ink` (default `FiliTheme.text`); click calls
  `Fili.askRob()`; `Accessible.name: Fili.tr("Ask Rob")`. The colour property is named **`ink`**, not `color`: a property
  `color` on a `Rectangle` root fails with "Property value set multiple times".
- **`Fili.askRob()`** in `src/bridge.rs` (invokable `askRob`): spawns `fili-chat here` with null stdio and reaps the child in
  a thread, exactly like `openPath` next to it.
- **`Main.qml`**: `RobButton { id: robButton; visible: Fili.hasTool("fili-chat") }` anchored to the left of `windowButton`
  (`space1` gap; to the left of `closeButton`, or at the margin, when the window buttons are hidden); the search field (or
  whatever sits left of the buttons) is anchored to `robButton.left` when it is visible.
- **`build.rs`**: `qml/RobButton.qml` added to `qml_files`. A QML file that is not listed is not in the module.
- **`i18n/fr.json`**: "Ask Rob" → "Demander à Rob" (already present in Casier: check each application's file for the key).
- On the shell side (this repository, already done): `fili-chat here` shows `FiliAsk.qml` (Enter sends and opens the chat on a
  new session, Shift+Enter sends without opening it, Esc cancels). The generic menu entry "Ask Rob…" (Mod+Ctrl+Y) is in
  `dotfiles/config/filigrane/appmenu/_default.json` and appears in every application's menu: the button is **never the only
  way** to reach Rob. The hidden briefs are `agents/rob/_default.md` and `agents/rob/<app_id>.md` (all six exist).

## 2. Decisions

- **Copy first, share later**, like the Debug panel (`docs/plan-debug-panel-rollout.md` §2): `RobButton.qml` is a shared file,
  **identical in every application**, reference Casier. A shared crate or QML module is a later decision, once seven
  applications carry the same three files.
- **Availability**: the button shows only where `fili-chat` is installed. Casier uses its existing `Fili.hasTool("fili-chat")`.
  An application without a `hasTool` invokable adds `robAvailable() -> bool` (a `PATH` lookup for `fili-chat`, same code as
  its other tool lookups) and uses `visible: Fili.robAvailable()`. Do not invent a third way.
- **Place**: left of the window button, as in Casier. It is part of the header anatomy (`app-window.md`, "Ask Rob button").
  It disappears with the header (`--no-header`, `[window] header = false`): nothing is reachable only from the header, the
  bar menu entry and Mod+Ctrl+Y exist.
- **Attention colour**: when an application highlights its header (`attend()`, header on the accent colour), the controls drop
  to a tint of `onAccent`. The button follows the same rule through `ink`: bind `ink` to the colour the other header
  controls use in that state. Applications without the attention mode keep the default.
- **No setting** to hide the button: it is cheap, and the header can already be turned off.
- Nothing is added to the applications' own menus: the generic entry in the bar covers it. (Casier's fallback menu file stays
  identical to the application's menu; `check-fili-file-menu.py` keeps it so.)

## 3. Per-application steps (the same checklist everywhere)

1. `cd ~/Projects/<app>`; `git switch -c feat/ask-rob-button main` (check `git status` first: if the tree is dirty with
   someone else's work, stop and ask).
2. Copy `RobButton.qml` from Casier (`~/Projects/fili-file/qml/RobButton.qml`) unchanged. List it in `build.rs`.
3. Rust bridge: add the invokable `askRob` (and `robAvailable` when the application has no `hasTool`), copying `ask_rob` from
   Casier's `src/bridge.rs`. cxx-qt invokable declaration with `#[cxx_name = "askRob"]`, implementation next to `open_path`.
4. `Main.qml`: instantiate `RobButton` next to `windowButton` as in Casier, re-anchor what was anchored to `windowButton.left`
   (search field, title, tools) to `robButton.left` when visible. Use the application's own tokens for margins.
5. Strings: add "Ask Rob" to `i18n/fr.json` if missing.
6. Build with the application's `make` (or `cargo build --release` with `QMAKE=/usr/lib/qt6/bin/qmake6`), run its checks
   (`make check`).
7. **Deploy locally and let the user test** (section 5 gives each application's command). Look at the header with a niri
   screenshot at normal and narrow widths: the button must not overlap the search field or the title, text must elide.
8. After the user's OK: `CHANGELOG.md` section, version bump, tag `vX.Y.Z` (the tag naming of each repository is in section
   5), then here: change `ref` in `apps/<app>/upstream`, run `tests/fili-shell/run.sh`, note version, CPU and RAM in the
   README (rule: every new application version records them), commit, and tick the box in section 7.

## 4. Work in this repository (once, before or with the first rollout)

- **`tests/fili-shell/check-app-window.py`**: add a `ROB_BUTTON` list next to `DEBUG_PANEL` (each application joins when it
  gets the button): `RobButton.qml` identical to Casier's, listed in `build.rs`, instantiated in `Main.qml`, `askRob` declared
  in `bridge.rs`. Casier is in the list from the start.
- **`agents/skills/filigrane-ui/references/app-window.md`**: the "Ask Rob button" paragraph already exists; extend the list of
  applications that have it as each one joins (same sentence style as the Debug panel's "Have it:" list).
- **`agents/rob/<app_id>.md`**: exists for the six applications; a new application with a window gets its brief at the same
  time (`check-fili-chat-here.py` fails otherwise).
- **`docs/plan-ask-rob-button-rollout.md`** (this file): tick section 7 as applications are done.
- Memory/todo: `fili-apps-todo` gets a line per application ("Ask Rob button") while it is open.

## 5. Per-application notes

| Application | Repository, current pin | Header in | Bridge | Deploy for the user's test |
| --- | --- | --- | --- | --- |
| Aéroport (`fili-term`) | `filigrane-os/fili-term`, `v3.1.0` | `qml/Main.qml` (`closeButton` ~l.1669, `windowButton` ~l.1688) | `src/gui/` (`app.rs` already spawns `fili-chat ask`: reuse that pattern) | `make` in `~/Projects/fili-term`, run the built binary |
| Facteur (`fili-mail`) | `filigrane-os/fili-mail`, `facteur-v1.4.1` | `qml/Main.qml` (~l.1467 / ~l.1486) | `src/gui/bridge.rs` | build there; it also has a daemon and CLI: only the GUI binary changes |
| Conversations (`fili-im`) | `filigrane-os/fili-im`, `v0.1.4` | `qml/Main.qml` (~l.491 / ~l.504) | `src/gui/bridge.rs` | build there; the daemon is separate and untouched |
| Baladeur (`fili-music`) | `filigrane-os/fili-music`, `v0.1.0` | `qml/Main.qml` (~l.568 / ~l.592) | `src/bridge.rs` (has `copyText`, `openPath`) | build there; shares the tornade-core library |
| Cassette (`fili-recorder`) | **this repository**, `apps/fili-recorder/` | `qml/Main.qml` (~l.378 / ~l.402) | `src/bridge.rs` (has `copy_text`, `open_path`) | `./bootstrap.sh --apps` (alone, no sudo) |

Line numbers are indications from 2026-11-19: search for `id: closeButton` and `id: windowButton`.

- **Aéroport**: the header has a tab strip; keep the button in the right-hand cluster, not in the tab strip. The window
  already has an "Ask Rob" on failed commands (`fili-chat ask`, context of the command): leave it alone, it is a different
  gesture (a question about a command block), and the header button asks about the application in general. Its attention mode
  (`attend()`, `attentionOn`) exists: bind `ink` as in section 2. The window can be headless; the Mod+Ctrl+Y path covers that.
- **Facteur**: the header carries layout buttons, a search field and navigation; the search field is the element to
  re-anchor. Mail content is untrusted text: nothing to do here, but the brief
  `agents/rob/fili-mail.md` already says so.
- **Conversations**: the daemon and the window are separate processes: only the window binary gets the invokable.
- **Baladeur**: the header holds the transport and search; check that the narrow window layout (when it collapses controls)
  still leaves room, else the button joins the collapsed group.
- **Cassette**: lives in this repository, so one commit covers it and no tag is needed; still let the user test first, and
  keep the screenshot check (it has the attention mode, `attend()`).
- **Rob itself (`fili-chat`)** has no button: it is the destination.
- Applications that are not `fili-*` (Chrome, foot) have no header of ours: the generic bar entry and Mod+Ctrl+Y are enough.

## 6. Order of work

1. **Cassette** (this repository, no tag, quickest to iterate: proves the checklist and `check-app-window.py` change).
2. **Baladeur** (smallest repository).
3. **Conversations**.
4. **Facteur**.
5. **Aéroport** (the most complex header: tabs, attention, headless).

One application per session of work; after each one the user tests it live before the next tag.

## 7. Done when

- [ ] Casier tagged with the button (version noted in its `CHANGELOG.md`, pin updated here, README figures)
- [x] Cassette
- [x] Baladeur (committed on feat/ask-rob-button, not tagged yet)
- [x] Conversations (committed on feat/ask-rob-button, not tagged yet)
- [x] Facteur (committed on feat/ask-rob-button, not tagged yet, not yet tried by the user)
- [x] Aéroport (committed on feat/ask-rob-button, not tagged yet, not yet tried by the user)
- [ ] `check-app-window.py` checks `ROB_BUTTON` for every application above, and `tests/fili-shell/run.sh` passes
- [ ] `app-window.md` lists the applications that have the button

Check on each application, by hand: the bubble is at the left of the window button; a click shows the floating field titled
"Rob, about <Name>" (the display name, e.g. "Casier"); Enter opens the chat on a new session that answers about this
application only; with the header off (`fili-theme header off`) the same works from the bar menu entry and Mod+Ctrl+Y.
