# -*- coding: utf-8 -*-
"""The level-2 pass: every live question read for uniqueness and fun, and every matchable effect
given its form "when hitting its own mark" (`GAME_BRIEF.md` § Every matchable effect has two levels).

    py levels.py fam C          every live question in family C, compact, with what is recorded
    py levels.py stat           coverage by family

Rows live in `levels/l*.py`, one per question: (qid, eid, verdict, level2, why).

    verdict   OK        kept as is
              REWORK    its options were rewritten (`fixkit.set_options`); `why` says what for
              WEAK      kept, but it gives the player no decision; `why` is shown to the owner
              DUP       retired in place (`fixkit.retire`) as a duplicate of the question in `why`
              TWIN      its level 1 is another effect's level 2; retired, `why` names the survivor
              ANSWERED  the owner already ruled; its level 2 is asked in family AC instead
    level2    a str     one level 2, true of all three options
              a tuple   one level 2 per option, (a, b, c)
              SUIT/RANK the options ARE the level-2 addition; level 1 is the plain suit or rank
              NONE      no level 2 beyond the flat talent or hat mult
              None      not matchable (type, consumable, status, hazard, structure), or retired

⚠ `qid` is checked against `eid` on every load: the question id is positional, so a row whose pair
no longer agrees is pointing at a different effect.
"""
import glob, io, json, os, re, subprocess, sys, importlib.util
from collections import Counter, OrderedDict

HERE = os.path.dirname(os.path.abspath(__file__))
DESIGN = os.path.join(os.path.dirname(HERE), "DESIGN.md")
ANSWERS = os.path.join(os.path.dirname(HERE), "answers.json")

SUIT, RANK, NONE = "SUIT", "RANK", "NONE"
VERDICTS = ("OK", "REWORK", "WEAK", "DUP", "TWIN", "ANSWERED")
MATCHABLE = ("skill", "stamp", "suit", "rank")


def order():
    """Qnnnn -> eid, as render.py numbers them."""
    tmp = os.path.join(HERE, "_levels_order.tsv")
    subprocess.run([sys.executable, os.path.join(HERE, "order_check.py"), tmp],
                   check=True, capture_output=True)
    pairs = [l.rstrip("\n").split("\t") for l in io.open(tmp, encoding="utf-8") if l.strip()]
    os.remove(tmp)
    return OrderedDict(pairs)


def rows():
    """eid -> (qid, verdict, level2, why), from every levels/l*.py."""
    out = {}
    for p in sorted(glob.glob(os.path.join(HERE, "levels", "l*.py"))):
        spec = importlib.util.spec_from_file_location("l_" + os.path.basename(p)[:-3], p)
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
        for qid, eid, verdict, level2, why in m.ROWS:
            assert verdict in VERDICTS, (qid, verdict)
            assert eid not in out, ("two level rows for", eid, qid)
            out[eid] = (qid, verdict, level2, why)
    return out


def check(q2e, lv):
    bad = [(r[0], e, q2e.get(r[0])) for e, r in lv.items() if q2e.get(r[0]) != e]
    if bad:
        raise SystemExit("!! level rows whose qid no longer names their eid: %s" % bad[:5])


Q = re.compile(r"^- \*\*(Q\d+)\*\* (`\[root\]` )?— (.*)$")
FAM = re.compile(r"^## Family ([A-Z]+) - ")


def questions():
    out, fam = OrderedDict(), "?"
    for line in io.open(DESIGN, encoding="utf-8"):
        line = line.rstrip("\n")
        m = FAM.match(line)
        if m:
            fam = m.group(1)
            continue
        m = Q.match(line)
        if m:
            out[m.group(1)] = {"fam": fam, "live": bool(m.group(2)), "text": m.group(3)}
    return out


def answers():
    if not os.path.exists(ANSWERS):
        return {}
    return json.load(io.open(ANSWERS, encoding="utf-8")).get("answers", {})


def slot_of(text):
    m = re.match(r"\*\*.+?\*\* [—-] (\w+),", text)
    return m.group(1) if m else "?"


def cmd_fam(fam):
    q2e, lv, ans, qs = order(), rows(), answers(), questions()
    check(q2e, lv)
    for qid, q in qs.items():
        if q["fam"] != fam or not q["live"]:
            continue
        eid = q2e[qid]
        a = ans.get(qid)
        said = ""
        if a:
            said = "  OWNER: %s%s" % (a.get("option") or "own words",
                                      (" - " + a["note"]) if a.get("note") else "")
        done = "  [%s]" % lv[eid][1] if eid in lv else ""
        print("%s %s%s%s\n  %s\n" % (qid, eid, done, said, q["text"].replace(" · ", "\n  ")))


def cmd_stat():
    q2e, lv, qs = order(), rows(), questions()
    check(q2e, lv)
    by = OrderedDict()
    for qid, q in qs.items():
        if q["fam"] == "AC" or (not q["live"] and q2e[qid] not in lv):
            continue
        t = by.setdefault(q["fam"], Counter())
        t["live"] += 1
        t["done"] += q2e[qid] in lv
    for fam, t in by.items():
        print("%-3s %4d / %4d" % (fam, t["done"], t["live"]))
    print("verdicts:", dict(Counter(r[1] for r in lv.values())))


if __name__ == "__main__":
    {"fam": lambda: cmd_fam(sys.argv[2]), "stat": cmd_stat}[sys.argv[1]]()
