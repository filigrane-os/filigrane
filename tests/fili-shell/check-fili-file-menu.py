#!/usr/bin/env python3
"""Le menu de fili-file dans la fili-bar (dotfiles/config/filigrane/appmenu/fili-file.json) doit rester celui de
l'application: pour chaque entrée `fili-file ctl ... action NOM`, la commande NOM existe dans apps/fili-file/qml/Main.qml
(table menuActions) avec le même libellé et le même raccourci; chaque commande à libellé de la barre de menus Qt est
proposée dans la barre. Code 0 si tout concorde, 1 sinon (chaque écart sur une ligne)."""
import json
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]
qml = (root / "apps/fili-file/qml/Main.qml").read_text(encoding="utf-8")
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
for top in menu["menus"]:
    for e in top["children"]:
        m = re.search(r"\bctl\b.*\baction ([a-z-]+)\b", e.get("exec", ""))
        if not m:
            continue
        name = m.group(1)
        seen.add(name)
        if name not in table:
            errors.append(f"commande « {name} » absente de menuActions (Main.qml)")
            continue
        text, shortcut = actions.get(table[name], ("", ""))
        if e["label"] != text:
            errors.append(f"{name}: libellé « {e['label']} » dans le menu, « {text} » dans Main.qml")
        if e.get("keys", "") != shortcut:
            errors.append(f"{name}: raccourci « {e.get('keys', '')} » dans le menu, « {shortcut} » dans Main.qml")
for name, action in table.items():
    if action != "aQuit" and actions.get(action, ("", ""))[0] and name not in seen:
        errors.append(f"commande « {name} » de Main.qml absente du menu de la fili-bar")

if errors:
    print("not ok - menu de fili-file dans la fili-bar:")
    for e in errors:
        print("#   " + e)
    sys.exit(1)
print(f"ok - menu de fili-file dans la fili-bar: {len(seen)} commandes concordantes")
