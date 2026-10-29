---
name: filigrane-ui
description: Design, build and review Filigrane's interface (the fili-shell in Quickshell/QML: fili-bar, fili-tooltip, fili-panel, fili-launcher, notifications, fili-about; the fili-* tools; GTK/foot themes), following the Filigrane desktop HIG derived from the historical Mac OS X guidelines (2005/2008), never GNOME. Use for any UI change: a new bar module, panel, card, dialog, control, menu, list, font size, spacing, radius, colour token, focus or keyboard behaviour, error or empty state, animation, and to review a screen against the checklist. Logo, wallpaper and brand files stay in the filigrane skill (references/brand.md).
---

# Filigrane UI

The interface follows the Filigrane desktop HIG: classic desktop conventions from the historical Apple Human Interface Guidelines (Mac OS X 2005 and Leopard 2008), applied with Filigrane's own identity. The system stays out of the way; content and the user's work come first.

## Always

- Desktop first: mouse and keyboard, never a touch/mobile model. Compact controls, useful density, readable text.
- Apple's typography and layout values (13 px Regular body, 8 px between controls, 20 px window margins...) are in `references/tokens.md`. Reuse a token before inventing a value; an unlisted value is a "décision à valider", said as such.
- One function, one look and one behaviour everywhere: same states (normal, hover, keyboard focus, pressed, selected, disabled, loading, error), same card layout, same keys.
- Everything works from the keyboard: logical order, visible focus (`FocusRing`), Esc closes, Enter acts.
- Colour is never the only signal (state also in a word: `MUTE`, `OFF`, `ASK`, or an icon).
- Feedback is local to the action; a global notification only for what needs attention outside the current context.
- Never: GNOME/GNOME HIG patterns, big cards for every group, large rounded radii, big buttons, uniform wide margins, cards instead of a list or table, decorative animation, a second accent colour, effects other than the blur behind the menu.
- Never present a Filigrane value as an official Apple rule: tag new rules "Principe Apple historique", "Règle Filigrane" or "Décision à valider".
- After a change in `dotfiles/config/quickshell/`: `tests/fili-shell/run.sh`; a new QML file needs `./bootstrap.sh` (links are per file). Check the result on screen with niri's screenshot.

## Order of decision

1. The explicit functional request. 2. This skill and its references. 3. Existing components and tokens (`FiliTheme.qml`, `PanelSection`, `PanelButton`, `PanelSwitch`, `PanelSlider`, `PanelChips`, `FocusRing`, `BarItem`, `BarScript`). 4. Historical Apple conventions. 5. When compactness and accessibility conflict, keep both; never drop a requirement silently. 6. An undecided important choice: say so and propose a decision.

## Load only what the task needs

- `references/hig.md`: the guide adapted to Filigrane (niri, fili-shell): principles, windows and panels, controls, menus, lists, forms, states and errors, notifications, motion, accessibility, and the review checklist.
- `references/tokens.md`: values: type scale, spacing, sizes, radii, colours (dark and light), states, and where each lives in the code.
- `references/hig-source.md`: the original generic guide (v1.0), for provenance only; `hig.md` wins where they differ.
- Brand (logo, brand colours, Jost, icons, sound, wallpapers): `filigrane` skill, `references/brand.md`. Shell architecture (files, scripts, tests, pipe commands): `filigrane` skill, `references/niri.md`.
