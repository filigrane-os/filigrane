#!/usr/bin/env python3
"""Check that fili-* application windows follow the common anatomy (agents/skills/filigrane-ui/references/app-window.md).

    check-app-window.py --ref CASIER_SRC APP_SRC [APP_SRC...]

CASIER_SRC is the reference application (fili-file): the shared QML files of every APP_SRC must be identical to its
copies, except for the `import Fili.<Module>` line and the name of the application singleton. Prints TAP-like lines,
exits 1 on the first failing application (all its problems are listed).
"""
import re
import sys
from pathlib import Path

# Sizes of app-window.md: header and sidebar from Casier, footer from Facteur
SIZES = {"toolbar_height": 44, "sidebar_width": 200, "side_row_height": 28, "row_height": 24, "status_height": 36, "border_width": 1}
SHARED = ["FiliScrollBar.qml", "KineticScroll.qml", "WindowGlyph.qml", "WindowPanel.qml"]
ROOT = Path(__file__).resolve().parents[2]


def theme_values(path):
    """Plain `key = value` integers of theme.toml, first occurrence wins (the [theme] section comes first)."""
    out = {}
    for line in path.read_text().splitlines():
        m = re.match(r"\s*([a-z_0-9]+)\s*=\s*(-?\d+)\b", line)
        if m and m.group(1) not in out:
            out[m.group(1)] = int(m.group(2))
    return out


def bare_views(text):
    """Scrollable views (Flickable, ListView, GridView) whose own block has no KineticScroll. A view that cannot
    scroll (`interactive: false`) or a horizontal strip is not concerned; `// no-scrollbar: reason` on the line
    before the view opts it out explicitly."""
    lines = text.splitlines()
    out = []
    for i, line in enumerate(lines):
        m = re.match(r"\s*(Flickable|ListView|GridView)\s*\{", line)
        if not m or (i and "no-scrollbar:" in lines[i - 1]):
            continue
        depth, block = 0, []
        for l in lines[i:]:
            block.append(l)
            depth += l.count("{") - l.count("}")
            if depth <= 0:
                break
        body = "\n".join(block)
        if re.search(r"interactive:\s*false|ListView\.Horizontal", body) or "KineticScroll" in body:
            continue
        out.append((i + 1, m.group(1)))
    return out


def normalize(text):
    """Drops the module import and the singleton name, the only allowed differences between copies."""
    text = re.sub(r"^import Fili\.\w+\s*$", "", text, flags=re.M)
    return re.sub(r"\b[A-Z][A-Za-z]*\.(?=(tr|window[A-Za-z]*)\b)", "APP.", text)


def check(ref, src, name):
    problems = []
    theme = src / "theme.toml"
    if not theme.is_file():
        problems.append("theme.toml missing")
    else:
        values = theme_values(theme)
        for key, want in SIZES.items():
            if values.get(key) != want:
                problems.append(f"theme.toml: {key} = {values.get(key)}, expected {want}")
    qml = src / "qml"
    for f in SHARED:
        mine, theirs = qml / f, ref / "qml" / f
        if not mine.is_file():
            problems.append(f"qml/{f} missing")
        elif normalize(mine.read_text()) != normalize(theirs.read_text()):
            problems.append(f"qml/{f} differs from Casier's copy")
    main = (qml / "Main.qml").read_text() if (qml / "Main.qml").is_file() else ""
    every = "\n".join(p.read_text() for p in sorted(qml.glob("*.qml")))
    if "FiliTheme.toolbarHeight" not in main:
        problems.append("Main.qml: header height is not FiliTheme.toolbarHeight")
    for wid in ("closeButton", "windowButton"):
        if f"id: {wid}" not in main:
            problems.append(f"Main.qml: no {wid} in the header")
    if "WindowPanel" not in main:
        problems.append("Main.qml: no WindowPanel")
    if re.search(r"^\s*(ScrollBar|ScrollView)\s*\{", every, re.M) or "ScrollBar.vertical:" in every:
        problems.append("Qt ScrollBar/ScrollView used: use KineticScroll + FiliScrollBar")
    for f in sorted(qml.glob("*.qml")):
        for line, kind in bare_views(f.read_text()):
            problems.append(f"qml/{f.name}:{line}: {kind} without KineticScroll + FiliScrollBar")
    menu = ROOT / "dotfiles/config/filigrane/appmenu" / f"{name}.json"
    if not menu.is_file():
        problems.append(f"no bar menu fallback {menu.relative_to(ROOT)}")
    elif "action about" not in menu.read_text():
        problems.append(f"{menu.name}: no About entry")
    return problems


def main(argv):
    if len(argv) < 3 or argv[0] != "--ref":
        print(__doc__.strip(), file=sys.stderr)
        return 2
    ref = Path(argv[1]).expanduser().resolve()
    failed = False
    for arg in argv[2:]:
        src = Path(arg).expanduser().resolve()
        # A cached pinned clone is named <app>-<tag>: the app name is the package name of Cargo.toml
        cargo = src / "Cargo.toml"
        m = re.search(r'^name\s*=\s*"([^"]+)"', cargo.read_text(), re.M) if cargo.is_file() else None
        label = m.group(1) if m else src.name
        problems = check(ref, src, label)
        if problems:
            failed = True
            print(f"not ok - {label}: window anatomy")
            for p in problems:
                print(f"#   {p}")
        else:
            print(f"ok - {label}: window anatomy")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
