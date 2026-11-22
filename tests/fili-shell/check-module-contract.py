"""Contract between the fili-bar and its modules (docs/bar.md, "The module contract").

A module folder of the distribution is self-contained: it imports only the Qt / Quickshell modules and the shell's
public API, and it names in `uses` of its manifest every other piece of the shell it relies on. Every module has a
manifest with a title, a group and a side; a translation of a text only this module shows lives in its own i18n/.
Usage: check-module-contract.py [ROOT]"""
import glob, os, re, sys

root = sys.argv[1] if len(sys.argv) > 1 else "."
mods = f"{root}/dotfiles/config/quickshell/bar/modules"
# The public API: what a module may use without declaring it
PUBLIC = {"BarModule", "BarItem", "BarScript", "BarLabel", "BarRow", "BarHover", "BarState", "BarWatched", "BarTone",
          "FiliTheme", "FiliI18n", "FiliShell", "FiliInfo", "FiliPanel", "FiliTooltip", "Niri"}
GROUPS = {"desktop", "system", "connectivity", "sound", "time", "ai"}
controls = {os.path.basename(f)[:-4] for f in glob.glob(f"{root}/dotfiles/config/quickshell/controls/*.qml")}
IMPORT_OK = re.compile(r"^(QtQuick(\.\w+)?|Quickshell(\.\w+)*|qs|qs\.bar|qs\.controls)$")
bad = []

def toml(path):
    out = {}
    for line in open(path):
        m = re.match(r"\s*([\w-]+)\s*=\s*(.+?)\s*(#.*)?$", line)
        if m: out[m[1]] = m[2]
    return out

for d in sorted(glob.glob(f"{mods}/*/")):
    name = os.path.basename(d.rstrip("/"))
    if os.path.islink(d.rstrip("/")): continue          # shipped by an application or a plugin: its own repository checks it
    manifest = f"{d}module.toml"
    if not os.path.isfile(manifest):                     # a folder of components, not a module (alert)
        continue
    m = toml(manifest)
    for k in ("title", "group", "side"):
        if k not in m: bad.append(f"{name}: module.toml has no {k}")
    if "group" in m and m["group"].strip('"') not in GROUPS:
        bad.append(f"{name}: unknown group {m['group']} (one of {', '.join(sorted(GROUPS))})")
    uses = set(re.findall(r'"([^"]+)"', m.get("uses", "")))
    local = {os.path.basename(f)[:-4] for f in glob.glob(f"{d}*.qml")}
    seen = set()
    for f in sorted(glob.glob(f"{d}*.qml")):
        src = open(f).read()
        for imp in re.findall(r"^import\s+(\S+)", src, re.M):
            if not IMPORT_OK.match(imp): bad.append(f"{name}: {os.path.basename(f)} imports {imp}")
        # Identifiers of the code: no comments, no string contents
        code = re.sub(r"//[^\n]*", "", src)
        code = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', code)
        seen |= set(re.findall(r"\b(Fili[A-Z]\w*|Bar[A-Z]\w*|Niri|Settings[A-Z]\w*)\b", code))
    for ident in sorted(seen - PUBLIC - local - controls):
        if ident not in uses: bad.append(f"{name}: uses {ident}, which is not in the public API: add it to `uses` of module.toml")
    for ident in sorted(uses - seen):
        bad.append(f"{name}: `uses` lists {ident}, which the module no longer uses")

for b in bad: print(b)
print("module contract:", "FAILED" if bad else "OK")
sys.exit(1 if bad else 0)
