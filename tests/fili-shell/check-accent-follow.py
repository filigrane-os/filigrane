"""The fili-bar has no accent colour: the items of the bar (the *Module.qml files) take the normal text colours, and show a
state by a word or a glyph (MUTE, a timer, an icon that appears). Only information colours appear, and only when something
deserves it: the warning yellow (sable / barWarn) and the red (cendre), for a low battery, a hot CPU, a full disk. The accent of
the user (Settings > Appearance) belongs to the selections of the windows and the panels, not to the strip of the bar. The one
exception is the marker of the active workspace."""
import pathlib, re, sys

qml = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".") / "dotfiles/config/quickshell"
# file -> how many times the warning colour may be used there (low battery; hot CPU and full disk; a gauge near its limit; the
# do-not-disturb mark of the notification centre)
warn_allowed = {"bar/modules/power/PowerModule.qml": 1, "bar/modules/resources/ResourcesModule.qml": 2, "bar/FiliTooltip.qml": 1, "FiliNotification.qml": 1}
accent_allowed = {"bar/modules/workspaces/WorkspacesModule.qml"}
bad = []
for path in list((qml / "bar").rglob("*.qml")) + [qml / "FiliNotification.qml"]:
    rel = str(path.relative_to(qml))
    text = path.read_text()
    n = len(re.findall(r"FiliTheme\.(?:sable|barWarn)\b", text))
    if n > warn_allowed.get(rel, 0):
        bad.append(f"{rel}: {n} use(s) of the warning colour, {warn_allowed.get(rel, 0)} allowed")
    if rel.endswith("Module.qml") and rel not in accent_allowed and re.search(r"FiliTheme\.(?:barAccent|voile)\b", text):
        bad.append(f"{rel}: the bar has no accent colour (use barText / barText2)")
if bad:
    print("not ok - bar colours: " + "; ".join(bad))
    sys.exit(1)
print("ok - bar colours: no accent in the items of the bar, warning colours only where something is wrong")
