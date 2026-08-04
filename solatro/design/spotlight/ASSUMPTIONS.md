# SPOTLIGHT — ASSUMPTIONS

Decisions taken while executing `PLAN.md` that the design did not cover, and that were
**reversible and clearly within intent** (gap protocol rule 1). Anything that was not is a file
in `gaps/`, not a line here.

One line each, citing the node it was taken under.

- **2026-08-04, S5 (D3).** `Game.score_line` builds a `ScoringSection` from the live board; a
  section that comes back **empty** skips the spotlight phase AND the re-evaluation, so the
  `Result` the caller handed in is banked unchanged. A real line always has cards (the scorer
  only calls `score_line` when it found a meld), so this only catches a caller that is not
  scoring a board line at all — the unit fixtures do exactly that. A section that HAD cards and
  lost them all is the design's own case and scores nothing (`Q244`=a).
- **2026-08-04, S6/S7 (D12b, `Q201`=b).** Every iteration of `_spotlight_section`'s unbounded
  loop calls `note_processing()`. `Q201` leaves the act-level runaway guard as the only bound,
  and without this the guard cannot see the loop: a chain whose handlers invoke no other mod
  never advances `act_calls`, so it would spin forever instead of tripping `act_event_cap`.
  Counting an activation sweep as one unit of processing is the same accounting the guard
  already applies per mod invoked and per prop slot entry.
- ~~**2026-08-04, S5 (D10, D19/D20, `Q16`).** `forced_spotlight` accumulates across the act's
  sections.~~ **WITHDRAWN the same day, and so was the gap that replaced it.** There was no
  decision here at all: `Q16` says the forced spotlight stays up for the whole act *and* that it
  *"increases or **decreases** based on cards being scored"* — one travelling light, which is
  what shipped. The apparent conflict existed only between two lossy RESTATEMENTS of that answer,
  not in the answer. See **GAP-002 (withdrawn)** for what that cost and what `DESIGN.md` v7
  changed so it cannot recur.
- **2026-08-04, S8 (D13b).** The re-evaluated `Scoring.Result` REPLACES the one passed into
  `score_line`, so the δ duplicate-class decision, `register_combo`, `animate_meld`,
  `show_meld_score` and `_run_score_effects` all read the new hand. `Q243`=(a) asks for the
  lights and jumps to re-cue when the meld changed; feeding every consumer the re-derived
  result is that, with no second code path.
