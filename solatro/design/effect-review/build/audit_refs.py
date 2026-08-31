# -*- coding: utf-8 -*-
"""Which rows of DESIGN_REFERENCES.md PROPOSED a mechanic and produced nothing?

Each table row carries a hook tag in backticks - `Skill`, `Naming`, `Visual`,
`Event` and so on. Rows tagged only Naming/Visual/Lore propose no mechanic and
are correctly absent from the mined set. Everything else should have produced a
row, and this reports the ones that did not - matched on the PROPOSAL half of
the row, not the historical half, which the miner was told to discard.
"""
import csv, io, re, collections, os

HERE = os.path.dirname(os.path.abspath(__file__))
REF = os.path.join(HERE, os.pardir, os.pardir, os.pardir, "DESIGN_REFERENCES.md")

L = io.open(REF, encoding="utf-8").read().split("\n")

mined = collections.defaultdict(list)
for r in csv.DictReader(io.open(os.path.join(HERE, "mine_designdocs.tsv"), encoding="utf-8"),
                        delimiter="\t"):
    m = re.match(r"DESIGN_REFERENCES\.md \u00a7([A-I]\d{0,2})", r["source"])
    if m:
        mined[m.group(1)].append((r["name"] + " " + r["mechanic"]).lower())

# tags that are explicitly NOT a mechanic proposal
FLAVOUR = {"naming", "visual", "lore", "flavor", "flavour", "cosmetic", "visual/naming",
           "naming/visual", "visual/lore", "naming/lore"}

TAG = re.compile(r"`([^`]+)`\s*[\u2014-]+\s*(.+)$")

def toks(s):
    return {w for w in re.findall(r"[a-z]{5,}", s.lower())}

code = None
proposals, skipped_flavour, misses = 0, 0, []
for i, ln in enumerate(L):
    if ln.startswith("#"):
        h = ln.lstrip("# ").strip()
        m = re.match(r"([A-I]\d{0,2})[.\s]", h) or re.match(r"PART ([A-I])\b", h)
        code = m.group(1) if m else None
        continue
    t = ln.strip()
    if not code or code == "H" or not t.startswith("|"):
        continue
    tm = TAG.search(t)
    if not tm:
        continue
    tag, prop = tm.group(1).strip(), tm.group(2).strip().rstrip("|").strip()
    if tag.lower() in FLAVOUR:
        skipped_flavour += 1
        continue
    proposals += 1
    tk = toks(prop)
    if len(tk) < 3:
        continue
    best = 0.0
    for mt in mined[code]:
        ov = len([w for w in tk if w in mt]) / len(tk)
        best = max(best, ov)
    if best < 0.45:
        misses.append((code, i + 1, round(best, 2), tag, prop))

print("rows tagged as pure flavour (correctly not mined): %d" % skipped_flavour)
print("rows that PROPOSED a mechanic: %d" % proposals)
print("of those, produced no matching mined row: %d" % len(misses))
print()
for c, i, b, tag, prop in misses:
    print("%-3s L%-4d %.2f [%s] %s" % (c, i, b, tag, prop[:135]))
