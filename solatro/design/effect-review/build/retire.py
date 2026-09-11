# -*- coding: utf-8 -*-
"""Rewrite retired architecture out of the questionnaire's SOURCES, in place.

The board this corpus was mined against had three acts, a Submit button, an upper/lower
tableau and Balatro's ante ladder. None of that exists. An option proposing a mechanic keyed
to a button nobody can press is not a design question, it is noise -- so the phrases below are
rewritten at the source and the questionnaire is re-rendered from them.

THE MAPPING, and why each one is what it is:

  act  ->  placement    for a TRIGGER only ("after each act"): one Submit was one scoring pass
                        and one placement is one.
  act  ->  refill       for a BUDGET or a GROUPING ("once per act", "one card per act", "a
                        scoreless act"). ⚠ An act was a third of a show and held many cards; a
                        placement is one card, and a single placement completes no line most of
                        the time. Mapping those to "placement" made budgets 7-13x stronger,
                        made scoreless effects fire almost every card, and made "the first card
                        this placement" vacuous. An Entrance refill (five cards, four to eight a
                        show) keeps the written cadence. This table got it wrong first; the
                        architecture review (`_verdicts.tsv`) re-expressed every instance.
  act count            The 1-of-3 structure is gone outright; a show runs until End. Effects
                        keyed to "the final act" or "2 acts remaining" are re-expressed
                        against End, or listed as residue for a human to retire.
  round -> show        Balatro's round is one blind is one show here.
  blind -> level       `blinds.csv` ships level modifiers; a LEVEL draws one, a boss level two.
                        The ante ladder that selects them does not exist.
  ante  -> lap         The map's endless pressure term (`lap_mult`), the nearest real thing.
  tableau / upper zone / lower zone -> the grid, the Entrance.

Ordered longest-phrase-first, so a specific rewrite beats a general one. Run, then run `spot.py`
over the families you touched: anything still carrying a retired term needs a human, not a table.
"""
import csv, io, os, re, glob, sys

DRY = "--dry" in sys.argv

HERE = os.path.dirname(os.path.abspath(__file__))

# (pattern, replacement) — applied in order, case-insensitively, preserving leading capital.
RULES = [
    # ---- the act count: the 1-of-3 structure, which has no successor ---------------
    (r"\bthe show has (\d+) submits instead of (\d+)\b", "the show is cut short"),
    (r"\b(\d+) submits per match\b", r"\1 scoring passes per show"),
    (r"\bacts? remaining\b", "placements remaining"),
    (r"\bthe (act|submit) limit\b", "the placement limit"),
    (r"\bcosts you an act\b", "costs you an Entrance card, discarded"),
    (r"\bcosts an act\b", "costs an Entrance card, discarded"),
    (r"\bcosting no act\b", "costing no Entrance card"),
    (r"\bthe final act\b", "the last placement before you press End"),
    (r"\bfinal act\b", "last placement before End"),
    (r"\bthe first act\b", "the show's first placement"),
    (r"\bfirst act\b", "the show's first placement"),
    (r"\bthe second act\b", "the show's second placement"),
    (r"\bsecond act\b", "the show's second placement"),
    (r"\bthree acts\b", "three scoring passes"),
    (r"\b(\d+) acts\b", r"\1 placements"),

    # ---- act, the quantified forms the first pass did not enumerate ------------------
    (r"\bevery sixth act\b", "every sixth placement"),
    (r"\bevery nth act\b", "every Nth placement"),
    (r"\bevery odd-numbered act\b", "every odd-numbered placement"),
    (r"\bevery odd act\b", "every odd placement"),
    (r"\bevery other act\b", "every other placement"),
    (r"\balternating acts\b", "alternating placements"),
    (r"\balternate acts\b", "alternate placements"),
    (r"\bconsecutive act\b", "consecutive placement"),
    (r"\bconsecutive acts\b", "consecutive placements"),
    (r"\ban earlier act\b", "an earlier placement"),
    (r"\ba later act\b", "a later placement"),
    (r"\bthe next ten acts\b", "the next ten placements"),
    (r"\bthe next several acts\b", "the next several placements"),
    (r"\bseveral acts\b", "several placements"),
    (r"\bunused acts\b", "Entrance refills still left in the deck"),
    (r"\bacts you did not use\b", "Entrance refills still left in the deck"),
    (r"\bcosts two acts\b", "costs two placements"),
    (r"\ba number of acts\b", "a number of placements"),
    (r"\ba single act\b", "a single placement"),
    (r"\btwo acts in three\b", "two placements in three"),
    (r"\bscoring acts\b", "scoring placements"),
    (r"\bextra acts\b", "extra placements"),
    (r"\bmore acts\b", "more placements"),
    (r"\bacts have been played\b", "placements have been made"),
    (r"\bacts have passed\b", "placements have passed"),
    (r"\bwhich act\b", "which placement"),
    (r"\blast act\b", "last placement"),
    (r"\bact payout\b", "placement payout"),
    (r"\brises with acts\b", "rises with placements"),
    (r"\bacts you wasted\b", "placements you wasted"),
    (r"\bone further act\b", "one further placement"),
    (r"\bone free act\b", "one free placement"),
    (r"\ba mixed act\b", "a mixed placement"),
    (r"\bnegative on alternate acts\b", "negative on alternate placements"),
    (r"\bit starts on\b", "it starts on"),
    # ---- the residue of round / discard-per / blind ----------------------------------
    (r"\bdiscards? per show\b", "discards per show"),
    (r"\bthe endless round\b", "the endless lap"),
    (r"\ba round\b", "a show"),
    (r"\bthe round\b", "the show"),
    (r"\brounds\b", "shows"),

    # ---- act -> placement -----------------------------------------------------------
    (r"\bonce per act\b", "once per Entrance refill"),
    (r"\bone per act\b", "one per Entrance refill"),
    (r"\bone card per act\b", "one card per Entrance refill"),
    (r"\bper act\b", "per Entrance refill"),
    (r"\bat act end\b", "when a placement finishes resolving"),
    (r"\bat act start\b", "when a placement begins"),
    (r"\bact ends\b", "a placement finishes resolving"),
    (r"\bact begins\b", "a placement begins"),
    (r"\bafter each act\b", "after each placement"),
    (r"\bat each act\b", "at each placement"),
    (r"\beach act\b", "each placement"),
    (r"\bevery act\b", "every placement"),
    (r"\bthis act\b", "this placement"),
    (r"\bthat act\b", "that placement"),
    (r"\bthe next act\b", "the next placement"),
    (r"\bnext act\b", "next placement"),
    (r"\bthe whole act\b", "the whole placement"),
    (r"\bthe previous act\b", "the previous placement"),
    (r"\bthe same act\b", "the same placement"),
    (r"\ba scoreless act\b", "a scoreless Entrance refill"),
    (r"\bscoreless act\b", "scoreless Entrance refill"),
    (r"\bthe resolving act\b", "the resolving placement"),
    (r"\bthe current act\b", "the current placement"),
    (r"\bone act\b", "one placement"),
    (r"\bno act\b", "no placement"),
    (r"\bany act\b", "any placement"),
    (r"\bits act\b", "its placement"),
    (r"\ba new act\b", "a new placement"),
    (r"\bfor one act only\b", "for one placement only"),
    (r"\bof an act\b", "of a placement"),
    (r"\ban act\b", "a placement"),
    (r"\bof the act\b", "of the placement"),
    (r"\bfor the act\b", "for the placement"),
    (r"\bto the act\b", "to the placement"),
    (r"\bthe act\b", "the placement"),

    # ---- submit ---------------------------------------------------------------------
    (r"\bonce per submit\b", "once per placement"),
    (r"\beach submit\b", "each placement"),
    (r"\bany submit\b", "any placement"),
    (r"\bafter each submit\b", "after each placement"),
    (r"\bthe first submit each show\b", "the show's first placement"),
    (r"\bon submit\b", "when a line scores"),
    (r"\bat submit\b", "when the placement scores"),
    (r"\bpress submit\b", "press End"),
    (r"\bpressed submit\b", "pressed End"),
    (r"\bsubmit may be pressed twice\b", "End may be pressed twice"),
    (r"\bsubmit also refreshes\b", "End also refreshes"),
    (r"\bsubmit scores every incomplete line\b", "End scores every incomplete line"),
    (r"\bwhen submitted\b", "when it scores"),
    (r"\bsubmitting\b", "scoring"),
    (r"\bsubmitted\b", "scored"),
    (r"\bsubmits\b", "placements"),
    (r"\bsubmit\b", "placement"),

    # ---- round -> show (the innocent senses are excluded by the word after it) -------
    (r"\bend of round\b", "end of show"),
    (r"\bonce per round\b", "once per show"),
    (r"\bper round\b", "per show"),
    (r"\beach round\b", "each show"),
    (r"\bevery round\b", "every show"),
    (r"\bthe next round\b", "the next show"),
    (r"\bof the round\b", "of the show"),
    (r"\bthe round number\b", "the show number"),
    (r"\b(\d+) rounds\b", r"\1 shows"),

    # ---- blind -> level, ante -> lap -------------------------------------------------
    (r"\bboss blinds?\b", "boss level"),
    (r"\bbig blinds?\b", "level"),
    (r"\bsmall blinds?\b", "level"),
    (r"\bwhen blind is selected\b", "when a level is entered"),
    (r"\bblind is selected\b", "a level is entered"),
    (r"\bblind is defeated\b", "a level is beaten"),
    (r"\bblinds\b", "levels"),
    (r"\bante (\d+)\b", r"lap \1"),
    (r"\beven antes\b", "even laps"),
    (r"\beach ante\b", "each lap"),
    (r"\bevery ante\b", "every lap"),
    (r"\bthis ante\b", "this lap"),
    (r"\bthe ante\b", "the lap"),
    (r"\bantes\b", "laps"),

    # ---- the retired board ------------------------------------------------------------
    (r"\bthe upper zone\b", "the Entrance"),
    (r"\bupper zone\b", "the Entrance"),
    (r"\bthe lower zone\b", "the grid"),
    (r"\blower zone\b", "the grid"),
    (r"\bthe tableau\b", "the grid"),
    (r"\btableau\b", "grid"),

    # ---- a held hand, which the Entrance replaced -------------------------------------
    (r"\bcards in hand\b", "cards in the Entrance"),
    (r"\bcards? in your hand\b", "cards in the Entrance"),
    (r"\bhand size\b", "Entrance width"),
    (r"\bheld hand\b", "the Entrance"),
    (r"\bdiscards? per round\b", "discards per show"),
    (r"\bdiscards? each round\b", "discards each show"),
]

COMPILED = [(re.compile(p, re.I), r) for p, r in RULES]

def rewrite(s):
    if not s:
        return s, 0
    n = 0
    for rx, rep in COMPILED:
        s, k = rx.subn(lambda m: _case(m, rep), s)
        n += k
    return s, n

def _case(m, rep):
    out = m.expand(rep)
    return out[0].upper() + out[1:] if m.group(0)[:1].isupper() and out[:1].islower() else out

# residue: what a table cannot fix
RESIDUE = re.compile(
    r"\bacts?\b|\bsubmit\w*\b|\btableau\b|\bantes?\b|\b(upper|lower)\s+zone\b", re.I)
# `act` as a circus PERFORMANCE is legitimate and must survive
INNOCENT = re.compile(
    r"\b(vanishing|tall|silent|rings|hard|opening|closing|circus|side|main|solo|duo|troupe|"
    r"aerial|clown|animal|magic|balancing|juggling|trapeze|strong)\s+acts?\b|\bacts? as\b|"
    r"\bcards act\b|\bplayers act\b|\bact of\b|\bact like\b", re.I)

def scan_residue(s):
    if not s:
        return []
    return [m.group(0) for m in RESIDUE.finditer(INNOCENT.sub("", s))]


# ⚠ AN EFFECT'S NAME IS ITS SORT KEY, AND THE QUESTION ID IS POSITIONAL.
# `render.py` numbers questions by walking rows sorted on (family, class, name.lower()), so
# renaming an effect MOVES it and silently renumbers every question after it — repointing every
# recorded answer at a different effect. Measured: rewriting names moved 7 questions in class
# A14 alone. So names are never touched here; `order_check.py` proves it after every run.
ROW_HEAD = re.compile(r'^\((\s*"[EG]\d+"\s*),(\s*"[^"]*"\s*),')

def patch_py(path):
    """Rewrite quoted design prose in a variants/generated/decisions module.

    Skips comments, and skips the NAME field of a `generated` row (see above).
    """
    src = io.open(path, encoding="utf-8").read()
    out, total = [], 0
    for line in src.split("\n"):
        if line.lstrip().startswith("#"):
            out.append(line)
            continue
        head = ROW_HEAD.match(line.strip())
        if head:
            # rewrite everything AFTER the name, leave `(eid, name,` byte-identical
            keep = line[:line.index(head.group(0)) + len(head.group(0))]
            tail, n = rewrite(line[len(keep):])
            total += n
            out.append(keep + tail)
            continue
        line, n = rewrite(line)
        total += n
        out.append(line)
    if total and not DRY:
        io.open(path, "w", encoding="utf-8", newline="\n").write("\n".join(out))
    return total


# corpus.tsv is the MINING RECORD. `source`, `origin` and `eid` are provenance and are never
# touched; only the two fields the owner actually reads are re-expressed for the grid.
# ⚠ `name` is the SORT KEY (see ROW_HEAD above) and is never rewritten.
# ⚠ `mechanic_grid` in batches/tagged*.tsv is the OTHER blurb source and was missed on the first
# pass: render.py prefers it over corpus.tsv's `mechanic`, so 32 questions kept their retired
# wording while corpus.tsv read clean. Found by the architecture review, not by the sweep.
CORPUS_FIELDS = ("mechanic", "mechanic_grid")

def patch_tsv(path):
    rows = list(csv.DictReader(io.open(path, encoding="utf-8"), delimiter="	"))
    fields = list(rows[0].keys()) if rows else []
    total = 0
    for r in rows:
        for f in CORPUS_FIELDS:
            if f in r:
                r[f], n = rewrite(r[f])
                total += n
    if total and not DRY:
        with io.open(path, "w", encoding="utf-8", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=fields, delimiter="\t", lineterminator="\n")
            w.writeheader()
            w.writerows(rows)
    return total


if __name__ == "__main__":
    files = (sorted(glob.glob(os.path.join(HERE, "variants", "v*.py")))
             + sorted(glob.glob(os.path.join(HERE, "generated", "g*.py")))
             + sorted(glob.glob(os.path.join(HERE, "decisions", "d*.py")))
             + [os.path.join(HERE, "corpus.tsv")]
             + sorted(glob.glob(os.path.join(HERE, "batches", "tagged*.tsv"))))
    grand = 0
    for p in files:
        n = patch_tsv(p) if p.endswith(".tsv") else patch_py(p)
        grand += n
        if n:
            print("  %-26s %d rewrite(s)" % (os.path.relpath(p, HERE), n))
    print("total rewrites: %d%s" % (grand, "  (DRY RUN, nothing written)" if DRY else ""))
