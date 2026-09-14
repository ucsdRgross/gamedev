# Board plan — assumptions logged during execution

One line each, reversible, within intent, citing the node being worked on. Anything larger is a
gap under `gaps/`.

- S23 / GAP-004: `ramp_match` is entries 6, 31, 3, 15, 12, 9 — gold first, because the activated rim
  wears entry 6 at rest, then the palette's other bright entries (cream, peach, pink, ice, lime), so
  the drift stays readable against a dark cell all the way round.
- S23 / GAP-004: the shimmer's tempo is `OutlineStyle.shimmer_period_fraction` = 2.0, one full
  there-and-back along the ramp per two `get_delay()`s — the slowest of the three alert kinds, which
  is what "slowly interpolate" asked for. It is a knob on the shipped style, not a literal.
- S18 / A3, Q93: `BoardPlan.stocks_of(state)` deals `state.draw_deck` round robin across the
  Entrance's slots, in the pile's own order and with no roll of its own, so the earlier slots take
  the extras; a board with no Entrance slots is one pile. The deal and a redraw both read it, and it
  is deleted when the slots own their own stocks. See `gaps/GAP-001.md`.
- S18 / Q108, Q109: an identity the deal takes leaves EVERY stock's offer and not only the stock it
  came out of, because two stocks can hold the same print — the pool is "every card in every stock,
  still unmarked this show" per PLAN §1.2.
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
  `cells / stocks` stratification are written over it exactly as PLAN §1.2 states; it holds one
  member per Entrance slot.
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
- S5 / Q13: the mark comparison calls `PipComparator.ask_pass` twice with `memoise = false`, so no
  verdict is remembered for the hand being scored -- "derived on every call" expressed through the
  existing dispatch rather than a second one. The hook family is passed as arguments, which that
  helper already takes, so nothing about the deny/allow mechanism was copied.
- S5 / Q41: the two passes are asked BEFORE any presence test, which is what pre-authorisation 9's
  "mirror `PipComparator`'s shape exactly" means: content may rescue a pip a card does not print,
  and only the fall-through to `printed_same` needs both slots filled. `pair_is_same` cannot express
  that -- its fall-through answers true for two absent prints -- so the mark spells the two passes
  over `ask_pass`, the comparator's own per-pass helper, and `PipComparator` is unchanged. A rescued
  rankless card is the no-integer-value case of Q26 and pays `plan_rank_flat_fallback`.
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
- S19 / GAP-002, chart C5: a mark effect reports its "+2" by ANSWERING `on_mark_line_mult(card,
  coord, matched) -> float`, which the composition asks of the mark's copied modifiers for every meld
  card standing on a marked cell, matching or not; every answer is summed into the line's mult. The
  two act hooks fire at BOTH moments -- once from `place_card_in_grid` when the card lands, and again
  for every line score through the cell -- so an effect never has to know which moment it is in.
  `CardEffectApi.add_line_mult` was deleted with its last caller.
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
- S19 / GAP-002: the composition's mult accumulator is a LOCAL of `Game._compose_line_score`. With
  the api seam gone nothing outside the composition can add to it, so a nested re-score inside a mark
  hook leaves the outer line whole without a sentinel or a save/restore.
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
  from a PLACEMENT, so no mod activation has ever fed the combo. `_note_mod_fired` now takes the two
  windows as separate flags: a board-wide BROADCAST (`feeds_act_combo`) still registers only while an
  act resolves, and an ACTIVATION (`counts_as_activation`, `run_mark_mods`'s flag threaded through)
  always registers. Reading the window off "a line is composing" instead would hand the
  combo to every broadcast inside a NESTED composition, and gating on `processing` would revive
  mod-activation combo for every content mod in every cascade -- neither is a change S9 was asked
  for. TP-79 pins the exclusion.
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
- S10 / Q108, Q109: the plan's stored seed has ONE home, `Board._plan_rng`, read by `deal_marks` (a
  late grid) and by `redraw_mark` (one cell). Both draw through one pick, `BoardPlan._take_for_cell`:
  an identity out of the offer, never the one the cell ALREADY prints -- a bare cell prints nothing so
  the deal's offer stands whole, so there is no second copy of the pool rule. ⚠ The deal CONSUMES one
  offer across a pass; rebuilding it per cell gives the same board and cost the plan suite 6x.
- S10 / QR5, what "redraw" means: a reroll's offer EXCLUDES the face it replaces, counted while that
  cell is still marked -- clear first and the cleared identity is the sole fewest-copies card, so on
  the 20-card / 25-cell board a reroll returns the same face forever. The cell is cleared only once a
  replacement is in hand, so an empty offer (an empty draw pile, a stock of one identity) leaves the
  mark standing and writes, bumps and reveals nothing. `reroll_mark` asserts the coordinate names a
  cell and that `plan_seed` is set; `mark_at` keeps its null answer for readers.
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
- S11 / Q63, owner ruling that SUPERSEDES the grey: *"i dont want grid marks to be monochromatic. try
  no outline to indicate it is a mark version for now, no other visual changes."* A marked empty cell
  therefore draws its face exactly as a played card does -- full colour, full size, all four printed
  properties -- and the only thing that says "mark" is that it wears NO RIM. Delivered through the
  outline shader's TYPE override layer (`TypeGridCell.outline_style()` returns the shipped style
  duplicated with `width = 0`), so it is still the palette-and-outline mechanism pre-authorisation 15
  requires and still never `modulate`. The `mark_ink` / `mark_rim` palette roles this step first added
  were REMOVED with the grey: a role nothing reads is a defect.
- S11: MEASURED bug, fixed rather than filed. `CardOutline.material_of` re-seeded `u_outline_width`
  from the shared constant on every call, and it runs AFTER `set_rim` on every refresh (`set_alert`,
  `set_clock`) -- so a per-type `OutlineStyle.width` override was silently overwritten by the shipped
  width and the TYPE layer of ARCHITECTURE_REVIEW §4j could not change a rim's thickness at all. The
  seed is gone; `set_rim` is the one writer. The shader's own default is the same value, so a polygon
  that never reaches `set_rim` is unchanged.
- S11 / Q69: the reveal is driven from `PlayArea.reveal_plan()`, called from `_start_fresh_show` after
  the view rebuild and only when a view exists. The cells still to be dealt live on the PlayArea as
  their own zone cards, `_bind_stack` derives each cell's `CardVisual.mark_drawn` from that list, and
  the per-cell step is the existing `anim_spin` on one tween-scheduled clock (S24)
  -- so a rebuild landing mid-reveal still shows exactly the marks the reveal has dealt.
- S24 / the playtest ruling: the WHOLE opening deal is `plan_reveal_multiplier * get_delay()` (1.0,
  replacing `plan_reveal_fraction`), divided by the cell count into the stagger the cells START
  apart. One `Tween` of delayed callbacks carries that schedule, so the stagger cannot drift with the
  frame rate; each callback deals its cell and leaves `anim_spin(get_delay())` running, so the spins
  OVERLAP and a spin is six tenths of a delay whatever the stagger is. The first cell lands on the
  frame after the reveal is scheduled rather than synchronously, which is what TP-76 stages its
  environment loss around. A spin whose visual is freed by a rebuild dies with it: the tween is bound
  to the CardVisual that created it.
- S11, S12 / owner rulings during execution, verbatim: "no outline on mark when not being selected and
  on board, then white outline when indicating it matches current card being selected to show it
  matches." and "marks dont have specific type for now, keep using the zone type art". PLAN §1.10
  carries both. Read with Q67/Q68 (each matching ELEMENT lights its own outline): the outline that
  lights is white, on a mark whose rest state is no outline at all.
- S11 / Q69: MEASURED bug, one seam. `CardVisual.anim_spin` re-resolved the pacing through
  `CardEnvironment.CURRENT`, which ANY screen entering or leaving the tree rewrites -- so the reveal,
  which awaits between cells, woke up on a null global and threw 24 engine errors mid-deal. The
  reveal already resolves its board once; it now hands that board's `get_delay()` to the spin, which
  is `anim_spin`'s only caller. No guard, no second resolution: the board that starts a reveal is
  what paces it. TP-76 takes the environment away mid-deal with a `FakeEnvironment` entering and
  leaving the tree, which is exactly what a suite running beside PLAN VISUALS does.
- S8 / Q59: the board-wide exclusion lives in `CardEnvironment._dispatch_mods()`, the one walk
  `run_all_mods`, `_compare_implementers` (and so `active_implementers` and every comparator helper)
  and `return_first_data_array_result` share: a marked cell contributes its own `TypeGridCell` and
  nothing the deal copied onto it. ⚠ THE CELL'S OWN TYPE STAYS IN THE WALK, and it is not optional:
  `TypeGridCell.on_can_place_stack` is dispatched through it, so excluding the whole CARD would refuse
  every placement onto a marked cell and end the show at the first legality sweep. `has_card_data()`
  answers the membership question on its own -- a mark is a square, never a card in play -- and the
  spotlight sweep needs no exclusion because `CardModifier.is_spotlit()` asks `BoardPlan.is_marked`
  first. `all_card_datas()` is untouched: relinking walks it and every home of a playing card is in it.
- S12 / Q66, Q67, Q68: the highlight and the landing feedback are ONE derivation,
  `PlayArea._refresh_mark_matches`, called from `set_card_zones_visuals` -- the pass a grab, an
  ungrab, a placement and a rebuild all end in. Each marked cell asks `MarkMatch.matches_at` about
  the held card (the MARK's agreeing elements take `match_rim`) and about every card standing on it
  (that CARD's agreeing elements take `match_rim_active`), and nothing is stored anywhere else, so
  an undo has nothing to un-set. A bare cell is skipped by `BoardPlan.is_marked` before anything is
  asked, which is what keeps an unmarked board at one predicate per cell.
- S12 / Q68, ARCHITECTURE_REVIEW §4j: the per-element rim is the STYLE layer resolved per element
  rather than per card -- `CardVisual._push_outline_ink` now pairs each polygon with the property it
  draws (rank, suit, art = talent, stamp = hat) and hands `set_rim` a duplicate of the shipped style
  in the match ink for the ones that agree. No fourth override layer, no second writer of the rim
  uniform, and never `modulate`. The match style takes the SHIPPED width back, because a mark's own
  style draws no rim at all and an element that lights has to have one.
- S12 / Q66: with a STACK held, the mark lights the union of what every held card agrees with -- the
  whole stack lands on that one cell, so any other reading would light less than what is about to
  happen. No shipped path grabs more than one card onto a grid cell today.
- S12 / Q66, TP-63: every cell `matches_at` reports non-zero for is highlighted, COVERED OR NOT. The
  data decides what agrees and the stack decides what is visible; a covered mark is a sliver, so the
  highlight on it is one too.
- S12 / Q66, Q82=(a): a cell the show cannot place into is not one the card "would match" -- once
  `state.committed_grid` is set, `_refresh_mark_matches` asks about the held card in THAT grid only
  (`Game.place_card_in_grid` refuses every other silently, and `try_place` still reports success, so
  a rim elsewhere promises a placement the board drops). Nothing else about legality enters the
  highlight: the height rules and `on_can_place_stack` can change within a show, the commitment
  cannot. The realized (`match_rim_active`) half still walks every grid -- the commitment lifts when
  the committed grid runs out of legal placements, and the cards standing in an earlier one keep
  their rims.
- S12 / TEST_PLAN TP-63: the pick-up is driven through `Viewport.push_input` in both the mouse and
  the keyboard route, which needs a real `GameView`; the event synthesis moved out of
  `test_interaction.gd` into `Tests/Support/test_input.gd` and both suites now share the one driver.
  The fixture's board carries NO dealt plan (the planner card is dropped from its rules row) and
  grants three marks by hand, so what a held card agrees with is a property of the test rather than
  of the shuffle.
- S12 / GAP-004: `match_rim` = 31 `#eddcc0` and `match_rim_active` = 6 `#f8c300`. The owner's ruling
  says WHITE and `Assets/CircusCrayon.png` has no white entry, so the choice is parked on GAP-004
  and these two values are what S12 was built, tested and photographed against; a ruling moves one
  number in `roles.tres` and nothing else, because every test asserts the ROLE.
- S13 / Q113, Q114, Q117: entering and leaving are the two shapes the answers asked for, over ONE
  flag (`PlayArea.plan_layer_open`). The InputMap action is a PEEK -- `is_action_pressed` opens it
  and `is_action_released` closes it, read in `_consume_as_view_action` beside Back/Forward -- while
  the HUD control TOGGLES: press to enter, press again to leave. Either way one board mutation
  closes it, so the two routes cannot disagree about what is on screen.
- S13 / Q115, Q116: "input is locked to looking" is drawn at the SELECTION line. `PlayArea`'s two
  `data_selected` emitters now go through `_select_data`, which is silent while the view is open, so
  grabbing, placing and dropping are refused on the mouse, the keyboard and the controller at once;
  `GameView` asks `_board_is_playable()` before undo and before end-show. Camera navigation --
  focus, overview, pan, Back/Forward, the arrow cursor -- is untouched, which is what makes
  `Q116`=(b) mean anything, and inspection still opens the info card.
- S13 / Q19, pre-authorisation 14: in the marks layer each grid cell draws its mark exactly as an
  empty marked cell draws it (full colour, no rim, the zone frame) and the cards played on it are
  hidden -- `CardVisual.visible`, derived in `update_grid_zone_visuals` on every refresh, never
  `modulate` and never a second renderer. A cell whose standing card realizes its mark has the MARK
  wear `match_rim_active` on the agreeing elements, because the card that would have worn it is the
  one being hidden. Unmarked cells draw their bare frame; the Entrance, the hand, the HUD and the
  deck viewer are untouched.
- S13 / Q19, owner ruling adopted in review: WHAT IS LOOKED AT IS WHAT IS DRAWN. While the layer is
  open a covered cell's FOCUS target and its `card_info` inspection are its MARK, and the focus
  brighten lands on the mark's visual; when it closes both are the played card again. One seam --
  `_size_stack_slot(slot, marks_layer)` collapses the cell's cards and gives the zone card the size,
  the hit area and `FOCUS_ALL`, so `focused_control` -> `ui_data` resolves to the mark with no
  reader asking twice; `_cell_focus_control` asks it which child is focusable rather than assuming
  the first. The `plan_layer_open` setter re-grabs the cell the cursor was on across the swap, so a
  peek never leaves the board without a cursor; focus on the HUD or the Entrance is left alone.
- S13 / pre-authorisation 17: the close lives in `PlayArea.queue_rebuild()` (the one call every
  revision bump reaches) and in `setup_gui()` (the rebuild an undo or a resume drives), in both
  cases AFTER the rebuild is under way -- a close asks for a visual refresh, and a refresh run
  against a board whose data has already changed reads a stale control tree.
- S13 / Q117, NAMES: `ui_plan_layer` is bound to the `M` key (`M` for mark) and to the X face
  button (`button_index` 2), both HELD to peek. Every shoulder was already taken -- L1/R1 are
  `wall_back` / `wall_forward` and the L2/R2 triggers are `grid_pan_left` / `grid_pan_right` -- so
  GAP-005 put the peek on the one free face button.
- S13 / TEST_PLAN TP-69: the mutation that closes the view is `swap_marks`, not `reroll_mark`. The
  PLAN VISUALS fixture deliberately runs with no planner card, so `plan_seed` is 0 and `reroll_mark`
  asserts on it; `swap_marks` is the same kind of caller -- a mark effect bumping `revision` -- and
  needs no dealt plan.
- S15 / Q104, Q105: the sim models a TALENT match from the card tuple's existing skill flag and
  models NO HAT at all -- a sim card carries no stamp slot, and no deck the grid model plays prints
  one. `M` is therefore 0 on every ladder line today and the composition reduces to `hand + flats`;
  a non-zero `M` is exercised by the engine's own MARK MATCH suite, not by the port.
- S15 / Q103, Q104: the sim has never modelled prop scoring and does not start now, so the suit rule
  is invisible to it. The parity boards are therefore dealt and filled from `PipSuitTest`, which
  spawns nothing: a standard suit fires its props the moment its cell's mark agrees on suit, and
  that would hand the port engine points it has no way to account for.
- S15 / Q25, Q104: `meld_positions` re-derives `Scoring.Result.meld` from the tag the port already
  returns, which is exact at the five cards a flat board's lines hold -- a house at scale 1, a
  scoring straight and a flush each consume the whole line, so only a set leaves cards outside it.
  A high-card line pays its single highest card, first of equals, mirroring `HighCardHandler`.
- S15 / Q8, Q99: the sim's deal draws on a generator of its own, seeded from the show's plan seed
  exactly as `plan_seed` is kept apart from the shuffle. Drawing it from the placement stream would
  shift every later choice, and the marked ladder would stop being paired with the unmarked one it
  is read against.
- S15 / TEST_PLAN TP-80: a parity board is filled with 25 cards drawn WITH REPLACEMENT from its
  deck's identities, so every board completes all twelve lines and the repeats make the sets whose
  meld leaves cards outside it. The parity deal is NOT a fewest-copies deal, though: `PipSuitTest.id`
  is a plain `var` that `duplicate_deep` does not carry, so every copied mark prints suit 0 and
  `_copies_of` counts no board copies of the suit-1..3 identities. Parity is unaffected -- the sim
  scores the marks the engine dumped -- and BOARD PLAN is where the fewest-copies rule is proven.
- S15 / Q104: the placement oracle values a placement by the COMPOSED line number, because it reads
  the same composition the board banks -- par play therefore sees the plan and places into the cells
  whose marks it agrees with.
- S15 / Q120: the goal tool's `shipped` reference column was still printing the retired tableau
  constants; it now reads two named mirrors beside the other PlayerSettings values, so the column
  means what the game ships.
- S22 / GAP-006: `goal_g0` is 18720, derived not transcribed -- at a flat alpha the beatable fit's
  largest legal `g0` is the ladder's own minimum, so `--grid-goals` now prints a FLAT line beside
  BEATABLE (`fit_power_beatable` scanned with alpha pinned to 0) and that line is the number:
  `FLAT: goal(N) = 18720.0 (alpha pinned to 0) tightness 0.47 of the ladder`, node 12's 25th
  percentile at 800 trials. The sim's `SHIPPED_G0` / `SHIPPED_ALPHA` mirrors moved with it.
- S20 / GAP-003: `reroll_line` and `reroll_grid` collect their cells and hand them to
  `CardEffectApi._redraw_marks`, the ONE write path all three rerolls share -- `Board.redraw_mark`
  per cell, so the pool rule has no second copy, and ONE `revision` bump after the batch rather than
  one per cell.
- S20 / GAP-003: a diagonal is the one line shape that does not reduce to an index and a height, so
  `ScoringSection` carries `line_cells`, the cells the line runs through, written by both grid
  constructors (the column walk is public as `LineGeometry.col_cells` for it). `_collect_grid_line` collects
  over that same list through `_cards_on_cells`, so the walk is not written twice.
- S19 / GAP-002: the query's dispatch is `CardEnvironment.run_mark_query(card, function, ...params)
  -> float`, named after `run_mark_mods` it shares its modifier list and skill gate with. It charges
  no processing and passes `feeds_act_combo = false`, so an answer registers nothing even while the
  placement's own act is cancellable.
- S19 / GAP-002: the landing dispatch sits in `place_card_in_grid` after the card has settled and
  before `_broadcast_board_mutation`, which is what the line detector scores from -- so a mark acts
  before any line through its cell can. It is inside the act, so undo rewinds what it did.
