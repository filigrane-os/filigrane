#!/usr/bin/env python3
"""Generates the emoji list of the menu (one per line: "😀 grinning face (face-smiling)")
from the Unicode emoji-test.txt. Usage: gen-emoji.py OUTPUT"""
import re, sys, urllib.request

URL = "https://unicode.org/Public/emoji/latest/emoji-test.txt"
out = sys.argv[1] if len(sys.argv) > 1 else "emoji.txt"
subgroup = ""
lines = []
for raw in urllib.request.urlopen(URL).read().decode().splitlines():
    m = re.match(r"# subgroup: (.+)", raw)
    if m:
        subgroup = m.group(1)
        continue
    m = re.match(r"^[0-9A-F ]+;\s*fully-qualified\s*#\s*(\S+)\s+E[\d.]+\s+(.+)$", raw)
    if m:
        if "skin tone" not in m.group(2):  # variantes de teinte: omises (liste lisible)
            lines.append(f"{m.group(1)} {m.group(2)} ({subgroup})")
open(out, "w").write("\n".join(lines) + "\n")
print(f"{len(lines)} émojis -> {out}")
