# Application window anatomy

Every `fili-*` application with a window (Casier/fili-file, Facteur/fili-mail, the next ones) is built from the same parts, with the same sizes and the same behaviour, so that moving from one to the other changes the content, never the frame. Reference application: **Casier** (`fili-file/qml/Main.qml`), except the footer, whose reference is **Facteur** (`fili-mail`). All rules here are **[Filigrane]**.

An application uses only the parts it needs (no empty header, sidebar or footer by principle), but a part it has follows this page. Sizes are tokens in the application's `theme.toml` (section `[theme]`, overridable in `<app>.toml` like any theme key, read by its `FiliTheme.qml`), never literals in the QML.

```
┌─────────────────────────────────────────────────────────────────────┐
│ (‹ ›)  Title                      tools   [Search      ]   ▣  ✕   │ header 44
├──────────────┬──────────────────────────────────────────────────────┤ 1 px line
│ Sidebar      │ Content (list, reader…)                            ┃ │
│ 200          │ rows 24                                    scrollbar┃ │
│ rows 28      │                                                      │
├──────────────┴──────────────────────────────────────────────────────┤ 1 px line
│ footer 36: status left, actions or progress right                  │
└─────────────────────────────────────────────────────────────────────┘
```

## Sizes

| Part | Token (`theme.toml` / `FiliTheme`) | Value | Reference |
|---|---|---:|---|
| Header (toolbar) | `toolbar_height` / `toolbarHeight` | 44 | Casier |
| Sidebar width | `sidebar_width` / `sidebarWidth` | 200 | Casier |
| Sidebar row | `side_row_height` / `sideRowHeight` | 28 | Casier |
| List row | `row_height` / `rowHeight` | 24 | Casier |
| Footer (status bar) | `status_height` / `statusHeight` | 36 | Facteur (`statusHeight + space2`) |
| Separators (header, sidebar, footer) | `border_width` / `borderWidth` | 1 | Casier |
| Window margin (left of the header, sides) | `margin` | 24 | Casier |

Other values of the header, taken from Casier: back/forward capsule 30 high, radius 8, `surface` with a 1 px `border`; icon buttons 28 × 24, glyph 16; search field 180 × 26, radius `radiusControl`, `Search` placeholder in `muted`, accent border on focus; `space3` between the groups of tools; title in `size` + `weightAccent`, elided, with an optional second line in `sizeList` + `textSecondary`.

## Header

- Background `background`, 1 px `border` line below. Left to right: back/forward capsule (when the application has a history), title, tools of the view, search, then the window buttons.
- **Window buttons at the far right of the header**: close (`WindowGlyph` `close`, red `danger` on hover, white glyph) at `(toolbarHeight - 24) / 2` from the right edge, the window button (`WindowGlyph` `window`, opens `WindowPanel`: niri actions, or fullscreen/maximize/minimize outside niri) `space1` to its left. Names for accessibility: "Close window", "Window".
- They can be hidden: setting `window_buttons = false` in `<app>.toml` and the checkable entry "Show Window Buttons" of the bar menu; the search field then takes `margin` from the edge. "Window Actions…" (Ctrl+Shift+W) and "Close" (Ctrl+W) stay in the menu either way.
- No title bar, no menu bar drawn in the window: the window title lives in the fili-bar.

## Sidebar

- Width `sidebarWidth`, background `background`, 1 px `border` line on its right, rows `sideRowHeight`, section headers foldable with an arrow. Top padding `space3`.
- An action tied to the sidebar (add an account, connect a server) sits at its bottom, in the footer band (same height as the footer).

## Footer

- Height `statusHeight` (36), full width, 1 px `border` line above, background `background`. Left: what the view shows (count, path, selection); right: progress or a short action. Text `sizeSmall`/`sizeList`.
- An error, a notice or an operation in progress takes the whole footer for its duration (Casier); an inline confirmation ("Delete the label…?") uses the same band, with the action as the default button on the right and Cancel to its left.

## Scrolling

- Every scrollable view uses the same pair: `KineticScroll {}` inside the `Flickable`/`ListView` (wheel, touchpad, inertia) and `FiliScrollBar` on its edge. No `ScrollBar` from Qt Quick Controls, no `ScrollView` default bars, no other behaviour.
- `FiliScrollBar.qml`, `KineticScroll.qml`, `WindowGlyph.qml` and `WindowPanel.qml` are the same file in every application (only the line `import Fili.<Module>` and the singleton name differ). Change them in Casier first, then copy.

## Menu, About, settings, theme, assistant

- Shared menu with the fili-bar (`hig.md` §7): every command and its shortcut, through a fallback `dotfiles/config/filigrane/appmenu/<app_id>.json` that calls `<app> ctl --pid %pid action NAME`; nothing important only in a button or a context menu.
- First entry "About <Name>" (About card), "Settings…" when `<app>.toml` exists, a "Window" menu with "Show Window Buttons", "Window Actions…".
- Theme and options in `~/.config/filigrane/<app>.toml` above `theme.toml` and the defaults of the repository (`hig.md` §7); state of use in `~/.local/state/filigrane/`.
- Context for the assistant (`assistant.md`).

## Check

`tests/fili-shell/check-app-window.py SRC_DIR [SRC_DIR…]` checks an application source tree against this page: sizes in `theme.toml`, shared QML files identical to Casier's, `toolbarHeight`/`statusHeight`/`sidebarWidth` used instead of literals, window buttons present, `KineticScroll` + `FiliScrollBar` and no Qt `ScrollBar`, fallback menu with About.
