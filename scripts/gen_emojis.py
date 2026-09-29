#!/usr/bin/env python3
"""Usage: scripts/gen_emojis.py scripts/emoji-test.txt > Sources/Emoji/emojis.json

Source: https://unicode.org/Public/emoji/latest/emoji-test.txt
Keeps fully-qualified emoji only, skips skin-tone variants and the Component group.
"""
import json
import re
import sys

groups, cur = [], None
for line in open(sys.argv[1], encoding="utf-8"):
    if line.startswith("# group:"):
        name = line.split(":", 1)[1].strip()
        cur = None if name == "Component" else {"name": name, "emojis": []}
        if cur:
            groups.append(cur)
    elif cur is not None and "; fully-qualified" in line:
        cps = line.split(";")[0].split()
        if any(0x1F3FB <= int(c, 16) <= 0x1F3FF for c in cps):
            continue
        m = re.search(r"# (\S+) E[\d.]+ (.*)$", line)
        cur["emojis"].append({"c": m[1], "n": m[2].lower()})

json.dump(groups, sys.stdout, ensure_ascii=False, separators=(",", ":"))
