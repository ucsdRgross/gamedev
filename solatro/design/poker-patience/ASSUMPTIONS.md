# Poker Patience — assumptions log

One line per reversible, clearly-within-intent decision the design did not spell out.
See the gap protocol in `PLAN.md` §0 — this is for (1), not (2)/(3).

- **BoardCoord.step** — beyond the last real grid, or before grid 0, the virtual continuation
  steps at the width of the nearest REAL edge grid (grid 0's width to the left, the last
  grid's width to the right), mirroring that one edge grid rather than, say, some fixed or
  averaged width. Reversible: nothing currently depends on a virtual block's width past
  "some grid-shaped continuation exists."

- **S9** — `Game.add_line_score` returns before its legacy zone-indexed write when
  `section.index < 0` (a grid-model section carries no legacy index). The per-grid bucket
  storage that write is meant to feed is S12's contract (§1.7); until it lands, a detector-scored
  grid line registers its combo class and runs its score effects but banks nothing. Reversible:
  nothing yet reads a grid line's banked amount.
- **S4** — `Board.place_in_cell` / `move_to_cell` always land at the TOP of the destination
  cell (current stack size, i.e. `h+1` of whatever card is already there) and ignore
  `coord.h` on the way in, mirroring `Anchor.ON_TOP`'s "insert above whatever is there"
  rule from the legacy engine rather than trusting a caller-supplied height that could
  disagree with the stack's actual size. PLAN.md §1: "Reuses `Anchor.ON_TOP` for stacking."

- **S12** — Renamed the pre-existing legacy `GameData.scores_col` (the old zone-board flat
  column bucket) to `scores_col_legacy` so the new NAMES.md `GameData.scores_col` (the per-grid
  height-0 column bucket) can use its fixed name without a duplicate-declaration collision.
  Behaviour of the legacy field is unchanged, only the identifier. Reversible: a pure rename,
  every call site updated together (`Levels/game.gd`, `Levels/game_view.gd`, `UI/play_area.gd`,
  and the persistence/board/act-score/game-data test suites).

- **S19** — The tableau card SCRIPTS are kept where they are; only their membership in `rules1`
  (and in `TestDecks.standard_rules`, its frozen mirror) is removed. GAP-007 cancels the archive
  directory and the archive builder, and the owner's bar is *"replace all existing to fit for now
  without throwing errors"* — deleting the files would take their own still-green suites with
  them, which is neither asked for nor "without errors". Reversible: nothing constructs them.

- **S19** — `GameData.live_total()` (`board_total() * combo_mult()`) is what the goal is measured
  against and what fame banks, replacing the retired act payout in `has_met_goal` / `_resolve_game`
  / `exit_show`. Chart D fixes all three parts — D12 the score is board total x combo, D13 there is
  no banking moment, D16 win if total >= goal and fame banks the full total — but no step wires
  them together, so the grid game could not be won at all. `total_score` and `apply_act_score` are
  left untouched: nothing in the grid game feeds them, and they go with the legacy board.
  Reversible: one derived method and three call sites.

- **S19** — A PLAYER's placement opens a fresh activation budget (`_begin_act()` in
  `place_card_in_grid`, guarded on `not processing`). A placement is the grid game's board action,
  the role Submit used to hold, and without the reset the counter climbs across the whole show
  until the pacing ramp floors and the runaway guard suppresses real scoring. The guard is what
  keeps a mid-cascade placement spending the SAME budget as the act that caused it.

- **S19** — `return_to_map()`'s end-of-show sweep now also empties the grid cells back into the
  draw deck. Cell ZONE cards stay, matching how a column header stays with its column. Without it
  a show returns fewer cards than it took.
