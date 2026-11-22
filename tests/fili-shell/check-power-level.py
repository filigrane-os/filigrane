"""Battery level of the bar: now / full (current full capacity), never the kernel "capacity" alone, which is
relative to the design capacity (a worn battery would never show 100 %). "capacity" stays as the fallback."""
import re, sys

root = sys.argv[1] if len(sys.argv) > 1 else "."
path = f"{root}/dotfiles/config/quickshell/bar/modules/power/PowerModule.qml"
src = open(path).read()
bad = []
for f in ("charge_now", "charge_full", "energy_now", "energy_full", "capacity"):
    if f'"/{f}"' not in src:
        bad.append(f"PowerModule.qml: {f} is not read")
if not re.search(r"parseInt\(cap\.text\(\)\)", src):
    bad.append("PowerModule.qml: the kernel capacity must stay as the fallback")
if not re.search(r"f\s*>\s*0", src):
    bad.append("PowerModule.qml: full capacity must be checked > 0 before dividing")
if not re.search(r"Math\.min\(100,\s*Math\.round\(100\s*\*\s*n\s*/\s*f\)\)", src):
    bad.append("PowerModule.qml: the level must be round(100 * now / full), capped at 100")
if bad:
    print("not ok - battery level: " + "; ".join(bad))
    sys.exit(1)
print("ok - battery level is now / full with the kernel capacity as the fallback")
