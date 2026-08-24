---
name: seam-checks-not-rereading
description: Every recurring miss on this repo is one shape — two representations of one fact with nothing comparing them; write the comparison when the second representation is created, not after it bites
metadata:
  type: feedback
---

**When a fact gets a SECOND representation, write the check that compares them — at that moment,
not after it bites.** Re-reading does not work; it has demonstrably not worked eight times.

## The measurement

Every gap filed on the spotlight stream, plus every non-gap miss in its review, fits one table: two
places that had to agree, and a third column that always read *nothing*. A chart's polarity vs a
plan's default; an answer vs the code; a doc's knob table vs the shipped properties; an exit code
vs the pixels; a still frame vs movement over time; a tool's `--shoot-all` vs its `--verify`.

⚠ **NOT ONE was "the agent did not read it".** Two were read in-session and contradicted an hour
later. **The failure is BINDING, not reading** — a 2400-line design re-read at session start binds
nothing to the line of code written later.

⚠ **The two things that disagree are almost always of DIFFERENT KINDS.** Same-kind disagreements get
caught, because one tool reads both. Cross-kind ones survive indefinitely because no single tool
reads both representations, so the contradiction has nowhere to surface.

## How to apply

1. **Create a second representation → write the comparison in the same commit.** A knob table in a
   doc? The test asserting each row resolves ships with it.
2. **Better: delete the second representation.** The best seam check is no seam — one
   `FxSpotlightStyle` property beats a `const` plus a doc row.
3. **Precedent here:** `test_the_design_16_knob_table_is_implemented` (doc table ↔ properties), the
   glow/light uniform-seam tests (style writes ↔ shader declares), `designloop check`'s `unclaimed`
   (answers ↔ plan steps), the engine-error scan (stderr ↔ suite banner), `doc_check.py`
   (docs ↔ disk).
4. **An answer stating BOTH a mechanism and a reason is two representations.** "Nearest" *because*
   "non-crossing" — on a column the mechanism defeats the reason. Check the mechanism still produces
   the reason in the case at hand.

## A rule stated with an EXAMPLE is two representations

⚠ The example and the general rule can differ. A fan described for one column
(*"middle of top gets first `-1-`, 2nd row gets `-212-`"*) admits "partition by ROW", which
reproduces the example exactly and is wrong for every other shape — on interleaved depths it
inverted the x order. The right reading was "partition by COLUMN, fan by depth inside each".

⚠ **Testing the shapes the rule was DESCRIBED with proves nothing: every candidate reading agrees on
those.** Write down which readings you were choosing between, and test the input that separates them
— the case the example does not cover.

## Evidence hierarchy

**green suite < printed counts < a rendered pixel < movement measured over time.**

⚠ **[[verify-visuals-by-eye]] is necessary and NOT sufficient.** A still cannot show a pulse, a
travel, a retire, or a cascade that never advances — a still of a working loop and of a dead one are
identical. Three misses in one session were invisible to a PNG by construction. **Anything with a
DURATION needs an instrument that samples over time**, reporting what MOVED
(`sections=4/4 show_flips=14 max_dim=0.75`), not that it did not crash.
