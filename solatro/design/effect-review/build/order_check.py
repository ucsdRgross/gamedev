# -*- coding: utf-8 -*-
"""Dump the rendered question order as `Qnnnn<TAB>eid`.

⚠ THE QUESTION ID IS POSITIONAL. `render.py` numbers questions by walking `ordered`, which is
sorted by (family, class, name.lower()). So renaming an effect can MOVE it and silently
renumber every question after it — which would repoint every recorded answer at a different
effect. Run this before and after any source edit and diff the two.
"""
import csv, io, os, glob, importlib.util, sys
from collections import defaultdict, OrderedDict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from taxonomy_data import FAMILIES

CLASS_ORDER, CLASS_FAM = OrderedDict(), {}
for fi, (code, title, blurb, items) in enumerate(FAMILIES):
    for ci, (cid, cname, cov, desc) in enumerate(items):
        CLASS_ORDER[cid] = (fi, ci)
        CLASS_FAM[cid] = code

def tsv(p):
    with io.open(p, encoding="utf-8") as f:
        return list(csv.DictReader(f, delimiter="\t"))

def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m

corpus = {r["eid"]: r for r in tsv(os.path.join(HERE, "corpus.tsv"))}
tags, variants = {}, {}
for p in sorted(glob.glob(os.path.join(HERE, "generated", "g*.py"))):
    m = load(p, "g_" + os.path.basename(p)[:-3])
    for eid, nm, cls, slot, mech, a, b, c, dflt in m.ROWS:
        corpus[eid] = {"eid": eid, "origin": "generated", "name": nm, "mechanic": mech}
        tags[eid] = {"class": cls, "verdict": "KEEP", "upgrade_of": ""}
        variants[eid] = True
for p in sorted(glob.glob(os.path.join(HERE, "variants", "v*.py"))):
    for eid, a, b, c, dflt in load(p, "v_" + os.path.basename(p)[:-3]).ROWS:
        variants[eid] = True
for p in sorted(glob.glob(os.path.join(HERE, "decisions", "d*.py"))):
    m = load(p, "d_" + os.path.basename(p)[:-3])
    for eid, reason in getattr(m, "DROPS", []):
        tags[eid] = {"class": "", "verdict": "DROP", "upgrade_of": ""}
    for row in getattr(m, "KEEPS", []):
        eid, cls = row[0], row[1]
        tags[eid] = {"class": cls, "verdict": "KEEP",
                     "upgrade_of": row[8] if len(row) > 8 else ""}
        variants[eid] = True
for p in sorted(glob.glob(os.path.join(HERE, "batches", "tagged*.tsv"))):
    for r in tsv(p):
        tags.setdefault(r["eid"], {"class": r.get("class", ""), "verdict": r.get("verdict", ""),
                                   "upgrade_of": r.get("upgrade_of", "")})
        tags[r["eid"]].setdefault("upgrade_of", r.get("upgrade_of", ""))
        if r["eid"] not in tags or not tags[r["eid"]].get("verdict"):
            tags[r["eid"]] = {"class": r.get("class", ""), "verdict": r.get("verdict", ""),
                              "upgrade_of": r.get("upgrade_of", "")}

keepers = [e for e, t in tags.items()
           if (t.get("verdict") or "").strip().upper() == "KEEP" and e in corpus and e in variants]

rows = []
for e in keepers:
    cls = (tags[e].get("class") or "").strip()
    rows.append({"eid": e, "cls": cls, "fam": CLASS_FAM.get(cls, "Z"),
                 "name": corpus[e]["name"].strip(),
                 "up": (tags[e].get("upgrade_of") or "").strip()})

by_eid = {r["eid"]: r for r in rows}
kids, roots = defaultdict(list), []
for r in rows:
    (kids[r["up"]].append(r) if r["up"] and r["up"] in by_eid and r["up"] != r["eid"]
     else roots.append(r))

def skey(r):
    fi, ci = CLASS_ORDER.get(r["cls"], (98, 98))
    return (fi, ci, r["name"].lower())

ordered, seen = [], set()
def emit(r):
    if r["eid"] in seen:
        return
    seen.add(r["eid"])
    ordered.append(r)
    for k in sorted(kids.get(r["eid"], []), key=skey):
        emit(k)
for r in sorted(roots, key=skey):
    emit(r)
for r in rows:
    emit(r)

out = io.open(sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "_order.tsv"),
              "w", encoding="utf-8", newline="\n")
for i, r in enumerate(ordered, 1):
    out.write("Q%04d\t%s\n" % (i, r["eid"]))
print("%d questions" % len(ordered))
