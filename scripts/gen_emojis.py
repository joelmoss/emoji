#!/usr/bin/env python3
"""Usage: scripts/gen_emojis.py > Sources/Emoji/emojis.json  (run from repo root)

Sources (checked in, see scripts/):
  emoji-test.txt                     https://unicode.org/Public/emoji/latest/emoji-test.txt
  cldr-annotations-en.json           unicode-org/cldr-json cldr-annotations-full/annotations/en/annotations.json
  cldr-annotations-derived-en.json   unicode-org/cldr-json cldr-annotations-derived-full/annotationsDerived/en/annotations.json

Per emoji: c = char, n = name, k = space-separated search words (name + CLDR keywords,
lowercase, accents folded), t = five skin-tone variants when all five uniform-tone
sequences exist. Fully-qualified only; Component group skipped.
"""
import json
import re
import unicodedata

TONES = range(0x1F3FB, 0x1F3FF + 1)


def norm(char):
    return char.replace("️", "")


def fold(text):
    text = unicodedata.normalize("NFKD", text.lower())
    return "".join(c for c in text if not unicodedata.combining(c))


def words(text):
    return re.findall(r"\w+", fold(text))


keywords = {}
for path in ("scripts/cldr-annotations-en.json", "scripts/cldr-annotations-derived-en.json"):
    data = json.load(open(path, encoding="utf-8"))
    for char, entry in next(iter(data.values()))["annotations"].items():
        keywords.setdefault(norm(char), []).extend(entry.get("default", []) + entry.get("tts", []))

groups, cur = [], None
variants = {}  # base code points (tuple) -> {tone: char}
for line in open("scripts/emoji-test.txt", encoding="utf-8"):
    if line.startswith("# group:"):
        name = line.split(":", 1)[1].strip()
        cur = None if name == "Component" else {"name": name, "emojis": []}
        if cur:
            groups.append(cur)
    elif cur is not None and "; fully-qualified" in line:
        cps = [int(c, 16) for c in line.split(";")[0].split()]
        m = re.search(r"# (\S+) E[\d.]+ (.*)$", line)
        char, name = m[1], m[2].lower()
        used = {c for c in cps if c in TONES}
        if not used:
            cur["emojis"].append({"c": char, "n": name, "cps": tuple(cps)})
        elif len(used) == 1:  # uniform tone only; mixed-tone couples are skipped
            base = tuple(c for c in cps if c not in TONES)
            variants.setdefault(base, {})[used.pop()] = char

out = []
for group in groups:
    emojis = []
    for e in group["emojis"]:
        seen = set()
        ordered = [w for w in words(e["n"] + " " + " ".join(keywords.get(norm(e["c"]), []))) if not (w in seen or seen.add(w))]
        entry = {"c": e["c"], "n": e["n"], "k": " ".join(ordered)}
        tones = variants.get(e["cps"], {})
        if len(tones) == 5:
            entry["t"] = [tones[t] for t in TONES]
        emojis.append(entry)
    out.append({"name": group["name"], "emojis": emojis})

print(json.dumps(out, ensure_ascii=False, separators=(",", ":")))
