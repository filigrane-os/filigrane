#!/usr/bin/env python3
""""Ask Rob" of every application (`fili-chat here`): the entry is in the default application menu, the key is bound in niri,
the CLI command exists, and the drawer handles the `here` action and the scope of the session.
Usage: check-fili-chat-here.py (from anywhere)."""
import json, pathlib, re, sys

root = pathlib.Path(__file__).resolve().parents[2]
errors = []
default = json.loads((root / "dotfiles/config/filigrane/appmenu/_default.json").read_text())
if not any(e.get("exec") == "fili-chat here" for e in default["app"]):
    errors.append("_default.json: no 'fili-chat here' entry in the app menu")
niri = (root / "dotfiles/config/niri/config.kdl").read_text()
if not re.search(r'^\s*Mod\+Ctrl\+Y\b.*spawn-sh "fili-chat here"', niri, re.M):
    errors.append("niri: Mod+Ctrl+Y does not run 'fili-chat here'")
qml = (root / "dotfiles/config/quickshell/FiliChat.qml").read_text()
for needle in ('case "here":', 'op: "scope"', "function hereNow()"):
    if needle not in qml:
        errors.append(f"FiliChat.qml: missing {needle}")
rs = (root / "apps/fili-chat/src/main.rs").read_text()
for needle in ('Some("here")', '"scope" =>', "fn scope_line"):
    if needle not in rs:
        errors.append(f"fili-chat main.rs: missing {needle}")
fr = json.loads((root / "dotfiles/config/quickshell/i18n/fr.json").read_text())
if "Ask Rob…" not in fr:
    errors.append("i18n/fr.json: 'Ask Rob…' is not translated")
# Every application with a fallback menu has its brief for Rob (agents/rob/<app_id>.md), and there is a generic one
if not (root / "agents/rob/_default.md").exists():
    errors.append("agents/rob/_default.md is missing")
for f in sorted((root / "dotfiles/config/filigrane/appmenu").glob("fili-*.json")):
    if f.stem != "fili-chat" and not (root / "agents/rob" / f"{f.stem}.md").exists():
        errors.append(f"agents/rob/{f.stem}.md is missing (brief of Rob for {f.stem})")
if errors:
    print("\n".join(errors))
    sys.exit(1)
print("fili-chat here: ok")
