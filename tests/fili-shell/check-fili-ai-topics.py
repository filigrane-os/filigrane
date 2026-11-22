# The topic icons of the sessions: the TOPICS list of the daemon (fili-ai repository) and that of the font
# (scripts/fili-icons.py) must be identical and in the same order (code = 0xF2000 + position).
# Usage: check-fili-ai-topics.py FILI_AI_SOURCE [ROOT]
import re
import sys

src = sys.argv[1]
root = sys.argv[2] if len(sys.argv) > 2 else "."
rs = open(f"{src}/crates/fili-ai-daemon/src/main.rs").read()
py = open(f"{root}/scripts/fili-icons.py").read()
a = re.findall(r'"([a-z0-9-]+)"', re.search(r"const TOPICS: \[&str; \d+\] = \[(.*?)\];", rs, re.S).group(1))
b = re.findall(r'"([a-z0-9-]+)"', re.search(r"TOPICS = \[(.*?)\]", py, re.S).group(1))
n = re.search(r"const TOPICS: \[&str; (\d+)\]", rs).group(1)
if a != b or int(n) != len(a):
    print(f"not ok - topic icons: daemon {len(a)} (declared {n}), font {len(b)}, or a different order")
    sys.exit(1)
print(f"ok - topic icons of the daemon and of the font agree ({len(a)})")
