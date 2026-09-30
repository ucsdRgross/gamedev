# -*- coding: utf-8 -*-
"""Dump every live question as one TSV row (qid, family, class, slot, name, the owner's ruling,
default, head, a, b, c) so a card concept can be checked against the existing effects.

    py live_index.py <answers.json> <out.tsv>
"""
import io, json, os, re, sys

DESIGN = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "DESIGN.md")
ans = json.load(io.open(sys.argv[1], encoding="utf-8"))["answers"]
Q = re.compile(r"^- \*\*(Q\d+)\*\* (`\[root\]` )?— (.*)$")
H = re.compile(r"\*\*(.+?)\*\* — (\w+), (\w+), from (.+?)\. (.*?) · \*\*\(a\)\*\* (.*?) · "
               r"\*\*\(b\)\*\* (.*?) · \*\*\(c\)\*\* (.*?) · \*\*\(d\)\*\*.*\*default\* \((\w)\)$")
rows, fam = [], "?"
for line in io.open(DESIGN, encoding="utf-8"):
    line = line.rstrip("\r\n")
    m = re.match(r"^## Family ([A-Z]+) - ", line)
    if m:
        fam = m.group(1)
        continue
    m = Q.match(line)
    if not m or not m.group(3).startswith("**"):  # a retired question renders as *italic*
        continue
    qid = m.group(1)
    name, slot, cls, src, head, a, b, c, dflt = H.match(m.group(3)).groups()
    st = ans.get(qid, {})
    opt = st.get("option")
    ruling = "rejected" if opt == "d" else ("approved:" + opt if opt else ("note" if st else ""))
    rows.append([qid, fam, cls, slot, name, ruling, dflt, head, a, b, c])
with io.open(sys.argv[2], "w", encoding="utf-8") as f:
    f.write("qid\tfam\tcls\tslot\tname\truling\tdefault\thead\ta\tb\tc\n")
    for r in rows:
        f.write("\t".join(x.replace("\t", " ") for x in r) + "\n")
print(len(rows), "live;", sum(r[5].startswith("approved") for r in rows), "approved;",
      sum(r[5] == "rejected" for r in rows), "rejected")
