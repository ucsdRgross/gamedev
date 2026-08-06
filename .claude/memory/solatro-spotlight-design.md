---
name: solatro-spotlight-design
description: solatro/design/spotlight/DESIGN.md (started 2026-08-01, version 6 on 2026-08-03) is a DESIGN-ONLY flowchart plan for the Spotlight mechanic + its VFX — nothing is implemented until every node and question is approved
metadata: 
  node_type: memory
  type: project
  originSessionId: c2e12eb4-4da5-425b-b1c7-49fb8ac3a906
  modified: 2026-08-01T12:18:13.757Z
---

`solatro/design/spotlight/DESIGN.md`, written 2026-08-01 via [[repo-claude-tooling]]'s
`/flowchart-design` skill. **Design CONFIRMED 2026-08-03; `PLAN.md` is the execution spec and §1 of
it is normative.**

⚠ **ALL FOUR PHASES ARE BUILT — every step S1–S18 is done (2026-08-06), suite green (29 suites);
check git status for what is committed.** Gates G3.1, G3.2, G2.3 and (2026-08-06 review pass) G3.3
closed; **G2.2 is the owner's eye**. A same-day review fixed ten confirmed defects — the fixes and
their reasoning are `design/spotlight/ASSUMPTIONS.md` (2026-08-06 entries) — and opened
**GAP-010/GAP-011** (overrun banking; emptied-section hooks), which need the owner. Live status is
`solatro/HANDOFF_spotlight.md`.
⚠ **FIFTEEN DEFECTS WERE FOUND AND FIXED ON 2026-08-05/06, EVERY ONE GREEN IN THE SUITE WHEN IT
SHIPPED, AND MOST FOUND BY THE OWNER LOOKING AT THE SCREEN.** Their forensics and the recurring shapes
are `solatro/ARCHITECTURE_REVIEW.md` **§9** — read it before trusting any similar claim. The shapes:
two representations of one fact (a tool and the game reaching the allocator/settings by different
routes); **independent envelopes on one visual** (`fade * _show` — three separate bugs, none visible in
either factor alone); fixtures that could not express the case they claimed to test (S16 "verified" on
a board one card deep); assertions measuring an intermediate instead of the claim; and rendering that
never reached a pixel (a zero-sized `ColorRect`, a `SubViewport`'s own LINEAR filter).
⚠ **GAP-009 — the row opening is a KNOB, not a derivation.** `spotlight_separation_mode`:
`CARD_HEIGHT` (pitch = one card) or `JUMP_ADJUSTED` (card − separation − jump rise). Both branches
return a TOTAL pitch; `row_open_extra()` subtracts the container's `separation` to get the strip.
⚠ **S16 and S17 are ONE change** — `slot_center_global` is uniform-pitch maths every prop anchors to.
⚠ **S15's cue is reachable only via `Cards/Skills/spotlight_probe.gd`** + the debug bar's **Cue**
button: `spotlight_cued` is `Q246`-filtered to skills implementing `on_spotlight` and the only shipped
one is a RULES card with no `CardVisual`. **Do not "fix" that by unfiltering — it recreates GAP-005.**
⚠ **`Tests/Visual/reveal_shot.tscn` is the ONLY instrument that shows the reveal in a real `GameView`**
— the tuning tool draws its own simulation and has no `PlayArea`.
⚠ **THE OWNER JUDGES EVERY VISUAL THROUGH THE TUNING TOOL** — *"I would rather do all testing via the
planned editor so dont ask me to check until it exists"*. **It exists**: `solatro/Tools/spotlight_tool.tscn`
(`@tool` + inspector, scenarios as JSON data, the old `spotlight_trace` merged in as `-- --trace`,
and `-- --verify` which runs every preset and reports what MOVED). Do not ask them to run the game or
open a snapshot instead. See [[verify-visuals-by-eye]].
⚠ **v10's real lesson is a workflow one, recorded in [[design-round-read-the-log]]: GAP-006's answer
had been given in round 1 and a gate stranded it.** `Q82`'s override — *"per anytime spotlight effect
is happening"* — went `active:false` at `answers.log` seq 269 and was never restored when the section
heading was widened, so an act-long dim shipped that nobody chose. `check` cannot detect this.
What shipped: `active` → **`spotlit`** everywhere (`is_spotlit`, `skill_spotlight_check`,
`on_spotlight`/`on_unspotlight`), `GameData.forced_spotlight` (per-act, NOT `@export_storage`, never
bumps `revision`), `ScoringSection` (`Scripts/scoring_section.gd` — the shape-agnostic "one scorer
invocation's cards", re-read after every hook), and `score_line` now RE-EVALUATES the hand over the
live section, so a synthetic `Scoring.Result` passed in for a populated zone is discarded.
**The rulings that shape the code, all folded in:** `blocks_spotlight()` defaults **true** (a covering
card hides the talent beneath; Kuroko overrides to false; Revealing is a property of the card itself),
and the seam REPLACES `is_data_topmost`. `forced_spotlight` **moves with the scoring section, never
accumulates**. **Two signals, and conflating them is GAP-005**: `spotlight_section_changed` carries
the scored section UNFILTERED and feeds the beam; `spotlight_cued` is `Q246`-filtered to skills with
an `on_spotlight` hook and is the momentary cue's alone. **The show PULSES PER SECTION** — visibility
(`LightLayer._show`, driven by `spotlight_reveal_ended`) is an axis separate from the light SET, and
the lights are never freed by the fade, because chart E has to travel from them.

⚠ **§17 is a branching DAG, not a list.** Measured by the parser, **version 6 (2026-08-03): 275 live
questions, 30 `⚑gate` (all 30 gating questions marked), 19 charts, 0 errors/warnings.** (v1 was 195
live / 8 roots.) Every question carries a gate in backticks (`[Q4=b|c]`), lettered
options, and a recommended default so *default* is a complete answer. Q140 is retired in place —
**IDs are never renumbered.**

**What the answers settled, and it re-frames the feature** — read §0a of the doc before anything:
**the GLOW is the point** (Q83: *"the glow is most important. Beam and circle and dim are helper"*);
**spotlight is a general "this card became active" cue, not a scoring feature** (Q149=b), so scoring
is one caller; **the dim follows the BEAMS** (QR2=d), not the submit. Scope grew too: `active` is
renamed to `spotlight` (Q2=b), the card-description icon is in (Q5/Q184=b), the board-spread toggle
is in (Q186), and **the full film pipeline is in as a SECOND deliverable shipped after Spotlight**
(QR10=a, Q239=a). ⚠ **Q265=(c) means the existing scoring animation does NOT change** — only the
meld jumps, as today; the wider lit set is carried by the spotlight alone.

**Version 2 existed because two round-1 answers were written in the owner's own words**, one at a
`⚑gate`. Both became real options rather than replacing anything, and the §17.6 gates were widened
so answers already given survived the switch:

- **QR2 — settled at (d), not (c).** (c) the TRANSIENT dim was v2's authored branch (chart S,
  §17.6b, kept); the ANSWER is **(d) the dim follows the spotlight — active if there are BEAMS**,
  which is what Q45/Q82/Q150/Q16 all described. ⚠ Adding (d) without widening §17.6's **section
  heading** gate stranded 20 answers when it was clicked — see [[design-round-read-the-log]].
- **Q24 (c) — COMPACT AND FOLLOW.** A meld card discarded mid-line: the column closes up (free — a
  column is a plain array, `game.gd:613`), the covering card slides into the slot, and the light
  follows the SLOT and force-spotlights the new occupant. Chart R, §17.2b. Q160 said the opposite
  and is re-gated.
- Plus a glow-shader braindump → **QR9** (is the spotlight circle drawn by the glow shader, and does
  it move onto the card?) and **QR10** (the halation/bloom/LUT/grain film pipeline — in scope?).

⚠ **Chart naming drifted and is now pinned.** Charts A–L were named by heading while their node
prefixes ran one letter ahead from §7 on (heading *Flowchart G* holds nodes `H1…`). v2 charts are
named by their own prefix (O, P, R, S). The prefix is the truth.

Why it exists: the previous cycle (the FX editor) shipped from a plan that was not thorough
enough, so design decisions got made silently during implementation. Owner's bar: *"what I
describe in review of plan will have functionally no difference once implemented."*

Load-bearing facts the plan is built on, worth keeping even if the doc is deleted:

- **Spotlight already existed as `active`, and is now `spotlit`.** `CardModifier.is_spotlit()` —
  rules card / StampGlobal / stage PLAY or ZONE / `forced_spotlight` / StampRevealing / else
  **is anything above me blocking** (`blocks_spotlight`, default true — this REPLACED
  `is_data_topmost`, identically). Only SKILLS are gated on it
  (`run_all_mods` fires type/stamp/status hooks with no spotlight check at all).
- ⚠ **A new `class_name` script does NOT resolve until the class cache is rebuilt.** Running the
  suite straight after adding one gives *"Could not find type X"* parse errors that cascade into
  dozens of unrelated failures. Fix: `<godot> --headless --path solatro --import` once. The owner's
  editor does it by itself; a headless-only session does not.
- **Board geometry:** a column is a VBox, a row is a child index across VBoxes; higher `z` draws
  later, sits lower and covers. A covered card shows only its top ~45 px of 125, and the card's
  32×32 art square is CENTRED, so a spotlight circle on a covered card is ~75% hidden — which is
  why the row must expand first.
- **Reveal precedent already ships:** held-stack expansion sets the control above the grabbed card
  to the full card size. Same operation.
- **`PlayArea.slot_center_global` is pure uniform-pitch math** and every prop anchors to it — any
  per-row expansion breaks it. Row score gutters must expand with their rows too.
- The two questions that restructure everything: **Q31** (is the spotlight set the whole line or
  just `result.meld`?) and **Q113** (beam origins screen-anchored vs content-anchored — the
  braindump contains both readings).
- **The glow needs almost no new machinery, and §1.6 has the audit.** `FxAttachment` IS a `Node2D`
  any host parents, so "a glow for cards and props" is one `.gdshader` + an `FxGlowStyle` SUBCLASS
  (never knobs on the `FxStyle` base) + a request. `FxRequest.reach` already lets an effect hang off
  the card's edge. **"Can overlap object pixels unlike the fire shader" is literally
  `u_inner_alpha < 1`** — an existing uniform no shipped style uses, because the owner ruled seeing
  art through flame *"looks very bad"*.
- ⚠ **There is NO screen read anywhere in this project** (grepped 2026-08-03: zero
  `SCREEN_TEXTURE` / `hint_screen_texture` / `BackBufferCopy` / viewport-texture hits outside
  `addons/`). So halation, bloom, film LUT, chromatic aberration, gate weave, dust and HDR
  tonemapping are a full-screen subsystem that does not exist and would change the WHOLE game's
  look — that is why they are QR10 and not a shader detail. Multi-layer glow, inverse-square
  falloff and the core→mid→edge colour shift need none of it (the shift is one `PaletteRamp`
  sample, which is what the palette contract wants anyway).

See also [[solatro-game-view-split]], [[solatro-structural-layering]],
[[solatro-pooled-board-controls]], [[solatro-tuning-knobs-in-settings]].

⚠ **THE ONE LESSON THAT OUTLIVES THIS FEATURE — see [[seam-checks-not-rereading]].** All eight gaps
and every non-gap defect are one shape: **two representations of one fact with nothing comparing
them**, and the surviving ones are always CROSS-KIND (chart vs answer, doc table vs property list,
exit code vs pixels). It is not a reading failure — `Q85` and §16 were both read in-session and
contradicted an hour later. Checks added: `designloop check`'s `unclaimed` (190 of 255 answers were
implemented by no plan step), a test that parses `DESIGN.md` §16 and asserts each knob exists, and
`Tools/spotlight_tool.tscn -- --verify`, because a still frame cannot show a pulse or a dead cascade.
