# Plan: the shared interface kit `fili-ui` in every fili-* application

Goal: every window application of Filigrane takes its interface controls, window parts and cards from **one place**, the
`fili-ui` kit (`filigrane-os/fili-ui`, clone `~/Projects/fili-ui`), instead of keeping its own copy. Casier (`fili-file`) is done
(1.18.0); this plan covers Facteur, Conversations, Aéroport, Baladeur, Cassette and Lia, one at a time. This file is written to be
handed to a fresh Claude Code instance: it is self-contained. Read it, then do one application at a time, in the order of section 7.

## 0. Rules that apply (from `AGENTS.md` and the user's standing instructions)

- **Rust only, never C++**, not even for Qt bridges. Everything written in a repository is **English** (code, comments, commits,
  docs, UI strings; translations go in `i18n/<language>.json`). Answers to the user are **French**, short, factual: say what was
  done, verified, not tested.
- **No AI attribution** in commits or pull requests (no `Co-Authored-By`, no "Generated with"), whatever a default says.
- Public repositories: **scan the staged diff** (tokens, passwords, keys, e-mails, IPs, `/home/<login>`) before each commit and show it.
- **Never push to `main`, never tag by hand, without the user's explicit go.** Push on any other branch is fine. A version is a
  commit that raises `version` in `Cargo.toml` and adds its `CHANGELOG.md` section; merging it to `main` makes the CI tag it
  (`vX.Y.Z`, `facteur-vX.Y.Z` for Facteur). **Deploy locally and let the user try before that merge**, one version per application,
  not one per tweak.
- Other sessions edit the repositories at the same time: never `git stash`, stage only your own hunks (`fili-mail` had two
  uncommitted files of another session when this plan was written: leave them alone).
- Never inject keystrokes (`wtype`) on the user's screen; never `pkill -f` with a pattern that appears in your own command (it kills
  the shell: use `ps -eo pid,args | awk` with `!/awk/`, or the PID you started). `ls` is aliased to eza: use `command ls` or `find`.
- Build environment: `QMAKE=/usr/lib/qt6/bin/qmake6`; a cold build of the Qt crates takes about 7 minutes, an incremental one 1 to 2.
- The Filigrane session renders Qt Quick **in software** (`QT_QUICK_BACKEND=software`, set by niri): `MultiEffect`, `ShaderEffect`,
  `ColorOverlay`, `DropShadow` and `layer.effect` **draw nothing**. Never use them (the kit refuses them in its tests).
- Memory notes exist for several of these rules; read `~/.claude/projects/-home-thomas-Projects-filigrane/memory/MEMORY.md`.

## 1. State when this plan was written (2026-11-23)

| What | State |
| --- | --- |
| `fili-ui` kit | **v0.3.0** released (`main`, tag `v0.3.0`). 36 components, 33 headless tests, `make demo`. |
| Casier (`fili-file`) | **1.18.0** merged on `main` (`6c2e0d3`); its CI creates `v1.18.0`. It takes from the kit: theme, focus ring, buttons, scroll, window glyph, menu, view switch, window panel, debug panel, Lia button, tab row. It keeps its own sidebar, header, path bar, footer, list, grid. |
| Pin of Casier here | `apps/fili-file/upstream` may still say `v1.16.0`: the pull request "Pin fili-file to v1.18.0" opens by itself (`.github/workflows/bump-app-pins.yml`), or `scripts/bump-app-pins.sh --apply fili-file`. Then run `tests/fili-shell/run.sh` and note version, CPU and RAM in the README. |
| Pin of the kit here | `libs/fili-ui/upstream` (v0.3.0), read by `scripts/upstream-dir fili-ui`; the bump workflow handles it like an application. |
| Checks here | `tests/fili-shell/check-app-shell-parity.py` checks the kit's own theme and kinetic scroll and, for an application without a local `KineticScroll.qml`, the kit's; `check-app-window.py --ref CASIER --kit KIT APP` accepts an application that takes the shared controls, Lia button and debug panel from the kit. |
| Tool | `scripts/fili-compare-ui`: before / after of a window, pixel by pixel (section 4). |

The other six applications still carry their own copies (7 variants of `IconButton`, 3 of `TextButton`, copies of `DebugPanel`,
`WindowPanel`, `LiaButton`, menus, icons…). `~/Projects/fili-ui/docs/inventory.md` has the first inventory.

## 2. The kit (read before touching an application)

- Repository `~/Projects/fili-ui`, module `Fili.UI`, a Rust crate (`links = "fili-ui"`) so an application depends on it by git tag
  and cxx-qt-build brings the QML module. Release: raise `version` in `Cargo.toml`, add the `CHANGELOG.md` section, merge to `main`:
  the CI (`make check` in a Void container) tags `vX.Y.Z`. `make check`: module lint, `cargo check --locked`, 33 headless tests
  (`scripts/run-tests.sh`, needs `qt6-quick-test`), demo theme in sync. `make demo [TAB=n OPEN=panel|settings|tooltip]` shows everything.
- Read `~/Projects/fili-ui/README.md` (component table), `docs/adoption.md` (the five edits per application), `docs/host-contract.md`
  (what an application gives the kit), `docs/inventory.md`, `CHANGELOG.md`.
- Components: **tokens** `FiliTheme`, `FiliHost`; **buttons** `FiliButton`, `FiliIconButton`, `FiliViewSwitch`; **choices**
  `FiliSwitch`, `FiliCheckBox`, `FiliRadioButton`, `FiliSelect`; **values** `FiliSlider`, `FiliTextField` (placeholder, ×, error),
  `FiliProgressBar`; **window anatomy** `FiliHeader`, `FiliNavCapsule`, `FiliSidebar` (+ `FiliSidebarSection`, `FiliSidebarRow`),
  `FiliTabBar`, `FiliFooter`; **dialogs and cards** `FiliDialog`, `FiliMenu`, `FiliAboutCard`, `FiliShortcutsCard`,
  `FiliWindowPanel`, `FiliLiaButton`, `FiliDebugPanel`; **shell cards** `FiliTooltip`/`FiliTooltipCard`, `FiliPanel`
  (+ `FiliPanelSection`, `FiliPanelButton`), `FiliSettings`; **pictures** `FiliIcon` (50 line icons), `FiliAvatar`, `FiliSpinner`;
  **scrolling and focus** `KineticScroll`, `FiliScrollBar`, `FocusRing`, `WindowGlyph`.
- `FiliTabBar` is **the** tab row: a tab can always be moved (drag, Ctrl+Shift+Left / Right), closed (×, middle click, Delete) and
  detached (drag far from the bar), plus context menu, `+`, file drops (`agents/skills/filigrane-ui/references/app-window.md`, "Tabs").
- The application gives the kit one object, `FiliHost.backend = <its Rust object>`, with the members listed in `docs/host-contract.md`
  (theme: `light`, `accent`, `settingsRev`, `keyNav`, `themeJson()`; `tr(text)`; window: `windowControl()`, `windowState()`,
  `windowAction(name)`; `askLia()`; debug: `logs(since)`, `logFile()`, `clearLogs()`, `openPath()`, `copyText()`,
  `reportProblem()`, `uiState()`, `setUiState()`; `aboutRows()`). Every fili-* application already exposes these the same way.

## 3. The recipe for one application (Casier is the model)

Model commits in `~/Projects/fili-file`: `344b50a` and `d1e6ad3` (adopt the crate), `2cbe845` (the first-binding fix), `8359f52`
(menu, view switch, panels, Lia button), `5ce8ebf` (tabs), `6c2e0d3` (release). Work on a branch of the application's repository.

1. **Pin the kit.** `Cargo.toml`: `fili-ui = { git = "https://github.com/filigrane-os/fili-ui", tag = "vX.Y.Z" }` (a `path = "../fili-ui"`
   only while developing both; never commit it). `cargo update -p fili-ui`.
2. **Link it.** First line of `src/main.rs` after the comments: `use fili_ui as _;` (without a reference Rust does not link the
   crate and the link fails on `cxx_qt_init_crate_fili_ui`). `build.rs`: `.depend("Fili.UI")` on the application's module and delete
   from `qml_files` every file you replace. Forward the token file to the tests:
   `if let Ok(p) = env::var("DEP_FILI_UI_THEME_QML") { println!("cargo::rustc-env=FILI_UI_THEME_QML={p}") }`; the test that checks the
   `FiliTheme.*` names reads `env!("FILI_UI_THEME_QML")` (Casier's `src/main.rs`, test `every_theme_token_used_in_qml_is_defined`).
3. **Give the kit the application's object, in the FIRST binding of the root item** (a `Binding` child or `Component.onCompleted` is
   too late: the first tokens are 0 and every `ListView` whose margin depends on them shifts):
   `readonly property bool kitReady: { FiliHost.backend = Fili; return true; }` (use the application's own object name:
   `grep -n qml_singleton src/*.rs`). Delete the local `FiliTheme.qml` (the kit's reads `themeJson()`, `light`, `accent`, `settingsRev`).
4. **Replace the copies**, file by file: `import Fili.UI` where a kit type is used; rename the uses (`TextButton` → `FiliButton`,
   `IconButton` → `FiliIconButton`, `ContextMenu` / `PopupMenu` → `FiliMenu`, `ViewSwitch` → `FiliViewSwitch`, `DebugPanel` →
   `FiliDebugPanel`, `WindowPanel` → `FiliWindowPanel`, `LiaButton` → `FiliLiaButton`, `Icon` → `FiliIcon`, `AboutCard` →
   `FiliAboutCard`, `ShortcutsCard` → `FiliShortcutsCard`, `LoadingBar` → `FiliProgressBar`, `Spinner` → `FiliSpinner`, `Avatar` →
   `FiliAvatar`, tab strip → `FiliTabBar`); `git rm` the local file. Where the kit lacks something the application uses, **add it to the
   kit first** (section 6), release it, then use it: never leave a local override of a kit file.
5. **Tests of the application that read QML or catalogs.** `src/window.rs` (Casier): the test that compares the window panel's actions
   with the allowed list reads the kit's `FiliWindowPanel.qml` next to `FILI_UI_THEME_QML`. `scripts/check-i18n.py` must also read the
   kit's `FiliHost.tr("…")` texts of the components the application uses (Casier's script finds the kit with `cargo metadata`, keeps
   the components it references and their dependencies; copy it). Add the translations the kit components need to `i18n/fr.json`.
   The CI installs `qt6-quick-test` if the application has a QML test (`tests/sidebar-drag.sh` in Casier).
6. **Compare** before and after (section 4), then `make check`.
7. **Release**: version + `CHANGELOG.md`, push the branch, **ask the user to try the build**, then merge on their go.
8. **Here** (this repository): the pull request bumping `apps/<name>/upstream` opens by itself; run `tests/fili-shell/run.sh`, note the
   version, CPU and RAM in the README (memory note "README: version + CPU/RAM par release").

## 4. Verification: before and after, pixel by pixel

`scripts/fili-compare-ui [--args "ARGS"] [--fuzz 1%] BEFORE_BIN AFTER_BIN STEPS_FILE` starts each build in isolation (own
`XDG_STATE_HOME`, a short private `XDG_RUNTIME_DIR`, no D-Bus session: the resident instance and the user's files are untouched), runs
the steps (`ctl WORDS…` = `BIN ctl --pid PID WORDS…`, `focus`, `sleep`, `shot NAME`) and prints, per shot, the pixels that differ.
Copy the "before" binary **before** you change anything (`cp target/release/<app> /tmp/…-before`).

- Steps per application: list the states with `<app> ctl actions` and the verbs of `shell/ctl/<app>.json`; cover each view, each panel
  the migrated components draw (window actions, debug logs, menus when a verb opens one), the tab row with two or three tabs
  (`ctl tab new`, `tab move`, `tab switch`, `tab close` where they exist).
- **Expect noise**: window focus and the keyboard cursor change colours on the first row of a list (an accent ring, an accent label).
  Run the same binary twice (`before before`) to see your noise; a real regression is a difference between builds beyond it. Look at
  the diff image (`diff-NAME.png`) and the crop of the changed region before concluding.
- What the user must try by hand (gestures `ctl` cannot make): drag of tabs and rows, context menus, drops, keyboard chords.
- Pitfalls met while doing Casier: the `ctl` socket path must stay under 108 bytes; two builds in one `CARGO_TARGET_DIR` share
  `qml_modules/` (`cargo clean -p <app>` between them); `niri msg action screenshot-window` also fills the clipboard.

## 5. Pitfalls (each cost time on Casier)

- **First binding** of the root (step 3), or the first tokens are 0 and lists shift.
- **Software rendering**: no shader effects. A glyph is tinted in its file, a round picture is cut by a Canvas (`FiliAvatar`).
  Conversations' own `Avatar` uses `MultiEffect` and is likely already broken in the user's session: the kit's replaces it.
- **Layouts**: kit components give `implicitWidth` / `implicitHeight`. Inside a `RowLayout` (the header's `leading` / `tools`) set a
  size with `implicitWidth` or `Layout.preferredWidth`, never `width`.
- `FiliMenu.open` resets its index **before** swapping the items (a submenu binding read the old index): do not wrap it.
- A menu must never overflow its text (memory note "Le texte ne déborde jamais"); QML follows the `filigrane-ui` skill tokens.
- `check-app-window.py` and the parity script here know applications that use the kit (`fili-ui` in `Cargo.toml`); an application
  that does not yet still has the old per-file checks.
- A pinned old version (`apps/<name>/upstream`) is not held to a check that starts at a later version (`ROB_BUTTON` in
  `check-app-window.py`): move that table with the application.

## 6. Kit work to do first (gaps found while surveying the applications)

Do these in `~/Projects/fili-ui` **before** the application that needs them, each as a kit version (tests included).

| Gap | Needed by | What |
| --- | --- | --- |
| `FiliTextField.secret` | Facteur, Conversations (`Field.qml`: password fields) | `echoMode: Password`; keep the × off for secrets |
| `FiliIconButton.name` / `filled` | Facteur, Conversations, Aéroport (their `IconButton` draws a line `Icon`) | use `FiliIcon` when `name` is set, the font glyph otherwise |
| `FiliTabBar` items with an `icon` | Facteur (pinned folders show an icon), Conversations (platform dots) | `model` items `{ label, count, icon }`; app-specific decoration through a `Component` if an icon is not enough |
| `FiliTabBar` overflow | Facteur (many pinned tabs) | scroll or shrink below 80 px with a wheel; measure with the Facteur's `TabStrip.overflows` |
| Form rows for dialogs | Facteur (`AccountDialog`, `LabelDialog`, `FolderTabDialog`), Baladeur (`TagEditor`) | optional: a `FiliFormRow` (label above, field, hint/error) so dialogs stop hand-laying fields |
| Extending the theme | Aéroport (`terminalColors` computed from the palette) | keep a small app-side singleton that reads `FiliTheme` and adds its own tokens; do not fork `FiliTheme` |

## 7. Applications, in this order

Order: smallest and closest to Casier first, so the recipe settles before the big ones.

| # | Application (repo, module, backend object) | Local copies to remove | Notes |
| --- | --- | --- | --- |
| 1 | **Cassette** (`fili-recorder`, `Fili.Cassette`) | `FiliTheme`, `FocusRing`, `KineticScroll`, `FiliScrollBar`, `WindowGlyph`, `TextButton`, `IconButton`, `ContextMenu`, `ViewSwitch`, `DebugPanel`, `LiaButton`, `WindowPanel` | `SourcePicker.qml` → `FiliSelect`. Closest to Casier: same copies. No tabs. |
| 2 | **Baladeur** (`fili-music`, `Fili.Baladeur`) | the same, plus `PromptDialog`, `WelcomeDialog` (→ `FiliDialog`), `FilterBar` (→ `FiliTextField`) | `IconButton` has `size`: keep `FiliIconButton.size`. `TagEditor`, `ScannerDialog` stay (own logic); `VolumeDial`, `Carousel`, `AlbumCard`… stay. |
| 3 | **Aéroport** (`fili-term`, `Fili.Term`) | the shared set, `Icon` (→ `FiliIcon`), `ContextMenu` (→ `FiliMenu`), `AboutCard`, `TextPrompt` (→ `FiliDialog`), `IconButton` (its window-drawn tip is the kit's) | `Tab.qml` is a **terminal split tree**, not a tab row: keep it. The tab row of its `Main.qml` becomes `FiliTabBar` (detach exists there). `terminalColors` stays app-side (section 6). Its `FiliTheme` has no `settingsRev`: use the kit's. |
| 4 | **Conversations** (`fili-im`, `Fili.Im`) | the shared set, `Icon`, `PopupMenu`, `AboutCard`, `ShortcutsCard`, `Field` (needs `secret`), `SearchField` (→ `FiliTextField`), `Spinner`, `Avatar`, `PairDialog` (→ `FiliDialog`), `TabBar` (→ `FiliTabBar`, which adds reorder and detach it lacks) | Open chats as tabs: closable, movable, detachable like everywhere. `Avatar` takes `win.avatars[...]`: keep a thin wrapper that gives `FiliAvatar` a `source`. `Bubble`, `Composer`, `ChatList`, `EmojiPicker`, `QuickLook` stay. |
| 5 | **Facteur** (`fili-mail`, `Fili.Mail`; tags `facteur-vX.Y.Z`) | the shared set, `Icon`, `PopupMenu`, `AboutCard`, `ShortcutsCard`, `LoadingBar` (→ `FiliProgressBar`), `Field`, `TabStrip` + `ListBar` (→ `FiliTabBar`: keys → index, counts, `+`, icons) | Biggest: `Sidebar`, `MessageList`, `Reader`, `Compose` stay. Two files were uncommitted by another session: check `git status` first. Facteur's `TabStrip` is the reference of reordering: make sure `FiliTabBar` keeps what it does (counts, overflow, `+` modal through `addRequested`). |
| 6 | **Lia** (`fili-ai`, window crate `crates/fili-ai-window`, `Fili.Ai`, branch `develop`) | `Theme.qml` (its own small token file, backend object `Link`) → `FiliTheme`, `TextButton`, `IconButton`, `FiliScrollBar`, `KineticScroll`, `DebugPanel`, `About` (→ `FiliAboutCard`) | A layer-shell drawer: check the window still sizes itself. `FiliHost.backend = Link`. Its pin is `develop` until a tag exists. |

Per application, the **done** checklist: Cargo pin + link + first binding; copies removed (`git rm`); the application's `make check`
passes (i18n and token tests included); `scripts/fili-compare-ui` run and explained; the user tried it live; version + changelog;
merged on their go; here: pin bump merged, `tests/fili-shell/run.sh` passes, README figures updated. Also update the entries of
`DEBUG_PANEL` / `ROB_BUTTON` in `check-app-window.py` only if an application's rules change.

## 8. After the last application

- Delete from `check-app-window.py` the per-file `SHARED` comparison and the `normalize` calls: the kit is the only copy (keep the
  anatomy checks: sizes, header, window buttons, menu).
- Update `agents/skills/filigrane-ui/SKILL.md` and `references/app-window.md`: "an application never writes its own button, menu, tab
  row or card: it uses `fili-ui`; a missing piece is added to the kit first".
- Casier's own header, sidebar, path bar, list and footer remain Casier's: if two applications end up with the same sidebar or footer
  logic, promote it to the kit then, not before.
