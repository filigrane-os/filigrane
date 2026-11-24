#!/usr/bin/env python3
"""Check that fili-* application windows follow the common anatomy (agents/skills/filigrane-ui/references/app-window.md).

    check-app-window.py APP_SRC [APP_SRC...]

Every APP_SRC takes its shared controls (theme, scroll, window glyph, window and debug panels, Lia button, buttons) from the
fili-ui kit: it has no local copy of them (the kit is the only copy) and uses the kit's components where the anatomy needs
them. Sizes, header, window buttons, footer, sidebar, tabs and bar menu are checked here. Prints TAP-like lines, exits 1 on the
first failing application (all its problems are listed).
"""
import re
import sys
from pathlib import Path

# Sizes of app-window.md: header and sidebar from Casier, footer from Facteur
SIZES = {"toolbar_height": 44, "sidebar_width": 200, "side_row_height": 28, "row_height": 24, "status_height": 28, "border_width": 1}
# Tabs (Facteur): only for applications that have a tab row
TABS = {"tab_bar_height": 40, "tab_height": 28}
# Files an application used to carry its own copy of: they live in the kit now (a local copy would drift)
KIT_ONLY = ["FiliTheme.qml", "FiliScrollBar.qml", "KineticScroll.qml", "WindowGlyph.qml", "WindowPanel.qml", "DebugPanel.qml",
            "LiaButton.qml", "RobButton.qml", "IconButton.qml", "TextButton.qml", "FocusRing.qml", "Icon.qml"]
# Applications that have the Debug panel and the incident pipeline (app-window.md, "Debug panel and incidents"), with the
# chord that opens the panel. An application joins this list when it gets the panel; it can never leave it.
DEBUG_PANEL = {"fili-music": "Ctrl+Shift+L", "fili-recorder": "Ctrl+Shift+L", "fili-im": "Ctrl+Shift+L",
               "fili-term": "Ctrl+Shift+L"}
# Applications that have the "Ask Lia" header button (app-window.md, "Ask Lia button"), with the first version that has
# it: a pinned older version (apps/<name>/upstream) is not held to it, and the check starts by itself when the pin reaches
# that version. An application joins this list when it gets the button; it can never leave it.
ROB_BUTTON = {"fili-file": (1, 14, 0), "fili-recorder": (0, 1, 0), "fili-music": (0, 1, 1), "fili-im": (0, 1, 5),
              "fili-mail": (1, 5, 0), "fili-term": (3, 2, 0)}
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


def uses_kit(src):
    """The application takes its shared controls from the fili-ui crate (Cargo.toml): it has no copies of them."""
    cargo = src / "Cargo.toml"
    return cargo.is_file() and re.search(r"^fili-ui\s*=", cargo.read_text(), re.M) is not None


def check(src, name):
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
    if not uses_kit(src):
        problems.append("Cargo.toml: no fili-ui dependency (the shared controls come from the kit)")
    for f in KIT_ONLY:
        if (qml / f).is_file():
            problems.append(f"qml/{f}: local copy of a kit component (use the kit's)")
    main = (qml / "Main.qml").read_text() if (qml / "Main.qml").is_file() else ""
    every = "\n".join(p.read_text() for p in sorted(qml.glob("*.qml")))
    if "FiliTheme.toolbarHeight" not in main:
        problems.append("Main.qml: header height is not FiliTheme.toolbarHeight")
    for wid in ("closeButton", "windowButton"):
        if f"id: {wid}" not in main:
            problems.append(f"Main.qml: no {wid} in the header")
    if "FiliWindowPanel" not in main:
        problems.append("Main.qml: no FiliWindowPanel (fili-ui)")
    if re.search(r"^\s*(ScrollBar|ScrollView)\s*\{", every, re.M) or "ScrollBar.vertical:" in every:
        problems.append("Qt ScrollBar/ScrollView used: use KineticScroll + FiliScrollBar")
    for f in sorted(qml.glob("*.qml")):
        for line, kind in bare_views(f.read_text()):
            problems.append(f"qml/{f.name}:{line}: {kind} without KineticScroll + FiliScrollBar")
    mlines = main.splitlines()
    foot = [i for i, l in enumerate(mlines) if re.search(r"height: FiliTheme\.statusHeight\b", l)]
    if foot:
        # An overlay bar (border.width right below its colour) may stay on `surface`; every other status bar is recessed
        def recessed(i):
            win = "\n".join(mlines[i:i + 5])
            return "FiliTheme.backgroundDeep" in win or "border.width" in win
        for i in foot:
            if not recessed(i):
                problems.append(f"Main.qml:{i + 1}: the footer is not on backgroundDeep")
    side = qml / "Sidebar.qml"
    if side.is_file() and "▸" not in side.read_text():
        problems.append("qml/Sidebar.qml: section headers cannot be folded (▾/▸ arrow)")
    if side.is_file() and not re.search(r"^\s*color: FiliTheme\.backgroundDeep", side.read_text(), re.M):
        problems.append("qml/Sidebar.qml: the sidebar is not on backgroundDeep")
    if re.search(r"property (var|int) tabs\b|win\.tabs\b", every):
        values = theme_values(theme) if theme.is_file() else {}
        for key, want in TABS.items():
            if values.get(key) != want:
                problems.append(f"theme.toml: {key} = {values.get(key)}, expected {want} (tab row)")
    # The fallback menu of the bar: the one the application ships (shell/appmenu/), else the one of this repository
    menu = src / "shell/appmenu" / f"{name}.json"
    if not menu.is_file():
        menu = ROOT / "dotfiles/config/filigrane/appmenu" / f"{name}.json"
    if not menu.is_file():
        problems.append(f"no bar menu fallback (shell/appmenu/{name}.json of the application, or dotfiles/config/filigrane/appmenu/)")
    elif "action about" not in menu.read_text():
        problems.append(f"{menu.name}: no About entry")
    if name in DEBUG_PANEL:
        problems += check_debug(src, name, menu)
    if name in ROB_BUTTON and version_of(src) >= ROB_BUTTON[name]:
        problems += check_rob(src)
    return problems


def version_of(src):
    """Version of Cargo.toml as a tuple, (0,) when there is none (a source without it is held to every check)."""
    cargo = src / "Cargo.toml"
    m = re.search(r'^version\s*=\s*"(\d+)\.(\d+)\.(\d+)', cargo.read_text(), re.M) if cargo.is_file() else None
    return tuple(int(x) for x in m.groups()) if m else (999,)


def check_rob(src):
    """The "Ask Lia" header button: the kit's FiliLiaButton in Main.qml and the `askLia` invokable."""
    problems = []
    main = (src / "qml" / "Main.qml").read_text() if (src / "qml" / "Main.qml").is_file() else ""
    rust = "\n".join(p.read_text() for p in sorted((src / "src").rglob("*.rs"))) if (src / "src").is_dir() else ""
    if not re.search(r"^\s*FiliLiaButton\s*\{", main, re.M):
        problems.append("Main.qml: no FiliLiaButton (fili-ui)")
    if not re.search(r"\bfn ask_lia\b", rust):
        problems.append("no `askLia` invokable for the Ask Lia button")
    return problems


def check_debug(src, name, menu):
    """The log, the Debug panel and its menu entry (app-window.md, "Debug panel and incidents")."""
    problems = []
    rust = "\n".join(p.read_text() for p in sorted((src / "src").rglob("*.rs"))) if (src / "src").is_dir() else ""
    if not (src / "src" / "logs.rs").is_file():
        problems.append("src/logs.rs missing (log, panics, incidents)")
    if not re.search(r"\blogs::init\(", rust):
        problems.append("logs::init is never called")
    if not re.search(r"\blogs::capture_qt\(", rust):
        problems.append("logs::capture_qt is never called (QML errors not logged)")
    for inv in ("logs", "logFile", "clearLogs", "reportProblem"):
        if not re.search(rf"\bfn {re.sub(r'([A-Z])', lambda m: '_' + m.group(1).lower(), inv)}\b", rust):
            problems.append(f"no `{inv}` invokable for the Debug panel")
    main = (src / "qml" / "Main.qml").read_text() if (src / "qml" / "Main.qml").is_file() else ""
    keys = DEBUG_PANEL[name]
    if not re.search(r"^\s*FiliDebugPanel\s*\{", main, re.M):
        problems.append("Main.qml: no FiliDebugPanel (fili-ui)")
    # The chord is in Main.qml, or in the Rust keymap of an application whose shortcuts are configurable (Aéroport)
    if f'"{keys}"' not in main and f'"{keys}"' not in rust:
        problems.append(f"no {keys} shortcut for the Debug panel (Main.qml, or the keymap)")
    if menu.is_file():
        entries = re.findall(r'\{[^{}]*"label":\s*"Debug Logs"[^{}]*\}', menu.read_text())
        if not entries:
            problems.append(f"{menu.name}: no Debug Logs entry")
        elif not any(f'"keys": "{keys}"' in e for e in entries):
            problems.append(f"{menu.name}: Debug Logs is not on {keys}")
    return problems


def main(argv):
    if not argv:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    rest = argv
    failed = False
    for arg in rest:
        src = Path(arg).expanduser().resolve()
        # A cached pinned clone is named <app>-<tag>: the app name is the package name of Cargo.toml
        cargo = src / "Cargo.toml"
        m = re.search(r'^name\s*=\s*"([^"]+)"', cargo.read_text(), re.M) if cargo.is_file() else None
        label = m.group(1) if m else src.name
        problems = check(src, label)
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
