---
name: filigrane-ui
description: Design, build and review Filigrane's interface (the fili-shell in Quickshell/QML: fili-bar, fili-tooltip, fili-panel, fili-launcher, notifications, fili-about; the fili-* tools; GTK/foot themes), following the Filigrane desktop HIG derived from the historical Mac OS X guidelines (2005/2008), never GNOME. Use for any UI change: a new bar module, panel, card, dialog, control, menu, list, font size, spacing, radius, colour token, focus or keyboard behaviour, error or empty state, animation, and to review a screen against the checklist. Logo, wallpaper and brand files stay in the filigrane skill (references/brand.md).
---

# Filigrane UI

The interface follows the Filigrane desktop HIG: classic desktop conventions from the historical Apple Human Interface Guidelines (Mac OS X 2005 and Leopard 2008), applied with Filigrane's own identity. The system stays out of the way; content and the user's work come first.

## Always

- Desktop first: mouse and keyboard, never a touch/mobile model. Compact controls, useful density, readable text.
- Code, comments, identifiers, commit messages and UI source strings are English (open source); translations go in the language files. New token or component names are English too.
- Apple's typography and layout values (14 px Regular body, 8 px between controls, 20 px window margins...) are in `references/tokens.md`. Reuse a token before inventing a value; an unlisted value is a "décision à valider", said as such.
- One function, one look and one behaviour everywhere: same states (normal, hover, keyboard focus, pressed, selected, disabled, loading, error), same card layout, same keys.
- Everything works from the keyboard: logical order, visible focus (`FocusRing`), Esc closes, Enter acts.
- Colour is never the only signal (state also in a word: `MUTE`, `OFF`, `ASK`, or an icon).
- Feedback is local to the action; a global notification only for what needs attention outside the current context.
- Never: GNOME/GNOME HIG patterns, big cards for every group, large rounded radii, big buttons, uniform wide margins, cards instead of a list or table, decorative animation, a second accent colour, effects other than the blur behind the menu.
- Never present a Filigrane value as an official Apple rule: tag new rules "Principe Apple historique", "Règle Filigrane" or "Décision à valider".
- Assistant: every `fili-*` application with a useful state (folder, selection, open document) exposes it to the AI and says how to act (`references/assistant.md`). Applications expose context and business capabilities; the system exposes generic and specialised execution tools; the assistant picks the simplest, most efficient and safest route, without having to go through the active application. No chat and no AI engine inside an application.
- Application window: every `fili-*` application window has the same anatomy (`references/app-window.md`): header 44 with the window buttons (window, close) at its far right, sidebar 200, footer 36, `KineticScroll` + `FiliScrollBar` on every scrollable view, its whole menu in the fili-bar. Check: `tests/fili-shell/check-app-window.py`.
- About: every `fili-*` application has an About card, first entry of its bar menu (`About <Name>`): its icon, its display name, "Also known as" `fili-…` (the program name, the *aka*), "Part of Filigrane", then the useful facts (version, what it uses or reads, state, settings file). Models: `FiliChatAbout.qml` (Rob), `fili-file/src/about.rs` (Casier); rule in `references/hig.md` §7.
- A fili-bar element is a module: a folder `bar/modules/<name>/` with `<Name>Module.qml` (a `BarModule`, `BarItem` or `BarScript`) and its panel `<Name>Panel.qml` next to it, placed by its `module.toml` manifest (`side`, `order`, `display`, `tray`, `show`; a manifest with `cmd` is a script plugin) and the optional `~/.config/filigrane/fili-bar.toml`; a personal one lives in `users/<login>/dotfiles/config/quickshell/bar/modules/` or is a plugin (`fili-bar new|install`). Guide: `docs/bar.md`. Rules in `references/hig.md` §5.
- After a change in `dotfiles/config/quickshell/`: `tests/fili-shell/run.sh`; a new QML file needs `./bootstrap.sh --fili-shell` (links are per file). Check the result on screen with niri's screenshot.

## Order of decision

1. The explicit functional request. 2. This skill and its references. 3. Existing components and tokens (`FiliTheme.qml`, `PanelSection`, `PanelButton`, `PanelSwitch`, `PanelSlider`, `PanelChips`, `FocusRing`, `BarModule`, `BarItem`, `BarScript`). 4. Historical Apple conventions. 5. When compactness and accessibility conflict, keep both; never drop a requirement silently. 6. An undecided important choice: say so and propose a decision.

## Load only what the task needs

- `references/hig.md`: the guide adapted to Filigrane (niri, fili-shell): principles, windows and panels, controls, menus, lists, forms, states and errors, notifications, motion, accessibility, and the review checklist.
- `references/app-window.md`: the anatomy shared by every `fili-*` application window (header, sidebar, footer, scrolling, window buttons, menu) and its check.
- `references/assistant.md`: the contract between `fili-*` applications and the AI assistant (context file, `about`, execution routes).
- `references/tokens.md`: values: type scale, spacing, sizes, radii, colours (dark and light), states, and where each lives in the code.
- `references/hig-source.md`: the original generic guide (v1.0), for provenance only; `hig.md` wins where they differ.
- Brand (logo, brand colours, Jost, icons, sound, wallpapers): `filigrane` skill, `references/brand.md`. Shell architecture (files, scripts, tests, pipe commands): `filigrane` skill, `references/niri.md`.
