# TODO — open backlog (owner-endorsed unless marked otherwise)

Add new items here; **delete an item when it lands**, recording the regression-critical residue in
ARCHITECTURE_REVIEW.md rather than keeping a log here. Current-state facts live in
ARCHITECTURE_REVIEW.md; done-work history lives in git.

## Known intermittent test failures (not owned by any current work stream)

⚠ **All four need the failing run's own `godot.log`, and a batch must COPY it per run.**
`run_tests.py` discards the suite's stdout by design and prints only the banner, so the evidence is
gone by the time you know you wanted it.

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

- ⬜ **`doc_check.py` scans code comments; the standing count over 230 source files is 138 dated ·
  101 blocks over 16 lines · 78 history · 13 restated · 0 line refs.** Zero errors — every reference
  resolves. ⚠ **A BACKLOG, not a regression**: the rules postdate the comments. Work it
  opportunistically — clean what you edit — rather than as one sweep. `--verbose` lists them.
  ⚠ **`dated` will not go to zero and should not**: 43 of them are measurements, where the date is
  part of the fact, and the checker cannot tell those from bookkeeping.

## Waiting on the owner

- ⬜ **Playtest the picture wall** — `HANDOFF_picture_wall.md` S40. Nothing else on that stream can
  be judged until someone drives it; two adversarial reviews traced journeys, neither played it.
- ⬜ **Picture wall: decide what unlocks `book`** — until it exists a whole subsystem is dead code
  ("Picture wall" below).
- ⬜ **Picture wall: look at real renders and rule on wall-view composition** at 16:9 and 32:9
  ("Picture wall" below).
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
    line of a submit gets it. Extra rank values alone are **x1.0** — they move positions, not
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

## Scoring engine test gaps

- ⚠ **SE4 IS NOT A TEST GAP AND SHOULD NOT SIT UNDER THIS HEADING.** "single-walk `_scan_wrap`" is a
  micro-OPTIMISATION of `Scripts/scoring.gd`: the scan restarts its walk from every rank
  (`for start in range(A, W + 1)`), where one pass could find the longest wrap-around run. Nothing
  about coverage. ⚠ **A benchmark now EXISTS** (`Tests/Engine/scoring_cost.tscn`, DEFERRED E1), so
  this is measurable rather than speculative — but measure before optimising: the wrap scan is one
  term inside a call that costs 9.1 ms on 30 cards, and E3 (the repeated profile rebuild) and E6
  (the ~2x identity-path regression) are both larger.
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
  rules card is HUNDREDS of ms per submit. Numbers in PERFORMANCE.md §4d. Q57(a) scoped E3 out —
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
  undo-across-submit feel, held-loop spin, formation system + editor end-to-end (no formation
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

## Patience & rerolls (owner playtest pending)

Full behavior and the settings list: ARCHITECTURE_REVIEW §4e.

- Tune `patience_max` (ships 3) and the per-stage `patience_influence_*` flags (ships PLAY only);
  decide whether the legality query `on_can_place_stack` should count at all — if not, add it to
  `patience_disabled_hooks` and re-tune what "interesting move" means.
- ⚠ `patience_max` ships **3**, but the original spec asked for **1** — confirm which is intended
  before drawing playtest conclusions (3 = three idle moves per round).
- Rule cards that raise `patience_max` / grant patience: the grant path exists
  (`patience_max_increased`), no content uses it yet.
- Booster rerolls (§4f): pool ships at 5 (`booster_reroll_pool`); reroll-count modifiers (the
  `luck()`-style content hook) not written yet.
- Watch existing suites for auto-Next fallout: any test that makes 3+ boring moves in one round now
  advances the round mid-test.
- Comparator hooks reach patience, and **plan step S21 changed WHICH ones**. During the placement
  legality query:
  - `on_compare_ranks` still fires (`return_first_compare_mod_result`) — the placer asks
    `compare_ranks` for run adjacency, which is a scalar and was deliberately left alone (Q55=a);
  - `on_compare_suits` **no longer fires there at all** — the suit question now goes through
    `stack_suits_same`, i.e. the STACK hooks;
  - the four `on_stack_*` hooks fire instead, through `return_first_true_pair_result`, which calls
    `_note_mod_fired` exactly as the old path did.

  So ANY board card with one of those modifiers still holds the counter (once per round under
  uniques) — but the decision this item is asking for now concerns a different set of hooks than it
  used to. Decide whether that is the intended "interesting move" bar or whether some of them
  belong in `patience_disabled_hooks`. ⚠ Note the two situations differ: a MELD rule fires during
  scoring, a STACK rule during the legality query, and only the second is a "move".
- `Game._on_patience_max_increased` edits `state.patience` with no commit — a mid-round grant is
  lost on quit and reverted by undo. Fine for a settings knob; revisit when a rule CARD grants
  patience (that grant should ride a committed action).
- `Game._ready` connects to `SettingsManager.settings.patience_max_increased` without the N9
  reconnect idiom, so the connection binds the settings resource that exists at show start. Only
  matters if `SettingsManager.settings` is ever reassigned at runtime (its setter supports it).
- Two gaps documented in ARCHITECTURE_REVIEW: the auto-Next pending-action replay caveat (§1.5) and
  the seen-set-only commit gap in `_perform_next` (§4e).

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
- **Controller still untested by anything automated**: deadzones, analogue-stick ramps, and device
  hotplug mid-session. `wall_selection_repeat_delay`'s repeat is now real and covered by a synthetic
  action test, but no real stick has driven it.
