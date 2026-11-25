"""The yellow of the shell is the colour of WARNINGS (sable / barWarn), and also the default accent: an element that shows a
state that is on (do not disturb, a timer running, caffeine, airplane mode, a normal temperature) must use the accent, or it stays
yellow whatever accent the user chose. The warning colour is allowed only where something is actually wrong."""
import pathlib, re, sys

qml = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".") / "dotfiles/config/quickshell"
# file -> what may use the warning colour there (a low battery, a gauge near its limit)
allowed = {"bar/modules/power/PowerModule.qml": 1, "bar/FiliTooltip.qml": 1}
bad = []
for path in list((qml / "bar").rglob("*.qml")) + [qml / "FiliNotification.qml"]:
    rel = str(path.relative_to(qml))
    n = len(re.findall(r"FiliTheme\.(?:sable|barWarn)\b", path.read_text()))
    if n > allowed.get(rel, 0):
        bad.append(f"{rel}: {n} use(s) of the warning colour (sable/barWarn), {allowed.get(rel, 0)} allowed: a state that is on takes the accent")
if bad:
    print("not ok - accent: " + "; ".join(bad))
    sys.exit(1)
print("ok - accent: the bar uses the warning colour only for warnings, states that are on follow the accent")
