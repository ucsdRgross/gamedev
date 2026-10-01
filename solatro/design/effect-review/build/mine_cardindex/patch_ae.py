# -*- coding: utf-8 -*-
"""Apply review fixes to a family-AE module by eid, then rewrite the module whole.

    import patch_ae
    m = patch_ae.load("g031")
    patch_ae.row(m, "CI0016", c="...", default="a")      # fields: name mechanic a b c default
    patch_ae.level2(m, "CI0016", ("...", "...", "..."))     # or level2(m, eid, b="...") for one option
    patch_ae.flag(m, "CI0016", "one line the owner sees")  # None removes it
    patch_ae.save(m)
"""
import importlib.util, io, os

GEN = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "generated")
FIELDS = {"name": 1, "mechanic": 4, "a": 5, "b": 6, "c": 7, "default": 8}


def load(stem):
    path = os.path.join(GEN, stem + ".py")
    spec = importlib.util.spec_from_file_location(stem, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    m.PATH, m.ROWS, m.FLAGS = path, [list(r) for r in m.ROWS], dict(getattr(m, "FLAGS", {}))
    m.HEAD = io.open(path, encoding="utf-8").readline()
    m.TITLE = io.open(path, encoding="utf-8").readlines()[1]
    return m


def row(m, eid, **fields):
    r = next(r for r in m.ROWS if r[0] == eid)
    for k, v in fields.items():
        r[FIELDS[k]] = v


def level2(m, eid, value=None, **per_option):
    """`level2(m, eid, "...")` sets it whole; `level2(m, eid, b="...")` sets one option's and keeps
    the others, turning a single string into a 3-tuple."""
    assert eid in m.LEVEL2
    if not per_option:
        m.LEVEL2[eid] = value
        return
    cur = m.LEVEL2[eid]
    cur = list(cur) if isinstance(cur, tuple) else [cur] * 3
    for letter, text in per_option.items():
        cur["abc".index(letter)] = text
    m.LEVEL2[eid] = tuple(cur)


def flag(m, eid, why):
    if why is None:
        m.FLAGS.pop(eid, None)
    else:
        m.FLAGS[eid] = why


def save(m):
    out = [m.HEAD, m.TITLE, "SOURCE = %r\nROWS = [\n" % m.SOURCE]
    for r in m.ROWS:
        assert " · " not in "".join(r[4:8]), r[0]
        out.append("\n(%r, %r, %r, %r,\n %r,\n %r,\n %r,\n %r,\n %r),\n" % tuple(r))
    out.append("]\n\n# eid -> level 2: a str, a 3-tuple, \"SUIT\", \"RANK\", or None\nLEVEL2 = {\n")
    out += [" %r: %r,\n" % (e, v) for e, v in m.LEVEL2.items()]
    out.append("}\n\n# eid -> the flag the owner sees\nFLAGS = {\n")
    out += [" %r: %r,\n" % (e, v) for e, v in m.FLAGS.items()]
    out.append("}\n")
    io.open(m.PATH, "w", encoding="utf-8", newline="\n").write("".join(out))
