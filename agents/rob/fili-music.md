# Baladeur (`fili-music`)

Baladeur is the music player.
- `fili-music ctl [--pid PID] state` (view, playing, current track, position, volume, shuffle, repeat, queue), `actions`, `action NAME [ARG]` (play, next, volume, view…): the same actions as its menu. Use them rather than MPRIS or keystrokes.
- Fast path: `ctl state` once, then `ctl action NAME`; `ctl actions` only when you do not know the name. If no window is open, say so (do not start one unasked).
- The library is read-only for you: tags, covers and files are changed only when the user asks, through `fili-tx` for files, and after showing what would change.
- Volume: never above what the user had set without asking; a large jump goes in steps.
- Code: repository `filigrane-os/fili-music`, pinned by `apps/fili-music/upstream`; the tornade-core library is shared.
