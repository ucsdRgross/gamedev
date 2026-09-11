# TODO — open backlog (owner-endorsed unless marked otherwise)

Add new items here; **delete an item when it lands**, recording the regression-critical residue in
ARCHITECTURE_REVIEW.md rather than keeping a log here. Current-state facts live in
ARCHITECTURE_REVIEW.md; done-work history lives in git.

## Known intermittent test failures (not owned by any current work stream)

✅ **THE LOG-COPYING THIS SECTION ASKED FOR IS NOW AUTOMATIC.** `run_tests.py` copies the whole log
directory aside — to `<user data>/Solatro/logs-stalled-<stamp>` or `logs-failed-<stamp>` — before it
kills a stalled run or reports a failing one. `--stall-timeout` (default 600 s) also watches the test
log's SIZE as a heartbeat and NAMES the suite that started without finishing, instead of letting one
silent suite eat the whole budget and report `NO SUITE BANNER` for all 45.
⚠ **SO THE RULE IS NOW: DO NOT RE-RUN BEFORE READING THE PRESERVED LOGS.** The evidence survives one
occurrence, not two — the next run still truncates the LIVE log, and a preserved directory is only
written when a run stalls or fails.

- ⬜ **The suite intermittently HANGS — a third mode, distinct from the segfault and the leak.**
  Killed at the timeout with **no banner**, so it never reached its own verdict. ⚠ A hang is not a
  crash and not a failure count — the wrapper prints `NO SUITE BANNER` + `TIMEOUT` with both gates
  "clean" underneath, which skims as healthy. Where it stops: **30 of 39 suites banner and pass**;
  `PIXELS`, `OUTLINE`, `INTERACTION`, `WALL INPUT`, `WALL PAUSE` and the chain behind them never
  print. Every one of those completes cleanly when run ALONE, so it is in the concurrency, not in
  any suite's logic — suspect shared render/GPU state or an `await_siblings_except` race.
  **Clusters in time: 3 consecutive hangs, then a clean HEAD twice, then the same working tree
  twice — 3 hangs and 4 passes with no code difference between them.**
  ⚠ **So a hung run is NOT reliably attributable to the change that produced it.** Re-run before
  bisecting; each attempt costs ~7 minutes. (The one-fix-at-a-time working agreement used to say a
  hang IS the change's fault outright; it now carries this exception.)
  ⚠ **SEEN AGAIN IN THE 45-SUITE ERA, AND IT PREDATES THE GRID BRANCH** — so this is not
  poker-patience's. One occurrence in 13 full runs: `GRID VIEW` printed its banner and then emitted
  ZERO checks for 27 minutes until the global timeout. Six runs aimed straight at reproducing it
  produced none. **What the evidence narrowed it to, and it is stranger than the concurrency theory
  above:** `TestLog.line` flushes EVERY line, so the log is write-through and its last line is the
  last line reached. The next statement after that banner is another `TestLog.line` that never
  appeared — so the stall sits between two consecutive log writes, in a window with no loop, no
  await and no branch, while the process burned a full core. ⚠ Two confident explanations were
  written down and both were WRONG: `GRID VIEW` has no concurrent siblings (every suite it excludes
  waits for IT), and every wait on its path is bounded. Do not re-derive either.
- ⬜ **Godot intermittently SEGFAULTS during final teardown**, after the banner and log paths print
  normally. Still unattributed — likely the exit-time leak's family, objects surviving into
  `cleanup()`. ✅ `run_tests.py` no longer misreports it: an exit status outside 0..125 is not a
  failure count, so a crash is named as a crash rather than read as 125 failures under a banner
  saying PASSED. **One observation total; did not recur in 7 runs.**
- ⬜ **PIXELS' mask-vs-art check is intermittent, and it is NOT ruled on.**
  `t=0.00: at rest the mask and the drawn face agree exactly` fails with **0 mask-without-art,
  3773 art-without-mask** — the mask polygon is valid (the "hands its rig to the mask, vertex for
  vertex" check passes in the same run) but disagrees with the drawn art everywhere, which reads as
  the card's art captured at a different pose than `card.fx._poly` describes. Seen in 1 run of 3,
  then again later. Most likely a settle/capture race in `_real_card()`/`_shoot()`, not a bad bound.
  ⚠ **Do not widen the bound** — the test's own comment says DO NOT RAISE IT TO GO GREEN, and the
  owner's ruling on the rotated-ball rows deliberately did not cover this one.
- ⬜ **LEAK CANARY +1, intermittent.** Rate has moved: ~1 run in 6, then 0 in 8 after S23, now **0 in
  7 more**. ⚠ Not fixed — it once passed 6 consecutively before failing. The suite prints
  `_report_growth` on the failing run (node/resource/other split, plus a running-tween count — a
  `Tween` is RefCounted and self-sustaining, which fits every observed property), so the next
  occurrence explains itself if the log is kept.
  ⚠ The **exit-time** ObjectDB count is a different measure and **not** a regression: 4 before this
  work and 4 now.

## Doc hygiene backlog (code comments — measured, not yet triaged)

- ⬜ **`doc_check.py` scans code comments. Standing count over 304 source files: 5664 indented ·
  2144 long doc · 739 long block · 599 trailing · 362 design id · 130 dated · 91 history ·
  52 restated · 4 line refs.** Zero errors — every reference resolves.
  ⚠ **A BACKLOG, not a regression**, and the numbers grew mostly because THE CHECKER GOT STRICTER,
  not because the code got worse: `long block` went from "over 16 lines" to "over 3", and
  `long doc`, `indented` and `trailing` are new categories. The rules postdate the comments. Work
  it opportunistically — clean what you edit — rather than as one sweep. `--verbose` lists them.
  ⚠ **`dated` will not go to zero and should not**: many are measurements, where the date is part
  of the fact, and the checker cannot tell those from bookkeeping.
  ⚠ **`design id` is the one that matters most** — 362 citations of design documents the code's
  reader cannot open. It is a standing breach of the no-design-ids-in-code rule
  (ARCHITECTURE_REVIEW §8), inherited from earlier work streams.

## Waiting on the owner

- ⬜ **Run `design/board-plan/`** — confirmed and handed off (`PLAN.md`, `TEST_PLAN.md`, `NAMES.md`,
  and the `/plan-run` prompt in its handover). **Runs after `design/sidebar/`**, whose per-slot stocks
  it deals from. It retires two shipped rules when it lands (a talented card no longer suppresses its
  own suit effect; rank now pays into a meld) and its phase 6 refits the goal curve, which is the
  design's answer to `GAP-041`.
- ⬜ **Keep answering `design/effect-review/`** — every question was re-read against the live board
  and the confirmed designs; `build/_verdicts.tsv` has one verdict per question and `build/REVIEW.md`
  says how to change the build without renumbering recorded answers.

- ⚠ **`GAP-042` — a prop scoring a card in the ENTRANCE banks into a dead bucket.**
  `PropScoreProps`/`PropScoreTalents` use the legacy `ScoringSection.of_line` for an Entrance
  card, which leaves `grid == -1`, so `add_line_score` takes the legacy path into
  `scores_row_upper`/`row_total` — neither of which `live_total()` reads. The combo still bumps.
  **LATENT: no shipped content can put a prop on the Entrance row** (props spawn only from a
  scored meld, which is always a grid line), but `row_slot_path` has an explicit Entrance branch
  and the first effect that re-routes a prop there fires it. Three options in
  `design/poker-patience/gaps/GAP-042.md`; it is an owner call about whether the Entrance
  participates in the economy at all.

- ⬜ **Playtest the picture wall** — `HANDOFF_picture_wall.md` S40. Nothing else on that stream can
  be judged until someone drives it; two adversarial reviews traced journeys, neither played it.
- ⬜ **Picture wall: decide what unlocks `book`** — until it exists a whole subsystem is dead code
  ("Picture wall" below).
- ⬜ **Picture wall: rule on wall-view composition** at 16:9 and 32:9 — now judgeable live in
  `Tools/wall_editor.tscn` (F6), not only from snapshots ("Picture wall" below).
- ⬜ **Picture wall: playtest the shell** — navigate, resize, alt-tab, controller, Info. The only
  remaining gate; nothing about how it FEELS has been checked by anything.
- ⬜ **Playtest the universal palette** (below) — the fire and ball colours changed.
- ⬜ **Playtest the shader FX** (FX_SHADER_PLAN §10, 17 steps).
- ⬜ **Delete FX_SHADER_PLAN.md + FX_HANDOFF.md** once that playtest passes. Their residue is
  already folded into ARCHITECTURE_REVIEW §4g/§4h.
- ⬜ **Delete HANDOFF_comparator_buckets.md** once the comparator playtest passes. Its residue is
  already folded into ARCHITECTURE_REVIEW §3c. ⚠ Keep `design/comparator_buckets/` — plan steps and
  code comments cite its question IDs (`Q85`, `Q96`) and its three gap files.
- ⬜ **Spotlight: answer GAP-010 / GAP-011** (overrun banking; emptied-section hooks —
  `design/spotlight/gaps/`), **judge G2.2** (rank-glyph readability), **pick
  `spotlight_separation_mode`**. Status ledger: HANDOFF_spotlight.md.
- ⬜ **Comparator buckets: a BALANCE call and one UX call.** ⚠ **Not a functionality question —
  the functionality is tested.** PLAN §6's six meld checks run through a real `Game`, stacking
  routes through its own hooks with GATE 8 asserting the isolation both ways, and the five authored
  cards from DESIGN §1e (Turk, Clever Hans, Humbug, Wildcard, plus StampedLoner) are each proven
  expressible. What is left is the two things a test cannot answer:
  - **Balance.** `Tests/Engine/scoring_cost.tscn` now prints the impact: a rank-merging rule
    multiplies a scored LINE by **x2.0 (5 cards) → x3.5 (8) → x6.0 (13) → x5.1 (30)**, and every
    line one placement completes gets it. Extra rank values alone are **x1.0** — they move positions, not
    score. Whether x5 per line is too strong is the same kind of call as everything under
    "Scoring / balance" below, which the sim explicitly cannot make.
  - **One UX judgement, `DEFERRED.md` R2.** A split meld shows three matching cards and counts
    two, with no cue explaining it (Q33=a chose that). That the cue is ABSENT is pinned by tests
    (`test_comparator.gd` §10 asserts the ordinary meld name, no marker); whether its absence reads
    as a scoring bug to a human is not a test's question.
Everything below is unscheduled backlog.

## Visual effects

**Anything fire, juggling, prop art or FX shaders starts at [VFX.md](VFX.md) §6/§7**, which carries
that whole backlog and its known bugs. Keeping the list here as well is exactly the two-places
drift this repo's doc hygiene forbids.

The current fire emitter is the **NOISE FIRE** (owner design): no tendrils, no comb, no ogee, no
onion shells. Fire is a cover field sampled from the art's own mask and carved by scrolling noise,
and every parameter ramps continuously with the stack count. Contract: ARCHITECTURE_REVIEW §4g;
the full record, including what only the owner can decide, is FX_HANDOFF §0.

- ⬜ **The two remaining FX tasks are FX_HANDOFF §0c/§0d** — the owner's words: *"our last tasks
  will be making fire vfx show behind the art and saving juggling performance"*. ⚠ Read §0c first:
  `inner_alpha` and `z_index` are NOT ruled out — the first attempt failed on a QUANTIZATION
  detail, and the one-line experiment to try before any layering change is named there. For the
  second, re-run the two levers whose blocker an unrelated fix removed. §0e explains `cover_taps`.
- **The three fire `.tres` were MIGRATED, not TUNED.** Only `noise_scale` was re-derived, because
  the retired build's value was ~6x too fine for a model where the noise IS the shape. **The art
  pass is the owner's and it is the biggest thing waiting.**
- **Fire still licks down a card's top corners.** The chamfer is in the RADII mask, not the flame
  model, so any correct model stands fire on it. FX_HANDOFF §8.

## Architecture / engine

- D6 command-log undo — the real fix for per-action deep-copy cost (E5); eliminates reference
  remapping entirely. Big.
- Board §5 step (5): delete the `move_data_to_coord` / `move_data_ontop_data` Vector3i adapters
  when convenient.
- D1 real mod-hook contract (single HOOKS list / signature checking) · D2 route ALL mod state
  mutation through Game/Board (some mods still write arrays directly) · D4 kill the
  `CardEnvironment.CURRENT` static reach-through (pass the environment/context instead).
- D8–D11 cosmetics: comparator speculative abstractions, editor-tool code out of `card_visual.gd`,
  unify the zone pair into one structure, Scoring section-banner rewrite.
- S3 same-column move edge cases (unit-test the remaining matrix), S4 `PlayArea.separation`
  int/float, S7 verify every ModsList consumer duplicates.

## Scoring / balance (playtest phase — the sim cannot answer these)

- Playtest per the SCORING_MATH_PLAN §10 protocol (git history): paired seeds, record sheets,
  acceptance bands. Open knobs: `difficulty` default, `combo_step` 0.1 vs 0.2,
  arrangement-capacity reality, mod-activation U generosity, Burning cascades as a combo source,
  δ fallback trigger, `score_additive` A/B (needs a goal_g0/alpha retune).
- Balance of the live `on_score` / `on_after_score` broadcasts — never balance-tested.
- Sim/doc fit drift: `--final --q 0.35` prints g0≈140/α≈2.03 while shipped constants are G0=130 /
  ALPHA=4.2. The owner is not worried (tunables cover it); arbitrate before recalibrating.
- Rarity tiers (luck currently only gates non-null stamp/skill/type rolls).

## Scoring — LIVE defects, found by the poker-patience close, none fixed

⚠ **ALL FOUR ARE SCORE LOSS OR SCORE SHORTFALL IN SHIPPED CONTENT, AND A GREEN SUITE DOES NOT SEE
ANY OF THEM.** `live_total() = board_total() * combo_mult()`, and `board_total()` sums `grid_score(i)`
over `state.grids`, reading ONLY `scores_row`, `scores_col`, `scores_cell` and `score_special`.
**Anything reaching `scores_row_upper`, `scores_row_lower`, `scores_col_legacy`, `row_total`,
`col_total` or `mult_score` is lost.** Grep those six names before adding any scoring path.

- ⬜ **`PropBankColScore` loses EVERY Firework column score.** `Cards/Props/Mods/prop_bank_col_score.gd:16-19`
  hand-builds a bare `ScoringSection.new()` and never sets `grid`, so it is always `-1` and
  `add_line_score` always takes the legacy branch. `PipSuitFirework` is shipped (deck12), so this
  fires in a real show; `register_combo` runs first, so the multiplier moves and the points do not.
  ⚠ **The fix is not a one-liner:** build the section from a coordinate, but `on_finish` fires when
  `p.route.is_empty()` and a firework that starts with an EMPTY rise route never entered a slot, so
  `p.at` is still `NOWHERE` — which is exactly the case `test_firework_banks_column` covers. Decide
  what an empty-route firework banks into (probably `prop.source`'s grid position).
  ⚠ That test asserts `col_total == 3`, so it **passes because the defect exists** — re-point it at
  `line_score(scores_col, ...)` as part of the fix or it will keep certifying the loss.
- ⬜ **No effect activation feeds the combo on a placement** — the grid game's only scoring action —
  contradicting `DESIGN.md` D11 (`Q323`=b). `game.gd:231` gates `register_combo` on
  `_act_cancellable`, written only inside `_perform_next`. See `gaps/GAP-043.md`: the design is
  ANSWERED (combo never resets, unbounded by design); what remains is which condition replaces it.
  **Not a bare delete** (setup would register) and **not `processing`** (that is the input lock —
  overloading it repeats the mistake that caused this). An explicit act-open flag set in
  `_begin_act()` is the honest fix; finding the clear sites is the work.
- ⬜ **`SkillExtraPoint` awards nothing, in 19 deck slots.** Description reads *"Gain 1 Extra Point
  Per Score"*; `add_points()` has no caller, its only call site commented out one line above. Even
  rewired it disagrees with the card (`add_total_score(10)`), and `total_score` has no other live
  writer. Pre-existing — dead on `main` before the branch too. `skill_hungry_hippo.eat_card()` is the
  same shape; between them they are the only consumers of `CardEffectApi.add_total_score`.
- ⬜ **`GameData.apply_act_score()` is dead production code its own tests keep alive.** Zero
  production callers; every caller is a test (`test_act_score.gd` ×7, `test_combo.gd` ×4,
  `test_game_headless.gd` ×1, whose comment already says *"there is no button that"* fires it).
  Deleting it removes a suite and part of another, so it is an owner call, not a cleanup.
  ⚠ The three `row_total`/`col_total` checks in `test_game_headless.gd` are DIFFERENT and should
  stay — they cover `add_line_score`'s legacy branch, which is still reachable and still defective.

## Scoring engine test gaps

- ⚠ **SE4 IS NOT A TEST GAP AND SHOULD NOT SIT UNDER THIS HEADING.** "single-walk `_scan_wrap`" is a
  micro-OPTIMISATION of `Scripts/scoring.gd`: the scan restarts its walk from every rank
  (`for start in range(A, W + 1)`), where one pass could find the longest wrap-around run. Nothing
  about coverage. ⚠ **A benchmark now EXISTS** (`Tests/Engine/scoring_cost.tscn`, DEFERRED E1), so
  this is measurable rather than speculative — but measure before optimising: the wrap scan is one
  term inside a call that costs 9.1 ms on 30 cards, and E3 (the repeated profile rebuild) and E6
  (the ~2x identity-path regression) are both larger.
- ⬜ **`LINE DETECT` cannot see the defect class this repo has hit four times.**
  `Tests/Engine/test_line_detect.gd` (1201 lines) asserts through a `RecordingGame` that captures the
  `amount` ARGUMENT to `add_line_score`. Verified: the file contains ZERO references to `live_total`,
  `board_total`, `grid_score`, `scores_row`, `scores_col`, `scores_cell` or `section.grid`. Every
  assertion is taken BEFORE `add_line_score` branches on `section.grid`, so a regression routing
  every grid section to the legacy bucket leaves the whole suite green while the score goes to zero.
  ⚠ The comments justifying this (*"which bucket a section banks into is a later step"*) are STALE.
  **Fix: one check on the DESTINATION per scoring test**, not on the argument.
- ⬜ **`combo_repeat_step` has ZERO references in the entire `Tests/` tree** — a shipped knob
  defaulting to 0.5 that multiplies the player's score. That is `TP-58`. `TP-59` (D11) has neither
  an implementation nor a test.
- ⬜ **`COMBO` leaks a `Game` and leaves the global pointing at it.** `test_combo.gd`'s
  `test_register_combo` does `Game.new()` + `CardEnvironment.CURRENT = g` and never frees or nulls —
  the file has ZERO `free()` and ZERO `CURRENT = null` — and it is the LAST test in the suite.
  `Game extends Node`, so that is a leaked Node plus global state left for whatever runs next.
- ⬜ **Two more production functions whose only callers are tests**: `GameData.discard_lower_board()`,
  and `Game.move_card_in_grid` / `remove_card_from_grid` — the latter pair unreachable from shipped
  content (no `CardEffectApi` wrapper, and the modifier boundary gate forbids naming `Game.`), yet
  three test-plan rows drive them.
- ⬜ **Only `Tests/Engine/` has ever had a test-quality review**, and eleven files in it got only a
  mechanical sweep. `Tests/UI`, `Interaction`, `Wall`, `Visual`, `Map`, `E2E` and `Support` have had
  none. The checklist is `.claude/memory/tests-that-prove-nothing.md`.
- ⬜ SD5 test-file section renumbering — cosmetic only, and `test_scoring.gd`'s own header already
  says the section numbers are historical and `_ready` order is the real one. Churn on a 1200-line
  file for no behavioural gain; left deliberately.

### ⬜ Comparator buckets — **phases 1–8 landed and verified; a playtest is what remains**

How the surface works and every landmine in it: **ARCHITECTURE_REVIEW §3c**. Behaviour authority:
[design/comparator_buckets/DESIGN.md](design/comparator_buckets/DESIGN.md); contracts and build
order: its [PLAN.md](design/comparator_buckets/PLAN.md); per-step evidence:
[HANDOFF_comparator_buckets.md](HANDOFF_comparator_buckets.md). Everything scoped OUT — with the
cards blocked on each and the seam it would land at — is
[DEFERRED.md](design/comparator_buckets/DEFERRED.md); add to that list rather than re-deriving it.

⚠ **Latent in shipped content, which is not the same as untested.** No authored card implements a
meld hook, so the identity path runs and scoring is unchanged until content asks otherwise —
while `test_game_headless.gd` drives PLAN §6's six checks through a real `Game`'s `submit()`.

**Open:**

- ⚠ **OWNER CALL — the identity path costs ~2x what it did before this work** (`DEFERRED.md` E6,
  numbers in PERFORMANCE.md §4d). No shipped card implements a meld hook, so **every real game
  today takes the path that got slower**: 30 cards with no rules went **5.01 ms → 9.15 ms** per
  scored line, 1.9–2.7x at every smaller size, measured current-tree vs a `HEAD~1` worktree in one
  session on one box, two runs each. C4's safety claim was verified byte-identical in RESULTS and
  never in COST — this is that gap closed, and it is a decision, not a bug: accept the 2x, or open
  a perf phase. Not diagnosed; E6 lists the suspects in the order worth measuring, and the extra
  classification profile per handler (ASSUMPTIONS S14) is first.

- ⬜ **DEFERRED E3 is now the biggest lever in the scoring path, and it is sized.** `Tests/Engine/scoring_cost.tscn`
  (E1, written): a scored line costs 9.5 ms on 30 cards unmodded, 16.2 ms with a rank-merging rule,
  31.9 ms with merging plus extra rank values. ⚠ `Game.score_line` runs per row AND column and
  `skill_eval_poker_best` scores both again from inside scoring, so a wide board with a merging
  rules card is HUNDREDS of ms for a placement that completes several lines at once. Numbers in PERFORMANCE.md §4d. Q57(a) scoped E3 out —
  reopening it is an owner call, but it is no longer an argument from arithmetic.
- ⬜ **Three fuzz invariants remain scoped rather than absolute** (3's held-cards set, 8's position
  model, 1's declared multi-key exception). Each is documented with why; each is also a place a real
  defect could hide. Invariant 9 is unrestricted again now that the generator's random predicate is
  a pure function.
- ⬜ **The fuzz's carrier axis is still not a full cross-product.** `stamp` / `status` / `skill` are
  typed to their own `CardModifier` subclasses, so one shim cannot hang in every slot; the generator
  rides on the type slot. The mounts that behave DIFFERENTLY are covered explicitly (all four for a
  pair rule, plus a skill carrying a whole-hand rule, which has its own dispatch and spotlit gate),
  so what is missing is combinations, not code paths.

## Props / UI (owner has NOT re-verified)

- Description-panel scroll-lock, knife row behavior, hoop visibility, ballistic poof,
  undo-across-a-placement feel, held-loop spin, formation system + editor end-to-end (no formation
  `.tres` authored yet).
- Firework in-run acquisition beyond deck12 (owner decision). Per-pip tooltip granularity.
- Win/lose screen font (226px) clips long "Fame +N" text. `game.tscn` grabs no initial focus, so
  keyboard/controller players must click first.

## Universal palette (owner playtest pending)

Contract: ARCHITECTURE_REVIEW §4i. Open follow-ups, all deferred by the owner rather than missed:

- **Map screen and in-game UI chrome are still hardcoded**, pending the owner's custom art
  (`world_map_controller.gd`, `map_player_token.gd`, `game_view.tscn`, `choice_viewer`,
  `deck_picker`, `deck_viewer`, `deck_builder`, `text_popup`). The PALETTE suite lists each as
  `[WARN][PLACEHOLDER]` every run — that list IS this task. When the art lands: add a role per surface, assign it in code at `_ready()`, never
  re-bake a literal into a `.tscn`.
- **`FireworkVisual` has no art** — its placeholder magenta polygon is the last non-deferred
  literal. The `suit_firework` role already exists for whenever that art is drawn.
- **The fire ramp's ENDS are an art call the owner has not made.** `ramp_fire` runs
  `[0, 20, 1, 2, 16, 30, 6, 3, 31, 19]`; entry 0 makes a 1-stack flame nearly black and entry 19
  puts a neutral grey at the white-hot end. Both are honest nearest-palette choices and both are
  one-line edits to `Assets/Palette/ramp_fire.tres`.
- **`suit_pips.png` has a few off-palette pixels** (e.g. `#ec0037`, 27 from entry 2). Authored art,
  not a plumbing bug; `tools/palette_conformance.py` finds them.

## Booster rerolls (owner playtest pending)

Full behavior and the settings list: ARCHITECTURE_REVIEW §4f.

- Pool ships at 5 (`booster_reroll_pool`); reroll-count modifiers (the `luck()`-style content hook)
  are not written yet.

⚠ **PATIENCE IS RETIRED AND ITS BACKLOG IS GONE WITH IT.** The whole family went with the tableau
(`design/poker-patience/PLAN.md` §1.6): no `patience_max`, no `patience_influence_*`, no
`patience_disabled_hooks`, no `patience_max_increased`, no `state.patience`. `test_grid_economy.gd`'s
TP-60 grep gate asserts zero readers of every one of those spellings in any `.gd` or `.tscn`, so
they cannot come back by accident. The open questions that used to live here — what counts as an
"interesting move", which comparator hooks should feed it — died with the mechanic; do not revive
them from git history without an owner ruling that patience is back.

## Card size + outline — landed, one thing open

Card is **40x54**; every element wears `Shaders/outline.gdshader`'s rim. Rules and landmines:
**ARCHITECTURE_REVIEW §4j**. Design record: `design/card_size_outline/`. Tuning:
`Shaders/Styles/outline_default.tres`, edited live on `tools/outline_atlas.tscn`.

- ⚠ **ART, owner's call — the rim MERGES the dense `suit_art` frames.** The highest-rank frames
  pack nine+ pips into 32x32 and invert into a dark lattice. The fix is art-side (space by 3) or
  scope-side (exempt the 32x32 art). Nothing in code is wrong.
- **Q6a / the alert's LOOK is unjudged.** GLARE and THROB are tunable live on the atlas; whether a
  card-space glare reads on an 8x8 pip (lit ~25 % of the sweep) is the owner's eye. The escape
  hatch is a per-host thickness scale.
- **FX numbers are stale by ~12 % of fill.** FX_HANDOFF.md carries a banner; re-run `fx_cost.gd`
  before spending that budget.

## Design work not started (DESIGN_DOC pointers)

- Entrance drop-down between acts (DESIGN_DOC §2) — decide and implement.
- Tips / hype-wagering / fog of war / tour planning (§15); circus renames (§9); shop & economy
  (§16); meta progression (§19); leaders/acts (§11); deterministic per-subsystem RNG streams
  (§6/§23 — required before any seed-sharing feature).

## Testing / infrastructure

- ⬜ **Focused suite testing** — a suite filter, timing instrumentation and a headless logic tier, so
  a one-line change stops costing a full windowed run. Plan, task list, and the doc/memory/skill
  updates it forces: `FOCUSED_TESTING_PLAN.md`. Delete this line and that file when it lands.
- E2E first-card fly-in in the pack preview: confirm fixed on a real run.
- Background-save robustness at scale unverified (large history serialize on a worker thread) —
  watch the console; the history cap bounds it.
- **PIXELS `test_the_card_mask_is_the_card_the_player_sees` WAS GREEN but PINNED, not fixed.** The
  check no longer demands exact cell agreement — that bar was unachievable and passed at rest by
  alignment. It asserts a band around the outline: **edges ≤ 1.7 FX cells** (the fraction is the
  32-slot wedge index, whose quantization is angular; measured worst 1.50) and **corner bite ≤ 2.6
  cells** (measured worst 2.45 at t=0.30). Both bounds are in CELL units so one `pixel` knob moves
  them together. The **COUNT** is asserted too — rest pose exact (0/0), deformed poses ≤ 130
  disagreeing cells (measured worst 104) — because the distance bars alone cannot see a shallow
  uniform boundary shift. ⚠ **All numbers are measured and deliberately tight so any worsening
  fails — do not raise them to go green.**

  Underneath it are **two independent model approximations**, diagnosed and NOT fixed; the fix is a
  model choice, so it is the owner's. The `[mask vs face WHERE]` line in `test_pixels.gd` buckets
  every disagreeing cell: corner cells 22/62/60 and edge cells 36/42/0 at the three deformed poses.
  - **CORNER class — `CardVisual.corner_points()`.** It puts the bite's middle point at
    `corner + along_prev + along_next`, assuming the corner cell stays a **parallelogram**. It is
    really a bilinear patch whose fourth point (the internal vertex, e.g. `(-14.25,-18.75)`) is
    skinned independently. Exact while the cell is a rectangle — which is why t=0.00 passes — and
    drifting as it shears. ⚠ **The function's own comment claims it is "exact under deformation";
    that claim is false**, and this is the measurement that shows it.
  - **EDGE class — the radial wedge mask.** `WEDGES = 32` (11.25° per slot) indexes which polygon
    segment a fragment is tested against, with only `WEDGE_CANDIDATES` consecutive slots tried.
    Deformation spreads the 24 vertices unevenly in angle, so a slot can span more segments than
    the window covers and points near a slot boundary test against the wrong segment.
  - **Options.** (1) Exact corner: re-do the skinning in GDScript from `Polygon2D.bones` weights
    for the 4 corner diagonals only — per-frame per-card code the comments already guard for cost.
    (2) Widen the candidate window, or drop the radial mask for a non-radial one. (3) Give the
    check a stated tolerance instead of demanding exactly 0.
  - **Already ruled out, do not re-open:** the baked `Offset/Visual` pose; the animation driving it
    (it does not — only bone `:position` tracks exist); bilinear filtering (a real harness bug,
    fixed, but t=0.30's 887 undecidable cells did not move); "tips vs skinning blend" (bone rests
    equal their vertices exactly and each vertex is ~0.99997 weighted to its own arm).
- **G2.3 / spotlight cost** (`fx_cost.gd::_spotlight_rows`). Over a 1.947 ms empty-scene floor:
  0 lights +0.478, 1 +0.607, 8 +1.537, 24 +4.666, 64 (MAX_LIGHTS) +12.237 ms. **≈0.19 ms per light,
  near-linear**, swept over LIGHT COUNT because `light.gdshader` shades the whole viewport
  regardless of host count. A realistic section (5–12 lights) is ~1–2.5 ms; 64 would blow a
  16.67 ms frame alone. `Q254`=(a): reported, nothing trimmed — the cut is the owner's call.
  ⚠ The GLOW is still unpriced: there is no `FxGlow` effect class, only the shader.

## Picture wall

See [PICTURE_WALL.md](PICTURE_WALL.md) for how it is put together and what will bite you, and
[HANDOFF_picture_wall.md](HANDOFF_picture_wall.md) for where the stream stands.

- **`sample_at()`'s INFO branch holds the SOURCE's info zoom for the whole transition**, so the
  approach to a differently-sized destination is framed on the picture being LEFT. `J10`/`Q137`
  ("the camera never leaves the info zoom") is what asks for one fixed value, and `_settle_camera()`
  now cuts to the destination's own info pose on landing — so the resting state is right and what
  remains is a single cut at the end, exactly the shape GAP-019=(c) chose deliberately for reduced
  motion. Left as-is unless the cut reads badly in playtest.
- **The map still BUILDS a full preview-card `InfoEntry` on every booster hover with Info mode off**,
  and `Main` frees it immediately. The leak is gone; the waste is not. Fixing that properly means
  either the map learning about Info mode (which `map.gd`'s own comment forbids — "the map has no
  business deciding whether Info mode wants it shown") or `info_hovered` carrying the NODE instead
  of a built entry, which is a `NAMES.md` signal-signature change and so a gap by that doc's own
  rule. Left as waste on a hover-enter path, deliberately.
- ⬜ **Camera/view findings — PARKED BY THE OWNER as todo, and NONE of them is verified.**
  ⚠ **The suite structurally cannot see any of these**: the layout suites are pinned to the OVERVIEW,
  and no `Tests/Visual/` harness drives props at all, so nothing renders a prop over a card at a
  non-1.0 `board_zoom`. **Building that harness is the first task, not the fix.**
  - `main.gd` / `wall_transition.gd` — the game picture's resting pose is `panned_state`, but
    `WallTransition` still interpolates between bare rect centres and `_on_info_toggled` still aims
    at unpanned poses, so the trailing `_settle_camera()` cuts a full grid pitch. The `else` branch
    of `_focus_picture` was fixed for exactly this and says so; the picture-to-picture branch — the
    route `map → game` actually takes — was not.
  - `wall_picture.gd:235` — `focus()` used to force `size_2d_override = Vector2i.ZERO`; the
    replacement engages a non-identity override on a FOCUSED picture whenever the render clamp
    bites, displacing every click inside the show.
  - Four zoom-awareness sites, all correct at zoom 1.0 and claimed wrong in FOCUSED mode:
    `play_area.gd:1399` `_card_control_at`, `play_area.gd:2919` `_position_focus_info`,
    `prop_layer.gd:193` `_body_over_any_card`, `card_visual.gd:696`'s held-card grab offset.
    ⚠ `/fx-verify` MEASURED the hoop's jump alignment and it is scale-aware and correct
    (jumped-card centre == ring centre exactly at `card_scale` 2.5 and 4.0, rest offset exactly
    proportional), so `card_scale` is NOT the axis in question — `board_zoom` is.
- ⬜ **`anim_spring_lift` / `anim_jump` descent mismatch** — confirmed by reading the tween chains,
  unverified by render. `anim_jump` tweens `offset.position:y` to `-CARD_JUMP_RISE` and NEVER
  returns it (only the SCALE pulses back); the card comes down separately via `anim_reset()` when
  the prop's HOLD ends. `anim_spring_lift` rises, holds, then returns y to 0 itself. **So the riders
  descend while the jumped card is still held up** — `Q310`=a (*"as if jumping card has all above
  cards on its shoulder"*) holds for the lift and breaks for the rest of the hold, and
  `_update_reactions` re-lifts the riders per arriving prop while the jumped card just stays up.
  ⚠ The function's own doc comment claims the opposite (*"then down together"*, *"as ONE RIGID
  BODY"*). It has a DURATION, so a still frame cannot settle it — run it and report what MOVED.
- **The Entrance renders through the LEGACY zone renderer, and switching it is the last piece.** Banking, the zone shape and the
  HEIGHT labels are all landed; what is left is its ROW label and multi-row cells, and both come
  free once it binds to `_create_grid_panel` / `_bind_grid_panel` -- which already take a panel and
  a `GridData` and never touch `state.grids`. Three things to add: label stacks
  for the Entrance's rows, height labels for the Entrance -- which stay ABOVE their stack like every
  other, the owner having reversed an earlier call, so the arithmetic is unchanged and only the
  separation band's BUDGET grows (column scores on top, Entrance height scores directly beneath) --
  and a cell lookup in `_sync_cell_score_labels` that is ZONE-GENERIC rather than grid-only.
  ⚠ Owner: *"no special cases"* -- no Entrance branch anywhere; the general form resolves a cell
  through whichever zone owns it, which is why the Entrance was made a `GridData` in the first
  place. What is still missing is an accessor handing back every zone rather than just `grids`. ⚠ A multi-row Entrance (the owner named 2x3) is SETTLED as real rows, with a slot's
  stack depth staying the HEIGHT axis -- which confirms the shipped banking rather than changing
  it. But `upper_zone` is a flat array of slots with nowhere to put a second row, so giving the
  Entrance rows is a STRUCTURAL change (it becomes cell-shaped like GridData), not a label one. ⚠ Row/col label COUNTS and the
  per-height stacks are ALREADY derived from the grid's own dimensions and buckets, so an 8x7 grid
  needs no work there; do not rebuild them.
- **The retired act payout's HUD nodes are EMPTIED, not removed, and the removal belongs to the
  GAP-038 pass.** `%MultScore` and its `Col`/`x`/`Row` children showed a frozen "0 x 0" because
  nothing in the grid economy writes `mult_score`/`col_total`/`row_total`; `GameView._ready` now
  blanks them. ⚠ **Deleting the nodes is the deeper fix and it is NOT free**: `%MultScore` is in
  `_furniture`, and `_hud_authored_width()` maxes over that list to publish
  `PlayArea.board_inset_left`, so removing it can shrink the HUD reserve and re-centre every grid.
  That is HUD geometry, which is parked on `GAP-038`. Do it with that pass, not before.
- **`ProfileManager.unlock()` has no production caller** — only tests call it, and `book` is the only
  locked entry, so S38/K2/K3/K4, `_repack_wall()`, `apply_layout(animate = true)` and
  `picture_unlocked` are all unreachable in the shipped game. Built-but-not-wired, and on neither
  PICTURE_WALL.md's wiring table nor this list until now.
- **Wall view never shows the whole wall, by design, and it may be too much.** `Q5`=b fills and
  crops, and `G10` supplies pan to reach what falls outside — but at 16:9 four of twelve pictures
  are cut by the frame, more at 32:9, and GAP-018=(a) keeps `view_margin` as extra crop, which
  makes it more pronounced. Wants an owner look at real renders before anything builds on it.
- **At 32:9 the ellipse clamp saves the layout but does not compose it** — nothing is stretched into
  a pancake, but the result is upper-heavy with empty bottom corners (`TEST_PLAN.md` §10 item 7).
- ⚠ **`start_menu` does NOT overflow its picture — an earlier note here said it did and was wrong.**
  Its widest content ends at x=1148 of a 1152 design width. The clipping seen in the tool was the
  tool's own rounded `preview_aspect` default (1.7778) landing 1.4e-05 past `is_equal_approx`, so
  `focused_scale()` applied its 2% overfill margin at what is really a matching aspect. Fixed by
  seeding `preview_aspect` from the live window. **The lesson generalises: any caller that hands
  `WallPacker` a rounded aspect instead of `window.x / window.y` will crop 2% off every focused
  picture.** `Main` computes it exactly, so the game is unaffected.
- **Nothing has ever HEARD a wall transition** — no `PictureEntry.music` is authored on any entry,
  so the crossfade has never had a stream to blend. The machinery is now previewable (the tool hosts
  the real `Wall`, and `_move_to()` drives `begin_music_crossfade()`/`update_travel_music()`/
  `finish_music_crossfade()`); what is missing is audio to point it at.
- **The editor's INSPECTOR preview still cannot drive four knobs** (`wall_selection_repeat_delay`,
  `wall_debug_readout`, `wall_reveal_delay_scale`, `wall_unlock_all`) because `Wall` is not `@tool`
  and loads there as a placeholder. All four work when the tool is RUN (F6), which hosts the real
  `wall.tscn`. Making `Wall` `@tool` would close this, but it would also instantiate the shipped
  autoload-facing shell in the editor — not attempted.
- **`UI/deck_builder.gd` is dead code with BROKEN preloads** — `res://Cards/card.tscn` and
  `res://UI/card_control.tscn` do not exist, so it throws four parse errors into any editor session
  that reloads scripts. Nothing references it but its own `deck_builder.tscn`; `player_save.gd`
  calls it "the Deck Maker dev tool". Unrelated to the wall — it surfaced while verifying the wall
  editor in editor mode. Delete both files, or repoint the preloads; not touched because removing a
  dev tool is an owner call.
- 🔴 **The info card lays its text out before the zoom-out finishes**, so the text is sized against
  the pre-move framing rather than what you end up looking at. Cause is an ordering choice I made
  deliberately: `_apply_info_mode()` shows the card FIRST so the camera's reserve can use the
  card's live height, which means the card pops to full size while the camera is still travelling.
  Fix paths: (a) split MEASUREMENT from DISPLAY — measure the entry's height with the card still
  hidden, reserve against that, and reveal it as the tween lands; (b) tween the card in over the
  same clock as the zoom so the two arrive together; (c) re-run `_resize_to_content()` on the
  camera's `finished`. (a) is the honest one — the reserve needs the height, not the visibility.
- 🔴 **Card descriptions are unreachable in the deck / discard / rules viewers.** `Q134`=c and chart
  J8 say every tooltip migrates to the info card; only `PlayArea` and the map were done.
  `DeckViewer`/`ChoiceViewer` still draw their own (`choice_viewer.gd` sets
  `card_info.text = ControlCard.describe_card(card)`), and publish nothing, so Info mode shows
  nothing there. Fix path: the same shape `PlayArea` now uses — give each viewer an
  `info_requested(entry)` signal, gate its own panel on a `_popups_allowed()` equivalent, and route
  it to `Main._on_screen_info_hovered`. `CardsViewer.populate()` already takes an `on_inspect`
  callback these viewers pass, so the hook exists; it needs pointing at `PlayArea.card_info()`.
- 🔴 **The per-screen info card does not actually persist across a transition** (`GAP-023` round 5
  claims it does — the mechanism landed, the behaviour did not). Suspects, in order: `Main` only
  RESTORES a remembered entry and never shows a default, so a screen entered with Info on and
  nothing stashed shows a blank card; `_info_entry_owner` is written from `_current_focus`, which
  is still the SOURCE for the whole of a move, so an entry read mid-move may be stashed against the
  wrong picture; and the tool rebuilds `wp.get_info()` on every `_apply_info_mode()`, which
  overwrites what was remembered. Nothing drives *enter A → read a card → go to B → come back* and
  looks at the result — write that case in `wall_editor_soak.gd` FIRST, then fix what it shows.
- **Bind the info-card scroll stick** (`GAP-023`, answered): the stick with NO d-pad beside it,
  since the stick+d-pad side is normal movement. Needs an InputMap action, wiring into
  `InfoCard`'s `ScrollContainer`, and a real pad to verify. Mouse wheel already works.
- **Possible split: popup = summary, info card = in-depth** (`GAP-023`, owner note). Both read
  `ControlCard.describe_card()` today — one string, no drift. Splitting them means a second
  authored description per card and is its own design question.
- **Touch is undefined for Info mode** (`GAP-023`) — neither hover nor click is specified for a
  finger on a card.
- **Controller still untested by anything automated**: deadzones, analogue-stick ramps, and device
  hotplug mid-session. `wall_selection_repeat_delay`'s repeat is now real and covered by a synthetic
  action test, but no real stick has driven it.
- **`deck`, `settings` and `book` are registered ids with no screen** — they pack, frame and accept
  navigation, and draw whatever `background_texture` they are given, or nothing. Building their
  contents is out of scope for this stream; the wall does not need changing to host them.
- **The suite intermittently HANGS at 30 of 39 suites with no banner**, in clusters, and every suite
  involved completes when run alone — so it is in the concurrency. RE-RUN before bisecting: a hung
  run is not reliably attributable to the change that produced it (`HANDOFF_picture_wall.md` S44).
- **PIXELS' mask-vs-art bound has never been ruled on** (0 mask-without-art, 3773 art-without-mask at
  rest). Its own comment forbids raising it to go green, so it stands as written (S41).
- **The comment backlog drains whole-file on touch, and is not a sweep.** A full `doc_check` run
  reports ~5.9k indented comments, ~2.1k over-long `##` docs, ~750 over-long `#` blocks and ~630
  trailing ones. The rules are ERRORS on any file a session edits, so the count falls as files are
  touched for other reasons. Do NOT open a branch to fix them all: the churn would be repo-wide,
  unreviewable, and would collide with every stream in flight.
