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
