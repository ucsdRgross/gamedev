# HANDOFF — Phase 9, the goal-curve refit

**Goal:** the grid game's economy is not the tableau's, and the goal curve was fitted to the
tableau's. Extend the simulation to the grid model, then refit `goal_g0` / `goal_alpha` against it.

**Phases 1–8 and 10 are done.** This is the last modelling work in `PLAN.md`.

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

**S38** — Extend `Tools/scoring_sim.py` to the grid model and the §1.6 economy.
**S39** — Refit `goal_g0` / `goal_alpha` and record the derivation.

**Done-when (phase):** the sim runs end to end and the fitted constants are committed **with the
command that produced them**.

⚠ There are **no `TEST_PLAN.md` rows for this phase** — its gate is the sim itself, not the suite.
Do not go looking for TP numbers; do not invent them.

## The curve being refitted

`RunManager.goal_for()`, verbatim in shape:

```
n_hat = goal_n0 + booster_yield * boosters_on_path
goal  = goal_g0 * (n_hat / goal_n0) ^ goal_alpha * difficulty * lap_mult ^ min(lap, 30)
        (* boss_mult on a boss)
```

Shipped today: `goal_g0` **130.0**, `goal_alpha` **4.2**. Both are `PlayerSettings` knobs.

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

⚠ **ITS OWN DOCSTRING LISTS THE SIMPLIFICATIONS IT ALREADY HAD** — arrangement is not
legality-constrained, props are static rank-weighted gutter points with no ticks or cascades,
Entrance persistence across acts is not modelled. Those were acceptable for the tableau. Decide
explicitly which survive the grid model rather than inheriting them silently, and write the decision
down.

⚠ **`SCORING_MATH_PLAN.md` DOES NOT EXIST IN THIS REPO** although the sim's docstring cites it
throughout. Do not go hunting; it is a dangling reference and worth deleting from the docstring
while you are in there.

## Environment — traps that have each cost real time

- Godot here is **4.7.2**; `.claude/memory/machine-profiles.md` records the binary per box.
- Suite, from the repo root, WINDOWED:
  ```bash
  GODOT_BIN="C:\Users\khanr\Desktop\Godot_v4.7.2-stable_win64_console.exe" py solatro/Tools/run_tests.py --timeout 600
  ```
  **EXPECT: ALL 45 SUITES, 2–4 FAILED** — `GRID LAYOUT`'s standing `116.0 px` cross-suite
  interference plus `TP-85`/`TP-87`'s mid-growth flakes. That suite **ALONE** is green.
  ⚠ **USE 600, NOT 400.** It is a GLOBAL wall-clock limit on the whole run; a COLD run exceeds
  400 s and dies with `NO SUITE BANNER`, which reads exactly like a hang.
  ⚠ **Judge by WHICH checks fail, never the count.** A NEW failure needs TWO full runs, or the
  suspect suite run alone, before you blame a change for it.
- ⚠ **The owner's Godot editor stays OPEN** — it hosts the `godot-ai` MCP. Leave it alone. The
  one-process rule binds GAME and TEST processes only. Never kill by image name or a
  `Get-Process|Where-Object` pipeline (a hook blocks it).
- ⚠ **`--check-only --script` IS NOT USABLE HERE** — it fails on unresolved autoloads. Launch a
  scene for two seconds instead; a compile break is instant to see. The same applies to
  `--headless --script`: anything touching an autoload (`SettingsManager`) will not compile.
- `export PYTHONIOENCODING=utf-8` before any python heredoc.
- ⚠ **`user://settings.tres` is POISONED with test values and stays that way.** A pristine default
  is recoverable from `PlayerSettings.new()`. **Do not overwrite it without the owner.**

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

## References

- `design/poker-patience/PLAN.md` — §1.6 IS the economy; §2 Phase 9 is this phase.
- `design/poker-patience/DESIGN.md` — the authority on behaviour.
- `HANDOFF_poker_patience.md` — the board work, its settled geometry and its open items.
- `Tools/scoring_sim.py` — the instrument.
