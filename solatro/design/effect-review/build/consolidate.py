# -*- coding: utf-8 -*-
"""Merge the five mining passes into one normalised table, then collapse
near-duplicates. Output: corpus.tsv (one row per surviving effect) plus
dupes.tsv (what was folded into what, so nothing vanishes silently)."""
import csv, io, os, re, sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = [
    ("mine_catalog.tsv",   "catalog"),
    ("mine_designdocs.tsv","designdocs"),
    ("mine_braindump.tsv", "braindump"),
    ("mine_balatro.tsv",   "balatro"),
    ("mine_cryptid.tsv",   "cryptid"),
]

def read(fn):
    with io.open(os.path.join(HERE, fn), encoding="utf-8") as f:
        return list(csv.DictReader(f, delimiter="\t"))

rows = []
for fn, origin in SRC:
    for r in read(fn):
        rows.append({
            "origin":   origin,
            "source":   (r.get("source") or "").strip(),
            "name":     (r.get("name") or "").strip(),
            "rarity":   (r.get("rarity") or "").strip(),
            "slot":     (r.get("slot_guess") or r.get("category") or "").strip(),
            "groups":   (r.get("groups") or "").strip(),
            "mechanic": re.sub(r"\s+", " ", (r.get("mechanic") or "")).strip(),
            "status":   (r.get("status") or "").strip(),
        })

print("loaded", len(rows))

# --- normalisation for comparison -------------------------------------------
STOP = set("a an the this that these those of to in on at for with and or is are be "
           "when if it its as by from card cards".split())

def norm_name(s):
    s = s.lower()
    s = re.sub(r"\(.*?\)", " ", s)
    s = re.sub(r"[^a-z0-9 ]", " ", s)
    return " ".join(s.split())

def sig(s):
    """bag of content words, for near-duplicate detection"""
    s = s.lower()
    s = re.sub(r"[^a-z0-9 ]", " ", s)
    return frozenset(w for w in s.split() if w not in STOP and len(w) > 2)

def jaccard(a, b):
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)

for i, r in enumerate(rows):
    r["id"] = i
    r["nname"] = norm_name(r["name"])
    r["sig"] = sig(r["mechanic"])

# --- collapse ----------------------------------------------------------------
# Priority for which row survives a merge: catalog > designdocs > braindump >
# balatro > cryptid. The repo's own wording is the one worth keeping.
PRIO = {"catalog": 0, "designdocs": 1, "braindump": 2, "balatro": 3, "cryptid": 4}

# Bucket by shared rare-ish word to keep the comparison from going O(n^2) across
# the whole corpus while still catching cross-source restatements.
buckets = defaultdict(list)
for r in rows:
    keys = set()
    if r["nname"]:
        keys.add("N:" + r["nname"])
    for w in sorted(r["sig"])[:14]:
        keys.add("W:" + w)
    for k in keys:
        buckets[k].append(r)

parent = list(range(len(rows)))
def find(x):
    while parent[x] != x:
        parent[x] = parent[parent[x]]
        x = parent[x]
    return x
def union(a, b):
    ra, rb = find(a), find(b)
    if ra != rb:
        parent[max(ra, rb)] = min(ra, rb)

NAME_HIT = 0.55   # same name -> a weaker mechanic overlap is enough
TEXT_HIT = 0.78   # different name -> needs to be near-verbatim

seen_pairs = set()
for key, group in buckets.items():
    if len(group) > 90:      # a word too common to be evidence of anything
        continue
    for i in range(len(group)):
        for j in range(i + 1, len(group)):
            a, b = group[i], group[j]
            pk = (min(a["id"], b["id"]), max(a["id"], b["id"]))
            if pk in seen_pairs:
                continue
            seen_pairs.add(pk)
            same_name = a["nname"] and a["nname"] == b["nname"]
            thr = NAME_HIT if same_name else TEXT_HIT
            if jaccard(a["sig"], b["sig"]) >= thr:
                union(a["id"], b["id"])

clusters = defaultdict(list)
for r in rows:
    clusters[find(r["id"])].append(r)

survivors, folded = [], []
for root, members in clusters.items():
    members.sort(key=lambda r: (PRIO[r["origin"]], len(r["mechanic"]) * -1))
    keep = members[0]
    keep["also_seen_in"] = ";".join(sorted({m["origin"] for m in members[1:]}))
    keep["dupe_count"] = len(members) - 1
    survivors.append(keep)
    for m in members[1:]:
        folded.append((keep["name"], keep["origin"], m["name"], m["origin"], m["source"], m["mechanic"]))

survivors.sort(key=lambda r: (PRIO[r["origin"]], r["nname"]))
for n, r in enumerate(survivors, 1):
    r["eid"] = "E%04d" % n

OUT = os.path.join(HERE, "corpus.tsv")
cols = ["eid", "origin", "source", "name", "slot", "rarity", "groups", "mechanic",
        "status", "also_seen_in", "dupe_count"]
with io.open(OUT, "w", encoding="utf-8", newline="") as f:
    w = csv.DictWriter(f, fieldnames=cols, delimiter="\t", extrasaction="ignore")
    w.writeheader()
    for r in survivors:
        w.writerow(r)

with io.open(os.path.join(HERE, "dupes.tsv"), "w", encoding="utf-8", newline="") as f:
    w = csv.writer(f, delimiter="\t")
    w.writerow(["kept_name", "kept_origin", "folded_name", "folded_origin", "folded_source", "folded_mechanic"])
    w.writerows(folded)

print("survivors", len(survivors), "folded", len(folded))
from collections import Counter
print(Counter(r["origin"] for r in survivors))
