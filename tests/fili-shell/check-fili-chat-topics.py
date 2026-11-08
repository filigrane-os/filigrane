# The topic icons of the sessions: the TOPICS list of the daemon (apps/fili-chat) and that of the font
# (scripts/fili-icons.py) must be identical and in the same order (code = 0xF2000 + position).
import re
import sys

root = sys.argv[1] if len(sys.argv) > 1 else "."
rs = open(f"{root}/apps/fili-chat/src/main.rs").read()
py = open(f"{root}/scripts/fili-icons.py").read()
a = re.findall(r'"([a-z0-9-]+)"', re.search(r"const TOPICS: \[&str; \d+\] = \[(.*?)\];", rs, re.S).group(1))
b = re.findall(r'"([a-z0-9-]+)"', re.search(r"TOPICS = \[(.*?)\]", py, re.S).group(1))
n = re.search(r"const TOPICS: \[&str; (\d+)\]", rs).group(1)
if a != b or int(n) != len(a):
    print(f"not ok - icônes de sujet: démon {len(a)} (déclaré {n}), police {len(b)}, ou ordre différent")
    sys.exit(1)
print(f"ok - icônes de sujet du démon et de la police d'accord ({len(a)})")
