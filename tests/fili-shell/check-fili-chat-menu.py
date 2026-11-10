#!/usr/bin/env python3
"""The fili-bar menu of the chat (dotfiles/config/filigrane/appmenu/fili-chat.json) stays in agreement with FiliChat.qml:
every `fili-shell chat ACTION` command of the menu is a `case "ACTION"` of act(), and every announced shortcut has its key
in the drawer. Usage: check-fili-chat-menu.py (from anywhere)."""
import json, pathlib, re, sys

root = pathlib.Path(__file__).resolve().parents[2]
menu = json.loads((root / "dotfiles/config/filigrane/appmenu/fili-chat.json").read_text())
qml = (root / "dotfiles/config/quickshell/FiliChat.qml").read_text()
cases = set(re.findall(r'case "([a-z-]+)":', qml))
keys = {"Ctrl+Shift+N": "Qt.ShiftModifier", "Esc": "Keys.onEscapePressed", "F2": "Qt.Key_F2", "Ctrl+N": "Qt.Key_N", "Ctrl+L": "Qt.Key_L", "Ctrl+.": "Qt.Key_Period",
        "Ctrl+Return": "Qt.Key_Return", "Ctrl+Backspace": "Qt.Key_Backspace"}
errors = []

def entries(items):
    for e in items:
        if "children" in e:
            yield from entries(e["children"])
        elif not e.get("sep"):
            yield e

for e in entries(menu["app"] + [m for top in menu["menus"] for m in top["children"]]):
    m = re.fullmatch(r"fili-shell chat ([a-z-]+)", e.get("exec", ""))
    if e.get("exec", "").startswith("fili-shell chat") and not (m and m.group(1) in cases):
        errors.append(f"commande sans case dans act(): {e['exec']}")
    k = e.get("keys")
    if k and (k not in keys or keys[k] not in qml):
        errors.append(f"raccourci sans touche dans FiliChat.qml: {k}")
for a in cases:
    if not any(e.get("exec") == f"fili-shell chat {a}" for e in entries(menu["app"] + [m for top in menu["menus"] for m in top["children"]])) and a not in ("toggle", "show", "open", "answer"):
        errors.append(f"action de act() absente du menu: {a}")
if errors:
    print("not ok - menu du chat:")
    print("\n".join("#   " + e for e in errors))
    sys.exit(1)
print("ok - menu du chat d'accord avec FiliChat.qml (%d actions)" % len(cases))
