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
  null) — against every playing card the state holds (draw, discard, either zone, grid cells; never
  a cell type, a zone type or a rules card). The walk IS `all_card_datas()` filtered to those, so no
  home of a playing card can be left out of it.
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
  allotment card sees every grid, which is what S4's deal needs. MEASURED at three grids: a 105-card
  show opens with 75 marks, 25 on each.
- S3 / A1: the planner card's `get_frame()` returns 13, the next unused frame on the rules-card row of
  `Assets/skill_art.png`. Its art is Phase 5's business.
- S3 / PLAN §0: `BOARD_PLANNER_CARD_DESCRIPTION` reads "On game start, deals a mark from the deck onto
  every cell of every grid.", mirroring the allotment card's sentence shape.
- S4 / Q10: a grid added mid-show deals its own marks inside `Board.add_grid`, the one mutator every
  appearance goes through -- the effect api, a fixture standing three grids up, a visual probe -- and
  only when `state.plan_seed != 0`, because at game start the creators add their grids BEFORE the
  planner runs and the planner's deal is the single writer of the opening plan. The deal sits ahead
  of the revision bump, so the rebuild that bump triggers renders a board whose marks are already on
  it.
- S4 / Q10: `CardEffectApi.add_grid` builds a fresh generator seeded from `plan_seed` on every call;
  two grids added in one show draw from identical streams against different boards, which stays
  deterministic across resume. No product break named.
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
- S5 / Q13: the mark comparison calls `PipComparator.pair_is_same` with `memoise = false`, so no
  verdict is remembered for the hand being scored -- "derived on every call" expressed through the
  existing dispatch rather than a second one. The hook family is passed as arguments, which that
  helper already takes, so nothing about the deny/allow mechanism was copied.
- S5 / Q26: "a value not convertible to an int" is `is_finite(rank.value)`. Every `PipRank` carries a
  float `value`, so the only rank with no integer value is one whose value is not a number; TP-35
  builds it with `value = NAN`. `HalfStepRank` does not exist, so the 2.5 case is
  `PipRankNumeral.with_value(2.5)`.
- S5 / QR3, Q34, Q37: `PipComparator._modifier_script` is now public `modifier_script`, so
  whole-card printed identity (I6 and the deal) and a single-slot talent or hat match share ONE
  definition of two slots naming the same thing. `printed_card_same` stays their conjunction.
- S5 / Q41: `mult_bonus`'s first parameter is spelled `_card`, because GDScript warns on an unused
  parameter and warnings are errors here. The type and position are as NAMES.md fixes them; S6's
  composition is what will read the card.
- S5 / TEST_PLAN TP-25: an EFFECT's placement is `Game.place_card_in_grid` with `processing == true`
  -- the branch that tells an effect placing mid-cascade from a player putting a card down. There is
  no grid placement on `CardEffectApi` today, so that is the whole difference between the two paths.
- S5 / TEST_PLAN TP-39: the dispatch count is read at the ENVIRONMENT, so a board with no
  implementer can be counted at all. `CountingEnvironment` moved out of `test_comparator.gd` into
  `Tests/Support/counting_environment.gd` and both suites now share the one probe.
- S6 / Q122, chart C5: no document names how a mark effect reports its "+2" into the line's summed
  mult, and the hooks are `-> void`. The existing content pattern is an effect calling the api, so
  the seam is `CardEffectApi.add_line_mult(amount: float)`, valid only while `score_line` is
  composing a line (asserted). No shipped content uses it yet, so renaming is cheap; NAMES.md carries
  it. Q52=(b) makes the mark hooks fire on every line score through the cell, so `score_line`
  dispatches `on_mark_hit` / `on_mark_covered` for each meld card on a marked cell; the landing-time
  dispatch from `place_card_in_grid` is S9's.
- S6 / Q104, Q122: the composition is ONE named function, `Game._compose_line_score(result)`, called
  from `score_line` where `result.score` used to be read; no document names it. The float product is
  truncated with `int()`, the same narrowing `ScoreModel` uses for its own float multipliers, and the
  `M == 0` skip is `is_zero_approx`.
- S6 / Q46, Q51: EVERY cover fires `on_mark_covered` at level 0, matching or not, and a match fires
  `on_mark_hit` ADDITIONALLY at level 1 -- owner ruling, from Q46's option (d) keeping (a)'s "fires
  for ANY card landing on the cell, matching or not" and Q51=(a)'s "the x2 mark multiplies whatever is
  put on it". DESIGN §27's exclusive branch is a drawing simplification, and PLAN §1.7's own comment
  already says "matching or not".
- S6 / Q49, Q111: the two mark hooks are dispatched through a new `CardEnvironment.run_mark_mods`,
  which is `run_card_mods` with the SKILL gate lifted -- a mark is never spotlit, so the existing
  per-card dispatch would silence the copied skill that IS the mark's behaviour. Both spellings are
  `run_card_mods`'s own body, now `_run_own_mods`, so there is one dispatch loop and not two.
- S6 / Q49: the hook spellings are `MarkMatch.MARK_HIT` / `MARK_COVERED`, named after the leniency
  family's own constants, because NAMES.md forbids retyping a duck-typed name at a call site.
- S6 / Q25: a coordinate's cell type is read through a new `GameData.cell_type_at(coord)`, the
  inverse of `cell_type_coord`; `MarkMatch.matches_at` now calls it too, so the composition and the
  match test cannot disagree about which card a cell's mark is.
- S6 / Q122: `Game.line_mult_bonus` is NAN except while a line composes, which is what
  `add_line_mult`'s assert reads -- the precondition lives in the value it is about rather than in a
  second flag.
- S6 / TEST_PLAN TP-30: the row's fixture re-derived. A pair of 5s melds TWO cards, so a 7 elsewhere
  in the row is outside `result.meld` and pays nothing by TP-36's own rule -- the row that pays
  `hand + 7` is a pair of SEVENS with one of them on a mark printing 7. TP-31 marks both sevens
  (`hand + 14`) and TP-32 needs three meld cards, so it scores three sevens.
- S6 / TEST_PLAN TP-128: `Tests/E2E/test_e2e_run.gd` pins `run.world_seed`. `RunManager.new_run`
  randomizes it and the plan is dealt from it, so the parity fixture's two shows carried DIFFERENT
  marks; with bonuses now banked that made the two boards score differently. Pinning it is what
  makes them one show again.
- S7 / Q87, Q103: the spawn gate lives in ONE place, `PipSuit._spawn_origin`, which every suit's
  `spawn_props()` already opens with. `MarkMatch.matches_at` is a coroutine, so `spawn_props()`
  becomes one too and `Game._run_score_effects` awaits it -- that await is the whole of game.gd's
  change; the rule itself is not restated there.
- S7 / Q87, QR6: an ENTRANCE card can no longer fire a suit effect at all, because the Entrance
  carries no marks and `has_cell` refuses its row. Nothing in the product loses a firing --
  `ScoringSection.of_entrance_row` is not a detected line, so an Entrance card is never in a scored
  meld -- but every suit-prop FIXTURE that stood in the Entrance moved onto marked grid cells.
- S7 / TEST_PLAN TP-40..TP-43: TP-40, TP-41 and TP-42 live in `test_suit_props.gd`, whose hand-built
  boards are the suit-prop instrument; TP-43 lives in `test_mark_match.gd`, which owns the real
  placement path a second meld membership needs.
- S7 / TEST_PLAN TP-41: the all-kinds prop fixture in `test_ui_props.gd` moved onto a marked grid,
  and its 6-column width check went with the Entrance shape it measured: the same claim, through the
  same helper, is asserted at 12 columns by `test_a_board_wider_than_the_window_stays_reachable`.
- S7 / Q87: `test_suit_props.gd` leaves `test_game_headless.gd`'s `ZONE_ONLY_TESTS` list, which that
  suite's own ratchet requires once a file covers a grid.
- S9 / Q54, Q57: `CardEnvironment._run_own_mods` takes a `counts_as_activation` flag, true only from
  `run_mark_mods`. The per-card path (the prop tick) must keep charging nothing -- asking a card a
  question is not an effect firing -- and both paths share the one dispatch loop.
- S9 / Q47: `run_mark_mods` now takes BOTH recipients, the mark and the card that covered it, and
  decides the skill gate itself (`BoardPlan.is_marked(card)` carries a mark's skill in; a real card
  keeps the spotlight rule, which the scoring beam has already satisfied for a meld card). S6 sent
  the placed card through `run_card_mods`, which cannot charge -- a looping effect living on the CARD
  would then have been unbounded, which is exactly what Q57's note forbids. Dispatch is unchanged.
- S9 / Q54: MEASURED, and it is a bug fix, not a decision: `Game._note_mod_fired` gated combo
  registration on `_act_cancellable`, which is set ONLY inside `_perform_next`. The grid game scores
  from a PLACEMENT, so no mod activation has ever fed the combo. The window is now "an act is
  resolving OR a line is composing", the second read off the `line_mult_bonus` sentinel that already
  means exactly that. Gating on `processing` instead would revive mod-activation combo for every
  content mod in every cascade -- a scoring-wide change S9 was not asked for.
- S9 / TEST_PLAN TP-53, TP-54: `TestGridFixtures.board_digest` gained every cell's own mark (printed
  identity plus `granted`), `plan_seed`, `combo_classes`/`combo_repeats` and `total_score`. A digest
  without the marks cannot say that undo or a replay brought the board back. Shared, so the E2E
  parity and the save-reload rows assert them too.
- S9 / TEST_PLAN TP-53: the expectation is the LIVE pre-placement board, with `duplicate_state()` as a
  second witness -- two copies compared with each other agree about anything neither of them carries.
- S9 / TEST_PLAN TP-54: the replay row is built from REAL suits. `PipSuitTest` keeps its id in a plain
  var, so a row of test suits comes back from a snapshot as ONE suit and flushes.
- S10 / QR5: a reroll or a swap MAY touch an occupied cell. The match is re-derived on the next ask
  (Q13=b), so the card standing there reflects the new mark at once, and no shipped content calls
  this surface yet -- the choice is invisible in the product today. What the player SEES when a mark
  changes is Phase 5's.
- S10 / Q108, Q109: the seeded deal has ONE home, `Board.deal_marks` (the private `_deal_late_grid`,
  made public and renamed), called by `add_grid` and by `reroll_mark`. `reroll_mark` clears the cell
  and deals: every other cell is marked, so the deal's own walk reaches that cell alone and takes the
  pool and the seeded pick the opening deal would have taken -- no second copy of either rule.
- S10 / Q53: `grant_mark` does not clear the cell first. `write_mark` assigns all four printed slots
  and `granted` unconditionally, so a preceding `clear_mark` would be dead code; TP-52 grants over a
  mark carrying a skill and a stamp and asserts neither survives.
- S10: the three mutators bump `revision` once, after the write, as the api's own MUTATION section
  contract requires (`add_rules_card` does the same) -- a mark changing mid-show has to invalidate the
  compare-mod cache and rebuild the board.
- S10 / PLAN §3: `mark_at` sits with the BOARD READS accessors and the three writers in the MUTATION
  section rather than all four together, because that section header is where the bump contract is
  stated. `Scripts/board.gd` is edited although S10's file row names only `card_effect_api.gd`, for
  the shared `deal_marks` seam above.
- S11 / Q69, pre-authorised 4: the reveal walks the shuffled deal order, which nothing stored. `deal()`
  records the cells in walk order on a transient `GameData.plan_reveal_order` (never persisted,
  never read by any rule); the view consumes it once at show start. Reversible and invisible.
- S11 / TEST_PLAN TP-74: the row said "and is skippable"; answers.json has `Q69` = (a), "dealt, cell
  by cell", not (c). The row is corrected against the source; no skip is built.
