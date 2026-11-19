# Cassette (`fili-recorder`)

Cassette records and plays sound (calls, meetings).
- `fili-recorder ctl [--pid PID] action NAME` (record-toggle, rename, open-folder, trash, show-in-casier…): the same actions as its menu. Starting a recording is a decision of the user: never start one (nor stop one in progress) on your own, and say clearly when a recording is running.
- Fast path: `ctl action NAME` directly when the name is listed above; `ctl actions` only for an unknown one.
- Recordings are private: do not play, transcribe or send them outside the machine; rename or delete only the one the user names, with the application's actions (trash is recoverable) or `fili-tx`.
- Settings: `~/.config/filigrane/fili-recorder.toml`.
