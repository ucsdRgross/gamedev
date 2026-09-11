# -*- coding: utf-8 -*-
"""The two fixes the architecture review applies, done the same way every time.

    patch(pattern, replacement)   rewrite prose in every source file render.py reads
    retire(qid, reason)           retire a question IN PLACE, keyed by its eid

⚠ Neither may change an effect's NAME: the name is the sort key and the question id is positional
(see `order_check.py`). `verify()` re-renders and proves Q0001-Q1409 still point where they did.
"""
import glob, io, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCES = (sorted(glob.glob(os.path.join(HERE, "variants", "v*.py")))
           + sorted(glob.glob(os.path.join(HERE, "generated", "g*.py")))
           + sorted(glob.glob(os.path.join(HERE, "decisions", "d*.py")))
           + [os.path.join(HERE, "corpus.tsv")]
           + sorted(glob.glob(os.path.join(HERE, "batches", "tagged*.tsv"))))
RETIRED_PY = os.path.join(HERE, "retired_questions.py")


def patch(pattern, replacement, expect=1):
    """Rewrite `pattern` everywhere. Fails loudly when it matched a different number of files
    than expected, so a patch that silently did nothing cannot be recorded as a fix."""
    hits = 0
    for p in SOURCES:
        s = io.open(p, encoding="utf-8").read()
        s2 = re.sub(pattern, replacement, s)
        if s2 != s:
            io.open(p, "w", encoding="utf-8", newline="\n").write(s2)
            hits += 1
    if expect is not None and hits != expect:
        raise SystemExit("patch matched %d file(s), expected %d: %s" % (hits, expect, pattern))
    return hits


def eid_of(qid):
    subprocess.run([sys.executable, os.path.join(HERE, "order_check.py"),
                    os.path.join(HERE, "_o.tsv")], check=True, capture_output=True)
    for line in io.open(os.path.join(HERE, "_o.tsv"), encoding="utf-8"):
        q, e = line.rstrip("\n").split("\t")
        if q == qid:
            return e
    raise SystemExit("no such question: " + qid)


def retire(qid, reason):
    """Add `qid`'s effect to RETIRED. Idempotent."""
    eid = eid_of(qid)
    src = io.open(RETIRED_PY, encoding="utf-8").read()
    if '"%s":' % eid in src:
        return eid
    entry = '    "%s": %r,  # %s\n' % (eid, reason, qid)
    src = src.rstrip()
    assert src.endswith("}")
    src = src[:-1].rstrip() + "\n\n" + entry + "}\n"
    io.open(RETIRED_PY, "w", encoding="utf-8", newline="\n").write(src)
    return eid


def verify():
    out = subprocess.run([sys.executable, os.path.join(HERE, "render.py")],
                         capture_output=True, text=True, encoding="utf-8")
    print(out.stdout.strip().split("\n")[1])
    subprocess.run([sys.executable, os.path.join(HERE, "order_check.py"),
                    os.path.join(HERE, "_o.tsv")], check=True, capture_output=True)
    base = io.open(os.path.join(HERE, "_order.baseline.tsv"), encoding="utf-8").read().split("\n")
    now = io.open(os.path.join(HERE, "_o.tsv"), encoding="utf-8").read().split("\n")
    os.remove(os.path.join(HERE, "_o.tsv"))
    moved = [b for b, n in zip(base, now[:len(base)]) if b and b != n]
    if moved:
        raise SystemExit("!! QUESTION ORDER MOVED: %s" % moved[:5])
    print("order unchanged for Q0001-Q%04d" % (len([b for b in base if b])))


def options_of(qid):
    """The (a, b, c) texts render.py would show for `qid`, and the file each lives in."""
    import importlib.util
    eid = eid_of(qid)
    for p in SOURCES:
        if not p.endswith(".py"):
            continue
        spec = importlib.util.spec_from_file_location("_m", p)
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
        for row in getattr(m, "ROWS", []) + list(getattr(m, "KEEPS", [])):
            if row[0] != eid:
                continue
            if "variants" in p:
                return p, row[1], row[2], row[3]
            if "generated" in p:
                return p, row[5], row[6], row[7]
            return p, row[4], row[5], row[6]
    raise SystemExit("no option row for %s (%s)" % (qid, eid))


def set_options(qid, a=None, b=None, c=None):
    """Replace whole option texts for one question, by exact string - each must occur once."""
    p, oa, ob, oc = options_of(qid)
    s = io.open(p, encoding="utf-8").read()
    for old, new in ((oa, a), (ob, b), (oc, c)):
        if new is None:
            continue
        lit = '"%s"' % old.replace('"', '\\"')
        if s.count(lit) != 1:
            raise SystemExit("%s: option text not unique in %s: %s" % (qid, p, old[:60]))
        s = s.replace(lit, '"%s"' % new.replace('"', '\\"'))
    io.open(p, "w", encoding="utf-8", newline="\n").write(s)
