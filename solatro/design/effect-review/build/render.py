# -*- coding: utf-8 -*-
"""Join corpus + tagging + written variants into the questionnaire DESIGN.md.

Runs at any point: whatever variants exist so far are rendered, and the report
says how much of the keeper set is still unwritten.
"""
import csv, io, os, re, sys, glob, importlib.util
from collections import Counter, defaultdict, OrderedDict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from taxonomy_data import FAMILIES

DEST = os.path.join(os.path.dirname(HERE), "DESIGN.md")

CLASS_ORDER, CLASS_NAME, CLASS_FAM, FAM_TITLE = OrderedDict(), {}, {}, OrderedDict()
for fi, (code, title, blurb, items) in enumerate(FAMILIES):
    FAM_TITLE[code] = title
    for ci, (cid, cname, cov, desc) in enumerate(items):
        CLASS_ORDER[cid] = (fi, ci)
        CLASS_NAME[cid] = cname
        CLASS_FAM[cid] = code

def tsv(p):
    with io.open(p, encoding="utf-8") as f:
        return list(csv.DictReader(f, delimiter="\t"))

corpus = {r["eid"]: r for r in tsv(os.path.join(HERE, "corpus.tsv"))}

tags = {}
for p in sorted(glob.glob(os.path.join(HERE, "batches", "tagged*.tsv"))):
    for r in tsv(p):
        tags[r["eid"]] = r

# generated effects live in the same shape as corpus rows, appended by the
# empty-class fill pass
gen_path = os.path.join(HERE, "generated.tsv")
if os.path.exists(gen_path):
    for r in tsv(gen_path):
        corpus[r["eid"]] = r
        tags[r["eid"]] = {"eid": r["eid"], "verdict": "KEEP", "drop_reason": "",
                          "class": r["cls"], "slot": r["slot"],
                          "mechanic_grid": r["mechanic"], "upgrade_of": r.get("upgrade_of", "")}

def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m

variants = {}

# generated/*.py — effects written to fill a taxonomy class the corpus left empty.
# Full rows: (eid, name, cls, slot, mechanic, a, b, c, default)
for p in sorted(glob.glob(os.path.join(HERE, "generated", "g*.py"))):
    spec = importlib.util.spec_from_file_location("g_" + os.path.basename(p)[:-3], p)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    src = getattr(m, "SOURCE", "generated")
    for eid, nm, cls, slot, mech, a, b, c, dflt in m.ROWS:
        corpus[eid] = {"eid": eid, "origin": "generated", "source": src,
                       "name": nm, "mechanic": mech, "rarity": ""}
        tags[eid] = {"eid": eid, "verdict": "KEEP", "drop_reason": "", "class": cls,
                     "slot": slot, "mechanic_grid": mech, "upgrade_of": ""}
        variants[eid] = (a, b, c, dflt)

for p in sorted(glob.glob(os.path.join(HERE, "variants", "v*.py"))):
    m = load(p, "v_" + os.path.basename(p)[:-3])
    for row in m.ROWS:
        eid, a, b, c, dflt = row
        if eid in variants:
            print("  ! duplicate variant for", eid, "in", os.path.basename(p))
        variants[eid] = (a, b, c, dflt)

# decisions/*.py — tagging AND variants in one pass, for the batches done inline
for p in sorted(glob.glob(os.path.join(HERE, "decisions", "d*.py"))):
    m = load(p, "d_" + os.path.basename(p)[:-3])
    for eid, reason in getattr(m, "DROPS", []):
        tags[eid] = {"eid": eid, "verdict": "DROP", "drop_reason": reason,
                     "class": "", "slot": "", "mechanic_grid": "", "upgrade_of": ""}
    for row in getattr(m, "KEEPS", []):
        eid, cls, slot, mech, a, b, c, dflt = row[:8]
        up = row[8] if len(row) > 8 else ""
        tags[eid] = {"eid": eid, "verdict": "KEEP", "drop_reason": "", "class": cls,
                     "slot": slot, "mechanic_grid": mech, "upgrade_of": up}
        if eid in variants:
            print("  ! duplicate variant for", eid, "in", os.path.basename(p))
        variants[eid] = (a, b, c, dflt)

keepers = [e for e, t in tags.items()
           if t.get("verdict", "").strip().upper() == "KEEP" and e in corpus]
written = [e for e in keepers if e in variants]
orphan_variants = [e for e in variants if e not in keepers]

print("keepers %d | variants written %d | still to write %d"
      % (len(keepers), len(written), len(keepers) - len(written)))
if orphan_variants:
    print("  ! variants with no KEEP row:", orphan_variants[:10])

# ---------------------------------------------------------------- ordering ---
rows = []
for e in written:
    t, c = tags[e], corpus[e]
    cls = (t.get("class") or "").strip()
    rows.append({
        "eid": e, "cls": cls, "fam": CLASS_FAM.get(cls, "Z"),
        "cls_name": CLASS_NAME.get(cls, "unclassified"),
        "slot": (t.get("slot") or "").strip() or "skill",
        "name": c["name"].strip(),
        "mech": (t.get("mechanic_grid") or c["mechanic"]).strip(),
        "src": c.get("source", "") or c.get("origin", ""),
        "origin": c.get("origin", ""),
        "up": (t.get("upgrade_of") or "").strip(),
        "a": variants[e][0], "b": variants[e][1], "c": variants[e][2],
        "d": variants[e][3],
    })

by_eid = {r["eid"]: r for r in rows}
kids = defaultdict(list)
roots = []
for r in rows:
    if r["up"] and r["up"] in by_eid and r["up"] != r["eid"]:
        kids[r["up"]].append(r)
    else:
        roots.append(r)

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

# ------------------------------------------------------------------ render ---
# Source files whose names contain a space cannot be rendered verbatim: doc_check
# splits references on whitespace, so `gam draft.txt:412` reads as a reference to
# a file called `draft.txt`. Give those three a label with no extension.
SRC_LABEL = {
    "gam draft.txt": "the braindump",
    "random potential effects.csv": "the random-effects sheet",
    "curated effects pre grid.csv": "the curated pre-grid sheet",
}

def label_src(src):
    """`gam draft.txt:412` -> `the braindump, line 412`"""
    name, _, line = src.partition(":")
    lbl = SRC_LABEL.get(name.strip())
    if not lbl:
        return src
    return "%s, line %s" % (lbl, line) if line.strip().isdigit() else lbl

def clean(s):
    """the parser's separator is ' \u00b7 '; it must never occur inside a field"""
    s = re.sub(r"\s+", " ", (s or "")).strip()
    s = s.replace(" \u00b7 ", ", ").replace("\u00b7", "-")
    return s.rstrip(".")

out = [io.open(os.path.join(HERE, "header.md"), encoding="utf-8").read()]
cur_fam = cur_cls = None
n = 0
for r in ordered:
    if r["fam"] != cur_fam:
        cur_fam = r["fam"]; cur_cls = None
        out.append("\n## Family %s - %s\n" % (cur_fam, FAM_TITLE.get(cur_fam, "unclassified")))
    if r["cls"] != cur_cls:
        cur_cls = r["cls"]
        out.append("\n### %s - %s\n" % (cur_cls or "?", r["cls_name"]))
    n += 1
    qid = "Q%04d" % n
    prov = (clean(r["src"]) or "generated") if r["origin"] == "generated" else "`%s`" % label_src(clean(r["src"]))
    head = "**%s** — %s, %s, from %s. %s" % (
        clean(r["name"]), r["slot"], r["cls"] or "unclassified", prov, clean(r["mech"]))
    out.append(
        "- **%s** `[root]` \u2014 %s \u00b7 **(a)** %s \u00b7 **(b)** %s \u00b7 **(c)** %s "
        "\u00b7 **(d)** reject \u2014 this effect does not enter the game \u00b7 *default* (%s)"
        % (qid, head, clean(r["a"]), clean(r["b"]), clean(r["c"]), r["d"])
    )
out.append("\n" + io.open(os.path.join(HERE, "footer.md"), encoding="utf-8").read())

io.open(DEST, "w", encoding="utf-8").write("\n".join(out) + "\n")
print("wrote %s - %d questions" % (DEST, n))
print("families present:", " ".join(sorted({r["fam"] for r in ordered})))
print("classes present: %d" % len({r["cls"] for r in ordered}))
