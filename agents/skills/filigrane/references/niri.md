# niri desktop

- Config: `dotfiles/config/niri/config.kdl` (linked to `~/.config/niri/`). `niri validate` before saving; niri reloads on save.
- `environment {}` sets `CHROME_FLAGS` (Void's chromium wrapper reads only that, no flags file) and `ELECTRON_OZONE_PLATFORM_HINT`. Autostart: `spawn-at-startup` lines.
- Keys (bépo right hand, arrows also work): `Mod+T/S/R/N` = left/down/up/right, `Ctrl` moves, `Shift` changes screen. `Mod+Return` foot, `Mod+Space` menu, `Mod+D` app launcher, `Mod+Y` AI agent (`fili-ai`), `Super+Alt+L` lock. `Mod+Shift+/` lists them.
- Personal additions: `users/<login>/dotfiles/config/niri/local.kdl` (included at the end of `config.kdl`).
- Menu: `~/.local/bin/menu` (fuzzel dmenu, one fuzzy list: `~/.config/menu/entries`, .desktop apps, "Category: Action" entries; `menu <section>` jumps to clip, emoji, calc...). `Shift+BackSpace` up one level, `Escape` quits. Blur behind it only: `apps/menu-backdrop`.
- Waybar: `dotfiles/config/waybar/` (`config.jsonc`, `style.css`); CPU/RAM/temperature from `apps/bar-stats`. Restart: `pkill waybar; waybar &`.
- Wallpaper: static `swaybg` via `~/.local/bin/wallpaper [image]`, images in `~/.local/share/wallpapers/`. Never animated.
- Visual changes follow `references/brand.md`.
