#!/usr/bin/env python3
""""Ask Lia" of every application (`fili-ai here`): the entry is in the default application menu, the key is bound in niri, and
the assistant package (repository fili-ai) handles the `here` verb and the scope of the session.
Usage: check-fili-ai-here.py FILI_AI_SOURCE"""
import json, pathlib, re, sys

root = pathlib.Path(__file__).resolve().parents[2]
src = pathlib.Path(sys.argv[1])
errors = []
default = json.loads((root / "dotfiles/config/filigrane/appmenu/_default.json").read_text())
if not any(e.get("exec") == "fili-ai here" for e in default["app"]):
    errors.append("_default.json: no 'fili-ai here' entry in the app menu")
niri = (root / "dotfiles/config/niri/config.kdl").read_text()
if not re.search(r'^\s*Mod\+Ctrl\+Y\b.*spawn-sh "fili-ai here"', niri, re.M):
    errors.append("niri: Mod+Ctrl+Y does not run 'fili-ai here'")
qml = (src / "crates/fili-ai-window/qml/Chat.qml").read_text()
for needle in ('case "here":', 'op: "scope"', "function hereNow()", "function askHere(", "fieldRequested()", "property bool awaiting"):
    if needle not in qml:
        errors.append(f"Chat.qml: missing {needle}")
rs = (src / "crates/fili-ai-daemon/src/main.rs").read_text()
for needle in ('Some("here")', '"scope" =>', "fn scope_line"):
    if needle not in rs:
        errors.append(f"fili-ai daemon: missing {needle}")
fr = json.loads((src / "crates/fili-ai-window/i18n/fr.json").read_text())
for k in ("Lia, about %1", "Ask anything about this application…"):
    if k not in fr:
        errors.append(f"i18n/fr.json of fili-ai: {k!r} is not translated")
# The generic brief ships with the package; the brief of each application is shipped by the application (shell/lia/<app_id>.md or
# the older shell/rob/<app_id>.md, checked by its own scripts/check-shell-menu.py)
if not (src / "data/prompts/lia/_default.md").exists():
    errors.append("data/prompts/lia/_default.md is missing in fili-ai")
if errors:
    print("\n".join(errors))
    sys.exit(1)
print("fili-ai here: ok")
