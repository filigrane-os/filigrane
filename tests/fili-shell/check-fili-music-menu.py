#!/usr/bin/env python3
"""The fili-bar menu of Baladeur (dotfiles/config/filigrane/appmenu/fili-music.json) stays in agreement with the window
(apps/fili-music/qml/Main.qml): every `fili-music ctl --pid %pid action NAME` of the menu is an action of the window,
every action of the window is in the menu (the few that have none are listed below), and every announced shortcut has its
`Shortcut` in the window. Usage: check-fili-music-menu.py (from anywhere)."""
import json, pathlib, re, sys

root = pathlib.Path(__file__).resolve().parents[2]
menu = json.loads((root / "dotfiles/config/filigrane/appmenu/fili-music.json").read_text())
qml = (root / "apps/fili-music/qml/Main.qml").read_text()
actions = set(re.findall(r'^\s+"([a-z-]+)": \{ on:', qml, re.M))
shortcuts = set(re.findall(r'Shortcut \{ sequence: "([^"]+)"', qml)) | set(re.findall(r'sequence: "([^"]+)"', qml))
# Actions only the assistant or a script uses (play-track ID, open-album ID, open-artist ID), and the duplicate of "search"
without_menu = {"play-track", "open-album", "open-artist", "view-search"}
errors = []

def entries(items):
    for e in items:
        if "children" in e:
            yield from entries(e["children"])
        elif not e.get("sep"):
            yield e

everything = list(entries(menu["app"] + menu["window"] + [m for top in menu["menus"] for m in top["children"]]))
used = set()
for e in everything:
    m = re.fullmatch(r"fili-music ctl --pid %pid action ([a-z-]+)", e.get("exec", ""))
    if not m or m.group(1) not in actions:
        errors.append(f"command without an action in Main.qml: {e.get('exec')}")
    else:
        used.add(m.group(1))
    k = e.get("keys")
    if k and k not in shortcuts:
        errors.append(f"shortcut without a Shortcut in Main.qml: {k}")
for a in sorted(actions - used - without_menu):
    errors.append(f"action of Main.qml missing from the menu: {a}")
if errors:
    print("not ok - menu of Baladeur:")
    print("\n".join("#   " + e for e in errors))
    sys.exit(1)
print("ok - menu of Baladeur agrees with Main.qml (%d actions)" % len(actions))
