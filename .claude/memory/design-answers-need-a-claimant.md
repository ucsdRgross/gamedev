---
name: design-answers-need-a-claimant
description: An answered design question that no plan step cites is invisible to every tool — check nodes→steps, not just steps→nodes, or answers get read and never implemented
metadata:
  type: feedback
---

**Reading the whole design does not make you implement it.** Measured on the Solatro spotlight
design: **255 answered questions, 65 cited by a plan step, 190 cited by none.** `Q85` —
*"Radius 16 art units, centred on the card's ART-SQUARE centre"* — was one of the 190. It was read
in-session, then the code centred the circle on the card's origin, and it shipped wrong through
three phases and two by-eye reviews before the owner spotted it on a stacked board.

**Why:** every designloop check validated **steps → nodes** (every citation resolves, no step cites
nothing). Nothing validated **nodes → steps**, so an answer no step claimed was invisible to the
whole toolchain, and therefore to the agent executing the plan.

⚠ **The failure mode is BINDING, not reading.** An answer read at the start of a session and a
contract written an hour later are not connected by anything. The design is 2400 lines; re-reading
it is not the mechanism. **A check that fails is.**

⚠⚠ **MEASURED A SECOND TIME ON COMPARATOR BUCKETS — AND THAT ONE PROVES THE CHECK IS NOT ENOUGH.**
`Q83`(a) — *every* situation gets a deny/allow pair — shipped with the four `on_stack_*` hooks
**declared, documented, and never dispatched by anything in production**, move legality still
calling the ORDERING hook it was supposed to stop using. **`unclaimed` was 0 throughout.** It could
not have caught it: `PLAN.md`'s `S3` cited `Q83` from the day the plan was written, while its body
said only *"add the hook names"*. The answer had a claimant; the claimant implemented a third of it.

> **A citation is a CLAIM, not a proof. `unclaimed` finds answers nobody claimed — it cannot find
> an answer someone claimed and half-built, and no tool in the repo can.**

Two corollaries, both cheap:
- **Cite narrowly.** A step that declares names cites the question about names. If a question says
  "every situation gets X", the step that satisfies it is the one that makes X *happen* at every
  situation — and if no step does that, leave it uncited so the check can see it.
- **A question containing "every", "all", "each" is an ENUMERATION.** Write down the list it
  quantifies over and check the list, the way rule 2 below does for design tables. `Q83`'s list was
  three situations long and two of them were wired.

⚠ **Do not record "we forgot to run the check" when the check was green** — that teaches the next
session to trust the exact instrument that missed it.

**How to apply:**

1. `npm --prefix designloop run check` now reports **`unclaimed`** — answered questions no step
   implements, free-text overrides ranked first (they carry the requirements nobody transcribed).
   Triaged ids go in `<design>/implements-nothing.txt`, one per line, so the list converges on zero
   rather than being ignored wholesale. Never a hard error: many answers are scope or rationale.
2. **When a design has a TABLE of things that must exist** (a knob list, a uniform list, a rename
   map), write a test that reads the DESIGN DOCUMENT and asserts each row resolves in code. Solatro's
   `test_fx_attachment.gd::test_the_design_16_knob_table_is_implemented` does this against §16 —
   it found 13 more knobs missing on its first run. §16's `FxSpotlightStyle` had been "specified" for
   three phases while `light.gdshader` declared 13 look uniforms and the layer pushed six.
3. **A skip list must carry the REASON per entry**, naming the step that will implement it or the
   answer that retired it (`PENDING_16`). An entry gets DELETED when its step lands, which is what
   turns the check on. A bare skip list is the original defect wearing a test's clothes.
4. Writing a line that decides a number, a position or a name? **Grep the design for that concept at
   that moment.** The up-front read is necessary and not sufficient.

⚠ **Related but distinct:** an answer *stranded by a gate* (`active:false`, never restored) is also
invisible and also needs a mechanical check, but it is a different query — strand events in
`answers.log` vs citation coverage in `PLAN.md`. Both bit this project inside one week; that one
lives in `.claude/skills/flowchart-design/SKILL.md`, beside the widening rule it belongs to.
