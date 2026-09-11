# -*- coding: utf-8 -*-
"""Emit questions for the architecture review, and hold the verdicts.

The vocabulary sweep (`retire.py`) was a regex pass: it could only ever find effects that USED
one of a fixed list of retired words. This is the other half — reading every question against
`GAME_BRIEF.md` and judging whether it still describes a mechanic this game can have.

    py review_batch.py next 25        the next 25 unjudged questions, with full option text
    py review_batch.py fam C          every unjudged question in one family
    py review_batch.py stat           how far the review has got

Verdicts live in `_verdicts.tsv`, one row per question, appended as the review proceeds:

    qid  eid  verdict  note

    OK          the effect still fits the architecture
    STALE       its premise is a mechanic that no longer exists; needs re-expressing
    CONTRADICTS it fits a slot but says something the live rules forbid
    ALREADY     it restates a rule the game already has
    DUPLICATE   the same design space as another question, named in the note
    RESCOPE     the idea survives but its options describe the wrong board
    UNSURE      needs the owner; the note says what the question is
"""
import csv, io, os, re, sys
from collections import Counter, OrderedDict

HERE = os.path.dirname(os.path.abspath(__file__))
DESIGN = os.path.join(os.path.dirname(HERE), "DESIGN.md")
VERDICTS = os.path.join(HERE, "_verdicts.tsv")

Q = re.compile(r'^- \*\*(Q\d+)\*\*(.*)$')
FAM = re.compile(r'^## Family ([A-Z]) - (.*)$')
CLS = re.compile(r'^### ([A-Z]\d+) - (.*)$')


def questions():
    """Every question line, in document order, tagged with its family and class."""
    out, fam, cls = [], "?", "?"
    for line in io.open(DESIGN, encoding="utf-8"):
        line = line.rstrip("\n")
        m = FAM.match(line)
        if m:
            fam = m.group(1)
            continue
        m = CLS.match(line)
        if m:
            cls = m.group(1)
            continue
        m = Q.match(line)
        if m:
            retired = m.group(2).lstrip().startswith("— *") and "`[root]`" not in m.group(2)
            out.append({"qid": m.group(1), "fam": fam, "cls": cls,
                        "retired": retired, "line": line})
    return out


def verdicts():
    if not os.path.exists(VERDICTS):
        return OrderedDict()
    rows = OrderedDict()
    with io.open(VERDICTS, encoding="utf-8") as f:
        for r in csv.DictReader(f, delimiter="\t"):
            rows[r["qid"]] = r
    return rows


def record(rows):
    with io.open(VERDICTS, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["qid", "cls", "verdict", "note"],
                           delimiter="\t", lineterminator="\n")
        w.writeheader()
        for r in rows.values():
            w.writerow({k: r.get(k, "") for k in ("qid", "cls", "verdict", "note")})


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "stat"
    qs, done = questions(), verdicts()
    live = [q for q in qs if not q["retired"]]

    if cmd == "stat":
        print("questions   %d live (%d retired in place)" % (len(live), len(qs) - len(live)))
        live_ids = {q["qid"] for q in live}
        print("judged      %d of the live questions (%d more verdicts are on questions since retired)"
              % (len(live_ids & set(done)), len(set(done) - live_ids)))
        print("remaining   %d" % len(live_ids - set(done)))
        c = Counter(r["verdict"] for r in done.values())
        for k, v in c.most_common():
            print("   %-12s %d" % (k, v))
        todo = Counter(q["fam"] for q in live if q["qid"] not in done)
        if todo:
            print("\nunjudged by family:")
            for k in sorted(todo):
                print("   %s  %d" % (k, todo[k]))
    elif cmd == "next":
        n = int(sys.argv[2]) if len(sys.argv) > 2 else 25
        todo = [q for q in live if q["qid"] not in done][:n]
        for q in todo:
            print("[%s %s] %s" % (q["fam"], q["cls"], q["line"]))
        print("\n-- %d shown, %d still unjudged --"
              % (len(todo), len([q for q in live if q["qid"] not in done]) - len(todo)))
    elif cmd == "fam":
        f = sys.argv[2]
        todo = [q for q in live if q["fam"] == f and q["qid"] not in done]
        for q in todo:
            print("[%s] %s" % (q["cls"], q["line"]))
        print("\n-- family %s: %d unjudged --" % (f, len(todo)))
