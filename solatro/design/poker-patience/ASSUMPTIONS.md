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

- **S36** — the pending placement is identified by its **Entrance slot**, not by the card.
  `Q236` says *the card and the target coordinate*, but names no way to write a card on disk:
  the pre-placement board a replay starts from is a restored snapshot carrying its own copies
  of every card, so no reference to the original survives. The slot is the only stable handle,
  and chart A has the player picking from the Entrance and nowhere else. Carried in two new
  `RunState` fields beside the existing `pending_action` (`pending_placement_slot`,
  `pending_placement_coord`). A placement whose card is NOT in the Entrance — an effect
  placing one, a test driving the engine — records no marker: it is not a player action, and
  there is no slot to replay it from. Reversible: the marker is write-only state cleared on
  every commit.

- **GAP-008** — `TypeGridCell.on_can_place_stack` accepts whenever the target is its OWN zone
  card, with no emptiness test of its own. The owner said a cell *"can always place ... by
  default"*, and chart A6/A7 says occupied cells refuse; both hold at once because an occupied
  cell presents the card on top of it as the drop target rather than its zone card, which is
  the convention `_no_held_card_has_a_legal_placement` already used. Reversible: adding an
  emptiness test here would change nothing today.

- **GAP-008** — `GameData.cell_type_coord(card)` is a linear scan of `cell_types`, not a
  fourth position index. It is asked once per player drop; the three indexes that do exist are
  there for hot per-card lookups and each one is a second representation that `validate()` then
  has to police. Reversible: the signature is what callers see.

- **H4/H6 (S26)** — the two view modes ship as STATE plus the input wiring only: the overview and
  the focused view differ in what a click does (orientation vs placement), not yet in what the
  camera shows. The camera move that makes the difference visible is the `H22`/`H23` stepping work
  in `S27`/`S28`; building a second zoom mechanism here would be the duplicate the owner ruled
  against. Reversible: the mode is read from one place.
- **H6 (S26)** — the overview intercepts the keyboard/controller `ui_accept` press on a grid
  exactly as it intercepts a mouse click, because `Q147` puts placement behind focus regardless of
  which device asks. Grid SELECTION in the overview is `S29`'s.

- **S27** (H7) — Forward with nothing to return to FALLS THROUGH to the wall, exactly as Back does
  from the all-grids view. `Q148` says Forward *"returns to same view as before"*, and before any
  Back has been pressed there is no such view; swallowing the press would make Forward dead on the
  game screen. Reversible: one guard in `PlayArea._consume_as_view_action`.

- **S27** (H9) — `PlayArea.focus_grid` also CENTRES the view on that grid, so `pan_grid` and
  `focused_grid` cannot disagree about where the view is. The design never states it, but a grid
  focused for placement that is not the grid in the middle contradicts *"view should always be
  snapped with a grid in the center"*. Reversible: one call.

- **S27** (H12, `Q159`=b) — `TopLevelVBox` is given `SIZE_EXPAND_FILL` so a board narrower than the
  window sits CENTRED instead of parked at the left edge. A `ScrollContainer` otherwise hands its
  content exactly the content's own minimum width, so the pan range collapsed to nothing with the
  board hard left (measured: one grid centred at 555 in a window centred at 782). This makes the
  "collapse to centre on an axis that already fits" rule the LAYOUT's answer rather than arithmetic
  in the pan. Reversible: one size flag.
- **Swipe direction follows the finger** (`H16`, `Q191`): dragging RIGHT brings the grid on the LEFT into view, i.e. the board moves with the finger. The design fixes that one swipe pans one grid but never which way; direct manipulation is the only reading consistent with the scroll container the pan already rides.
