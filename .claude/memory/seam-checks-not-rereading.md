---
name: seam-checks-not-rereading
description: Every recurring miss on this repo is one shape — two representations of one fact with nothing comparing them; write the comparison when the second representation is created, not after it bites
metadata:
  type: feedback
---

**When a fact gets a SECOND representation, write the check that compares them — at that moment, not
after it bites.** Re-reading does not work and has now demonstrably not worked eight times.

## The measurement

Every gap filed on [[solatro-spotlight-design]] plus every non-gap miss in the 2026-08-04 session
fits one table. The columns are two places that had to agree; the last column is always the same.

| Miss | Representation A | Representation B | Compared by |
|---|---|---|---|
| GAP-001 | chart A8's polarity | `PLAN` §1.4's default | nothing |
| GAP-003 | chart O11's premise | `Q134`/`Q135`/`Q214` | nothing |
| GAP-004 | `Q73` dims the HUD | `Q74`–`Q76` exempt things above it | nothing |
| GAP-005 | `Q246` filters the CUE | `Q16`/chart E drive the BEAM | nothing |
| GAP-006 | `QR2`=(d) | `Q16`'s free text, `Q82` stranded | nothing |
| GAP-007 | `Q176` (form) | `Q174`/`Q175` (fidelity) | nothing |
| GAP-008 | `Q111`'s mechanism | `Q111`'s own stated rationale | nothing |
| `Q85` | the answer | `SpotlightDirector`'s code | nothing |
| §16 knob table | the design table | the shipped properties | nothing |
| column reveal | chart D4, `Q46`, `Q52` | an invented `return -1` | nothing |
| blank PNG ×2 | exit code 0 | the pixels | nothing |
| dead cascade | a still frame | movement over time | nothing |
| tool disagreement | `--shoot-all` | `--verify` | nothing |

⚠ **NOT ONE of these is "the agent did not read it".** `Q85` and §16 were both read in-session and
then contradicted an hour later. The failure is **binding**, not reading — and a 2400-line design
re-read at session start binds nothing to the line of code written later.

## The sub-pattern that explains why they survive review

⚠ **The two things that disagree are almost always of DIFFERENT KINDS.** A chart vs an answer, a doc
table vs a property list, an exit code vs a pixel, an answer vs its own rationale. **Same-kind
disagreements get caught** — two answers that conflict are noticed, because one tool reads both.
Cross-kind ones survive indefinitely because **no single tool reads both representations**, so there
is no place the contradiction can surface.

## How to apply

1. **At the moment you create the second representation, write the comparison.** Adding a knob table
   to a doc? The test that asserts each row resolves goes in the same commit. Adding a tool that
   mirrors shipped behaviour? The assertion that both use one source goes in with it.
2. **Prefer deleting the second representation.** The best seam check is no seam: `circle_radius` as
   a `const` AND a §16 row was two truths; one `FxSpotlightStyle` property is one. `CardVisual.
   spotlight_center()` beats an offset copied into the director.
3. **Existing seam checks on this repo, as precedent** — `test_the_design_16_knob_table_is_implemented`
   (doc table ↔ properties), the glow/light uniform-seam tests (style writes ↔ shader declares),
   `designloop check`'s `unclaimed` (answers ↔ plan steps), `dag audit` and `stale` (answers ↔
   charts), G1.7 (headless ↔ windowed logs), the engine-error scan (stderr ↔ the suite banner).
4. **An answer that states BOTH a mechanism and a reason is two representations.** `Q111`=(a) said
   "nearest" *because* "non-crossing", and on a column the mechanism defeats the reason. When
   implementing, check the mechanism still produces the reason in the case at hand — GAP-008.

## The variant that bit twice in one day: a rule stated with an EXAMPLE

⚠ **When a rule arrives with a worked example, the example is one representation and the general rule
is another — and they can differ.** GAP-008: the owner's fan was described for a single column
(*"middle of top gets first `-1-`, 2nd row gets `-212-`"*). I implemented "partition the bar by ROW",
which reproduces the example exactly and is wrong for every other shape; on a set with depths
interleaved across columns it inverted the x order and produced three crossings. The correct reading
was "partition by COLUMN, fan by depth inside each".

⚠ **The test did not catch it because I tested the two shapes the rule was DESCRIBED with — a column
and a row — and both readings agree on those.** Only an interleaved set separates them, and that was
the one case with no test. **When implementing a rule from an example, the test that matters is the
case the example does not cover**; write down which readings you were choosing between, and test the
input that tells them apart.

## The evidence hierarchy, and the part that is new

**green suite < printed counts < a rendered pixel < movement measured over time.**

⚠ **[[verify-visuals-by-eye]] is necessary and NOT sufficient: a still frame cannot show a pulse, a
travel, a retire, or a cascade that never advances.** Three misses in one session were invisible to a
PNG by construction — the per-section pulse, the retire beat throwing every frame, and a cascade
stuck on section 0 — because a still of a working loop and a still of a dead one are identical.
**Anything with a DURATION needs an instrument that samples over time**, and it should report what
MOVED (`sections=4/4 show_flips=14 max_dim=0.75`) rather than that it did not crash.
`Tools/spotlight_tool.tscn -- --verify` is this repo's example.
