# Board plan — assumptions logged during execution

One line each, reversible, within intent, citing the node being worked on. Anything larger is a
gap under `gaps/`.

- S4 / A3, Q93: until sidebar S19 lands, `BoardPlan.deal()` reads ONE stock, `state.draw_deck` — the
  stocks' union per DESIGN §1l-bis. The round-robin loop is written per PLAN §1.2 regardless.
  See `gaps/GAP-001.md`.
- S1 / Q58, QR7: `is_marked` lives in `Scripts/board_plan.gd` as `BoardPlan.is_marked`, as NAMES.md
  fixes it; PLAN §3's S1 row said `Scripts/grid_data.gd` and was corrected. The file is created at
  S1 and `deal()` joins it at S4.
- S2 / Q61, Q121: I6's "names a card printed by some card in the deck" compares every copied slot —
  rank and suit via `PipComparator.printed_same`, skill and stamp by script identity (null equals
  null) — against every playing card the state holds (draw, discard, Entrance, grid cells; never a
  cell type, a zone type or a rules card).
- S1 / Q59: the `is_spotlit()` call site S1's done-when requires is the spotlight exclusion itself,
  so S8's code lands with S1 and S8 only confirms its tests.
- S8 / Q59: MEASURED, and PLAN §1.8's premise is inaccurate for a GRID cell -- a grid card is not
  naturally spotlit at all, because `_blocked_from_above` reads the legacy `position_of` index, which
  carries no grid coordinate and so fails closed. TP-44 therefore contrasts a forced mark against a
  forced playing card: the scoring beam is the only lever that lights a grid card, and the exclusion
  sits ahead of it. The exclusion is still required as specified.
- S8 / Q60: a cell's zone card can never be ABOVE another card (`_blocked_from_above` walks a
  column's `datas`, and `cell_types` is a sibling array), so no fixture can make a mark's
  `blocks_spotlight()` observable through the engine. TP-45 asserts it directly and keeps the
  board-wide spotlit-set comparison as a regression guard; that half stays green when the exclusion
  is removed.
- S3 / Q9: `SkillBoardPlanner` is appended LAST in `_build_rules1()` and in `TestDecks.standard_rules()`.
  `CardEnvironment.run_all_mods` walks `rules_deck` in array order and sweeps the spotlight after each
  mod, so the allotment's creator cards build their grids inside that walk -- only a planner after the
  allotment card sees every grid, which is what S4's deal needs.
- S3 / A1: the planner card's `get_frame()` returns 13, the next unused frame on the rules-card row of
  `Assets/skill_art.png`. Its art is Phase 5's business.
- S3 / PLAN §0: `BOARD_PLANNER_CARD_DESCRIPTION` reads "On game start, deals a mark from the deck onto
  every cell of every grid.", mirroring the allotment card's sentence shape.
- S4 / Q10: a grid added mid-show is dealt by `CardEffectApi.add_grid` itself, and only when
  `state.plan_seed != 0` -- at game start the creators call `add_grid` BEFORE the planner runs, and
  the planner's own deal has to stay the single writer of the opening plan.
- S4 / Q8: the planner reaches the run through two new `CardEffectApi` accessors, which PLAN §3's S4
  row provides for ("the accessors it needs"): `board_state()` for the `GameData` the deal writes
  onto, and `plan_seed_for_node()`, which is `hash(Vector2i(world_seed, current_node_id))` forced off
  0. It reads `Main.save_info`, the never-null mirror of `RunManager.run` that `_start_fresh_show`
  already reads for the node's goal; `RunManager.run` is null outside a run.
- S4 / Q9, Q93: GDScript has no nested typed arrays, so the stock list is `Array[Array]` rather than
  `Array[Array[CardData]]` (the same shape `on_meld_group_ranks` uses). The round-robin and the
  `cells / stocks` stratification are written over it exactly as PLAN §1.2 states; today it holds one
  member, `state.draw_deck`.
- S4 / Q108, Q61: printed identity is compared in ONE place. The four-slot conjunction was inline in
  `GameData._mark_violations`; it is now `PipComparator.printed_card_same`, which I6 and the deal's
  unused set both call, so the invariant and the deal cannot disagree about what "the same card"
  means.
- S4 / Q8: the deal is a function of the plan seed AND the stock's order. The show's shuffled deck is
  saved with the board and a resumed show never re-deals, so nothing re-derives a plan from a
  re-shuffled deck; two shows started on one node with the same deck order deal the same board.
- S4 / Q102, Q108, Q109: "no card is marked again while another is marked less often" holds by COPY
  COUNT, not just by marked-at-all, so the pass in progress is the stock's identities the board has
  marked FEWEST times, recounted off the board at each pass boundary. A deal onto a board that
  already carries marks therefore CONTINUES the cycle rather than restarting it, and every card's
  copy count stays within one of every other's.
- S4 / TEST_PLAN TP-14: the row's arithmetic re-derived. 25 + 25 cells over 20 cards is 50 marks, so
  no cap of two copies per card is possible: 50 is two full passes plus ten cells of a third, which
  makes it exactly ten cards at three copies and ten at two, nothing higher, with grid 0's 25 marks
  unchanged by the second deal. The 52-card variant in the same test is what proves the added grid
  avoids cards used anywhere: 50 cells, 50 distinct.
- S4 / TEST_PLAN TP-09: which cell receives the FIRST mark is not observable on the board, so TP-09
  reads which cells carry a repeat. An unshuffled walk would repeat in the last five row-major cells
  of every deal (100%); a shuffled walk spreads repeats over all 25 (about 40% each), and the test's
  bound is 60% over 200 seeded deals.
- S4 / TEST_PLAN TP-03, TP-15: the "30-card" and "25-card" decks those rows name are
  `deck_standard_52().slice(...)`, so they cannot drift apart from the shipped 52-card fixture.
- S4 / Q78: TP-15's added 26th cell makes `cells` and `cell_types` longer than
  `grid_width * grid_height`, which I2 reports by design, so that row does not assert `validate()`
  clean -- the ragged shape stays in tests exactly as the anti-scope says.
