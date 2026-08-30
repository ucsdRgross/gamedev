# -*- coding: utf-8 -*-
"""Turn the answered questionnaire into the deliverable CSV.

Lives beside DESIGN.md and answers.json and reads only those two, so it works
wherever this directory is.

Run it at any point: unanswered questions come out as `unanswered` rather than
being dropped, so the file is always a complete picture of the review.

    py export_csv.py
"""
import csv, io, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
DESIGN = os.environ.get("EFFECT_REVIEW_DIR", HERE)
DOC = os.path.join(DESIGN, "DESIGN.md")
OUT = os.path.join(DESIGN, "EFFECTS.csv")

# ---- parse the questionnaire back out of the document ----------------------
# The document is the source of truth; nothing here re-derives from scratchpad
# state, so the CSV matches exactly what the owner was shown.
Q = re.compile(r"^- \*\*(Q\d+)\*\* `\[root\]` \u2014 (.*)$")
OPT = re.compile(r"\*\*\(([a-d])\)\*\* ")

questions, fam, cls = {}, "", ""
order = []
for line in io.open(DOC, encoding="utf-8"):
    line = line.rstrip("\n")
    if line.startswith("## Family "):
        fam = line[len("## Family "):].strip()
        continue
    if line.startswith("### "):
        cls = line[4:].strip()
        continue
    m = Q.match(line)
    if not m:
        continue
    qid, rest = m.group(1), m.group(2)
    parts = rest.split(" \u00b7 ")
    head = parts[0]
    opts, default = {}, ""
    for p in parts[1:]:
        om = OPT.match(p)
        if om:
            opts[om.group(1)] = p[om.end():].strip()
        elif p.startswith("*default* ("):
            default = p[11:12]
    # head: **Name** — slot, class, from source. mechanic
    hm = re.match(r"\*\*(.+?)\*\* [\u2014-] (.*)$", head)
    nm, meta = (hm.group(1), hm.group(2)) if hm else (head, "")
    bits = meta.split(", ", 2)
    slot = bits[0] if bits else ""
    klass = bits[1] if len(bits) > 1 else ""
    tail = bits[2] if len(bits) > 2 else ""
    src, mech = "", tail
    sm = re.match(r"from (.+?)\. (.*)$", tail)
    if sm:
        src, mech = sm.group(1), sm.group(2)
    questions[qid] = {"qid": qid, "family": fam, "class_group": cls, "name": nm,
                      "slot": slot, "class": klass, "source": src,
                      "mechanic": mech, "opts": opts, "default": default}
    order.append(qid)

print("parsed %d questions" % len(questions))

# ---- answers ----------------------------------------------------------------
answers = {}
ap = os.path.join(DESIGN, "answers.json")
if os.path.exists(ap):
    raw = json.load(io.open(ap, encoding="utf-8"))
    answers = raw.get("answers", raw) if isinstance(raw, dict) else {}
    print("loaded %d answers" % len(answers))
else:
    print("no answers.json yet - every row will read 'unanswered'")

# answers.json contract, designloop PLAN.md §4.3:
#   state    chosen | not_relevant | defaulted
#   option   the letter, or null when override is true
#   note     free text, may accompany any state
#   override true = free text INSTEAD of choosing
#   active   false = stranded by a changed upstream answer; never deleted
rows = []
for qid in order:
    q = questions[qid]
    a = answers.get(qid) or {}
    letter = (a.get("option") or "")
    letter = str(letter).strip().lower()[:1] if letter else ""
    note = str(a.get("note") or "").strip()
    state = str(a.get("state") or "").strip()
    override = bool(a.get("override"))
    active = a.get("active", True)

    if not a:
        status, approved = "unanswered", ""
    elif override:
        status, approved = "own wording", note
    elif letter == "d":
        status, approved = "rejected", ""
    elif letter in ("a", "b", "c"):
        approved = q["opts"].get(letter, "")
        status = {"defaulted": "approved (Enter-defaulted)",
                  "not_relevant": "approved (waved through as not relevant)"}.get(state, "approved")
        if note and state == "chosen":
            status = "approved with note"
    else:
        status, approved = "unanswered", ""
    if a and not active:
        status += " (INACTIVE)"

    rows.append({
        "id": qid,
        "name": q["name"],
        "status": status,
        "approved_effect": approved,
        "slot": q["slot"],
        "class": q["class"],
        "family": q["family"],
        "class_group": q["class_group"],
        "variant": letter if letter in "abc" else "",
        "was_recommended": "yes" if letter and letter == q["default"] else "",
        "answer_state": state,
        "owner_note": note,
        "one_line_summary": q["mechanic"],
        "provenance": q["source"],
        "option_a": q["opts"].get("a", ""),
        "option_b": q["opts"].get("b", ""),
        "option_c": q["opts"].get("c", ""),
    })

cols = ["id", "name", "status", "approved_effect", "slot", "class", "family",
        "class_group", "variant", "was_recommended", "answer_state", "owner_note",
        "one_line_summary", "provenance", "option_a", "option_b", "option_c"]
with io.open(OUT, "w", encoding="utf-8-sig", newline="") as f:
    w = csv.DictWriter(f, fieldnames=cols)
    w.writeheader()
    w.writerows(rows)

from collections import Counter
print("wrote", OUT)
print(Counter(r["status"] for r in rows).most_common())
