# Everyday use

Paths are relative to `$FILIGRANE_DIR`. `<layer>` is `users/<login>/` from `.user-layer`; if it is `none` and the change is personal, create `users/<login>/` and run `./bootstrap.sh --user-layer <login>` once.

## Packages

- Search `xbps-query -Rs <word>`, details `xbps-query -R <pkg>`, files `xbps-query -f <pkg>`, who needs it `xbps-query -X <pkg>`.
- Install: resource check first (SKILL.md), `sudo xbps-install <pkg>`, then add it to a list so `bootstrap.sh` replays it: `<layer>/packages/<name>.txt` (personal) or `packages/*.txt` (distribution: `base`, `desktop`, `dev`...).
- Remove: `sudo xbps-remove <pkg>` (never `-R`/`-f` without asking) and delete it from its list. Orphans: `sudo xbps-remove -o`, cache: `sudo xbps-remove -O`.
- Not in Void (`restricted`, e.g. proprietary): `<layer>/packages/restricted.txt`, built by `bootstrap.sh` with xbps-src. Anything else downloaded: in `<layer>/layer.sh` (`layer_system`), with a pinned version and checksum.
- GUI menu: `Mod+Space` › Packages.

## Services (runit)

- State: `sudo sv status /var/service/*`. Enable: name in `services/*.txt` or `<layer>/services/*.txt`, then `./bootstrap.sh --system-only` (links `/etc/sv/<svc>` into `/var/service`). Disable: remove it from the list and `sudo rm /var/service/<svc>` (ask first).
- Logs: `/var/log/socklog/<facility>/current` (`daemon`, `kernel`, `messages`...). No journalctl, no cron daemon (`references/system.md`).

## Settings

`config.env` holds the distribution defaults; `<layer>/config.env` overrides them with the same `VAR="${VAR:-value}"` form; an environment variable beats both. Then `./bootstrap.sh`.

| Variable | Role |
|---|---|
| `KEYMAP`, `XKB_LAYOUT`, `XKB_VARIANT`, `XKB_OPTIONS` | console keymap, niri keyboard (generated `~/.config/niri/keyboard.kdl`) |
| `TIMEZONE`, `LOCALE`, `LOCALES` | time zone, system language, glibc locales generated for `fili-lang` (switch the session language live: `fili-lang set fr\|en\|system`) |
| `AUTOLOGIN` | `1`/`0`/`auto` (auto = VM only) |
| `USER_GROUPS` | groups added to the user |
| `FILI_AI`, `FILI_AI_MODEL`, `FILI_AI_WORKDIR`, `FILI_AI_ARGS` | AI agent (below) |

Desktop: niri `<layer>/dotfiles/config/niri/local.kdl` (included last), bar/notifications/menu (Quickshell), menu entries `~/.config/menu/entries`: `references/niri.md`.

## Updating

- **Void packages**: `sudo xbps-install -Su` (ask first; `watch-void` notifies when updates exist). Mac T2: `void-update` instead (snapshots), kernels per `hardware/mac-t2/README.md`. After a kernel update, mention the reboot.
- **Filigrane** (repo): if `$FILIGRANE_DIR/.git` exists: `git -C "$FILIGRANE_DIR" status` (local changes must be committed or belong in `users/`), `git -C "$FILIGRANE_DIR" pull --ff-only`, summarise `git log --oneline ORIG_HEAD..`, then `./bootstrap.sh`. No `.git` (copy installed from the ISO): offer to turn it into a clone of `DISTRO_GIT` (`distro/distro.env`), asking first since distribution files edited in place are overwritten (`users/` survives): `git init -q && git remote add origin <DISTRO_GIT> && git fetch -q origin && git checkout -f -B main origin/main`.
- **AI agent**: `fili-ai update` (Claude Code also updates itself).

## AI agent (`fili-ai`)

- `fili-ai` (`Mod+Y`, menu › AI) starts the chosen agent in its work dir (`~/work` by default, `FILI_AI_WORKDIR`), with `FILIGRANE_DIR` exported and the repo writable.
- `fili-ai use <agent>` switches and installs if needed: `claude` (Anthropic, Claude Code), `codex` (OpenAI, Codex CLI), `ollama` (local models: Codex CLI on Ollama, nothing leaves the machine), `opencode` (other providers: Mistral, Gemini, OpenRouter, DeepSeek...), `none`. The choice lives in `~/.config/filigrane/ai.env`; to make it durable put `FILI_AI` in `<layer>/config.env` (a layer value wins at the next `bootstrap.sh`).
- `fili-ai status`, `fili-ai update`, `fili-ai install <agent>`. Binaries in `~/.local/opt/<agent>-<version>`, linked in `~/.local/bin`.
- Sign in: Claude Code `/login`, Codex `codex login`, opencode `/connect` (or `opencode auth login`). Never read or copy the credential files.
- Model: `FILI_AI_MODEL` (empty = agent default). Local models need RAM: the Codex default `gpt-oss:20b` wants ~16 GB; with less, a smaller model (`FILI_AI_MODEL=qwen3:8b`, ~6 GB). Models live in `~/.ollama/models`; `ollama list`, `ollama rm <model>`. Ollama only runs while `fili-ai` does (no service).
- Safety: Claude Code and Codex get passwordless `sudo` for `sv` and `xbps-*` only (`/etc/sudoers.d/zz-agent`, written by `bootstrap.sh` from `FILI_AI`); the confirmation comes from the agent (Claude Code permissions + `~/.claude/hooks/guard-destructive.sh`, Codex sandbox + `~/.codex/rules/filigrane.rules`). opencode asks before every shell command (`~/.config/opencode/opencode.json`) and sudo keeps its password.

## Help for the user

- Keys: `Mod+K` shows them; `Mod+Space` menu (search everything), `Mod+D` apps, `Mod+Return` terminal, `Mod+Y` AI agent.
- Resource use: `budget` (system vs user work), `budget check`.
- Docs: `README.md` (desktop), `distro/README.md` (ISO, xbps repo), `hardware/<machine>/README.md`.
