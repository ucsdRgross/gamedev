# HANDOFF — Phase 9, the goal-curve refit

**Goal:** the grid game's economy is not the tableau's, and the goal curve was fitted to the
tableau's. Extend the simulation to the grid model, then refit `goal_g0` / `goal_alpha` against it.

**Phases 1–8 and 10 are done.** This is the last modelling work in `PLAN.md`.

## STATE — S38 and S39 are BUILT; the phase is BLOCKED on `GAP-041`

`S38` and `S39` are done and committed. The refit ran, and it says the shape moved:

- **A show's score peaks at node 3 and ends the run at 0.16x that peak.** Two measured causes, both
  in shipped code: the board holds **25 cells for the whole run** (`grid_cards_per_unlock` 52 is
  never crossed, so a run never unlocks a second grid), and `TypeBoosterBasic` draws ranks
  **1-13** against a start deck of **1-5**, thinning the collisions that make melds.
- **No two constants fit that ladder.** The MINIMAX fit — the best any `(g0, alpha)` pair can do —
  is still **100% out** at some node. That is the proof, not the least-squares R².
- Committed at the **BEATABLE** fit (the hardest curve that stays winnable everywhere):
  `goal_g0` **5376.0**, `goal_alpha` **0.26**. Validates at 17.2 / 15.2 / 10.5% run-win for
  skilled / par / average. ⚠ A near-flat alpha is the curve admitting it has no driver.
- **`GAP-041` carries the four options and is unanswered.** Do not pick one.

⚠ **THE SIM IS NOW ASSERTED AGAINST THE ENGINE.** `Tools/scoring_parity.gd` dumps what
`Scoring.PokerHands`, `GameData.grid_score` and `GameData.combo_mult` actually say, and
`--parity` checks the port against it — 1200 lines, 0 score mismatches. Run BOTH after any
change to either side:

```bash
Godot --path solatro res://Tools/scoring_parity.tscn
py solatro/Tools/scoring_sim.py --parity "%APPDATA%/Godot/app_userdata/Solatro/scoring_parity.json"
py solatro/Tools/scoring_sim.py --grid-goals --trials 800 --q 0.25
```

⚠ **TRIAL COUNT MOVES THE CONSTANTS.** 300 trials gave `5038.4 / 0.42` where 800 gave
`5376.0 / 0.26`. The committed pair is the 800-trial run; quote the trial count with any refit.

## Design provenance and gap protocol — COPY THIS BLOCK INTO ANYTHING DERIVED FROM THIS DOCUMENT

Derived from `design/poker-patience/DESIGN.md` v2 and `design/grid-view/DESIGN.md` v2.

Reaching a decision the design does not cover:
1. Reversible and clearly within intent -> do it, append one line to `ASSUMPTIONS.md` citing the
   node. Never silently.
2. Otherwise -> **park that thread, file a gap, keep unaffected threads moving, tell the owner.**
3. The design contradicts itself or the code -> always a gap, highest priority.
4. ⚠ Two documents disagreeing is NOT automatically (3) — read the answer they are both restating.

Gaps live at `design/poker-patience/gaps/GAP-NNN.md`, options in the questionnaire grammar. Do not
resolve a gap by picking an answer. Do not delete one — it is closed by a new design version.
⚠ **CHECK FOR A FOURTH OPTION FIRST.** The owner has answered with an unlisted option many times,
including deciding `GAP-018` from platform research rather than from either filed option.

## The two steps

**S38** — DONE. `Tools/scoring_sim.py` carries the grid model as its own section; every tableau
entry point now prints a RETIRED banner, and `score_additive` is gone.
**S39** — DONE. Constants committed with their command; the derivation is in `GAP-041`.

**Done-when (phase):** the sim runs end to end and the fitted constants are committed **with the
command that produced them**. Both hold. The PHASE still needs an owner answer on `GAP-041`.

⚠ There are **no `TEST_PLAN.md` rows for this phase** — its gate is the sim itself, not the suite.
Do not go looking for TP numbers; do not invent them.

## The curve being refitted

`RunManager.goal_for()`, verbatim in shape:

```
n_hat = goal_n0 + booster_yield * boosters_on_path
goal  = goal_g0 * (n_hat / goal_n0) ^ goal_alpha * difficulty * lap_mult ^ min(lap, 30)
        (* boss_mult on a boss)
```

Shipped today: `goal_g0` **5376.0**, `goal_alpha` **0.26**. Both are `PlayerSettings` knobs.
The pair they replaced (**130.0** / **4.2**) was fitted to the tableau and asked 130 at node 0
against a measured median score of 9,360 — every goal in the game was trivial.

## ⚠ WHY A REFIT MAY NOT BE ENOUGH — READ THIS BEFORE FITTING TWO CONSTANTS

The tableau's score was **additive**. The grid's is a **PRODUCT**, and that is a different curve
shape, not a different scale. `PLAN.md` §1.6, owner's worked example verbatim (`Q322`):

> *"row + col + diag = 0 + 0 + 0. Row gets 10 score. it is now 10 + 0 + 0 = 10. Col gets 5 score. It
> is now 10 \* 5 + 0 = 50. Diag gets 2 score. It is now 10 \* 5 \* 2 = 100."*

- `grid_score` = the product of every bucket whose value is **> 0**; 0 when none is.
  ⚠ **A bucket that has not scored ADDS 0 — it never multiplies by 0**, and the test is the VALUE,
  never touched-ness: *"if score is 0 do not multiply regardless of if 0 is somehow a returned
  actual score from something."*
- `board_total` = the sum of `grid_score` over grids.
- `combo` = `1 + combo_unique_step * firsts + combo_repeat_step * repeats` (1.0 and 0.5), melds and
  effects on the same terms, accumulating for the whole show and never reset (`Q130`=a).
- **displayed = `board_total * combo`, applied at DISPLAY time, not at banking time** (`Q129`).

⚠ **RETIRED, AND THE SIM STILL MODELS SOME OF IT:** `MAX_SUBMITS`/`submits_used` entirely
(`Q132`=b), `score_additive` and its settings field (`Q136`=a), `duplicate_class_scale` (`Q135`=b),
and the whole patience family (`Q26`=a). A refit against a sim that still has these is a refit
against the old game.

⚠ **THERE IS NO LINE-SCORED MEMORY AND NO WITHIN-PASS GUARD** (`Q51`=a). Every completion scores,
every time; an effect that removes and replaces a card in a complete line re-scores it on every
cycle, and that is a legitimate archetype. **`act_event_cap` / `MAX_TICKS` are therefore
load-bearing for CORRECTNESS, not just safety — do not tune them away to make a distribution look
nicer.**

⚠ **THE RUNAWAY GUARD WAS REDESIGNED; DO NOT MODEL THE OLD ONE.** It no longer counts activations,
it counts **repeats** — an activation keyed by (modifier instance, hook) that has fired before. It
resets **per meld**, and carries a second counter over the whole act that no meld boundary resets,
because a re-scoring runaway would otherwise reset its own budget every lap. Props and legality
CHECKS do not charge it at all. The consequence for a balance model: **the cap no longer trips on
the SIZE of a legal cascade**, so a distribution that used to be clipped by it is not any more and
any table baked against that clipping is stale. Measured: one placement completing four lines spent
125 activations, of which 1 was a repeat.

⚠ A vertical stack scores at every multiple of 5 and scores the WHOLE stack (5, 10, 15…), heights
6–9 score nothing, and each completion is its own payout — the bottom five being paid again at
height 10 is intended (`Q80`, `Q81`).

## The instrument

`Tools/scoring_sim.py` — a Python port of the scoring model plus a Monte Carlo of shows and runs.

```bash
py solatro/Tools/scoring_sim.py --baseline      # the plan-2 baseline tables
py solatro/Tools/scoring_sim.py --ofat all      # one-factor-at-a-time sweeps
py solatro/Tools/scoring_sim.py --lhs 300       # Latin-hypercube sample
py solatro/Tools/scoring_sim.py --run-sim V2A   # full 12-node run simulation
py solatro/Tools/scoring_sim.py --goals V2A     # the goal-curve view
```

⚠ **THE CLI ABOVE IS THE RETIRED TABLEAU'S.** `--grid-goals`, `--grid-show` and `--parity` are the
live ones; the file's own docstring now separates them.

⚠ **ITS OWN DOCSTRING LISTS THE SIMPLIFICATIONS IT ALREADY HAD** — arrangement is not
legality-constrained, props are static rank-weighted gutter points with no ticks or cascades,
Entrance persistence across acts is not modelled. Those were acceptable for the tableau. Decide
explicitly which survive the grid model rather than inheriting them silently, and write the decision
down.

The scoring-math plan the sim's docstring used to cite throughout is not in this repo; those
dangling citations are gone.

## Environment — traps that have each cost real time

- Godot here is **4.7.2**; `.claude/memory/machine-profiles.md` records the binary per box.
- Suite, from the repo root, WINDOWED:
  ```bash
  GODOT_BIN="C:\Users\khanr\Desktop\Godot_v4.7.2-stable_win64_console.exe" py solatro/Tools/run_tests.py --timeout 1800
  ```
  **EXPECT: ALL 45 SUITES, ONE failure** — `TP-85`'s documented mid-growth flake, which may or may
  not fire. Every other suite reports `ALL … CHECKS PASSED`.
  ⚠ **USE 1800.** The old advice was 600, measured against a `user://settings.tres` poisoned with
  `base_delay` 0.1 — a tenth of the real value — so every animation in every non-isolating suite
  ran ten times too fast. That file is restored and the honest runtime is far longer: `SUIT PROPS`
  alone takes **6m40s**. A run dying with `NO SUITE BANNER` reads exactly like a hang and is
  usually just the timeout.
  ⚠ **THE AGGREGATE BANNER'S COUNT DISAGREES WITH THE SUITES IT AGGREGATES.** Measured: it said
  `12 FAILED (1 behavior, 0 implementation)` while every per-suite banner said `ALL … CHECKS
  PASSED` except `GRID LAYOUT`'s `133 passed, 1 FAILED of 134`. Unexplained. **Read the per-suite
  banners and the `[FAIL]` lines, never the aggregate.**
  ⚠ **Judge by WHICH checks fail, never the count.** A NEW failure needs TWO full runs, or the
  suspect suite run alone, before you blame a change for it.
- ⚠ **The owner's Godot editor stays OPEN** — it hosts the `godot-ai` MCP. Leave it alone. The
  one-process rule binds GAME and TEST processes only. Never kill by image name or a
  `Get-Process|Where-Object` pipeline (a hook blocks it).
- ⚠ **`--check-only --script` IS NOT USABLE HERE** — it fails on unresolved autoloads. Launch a
  scene for two seconds instead; a compile break is instant to see. The same applies to
  `--headless --script`: anything touching an autoload (`SettingsManager`) will not compile.
- `export PYTHONIOENCODING=utf-8` before any python heredoc.
- ⚠ **`user://settings.tres` WAS poisoned and has been RESTORED to defaults** (owner permission).
  It carried `act_event_cap` 60 against a default of 6000, which aborted any placement completing
  several melds at once. If a suite ever dies by timeout again, check this file FIRST: a killed run
  never reaches its restore, and test values become the player's live settings.
  ⚠ **RESTORING IT ALSO RETIRED THE STANDING `116.0 px` GRID LAYOUT FAILURE** that `GAP-030`'s
  "cross-suite settings interference" was blamed for throughout the board work. The injection seam
  is still worth building; the symptom it was credited with was this file.

## Owner working agreements

- **Never commit to `main`** — the owner drives it through GitHub Desktop. **On any other branch
  committing is fine and needs no permission**; one verified step per commit, evidence in the
  message.
- **Reuse, do not reinvent.** Declining reuse is fine ON RECORD with the reason.
- **All stacking uses the same code — no duplication.** Stated for the board, and it is a general
  rule: `_stack_slot_center()`, `_size_stack_slot()` and `_bind_stack()` are what it looks like.
- **Online research is allowed and expected** when a blocker may be a misunderstanding rather than a
  design gap. Cite the source, and keep *"the docs say X"* separate from *"I measured X here"*.
- **No design ids in product code** — not in a comment, not in an `@export_group` label. `Tests/` is
  exempt.
- **No comment inside a method body.** A `##` above it says WHY.

## Non-negotiables, each of which caught a real defect in this project

- **MEASURE BEFORE YOU BUILD**, and say whether a number is measured or inferred.
- **RED-THEN-GREEN for every check**, and confirm the red failed the checks you EXPECTED.
  Neutralise the BEHAVIOUR, not the test.
- ⚠ **A TEST THAT RE-DERIVES THE CODE'S OWN FORMULA AGREES WITH IT BY CONSTRUCTION.** Three checks
  here hand-copied a card's anchoring and so could never catch a wrong anchor; they ask the
  production function now. For a SIM, the equivalent is a Python port drifting from the GDScript it
  models — assert them against each other, not each against itself.
- **ASSERT THE PROPERTY, NOT THE TOTAL.**
- **A tunable literal in a source file is a defect**, even when it looks like an epsilon.
- ⚠ **BACKTICKS DIE INSIDE `py -c "..."` FROM THE BASH TOOL** — bash command-substitutes them and
  silently empties the text. Use a heredoc or write the script to a file. Multi-line replace guards
  fail on invisible whitespace too; prefer the Edit tool for those, and beware that a `\` line
  continuation is easy to eat.

## ⚠ Known broken, and NOT yours to fix

- **The picture wall renders wrong** — the map's screen content draws outside its own frame, and the
  map cannot be clicked. Confirmed **pre-existing** (pixel-identical at the commit the board work
  started from) and confirmed **not** caused by the settings file. Nothing in Phase 9 touches it;
  do not let it absorb the phase.
- **`GAP-038` is answered (d) but NOT BUILT** — the HUD moves out of the picture onto the wall
  overlay and fades into wall view. Its gap file carries a measurement a reader will otherwise get
  wrong.

## References

- `design/poker-patience/PLAN.md` — §1.6 IS the economy; §2 Phase 9 is this phase.
- `design/poker-patience/DESIGN.md` — the authority on behaviour.
- `HANDOFF_poker_patience.md` — the board work, its settled geometry and its open items.
- `Tools/scoring_sim.py` — the instrument.
