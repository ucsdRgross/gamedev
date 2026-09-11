# -*- coding: utf-8 -*-
"""The overseer's own pass after each auditor returns: print every question in the given families
whose text matches a known damage shape, so a missed defect is looked at rather than trusted away.

    py spot.py P Q
"""
import re, sys
import review_batch as rb

SHAPES = re.compile(
    r"\b(this|each|per|every|that|the next|one) placement\b"
    r"|\bplacement'?s? (start|end|combo)\b|\bwhen a placement finishes resolving\b"
    r"|\bcards? (played|placed) this placement\b|\bfirst (card|placement)\b"
    r"|\b(rows?|columns?) (scored|score) (a meld )?this\b"
    r"|\bhand(?! type)(?!s? (it|they) (made|make))\b|\bdiscards?\b|\brounds?\b|\bresets?\b"
    r"|\bshow end\b|\bsubmit|\bante\b|\bNext\b|\btableau\b|\bmark(ed|s)?\b", re.I)

if __name__ == "__main__":
    fams = set(sys.argv[1:])
    n = 0
    for q in rb.questions():
        if q["fam"] in fams and not q["retired"] and SHAPES.search(q["line"]):
            n += 1
            body = re.sub(r"^.*?— \*\*", "**", q["line"])
            print(q["qid"], body[:420].encode("ascii", "replace").decode())
            print()
    print("%d candidates" % n)
