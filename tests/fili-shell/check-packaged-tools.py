"""Programs installed by a package (/usr/bin) must be found through PATH (FiliTheme.tool), never at
FiliTheme.bin (~/.local/bin), where they do not exist: the calls failed and blocked the fili-shell pipe."""
import re, sys

root = sys.argv[1] if len(sys.argv) > 1 else "."
qml = f"{root}/dotfiles/config/quickshell"
packaged = ("fili-appmenu", "fili-ai-session")
bad = []
import glob
for path in glob.glob(f"{qml}/**/*.qml", recursive=True):
    src = open(path).read()
    for name in packaged:
        if re.search(r'FiliTheme\.bin\s*\+\s*"/' + name, src):
            bad.append(f"{path.removeprefix(qml + '/')}: {name} is looked up in ~/.local/bin")
if "function tool(name)" not in open(f"{qml}/FiliTheme.qml").read():
    bad.append("FiliTheme.qml: tool() is missing")
if bad:
    print("not ok - packaged tools: " + "; ".join(bad))
    sys.exit(1)
print("ok - packaged tools are found through PATH, not ~/.local/bin")
