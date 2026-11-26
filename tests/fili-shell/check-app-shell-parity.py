#!/usr/bin/env python3
"""A Filigrane application follows the fili-shell: the defaults of its theme.toml are the tokens of FiliTheme.qml (colours per mode,
fonts, sizes, radii, spacing, accent tones), and its qml/KineticScroll.qml is the shell's file. These checks live here, not in the
application: the shell is the reference, and the applications (Casier, Cassette, Baladeur) keep only tests about themselves.
An application that takes its shared controls from the fili-ui kit has no qml/KineticScroll.qml of its own: with `--kit KIT_DIR` the
kit's file is the one compared with the shell's. The kit itself can be checked (APP_SOURCE_DIR = the kit): its demo/theme.toml
carries the defaults.
Usage: check-app-shell-parity.py APP_SOURCE_DIR [NAME] [--kit KIT_DIR]   (exit 0 if everything agrees, 1 otherwise; each difference on one line)."""
import pathlib, re, sys

root = pathlib.Path(__file__).resolve().parents[2]
shell = root / "dotfiles/config/quickshell"
if len(sys.argv) < 2:
    sys.exit(__doc__)
args = sys.argv[1:]
kit = None
if "--kit" in args:
    i = args.index("--kit")
    kit = pathlib.Path(args[i + 1])
    del args[i:i + 2]
app = pathlib.Path(args[0])
name = args[1] if len(args) > 1 else app.name
# The kit itself: no theme.toml at its root, its defaults are the demo's
is_kit = (app / "qml/Fili/UI").is_dir()

# (shell token, theme.toml key): colours per mode ("ov(key, light, dark)"), the rest shared by both modes
COLORS = [
    ("nuit", "background"), ("nuitProfond", "background_deep"), ("nuit2", "surface"), ("nuit3", "surface_hover"),
    ("nuit4", "surface_active"), ("ardoise", "muted"), ("brume2", "text_secondary"), ("brume", "text"),
    ("sable", "warning"), ("cendre", "danger"), ("sauge", "success"), ("border", "border"),
]
PLAIN = [
    ("font", "font"), ("mono", "mono"), ("size", "size"), ("sizeList", "size_list"), ("sizeSmall", "size_small"),
    ("sizeLabel", "size_label"), ("sizeTitle", "size_title"), ("weightAccent", "weight_accent"),
    ("radiusMark", "radius_mark"), ("radiusControl", "radius_control"), ("radiusWindow", "radius_window"),
    ("space1", "space_1"), ("space2", "space_2"), ("space3", "space_3"), ("space4", "space_4"), ("space5", "space_5"),
    ("space6", "space_6"), ("borderWidth", "border_width"),
]
errors = []


def at(rel):
    """The file of the application: at its root, or in the crate of a workspace (fili-ai: crates/fili-ai-window/)"""
    for c in [app / rel] + sorted(app.glob(f"crates/*/{rel}")):
        if c.is_file():
            return c
    return app / rel


def tokens(qml):
    """'readonly property <type> <name>: <value>' -> {name: value}"""
    out = {}
    for line in qml.splitlines():
        line = line.strip()
        if not line.startswith("readonly property "):
            continue
        decl, sep, value = line[len("readonly property "):].partition(":")
        if sep and decl.split():
            out[decl.split()[-1]] = value.strip()
    return out


def defaults(toml):
    """'[section] key = "value" # comment' -> {(section, key): value}"""
    out, section = {}, ""
    for line in toml.splitlines():
        line = line.split(" #")[0].strip()
        m = re.fullmatch(r"\[(.*)\]", line)
        if m:
            section = m.group(1)
        elif "=" in line:
            k, v = line.split("=", 1)
            out[(section, k.strip())] = v.strip().strip('"')
    return out


tok = tokens((shell / "FiliTheme.qml").read_text())
toml = (app / "demo/theme.toml" if is_kit else at("theme.toml")).read_text()
d = defaults(toml)
common = 0
for token, key in COLORS:
    v = tok.get(token)
    if v is None or not v.startswith(f'ov("{key}", '):
        errors.append(f'{token}: expected ov("{key}", ...) in the shell, found {v!r}')
        continue
    hexes = [h for h in v.split('"')[1::2] if h.startswith("#")]
    light, dark = (hexes[0], hexes[1]) if len(hexes) == 2 else (hexes[0], hexes[0])
    for mode, want in (("light", light), ("dark", dark)):
        got = d.get((f"theme.{mode}", key))
        if got != want:
            errors.append(f"{token} {mode}: theme.toml has {got!r}, the shell {want!r}")
    common += 1
for token, key in PLAIN:
    v = tok.get(token)
    if v is None or not v.startswith(f'ov("{key}", '):
        errors.append(f'{token}: expected ov("{key}", ...) in the shell, found {v!r}')
        continue
    v = v.split(", ", 1)[1].rstrip().removesuffix(")")
    want = "600" if v == "Font.DemiBold" else v.strip('"')
    got = d.get(("theme", key))
    if got != want:
        errors.append(f"token {token}: theme.toml has {got!r}, the shell {want!r}")
    common += 1
# Accent tones: each one of theme.toml appears as it is in the shell
tones = tok.get("accentTones", "")
n = 0
lines = toml.splitlines()
if "[theme.accents]" in lines:
    for line in lines[lines.index("[theme.accents]") + 1:]:
        if "=" not in line:
            continue
        tone, lst = (x.strip() for x in line.split("=", 1))
        if f"{tone}: {lst}" not in tones:
            errors.append(f"accent {tone}: not as in the shell")
        n += 1
if n < 7:
    errors.append(f"only {n} accent tones in theme.toml")
if common < 25:
    errors.append(f"only {common} shared tokens")
# The scroll file is the shell's, byte for byte
own = app / "qml/Fili/UI/KineticScroll.qml" if is_kit else at("qml/KineticScroll.qml")
if not own.is_file() and kit is not None:
    own = kit / "qml/Fili/UI/KineticScroll.qml"
if not own.is_file():
    errors.append("no KineticScroll.qml: neither in the application nor (--kit) in the fili-ui kit")
elif own.read_text() != (shell / "KineticScroll.qml").read_text():
    errors.append(f"{'the kit' if own.is_relative_to(kit or app / 'x') and kit else 'qml'}/KineticScroll.qml differs from the shell's")

if errors:
    print(f"not ok - {name} no longer matches the shell:")
    print("\n".join("#   " + e for e in errors))
    sys.exit(1)
print(f"ok - {name} follows the shell (theme defaults, kinetic scroll)")
