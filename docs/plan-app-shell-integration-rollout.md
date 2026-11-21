# Plan: every application ships its own integration (launcher, icon, bar module, bar menu, brief of Rob)

Goal: updating an application = updating its package. Everything an application brings to the Filigrane desktop lives in **its
own repository** and is installed **by its package**: the program, the launcher, the icon, the module of the fili-bar, the
fallback menu of the global menu, the brief of Rob. Nothing of it stays in `filigrane-os/filigrane`, so a release of the
application never needs a second change here (except the pin, which the bot proposes).
Baladeur (`fili-music`) did it first and is the reference. This file is written to be handed to a fresh Claude Code instance:
it is self-contained. Read it, then do one application at a time, in the order of section 6.

## 0. Rules that apply (from `AGENTS.md` and the user's standing instructions)

- **Rust only, never C++.** Everything written in a repository is **English** (code, comments, commits, docs, UI strings;
  translations in language files). Answers to the user in the conversation are **French**, short, factual: what was done,
  verified, not tested.
- **No AI attribution** in commits or PRs. The repositories are public: scan the staged diff for tokens, passwords, keys,
  e-mails, IPs before every commit. Never push `main` of `filigrane` (nor force-push); pushing `develop` is allowed.
- **Test live before publishing.** A version is published by merging to `main` the commit that raises `version` in
  `Cargo.toml` (the CI of the application creates the tag and the release). Ask the user before merging an application's
  branch to `main`: that merge publishes.
- Applications live in `~/Projects/<app>`; work on a branch (`feat/shell-integration`) created from `main`. **Other sessions
  edit these repositories in parallel**: `git status` first, never `git stash`, never commit what is not yours (commit with
  paths, or with a temporary index when a file also holds someone else's hunks).
- Never inject keystrokes (`wtype`, `ydotool`). Look at the screen with niri's own screenshot.
- Containers: **podman** (rootless, no daemon; Docker is removed from the machine). `/tmp` is a 7.8 GB tmpfs (memory): put
  cargo target directories in `~/.cache`, not in the scratchpad.

## 1. What exists (the model to copy: Baladeur)

Repository `filigrane-os/fili-music`, tag `v0.2.0` (commits `5bc43be`, `f8407a2`, merge `e799d83`):

```
shell/fili-bar/<module>/   module.toml, <Name>Module.qml, <Name>Panel.qml, i18n/fr.json   (the module of the fili-bar)
shell/appmenu/<app_id>.json                                                               (fallback menu of the global menu)
shell/rob/<app_id>.md                                                                     (hidden brief of Rob for this app)
data/<app_id>.desktop                                                                     (launcher)
icons/<app_id>.svg  (or data/icons/hicolor/scalable/apps/)                                 (icon)
Makefile            build, test, install, install-data, uninstall
scripts/check-shell-menu.py                                                               (the bar menu agrees with Main.qml; run by `make test`)
```

- **`make install-data`** installs everything but the binary (launcher, icon, licences, and `shell/` merged into
  `$(DATADIR)/filigrane/shell/`); `make install` = `build` + `install-data` + the binary and its aliases.
- On the distribution side (all in this repository, already done and tested):
  - `distro/build-repo.sh`: an app with a `Makefile` installs itself (`make install PREFIX=/usr DESTDIR=...`); one without
    gets its `shell/` copied to `/usr/share/filigrane/shell/`.
  - `bootstrap.sh` (`setup_app_shell`): a source build runs the app's `make install-data PREFIX=~/.local` when the target
    exists (else links its `shell/` into `~/.local/share/filigrane/shell/`), then `fili-bar link-system`.
  - **`fili-bar link-system`** (also run by `fili-bar autostart` at login): links `shell/fili-bar/<name>/` into
    `~/.config/quickshell/bar/modules/` and `shell/appmenu/*.json` into `~/.config/filigrane/appmenu/`, from
    `/usr/share/filigrane/shell` and `~/.local/share/filigrane/shell` (`FILI_SHELL_DIRS` replaces both, for tests). It
    **never replaces** a module of the repository, a plugin or a file of the user's own (those win), and forgets the links of
    what a package no longer ships. Tests: `tests/fili-shell/check-fili-bar-cli.sh`.
  - **`fili-chat`** reads the brief of Rob from `agents/rob/<app_id>.md` of the repository, else from the shipped
    `rob/<app_id>.md` (last shipped folder wins). Test: `apps/fili-chat` unit tests.
  - **The shell bench** (`tests/fili-shell/run.sh`) loads the modules and fallback menus shipped in the `shell/` of the pinned
    applications (`scripts/upstream-dir`, or `FILI_SRC_<APP>=~/Projects/<app>` for a local checkout), like a machine where the
    packages are installed. `check-app-window.py` finds the menu in `shell/appmenu/<app_id>.json` of the checked source.
- The removal commit in this repository (`410c048`) is the model of step 8 below: pin to the new tag, `git rm` the module,
  fallback menu, brief, launcher, icon and the menu check, drop the module-only strings of
  `dotfiles/config/quickshell/i18n/fr.json`, adapt `run.sh` (`want` regex, the call of the old menu check).

## 2. Decisions

- **Code stays at the root** of each application repository (no `app/` folder): `Cargo.toml`, CI, `package.env` and the pins
  assume it. The new folders are `shell/` and `data/`.
- **A module folder is named after the module** (`baladeur`, `recorder`, `mail`, `messages`): that is the name the bar and
  `fili-bar.toml` use. One application may ship several modules.
- **The repository's copy wins** over a shipped one while both exist, so an application is migrated without a flag day:
  ship it, release it, then remove the copy here in the same commit as the pin.
- **Translations of the module** go to `shell/fili-bar/<module>/i18n/fr.json` (extract the strings the module uses from the
  shell's `fr.json`; a string also used by the shell stays in both). The strings only the module used leave the shell's
  catalog, or `scripts/check-i18n.sh` fails with "unused entry".
- **No API freeze** (decided with the user): `api = 1` stays as it is, nobody else uses the interface.
- **Versions**: each application raises a minor version ("ships its launcher, bar module and menu") with a `CHANGELOG.md`
  section; the merge to `main` publishes it. Do not tag by hand.
- What **stays here**: the shell (bar, taskbar, panels, launcher), generic modules (clock, audio, network…), `_default.json`,
  the menus of programs that are not Filigrane applications (`foot.json`, `google-chrome.json`), the menu of Rob itself
  (`fili-chat.json`: Rob lives in `apps/fili-chat` of this repository), the launchers of the shell (`fili-chat`,
  `fili-settings`, `nvim-foot`).

## 3. Per-application steps (the same checklist everywhere)

1. `cd ~/Projects/<app>`; `git status`; `git switch -c feat/shell-integration main`.
2. Copy from this repository (`git show`/`cp`, do not delete yet): the bar module folder → `shell/fili-bar/<module>/`
   (+ `i18n/fr.json`), `dotfiles/config/filigrane/appmenu/<app_id>.json` → `shell/appmenu/`, `agents/rob/<app_id>.md` →
   `shell/rob/`, the launcher and icon if they are here.
3. `Makefile`: add `install-data` (launcher, icon, licences, `cp -r shell/. $(DESTDIR)$(DATADIR)/filigrane/shell/`) and make
   `install` depend on it; add the module and menu files to `uninstall`. An app without a Makefile gets one modelled on
   `fili-music/Makefile` (QMAKE for cxx-qt, `build`, `test`, `install`, `install-data`, `uninstall`).
4. Port the menu check to `scripts/check-shell-menu.py` of the app (model: Baladeur's; for Casier see section 5) and call it
   from `make test`. Check the CI (`.github/workflows/ci.yml`) runs `make build test`.
5. `make install-data DESTDIR=$(mktemp -d) PREFIX=/usr` and read the file list; `make uninstall` leaves no file.
6. Version bump + `CHANGELOG.md` section (the `Cargo.lock` line too); `make build test` locally.
7. **Prove it without removing anything here**: temporarily move the app's copies out of this repository's working tree
   (module, appmenu json, brief), run `FILI_SRC_<APP>=~/Projects/<app> FILI_APPS=/nonexistent tests/fili-shell/run.sh`
   (0 failure; the module's `expectClick`/`expectMenu` tests pass), then put the copies back.
8. After the user's OK, merge the branch to the application's `main` and push: the CI publishes the tag. Then **one commit
   here**: `apps/<app>/upstream` → the new tag, `git rm` the copies (module, appmenu json, brief, launcher, icon, old menu
   check), remove the check from `tests/fili-shell/run.sh` (call and `want` regex), drop the module-only strings from
   `fr.json`, then `scripts/check-i18n.sh`, `tests/fili-shell/check-app-window.py --ref ~/Projects/fili-file ~/Projects/<app>`,
   `tests/fili-shell/run.sh`; commit, push `develop`, watch the CI.
9. Tick the box in section 7.

## 4. Work in this repository (once, with the first application after Baladeur)

- **`docs/bar.md`**: add the section "Shipped by an application" (the `shell/` layout, `link-system`, precedence). The code
  comments of `fili-bar` already point at it and it does not exist yet.
- **`AGENTS.md`**: rewrite the rules that still say the opposite: the Casier bullet ("Le fichier de repli du menu reste ici et
  `check-fili-file-menu.py` le garde identique"), the fili-bar bullet (a personal module goes to `users/<login>/`, an
  application's module goes in its own `shell/fili-bar/`), the "Demander à Rob" bullet (the brief of an application is
  `shell/rob/<app_id>.md` of the application; `agents/rob/<app_id>.md` stays only for programs without a repository).
- **Skills**: `agents/skills/filigrane-ui/references/hig.md` §7 and `app-window.md` mention `dotfiles/config/filigrane/appmenu/`
  as the place of the fallback menu: say "the `shell/appmenu/` of the application".
- **`tests/fili-shell/check-fili-chat-here.py`**: it demands a brief here for every fallback menu here; once the menus leave,
  nothing remains to check. Add the same check to each application's `check-shell-menu.py`: `shell/rob/<app_id>.md` exists.
- **Bot of the pins** (`scripts/bump-app-pins.sh`, `.github/workflows/bump-app-pins.yml`): it only raises `ref`. Step 8's
  removal is done by hand (or added to the bot's branch); say so in the PR body of the bot if it becomes a habit.

## 5. Per-application notes (inventory of 2026-11-19)

| Application | Module (bar) | Fallback menu | Brief | Launcher / icon here | Menu check here | Makefile |
| --- | --- | --- | --- | --- | --- | --- |
| Cassette `fili-recorder` | `recorder` (3 files) | `fili-recorder.json` 3 KB | yes | **yes** (`.desktop`, `.svg`) | `check-fili-recorder-menu.py` | **none: create** |
| Conversations `fili-im` | `messages` (3 files, panel 11 KB) | `fili-im.json` 5 KB | yes | no (in the app) | none | yes |
| Facteur `fili-mail` | `mail` (2 files) | `fili-mail.json` 4 KB | yes | no (in the app) | none | yes |
| Aéroport `fili-term` | none | `fili-term.json` 7 KB | yes | no (in the app) | none | yes |
| Casier `fili-file` | none | `fili-file.json` 6 KB | yes | no (in the app) | `check-fili-file-menu.py` | yes |

- **Cassette**: the simplest after Baladeur, and the only other app without a Makefile. The `status` module of the bar hosts a
  recording indicator (`bar-status rec`, `bar-toggle rec`, shell scripts) that stays here: a generic indicator host that knows
  Cassette. Out of scope; a later step could let applications contribute indicators. Aliases: `cassette` (`package.env`).
  The module calls `fili-recorder toggle`, `fili-recorder folder`: nothing else to carry. Tests to follow in
  `TestShell.qml`: `expectClick("recorder", M, "fili-recorder toggle")` and `expectMenu("recorder", "fili-recorder", true)`
  (they pass once the bench loads the shipped module).
- **Conversations**: `MessagesPanel.qml` uses the `fili-im` CLI and `BarState.alerts` and imports `qs.bar.modules.alert`:
  these imports resolve from the config root, so a linked module folder works (it did for Baladeur). The Rob brief says
  `fili-im send` needs a confirmation: keep it word for word. Go connectors: nothing to do with `shell/`.
- **Facteur**: `MailModule.qml` imports `qs.bar.modules.alert`. The repository holds other sessions' work often: `git status`
  first. Its ctl actions may not be declared like Baladeur's (not checked when this plan was written): read `qml/Main.qml`
  before porting the check, and write the check against what it really declares (do not copy the regex blindly).
- **Aéroport**: shortcuts are configurable (Rust keymap), so a menu check against `Shortcut` items in QML does not apply:
  check the `ctl` actions only, or the keymap defaults. No module, no launcher to move.
- **Casier**: the largest menu and the strictest rule ("the fallback menu is identical to the application's menu",
  `check-fili-file-menu.py`, which reads the `menuActions` table of `qml/Main.qml`): port that script to
  `scripts/check-shell-menu.py` of Casier unchanged in spirit (menu file path and source path become repo-relative) and run it
  from `make check`. Rewrite the AGENTS.md bullet in the same commit as the removal here. Casier also ships a portal; leave it.
- **Not applications**: `fili-chat` (Rob, `apps/fili-chat` here), `fili-incident`, `fili-receive`, `fili-automount`,
  `bar-stats`, `budget`, `fili-appmenu`, `fili-ai-session` are part of the distribution: unchanged.

## 6. Order of work

1. **Cassette** (module + menu + brief + launcher; creates the Makefile; shows the pattern works for a second app).
2. **Conversations** (module with a panel and a CLI).
3. **Facteur** (module; check to write against its own `Main.qml`).
4. **Aéroport** (menu and brief only).
5. **Casier** (the menu check and the AGENTS.md rule; last because it changes the most documentation).

One application per session; after each, the user tests it live (`./bootstrap.sh` then `fili-bar list` shows `(app)` next to
the shipped module) before the merge that publishes. The user's machine has the `fili-apps` package, so the package route
is the real one there; `bootstrap.sh` covers a source build.

## 7. Done when

- [x] Baladeur (`v0.2.0`, removal commit `410c048`)
- [x] Cassette (`v0.2.0`)
- [x] Conversations (`0.2.0`)
- [ ] Facteur
- [ ] Aéroport
- [ ] Casier
- [ ] `docs/bar.md` has the section "Shipped by an application"; `AGENTS.md` and the skills say the same thing
- [ ] `tests/fili-shell/check-fili-chat-here.py` no longer depends on briefs kept here

Check on each application, by hand: `fili-bar list` marks its module `(app)`; its menu appears in the bar when its window has
the focus; `Ask Rob…` from its window gets its brief (read the first message of the session); its launcher and icon are
found by the launcher; uninstalling the package removes all of it (`fili-bar link-system` forgets the dangling links).
