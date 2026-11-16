# Baladeur (fili-music)

The music player of Filigrane: a Qt Quick window on [tornade-core](https://github.com/tornade-player/tornade-core) (MIT), a
port of the TornadeUI-macOS interface. The core runs inside the app (a cxx-qt plugin): no daemon.

- Library: tracks, albums, artists, genres, playlists, search; scanner with progress.
- Player: queue (drag to reorder, drag albums and tracks onto it), shuffle, repeat, volume dial, seek.
- Tag editor for a track, an album or several tracks (MusicBrainz lookup, artwork, write to the files).
- MPRIS on the session bus (`org.mpris.MediaPlayer2.fili_music`): media keys, `playerctl`.
- Menu in the fili-bar (`dotfiles/config/filigrane/appmenu/fili-music.json`) driven by `fili-music ctl --pid PID action NAME [ARG]`.

Library database: `~/.config/tornade/library.db` (shared with other Tornade frontends).

## Build

```
QMAKE=/usr/lib/qt6/bin/qmake6 cargo build --release
```

`tornade-core` comes from the `expose-ffi-rust-api` branch (its FFI entry points made `pub`); move the dependency to `main`
once merged.

## Weight

Measured on the release binary, isolated session, 17 tracks, window open.

| Version | Binary | RAM (resident) | CPU idle | CPU playing |
|---------|--------|----------------|----------|-------------|
| 0.1.0 (unreleased) | 12 MB | 162 MB (118 MB shared Qt libraries) | 0 % | 3.2 % of one core |

## Not done yet

Rating editor (the core has no FFI call to set a rating), ambient album colours, similar artists, file import by drop,
preferences, M3U import, bar mini-player.
