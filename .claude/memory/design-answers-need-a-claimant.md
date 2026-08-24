---
name: design-answers-need-a-claimant
description: An answered design question that no plan step cites is invisible to every tool — check nodes→steps, not just steps→nodes, or answers get read and never implemented
metadata:
  type: feedback
---

**Reading the whole design does not make you implement it.** Measured on the spotlight design:
**255 answered questions, 65 cited by a plan step, 190 cited by none.** One of the 190 fixed a
circle's centre on the card's ART-SQUARE centre; it was read in-session, the code centred on the
card's origin, and it shipped wrong through three phases and two by-eye reviews.

**Why:** every check validated **steps → nodes** (every citation resolves, no step cites nothing).
Nothing validated **nodes → steps**, so an answer no step claimed was invisible to the toolchain.

⚠ **The failure mode is BINDING, not reading.** An answer read at session start and a contract
written an hour later are not connected by anything. Re-reading a 2400-line design is not the
mechanism. **A check that fails is.**

⚠⚠ **MEASURED AGAIN ON COMPARATOR BUCKETS — AND THAT ONE PROVES THE CHECK IS NOT ENOUGH.** An answer
requiring *every* situation to get a deny/allow pair shipped with its four hooks **declared,
documented, and never dispatched by anything in production**. **`unclaimed` was 0 throughout**: the
plan step cited that answer from the day it was written, while its body said only *"add the hook
names"*.

> **A citation is a CLAIM, not a proof. `unclaimed` finds answers nobody claimed — it cannot find
> an answer someone claimed and half-built, and no tool in the repo can.**

Two corollaries:
- **Cite narrowly.** A step that declares names cites the question about names. If a question says
  "every situation gets X", its claimant is the step that makes X *happen* everywhere — and if no
  step does, leave it uncited so the check can see it.
- **A question containing "every", "all", "each" is an ENUMERATION.** Write down the list it
  quantifies over and check the list. That one's list was three long and two were wired.

⚠ **Do not record "we forgot to run the check" when the check was green** — that teaches the next
session to trust the exact instrument that missed it.

**How to apply:**

1. `npm --prefix designloop run check` reports **`unclaimed`** — answered questions no step
   implements, free-text overrides first (they carry the requirements nobody transcribed). Triaged
   ids go in `<design>/implements-nothing.txt`, one per line, so the list converges on zero rather
   than being ignored wholesale. Never a hard error: many answers are scope or rationale.
2. **When a design has a TABLE of things that must exist** (a knob list, a uniform list, a rename
   map), write a test that reads the DESIGN DOCUMENT and asserts each row resolves in code.
   `test_fx_attachment.gd::test_the_design_16_knob_table_is_implemented` does this — it found 13
   missing knobs on its first run, after three phases of "specified".
3. **A skip list must carry the REASON per entry**, naming the step that will implement it or the
   answer that retired it. An entry is DELETED when its step lands, which is what turns the check
   on. A bare skip list is the original defect wearing a test's clothes.
4. Writing a line that decides a number, a position or a name? **Grep the design for that concept at
   that moment.** The up-front read is necessary and not sufficient.

⚠ **A CLAIM IS MADE IN `PLAN.md`, NEVER IN THE CODE.** The wrong way to bind an answer is to write
its id into a comment or an Inspector label: it satisfies nothing the checker reads and leaks the
design conversation into a layer that outlives it. See [[design-ids-stay-out-of-code]].

⚠ **Related but distinct:** an answer *stranded by a gate* (`active:false`, never restored) is also
invisible and needs its own check — strand events in `answers.log`, not citation coverage. That one
lives in the `/flowchart-design` skill, beside the widening rule it belongs to.
