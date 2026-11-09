"""Notification action buttons must stay inside the bubble: the row shrinks its buttons (fit factor)
and each label is elided, since a French label like "Oui, maintenant (Recommandé)" is wider than 360 px."""
import re, sys

root = sys.argv[1] if len(sys.argv) > 1 else "."
src = open(f"{root}/dotfiles/config/quickshell/FiliNotification.qml").read()
bad = []
if not re.search(r"readonly property real fit:.*avail", src):
    bad.append("the action row has no fit factor bounded by the card width")
if not re.search(r"width: naturalWidth \* btnRow\.fit", src):
    bad.append("action buttons do not use the fit factor")
if not re.search(r"id: label.*?elide: Text\.ElideRight", src, re.S):
    bad.append("the action button label is not elided")
if bad:
    print("not ok - notification buttons can overflow the bubble:")
    print("\n".join(bad))
    sys.exit(1)
print("ok - notification buttons fit the bubble")
