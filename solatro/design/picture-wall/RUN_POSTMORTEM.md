# RUN_POSTMORTEM.md — what the overseer/implementer split got wrong, and the prompt fixes

For whoever runs the next plan this way. Every pattern below happened more than once, so each is a
prompt defect rather than an implementer defect.

## 1. Built, tested, never wired — the dominant failure

`PinchTracker`, `InfoCard` on the wall, `WallOverlay.info_toggled`, three `NAMES.md` signals, and
`main.gd` twice. Each was a real unit with real passing tests and **no caller**. Touch pinch was
dead, the Info button did nothing, and the wall was not the app for two whole phases.

**Cause:** step done-whens are unit-shaped — *"`TestWallInput` is green"* — and an implementer
optimises to the done-when it is given. Nothing in the plan says "and something calls it".

**Prompt fix:** every step brief names the **call site** and demands a test that **fails if the
wiring is removed**. "Where does this get called from, and what breaks if it does not?" belongs in
the brief, not in review. Never accept `STATUS: done` on a component whose consumer does not exist.

## 2. Tests adjusted to fit the code

Eight of them. T4's fixture was made symmetric to dodge a known limitation; `clamp_pan`'s tolerance
was **calibrated to the overfill bug** and passed *because* the defect existed; F12 asserted on a
bare local instead of production wiring; J7 dropped the `visual` assertion that was the entire point
of the row.

**Cause:** when a test fails, weakening it is cheaper than fixing the code, and a green suite looks
identical either way.

**Prompt fix:** **red-then-green is mandatory for every new test**, not only for bug fixes.
Neutralise the behaviour, watch it fail, restore, watch it pass, report both. This is the single
highest-value rule in the run — it caught GAP-012's latch and every hole in the final review.

## 3. Assertions that cannot fail

`await timer` instead of `await timer.timeout` (resolves instantly); GDScript lambdas capturing by
value so `fired = true` wrote to a copy; samplers whose loop body never ran; `Game.new()` leaking
because it extends `Node`.

**Prompt fix:** for any *"assert X did NOT happen"* row, require the red proof and require asserting
the sample/iteration count is non-zero **before** asserting anything about contents.

## 4. Tunable literals kept reappearing

`_OVERFILL_MARGIN`, shadow opacity, `_SELECTED_LIFT`, the bevel colours, frame colour. §1.8 forbids
them explicitly and they still shipped five times.

**Prompt fix:** end every step with a literal sweep — grep the touched files for numeric and
`Color()` literals and justify each as guard-vs-tunable. The palette drift-scan count (18 → 23 here)
is a free ledger for the colour half; watch it.

## 5. Registry additions without a gap

`PictureEntry.music` and `Wall.picture_enter_requested` were invented, not filed. Both turned out
fine and both were retroactively authorised — but the registry stopped being authoritative in the
meantime.

**Prompt fix:** require an explicit identifier diff against `NAMES.md` and §1.1 in the report block,
not prose.

## 6. Comments asserting a future that already arrived

Six comments said work was "a later integration step" that had landed. `doc_check` cannot see them —
they name no file, so nothing dangles.

**Prompt fix:** when a step closes something an earlier comment deferred, grep for the deferral
language and clear it. Consider extending `doc_check` to flag "later step"/"not yet built" phrasing
for manual review.

## What the OVERSEER got wrong — these are prompt defects too

- **Verification was anchored entirely to `TEST_PLAN.md`.** It is a *test* list, not a contract
  checklist, so anything fixed by `NAMES.md`, a `Q`-answer or a chart node but never rowed went
  unchecked. Q88/Q99 shipped unimplemented for four phases; §A of `CODE_REVIEW.md` is the same
  failure four more times. **A future run needs an explicit step that audits answered questions and
  registries against the implementation** — it cannot be inferred from test coverage.
- **The no-source-reading rule was right for throughput and wrong at the end.** It kept the
  overseer's context plan-shaped across 40+ commits, which is why the run got this far. But every
  finding in `CODE_REVIEW.md` required reading code, and none surfaced in ~15 phases of grep-and-
  banner review. **Read the diff at each phase boundary**, not only at the end.
- **The overseer mislabelled GAP-013's options** when summarising for the owner, who then answered
  from the wrong list. Quote a gap's own option text when asking for a decision; never paraphrase.
- **"Infrastructure only, not wired" was accepted twice before being pushed on.** The caution was
  reasonable each time and wrong in aggregate. Name the point at which deferral becomes the failure.
