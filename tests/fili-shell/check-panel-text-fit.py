"""Panel text must not overflow the 340 px card: a Text showing a translated string of 18+ characters
in a panel QML file needs wrapMode or elide (a French string is often longer than the English one)."""
import glob, re, sys

root = sys.argv[1] if len(sys.argv) > 1 else "."
bad = []
files = glob.glob(f"{root}/dotfiles/config/quickshell/bar/modules/*/*Panel.qml")
for f in files:
    lines = open(f).read().split("\n")
    for i, l in enumerate(lines):
        if not re.match(r"\s*Text\s*\{", l):
            continue
        depth, blk = 0, []
        for j in range(i, len(lines)):
            blk.append(lines[j])
            depth += lines[j].count("{") - lines[j].count("}")
            if depth <= 0:
                break
        b = "\n".join(blk)
        m = re.search(r'text:\s*FiliI18n\.tr\("([^"]*)"\)\s*$', b, re.M)
        if m and len(m.group(1)) >= 18 and not re.search(r"wrapMode|elide", b):
            bad.append(f"{f.replace(root + '/', '')}:{i + 1}: {m.group(1)}")
# Shared controls: the information card and the button detail must stay inside the card (fillWidth + elide)
def need(path, pattern, why):
    if not re.search(pattern, open(f"{root}/dotfiles/config/quickshell/controls/{path}").read(), re.S):
        bad.append(f"controls/{path}: {why}")
need("PanelInfo.qml", r"RowLayout \{\s*Layout\.fillWidth: true", "the title/values row must fill the width of the card")
need("PanelInfo.qml", r"GridLayout \{[^}]*Layout\.fillWidth: true", "the values grid must fill the width of the card")
need("PanelInfo.qml", r"Layout\.fillWidth: !modelData\.key", "the value column must take the remaining width")
need("PanelButton.qml", r"btn\.detail[^}]*Layout\.maximumWidth[^}]*elide", "a long detail must be bounded and elided")
if bad:
    print("not ok - panel text can overflow (add wrapMode: Text.Wrap and Layout.fillWidth, or elide):")
    print("\n".join(bad))
    sys.exit(1)
print("ok - panel texts fit the card")
