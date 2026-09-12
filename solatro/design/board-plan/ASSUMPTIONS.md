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
