#!/usr/bin/env python3
"""The menu of fili-file in the fili-bar (dotfiles/config/filigrane/appmenu/fili-file.json) must stay the one of
the application: for each entry `fili-file ctl ... action NAME`, the command NAME exists in qml/Main.qml of fili-file
(menuActions table) with the same label and the same shortcut; each command with a label of the Qt menu bar is
offered in the bar. Exit code 0 if everything agrees, 1 otherwise (each difference on one line)."""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]
# Source of fili-file: the version pinned in apps/fili-file/upstream (or FILI_SRC_FILI_FILE, a local checkout)
src = Path(subprocess.run([str(root / "scripts/upstream-dir"), "fili-file"], capture_output=True, text=True, check=True).stdout.strip())
qml = (src / "qml/Main.qml").read_text(encoding="utf-8")
menu = json.loads((root / "dotfiles/config/filigrane/appmenu/fili-file.json").read_text(encoding="utf-8"))

# Action { id: aCopy; text: Fili.tr("Copy"); shortcut: "Ctrl+C"; ... }
actions = {}
for m in re.finditer(r'Action \{ id: (\w+);(?: text: Fili\.tr\("([^"]+)"\);)?(?: shortcut: "([^"]+)";)?', qml):
    actions[m.group(1)] = (m.group(2) or "", m.group(3) or "")
# "copy": aCopy
table_src = re.search(r"menuActions: \(\{(.*?)\}\)", qml, re.S)
if not table_src:
    sys.exit("not ok - table menuActions introuvable dans Main.qml")
table = dict(re.findall(r'"([a-z-]+)":\s*(\w+)', table_src.group(1)))

errors = []
seen = set()
for entries in [menu.get("app", []), menu.get("window", [])] + [top["children"] for top in menu["menus"]]:
    for e in entries:
        m = re.search(r"\bctl\b.*\baction ([a-z-]+)\b", e.get("exec", ""))
        if not m:
            continue
        name = m.group(1)
        seen.add(name)
        if name not in table:
            errors.append(f"command \"{name}\" missing from menuActions (Main.qml)")
            continue
        text, shortcut = actions.get(table[name], ("", ""))
        if e["label"] != text:
            errors.append(f"{name}: label \"{e['label']}\" in the menu, \"{text}\" in Main.qml")
        if e.get("keys", "") != shortcut:
            errors.append(f"{name}: shortcut \"{e.get('keys', '')}\" in the menu, \"{shortcut}\" in Main.qml")
for name, action in table.items():
    if action != "aQuit" and actions.get(action, ("", ""))[0] and name not in seen:
        errors.append(f"command \"{name}\" of Main.qml missing from the fili-bar menu")

if errors:
    print("not ok - menu of fili-file in the fili-bar:")
    for e in errors:
        print("#   " + e)
    sys.exit(1)
print(f"ok - menu of fili-file in the fili-bar: {len(seen)} matching commands")
