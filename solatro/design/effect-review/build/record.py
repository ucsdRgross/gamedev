# -*- coding: utf-8 -*-
"""Record a family's verdicts: every question still unjudged in the named families becomes OK
unless it is named in NOTES. Keeps the adjudicated calls and their reasons in one place.

    from record import record_families
    record_families(["A", "B"], {"Q0034": ("RESCOPE", "why"), ...}, extra=[...])
"""
import io, os
import review_batch as rb

HERE = os.path.dirname(os.path.abspath(__file__))


def record_families(fams, notes, extra=()):
    done = rb.verdicts()
    rows = []
    for q in rb.questions():
        if q["fam"] in fams and not q["retired"] and q["qid"] not in done:
            v, n = notes.get(q["qid"], ("OK", ""))
            rows.append("%s\t%s\t%s\t%s\n" % (q["qid"], q["cls"], v, n))
    for qid, cls, v, n in extra:
        if qid not in done:
            rows.append("%s\t%s\t%s\t%s\n" % (qid, cls, v, n))
    missing = [k for k in notes if k not in {r.split("\t")[0] for r in rows}]
    if missing:
        raise SystemExit("adjudicated but not in these families / already judged: %s" % missing)
    with io.open(os.path.join(HERE, "_verdicts.tsv"), "a", encoding="utf-8", newline="\n") as f:
        f.write("".join(rows))
    print("recorded %d verdicts for %s" % (len(rows), "".join(fams)))
