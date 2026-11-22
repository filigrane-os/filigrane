#!/usr/bin/env python3
""""Ask Rob" of every application (`fili-ai here`): the entry is in the default application menu, the key is bound in niri,
the CLI command exists, and the drawer handles the `here` action and the scope of the session.
Usage: check-fili-ai-here.py (from anywhere)."""
import json, pathlib, re, sys

root = pathlib.Path(__file__).resolve().parents[2]
errors = []
default = json.loads((root / "dotfiles/config/filigrane/appmenu/_default.json").read_text())
if not any(e.get("exec") == "fili-ai here" for e in default["app"]):
    errors.append("_default.json: no 'fili-ai here' entry in the app menu")
niri = (root / "dotfiles/config/niri/config.kdl").read_text()
if not re.search(r'^\s*Mod\+Ctrl\+Y\b.*spawn-sh "fili-ai here"', niri, re.M):
    errors.append("niri: Mod+Ctrl+Y does not run 'fili-ai here'")
qml = (root / "dotfiles/config/quickshell/FiliAi.qml").read_text()
for needle in ('case "here":', 'op: "scope"', "function hereNow()", "function askHere(", "FiliAsk.show()", "property bool awaiting"):
    if needle not in qml:
        errors.append(f"FiliAi.qml: missing {needle}")
if "FiliAsk.open;" not in (root / "dotfiles/config/quickshell/shell.qml").read_text():
    errors.append("shell.qml: FiliAsk is not instantiated at start")
if not (root / "dotfiles/config/quickshell/FiliAsk.qml").exists():
    errors.append("FiliAsk.qml is missing")
rs = (root / "apps/fili-ai-daemon/src/main.rs").read_text()
for needle in ('Some("here")', '"scope" =>', "fn scope_line"):
    if needle not in rs:
        errors.append(f"fili-ai main.rs: missing {needle}")
fr = json.loads((root / "dotfiles/config/quickshell/i18n/fr.json").read_text())
for k in ("Rob, about %1", "Ask anything about this application…"):
    if k not in fr:
        errors.append(f"i18n/fr.json: {k!r} is not translated")
if "Ask Rob…" not in fr:
    errors.append("i18n/fr.json: 'Ask Rob…' is not translated")
# The generic brief exists; the brief of each application is shipped by the application (shell/rob/<app_id>.md, checked by its own
# scripts/check-shell-menu.py)
if not (root / "agents/rob/_default.md").exists():
    errors.append("agents/rob/_default.md is missing")
if errors:
    print("\n".join(errors))
    sys.exit(1)
print("fili-ai here: ok")
