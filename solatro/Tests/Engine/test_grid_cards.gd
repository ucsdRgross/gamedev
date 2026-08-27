extends TestSuite
# res://Tests/Engine/test_grid_cards.gd
# Phase 4 of the poker-patience board: the rules cards that manage the grid board itself.
# TP-62..TP-65 -- SkillGridAllotment matches the grid count to the deck size at game start.

func suite_name() -> String:
	return "GRID CARDS"

func _ready() -> void:
	TestLog.line("============ GRID CARDS TEST PASS ============")
	check_all_tests_registered()
	run_effect_api_boundary_gate()
	await run_small_deck_yields_one_grid_test()
	await run_the_52_53_boundary_test()
	await run_105_yields_three_grids_test()
	await run_the_cap_holds_test()
	await run_grid_creator_builds_5x5_test()
	await run_unspotlight_discards_grid_cards_test()
	await run_removed_grid_labels_go_score_stays_test()
	await run_meta_card_adds_and_subtracts_creators_test()
	await run_refill_fills_left_to_right_test()
	await run_short_refill_leaves_right_slots_empty_test()
	await run_refill_fires_on_empty_entrance_test()
	await run_refill_fires_on_no_legal_move_test()
	await run_refill_keeps_unused_cards_in_their_slots_test()
	await run_first_placement_commits_the_batch_test()
	await run_placement_into_other_grid_while_committed_refused_test()
	await run_commitment_lifts_when_no_legal_placement_remains_test()
	await run_undo_lifts_commitment_nothing_else_does_test()
	await run_every_placement_is_one_undo_step_test()
	await run_undo_rewinds_every_score_a_placement_made_test()
	await run_a_placement_that_changes_nothing_commits_nothing_test()
	await run_entrance_grabs_regardless_of_stack_test()
	await run_empty_cell_always_accepts_test()
	await run_occupied_cell_refuses_test()
	await run_pending_marker_names_the_placement_test()
	await run_replay_reproduces_the_interrupted_placement_test()
	await run_replayed_refill_is_identical_test()
	finish()

# ==============================================================================
# Helpers: a bare Game wired to a rules deck holding one spotlit SkillGridAllotment,
# mirroring test_grid_economy's detector_game.
# ==============================================================================
func _rules_card(skill: CardModifierSkill) -> CardData:
	var c := CardData.new().with_skill(skill)
	c.stage = CardData.Stage.RULES
	skill.spotlit = true
	return c

## A Game whose draw_deck is `deck` and whose only rules card is a spotlit
## SkillGridAllotment -- enough to fire on_game_start the way Levels/game.gd does.
func _allotment_game(deck: Array[CardData]) -> Game:
	var g := Game.new()
	var state := GameData.new()
	state.draw_deck = _as_draw_deck(deck)
	state.rules_deck = [_rules_card(SkillGridAllotment.new())] as Array[CardData]
	g.state = state
	CardEnvironment.CURRENT = g
	return g

func _free_game(g: Game) -> void:
	CardEnvironment.CURRENT = null
	g.free()

# ==============================================================================
# TP-62 -- FIX-DECK-20 -> 1 grid.
# ==============================================================================
func run_small_deck_yields_one_grid_test() -> void:
	behavior_section("A SMALL DECK YIELDS ONE GRID")
	var g := _allotment_game(TestDecks.deck_20())
	await g.run_all_mods(&"on_game_start")
	check(g.state.grids.size() == 1,
			"a 20-card deck allots exactly 1 grid",
			"got %d" % g.state.grids.size())
	_free_game(g)

# ==============================================================================
# TP-63 -- FIX-DECK-52 -> 1 grid; FIX-DECK-53 -> 2. The exact-multiple boundary.
# ==============================================================================
func run_the_52_53_boundary_test() -> void:
	behavior_section("THE 52/53 BOUNDARY")
	var g52 := _allotment_game(TestDecks.deck_standard_52())
	await g52.run_all_mods(&"on_game_start")
	check(g52.state.grids.size() == 1,
			"an exact multiple of grid_cards_per_unlock (52) does NOT round up",
			"got %d" % g52.state.grids.size())
	_free_game(g52)

	var g53 := _allotment_game(TestDecks.deck_53())
	await g53.run_all_mods(&"on_game_start")
	check(g53.state.grids.size() == 2,
			"one card past the boundary (53) rounds up to 2",
			"got %d" % g53.state.grids.size())
	_free_game(g53)

# ==============================================================================
# TP-64 -- FIX-DECK-105 -> 3 grids.
# ==============================================================================
func run_105_yields_three_grids_test() -> void:
	behavior_section("105 CARDS YIELDS THREE GRIDS")
	var g := _allotment_game(TestDecks.deck_105())
	await g.run_all_mods(&"on_game_start")
	check(g.state.grids.size() == 3,
			"a 105-card deck allots exactly 3 grids",
			"got %d" % g.state.grids.size())
	_free_game(g)

# ==============================================================================
# TP-65 -- the cap holds: a 300-card deck still yields 3, not more.
# ==============================================================================
func run_the_cap_holds_test() -> void:
	behavior_section("THE CAP HOLDS")
	var big : Array[CardData] = []
	for _i : int in 6:
		big.append_array(TestDecks.deck_standard_52())
	var g := _allotment_game(big)
	await g.run_all_mods(&"on_game_start")
	check(g.state.grids.size() == 3,
			"a deck far past 3 grids' worth is still capped at grid_max_count (3)",
			"got %d" % g.state.grids.size())
	_free_game(g)

# ==============================================================================
# Helper: a bare Game with one spotlit SkillGridCreator card in the rules deck, and the card
# itself for the test to call its hooks on directly.
# ==============================================================================
func _creator_game() -> Array:
	var creator := SkillGridCreator.new()
	var g := Game.new()
	var state := GameData.new()
	state.rules_deck = [_rules_card(creator)] as Array[CardData]
	g.state = state
	CardEnvironment.CURRENT = g
	return [g, creator]

# ==============================================================================
# TP-66 -- FIX-GRID-1: the grid creator builds a 5x5 grid on on_spotlight.
# ==============================================================================
func run_grid_creator_builds_5x5_test() -> void:
	behavior_section("THE GRID CREATOR BUILDS 5X5")
	var parts := _creator_game()
	var g : Game = parts[0]
	var creator : SkillGridCreator = parts[1]
	await creator.on_spotlight()
	check(g.state.grids.size() == 1,
			"on_spotlight adds exactly one grid",
			"got %d" % g.state.grids.size())
	var grid : GridData = g.state.grids[0]
	check(grid.grid_width == 5 and grid.grid_height == 5,
			"the grid is 5 wide and 5 tall",
			"got %d x %d" % [grid.grid_width, grid.grid_height])
	check(grid.cells.size() == 25 and grid.cell_types.size() == 25,
			"25 cell zone cards were built, one real card per cell",
			"got %d cells, %d types" % [grid.cells.size(), grid.cell_types.size()])
	_free_game(g)

# ==============================================================================
# TP-67 -- FIX-ROW-FLUSH: on_unspotlight removes the grid and discards its cards.
# ==============================================================================
func run_unspotlight_discards_grid_cards_test() -> void:
	behavior_section("ON_UNSPOTLIGHT REMOVES THE GRID AND DISCARDS ITS CARDS")
	var parts := _creator_game()
	var g : Game = parts[0]
	var creator : SkillGridCreator = parts[1]
	await creator.on_spotlight()
	var occupant := CardData.new()
	g.state.grids[0].cells[0].datas.append(occupant)
	await creator.on_unspotlight()
	check(g.state.grids.is_empty(),
			"the grid is gone from the board",
			"still %d grids" % g.state.grids.size())
	check(occupant in g.state.discard_deck,
			"the card that was sitting in a cell was discarded",
			"discard_deck: %s" % [g.state.discard_deck])
	_free_game(g)

# ==============================================================================
# TP-68 -- FIX-ROW-FLUSH, Q126: a removed grid's labels go; accumulated score does not.
# ==============================================================================
func run_removed_grid_labels_go_score_stays_test() -> void:
	behavior_section("A REMOVED GRID'S LABELS GO -- ACCUMULATED SCORE DOES NOT")
	var parts := _creator_game()
	var g : Game = parts[0]
	var creator : SkillGridCreator = parts[1]
	await creator.on_spotlight()
	# A second grid, untouched, to prove the removal shifts indices rather than wiping siblings.
	var other := GridData.new()
	Board.add_grid(g.state, other)
	g.state.total_score = 500
	g.state.resize_grid_bucket(g.state.scores_row, 2)
	g.state.resize_grid_bucket(g.state.scores_col, 2)
	g.state.resize_grid_bucket(g.state.score_special, 2)
	g.state.scores_row[0].plus_equals(10)
	g.state.scores_col[0].plus_equals(20)
	g.state.score_special[0].plus_equals(30)
	g.state.scores_row[1].plus_equals(40)
	g.state.bank_cell_score(0, Vector2i(1, 1), 5)
	g.state.bank_cell_score(1, Vector2i(2, 2), 7)

	await creator.on_unspotlight()

	check(g.state.total_score == 500,
			"the banked total is untouched by removing the grid",
			"got %d" % g.state.total_score)
	check(g.state.scores_row.size() == 1 and g.state.scores_row[0].to_float() == 40.0,
			"the removed grid's row label is gone and the surviving grid shifted down to index 0",
			"got size %d, value %f" % [g.state.scores_row.size(), g.state.scores_row[0].to_float()])
	check(g.state.cell_score(0, Vector2i(2, 2)) == 7.0,
			"the surviving grid's cell label shifted down with it",
			"got %f" % g.state.cell_score(0, Vector2i(2, 2)))
	check(g.state.cell_score(0, Vector2i(1, 1)) == 0.0,
			"the removed grid's cell label is gone",
			"got %f" % g.state.cell_score(0, Vector2i(1, 1)))
	_free_game(g)

# ==============================================================================
# TP-69 -- FIX-DECK-53, Q202: the meta card adds AND subtracts persistent creator cards on
# deck change -- both directions in one test.
# ==============================================================================
func run_meta_card_adds_and_subtracts_creators_test() -> void:
	behavior_section("THE META CARD ADDS AND SUBTRACTS PERSISTENT CREATORS")
	var g := _allotment_game(TestDecks.deck_20())
	await g.run_all_mods(&"on_game_start")
	check(_creator_count(g) == 1,
			"a small deck leaves exactly one persistent creator card",
			"got %d" % _creator_count(g))
	check(g.state.grids.size() == 1,
			"and that creator built its grid",
			"got %d grids" % g.state.grids.size())

	# GROWS past a boundary: swap in a big deck and re-run the same game-start hook.
	var big : Array[CardData] = []
	for _i : int in 6:
		big.append_array(TestDecks.deck_standard_52())
	g.state.draw_deck = big
	await g.run_all_mods(&"on_game_start")
	check(_creator_count(g) == 3,
			"a deck far past the cap grows the creator count to the cap (3)",
			"got %d" % _creator_count(g))
	check(g.state.grids.size() == 3,
			"and grid count follows",
			"got %d grids" % g.state.grids.size())

	# SHRINKS back: swap in a small deck and re-run again.
	g.state.draw_deck = TestDecks.deck_20()
	await g.run_all_mods(&"on_game_start")
	check(_creator_count(g) == 1,
			"shrinking the deck subtracts creator cards back down to one",
			"got %d" % _creator_count(g))
	check(g.state.grids.size() == 1,
			"and grid count follows back down",
			"got %d grids" % g.state.grids.size())
	_free_game(g)

## How many persistent SkillGridCreator cards are in the rules deck right now.
func _creator_count(g: Game) -> int:
	var n := 0
	for card : CardData in g.state.rules_deck:
		if card.skill is SkillGridCreator: n += 1
	return n

# ==============================================================================
# TP-70..TP-74 -- S17: TypeInput's on_next is gone; the Entrance refills itself left to
# right, on the same two triggers (empty Entrance / no legal move), through on_game_start
# (the initial deal) and on_card_placed (every later placement).
# ==============================================================================

## A bare Game with 5 spotlit SkillAdderInputUpper cards (the Entrance's 5 columns) and no
## grid. Returns the game and the 5 TypeInput header instances, left to right.
## Stamps a hand-assigned deck DRAW and returns it. Assigning `state.draw_deck` directly
## skips `Game.add_deck`, which is what normally stamps the stage, and `validate()` checks a
## card's stage against where it actually sits -- so without this every undo in the suite
## reports the whole deck as I5 violations (stage PLAY, expected DRAW).
func _as_draw_deck(deck: Array[CardData]) -> Array[CardData]:
	for card : CardData in deck:
		card.stage = CardData.Stage.DRAW
	return deck

func _entrance_game(deck: Array[CardData]) -> Dictionary:
	var g := Game.new()
	var state := GameData.new()
	state.draw_deck = _as_draw_deck(deck)
	var adders : Array[SkillAdderInputUpper] = []
	for _i : int in 5:
		adders.append(SkillAdderInputUpper.new())
	var rules : Array[CardData] = []
	for adder : SkillAdderInputUpper in adders:
		rules.append(_rules_card(adder))
	state.rules_deck = rules
	g.state = state
	CardEnvironment.CURRENT = g
	var headers : Array[TypeInput] = []
	for adder : SkillAdderInputUpper in adders:
		await adder.on_spotlight()
		headers.append(adder.card_data.type as TypeInput)
	return {"game": g, "headers": headers}

## Deals the initial hand the way the game does: ask for a refill. The DECISION is the
## game's (the Entrance is empty, so it is due one); the headers each fill their own slot,
## left to right, in dispatch order.
func _deal(g: Game) -> void:
	await g.refill_entrance_if_due()

# ==============================================================================
# TP-70 -- FIX-DECK-52: a full refill fills slots 0-4 in draw order, leftmost first.
# ==============================================================================
func run_refill_fills_left_to_right_test() -> void:
	behavior_section("A FULL REFILL FILLS LEFT TO RIGHT")
	var deck := TestDecks.deck_standard_52()
	# ⚠ Capture the expectation BEFORE handing the deck over: _entrance_game moves the cards
	# into the draw deck and leaves this array empty, so reading it afterwards is out of bounds.
	# draw_card() pops from the BACK, so the leftmost slot gets the LAST card.
	var expected : Array[CardData] = []
	for i : int in 5:
		expected.append(deck[deck.size() - 1 - i])
	var parts := await _entrance_game(deck)
	var g : Game = parts["game"]
	await _deal(g)
	var ok := true
	for i : int in 5:
		if g.state.upper_zone[i].datas.size() != 1 or g.state.upper_zone[i].datas[0] != expected[i]:
			ok = false
	check(ok, "the deck's last 5 cards land in slots 0-4 in that exact order",
			"upper_zone: %s" % [g.state.upper_zone.map(func(c: ArrayCardData) -> String: return str(c.datas))])
	_free_game(g)

# ==============================================================================
# TP-71 -- FIX-DECK-20: a short refill fills leftmost first, leaving the right slots empty.
# ==============================================================================
func run_short_refill_leaves_right_slots_empty_test() -> void:
	behavior_section("A SHORT REFILL FILLS LEFTMOST FIRST")
	var deck := TestDecks.deck_20().slice(0, 3)  # only 3 cards left to deal
	var parts := await _entrance_game(deck)
	var g : Game = parts["game"]
	await _deal(g)
	check(g.state.draw_deck.is_empty(), "the short deck was drained entirely",
			"got %d cards left" % g.state.draw_deck.size())
	for i : int in 3:
		check(g.state.upper_zone[i].datas.size() == 1,
				"slot %d got one of the 3 available cards" % i,
				"got %d cards" % g.state.upper_zone[i].datas.size())
	for i : int in [3, 4]:
		check(g.state.upper_zone[i].datas.is_empty(),
				"slot %d stayed empty -- the deck ran out before reaching it" % i,
				"got %d cards" % g.state.upper_zone[i].datas.size())
	_free_game(g)

# ==============================================================================
# TP-72 -- FIX-DECK-52: refill fires when the Entrance is empty.
# ==============================================================================
func run_refill_fires_on_empty_entrance_test() -> void:
	behavior_section("REFILL FIRES ON AN EMPTY ENTRANCE")
	var deck := TestDecks.deck_standard_52()
	var parts := await _entrance_game(deck)
	var g : Game = parts["game"]
	check(g.state.upper_zone.is_empty() or g.state.upper_zone[0].datas.is_empty(),
			"the Entrance starts empty, before any deal", "setup invariant broke")
	await _deal(g)
	var filled := 0
	for column : ArrayCardData in g.state.upper_zone:
		if column.datas.size() == 1: filled += 1
	check(filled == 5, "an empty Entrance triggers a full refill of all 5 slots",
			"got %d filled slots" % filled)
	_free_game(g)

# ==============================================================================
# TP-73 -- FIX-GRID-1: refill also fires when no legal move remains, with cards still held.
#
# "No legal move" is made true by construction: the grid's cells are TypeGridCell zone cards,
# which implement no on_can_place_stack at all (that acceptance rule ships in a later step),
# so any grid built by SkillGridCreator has zero legal placements for anything held in the
# Entrance -- the same on_can_place_stack dispatch try_place uses (via CardEffectApi.
# can_place_stack) simply never finds a claimant.
# ==============================================================================
func run_refill_fires_on_no_legal_move_test() -> void:
	behavior_section("REFILL FIRES ON NO LEGAL MOVE, WITH CARDS STILL HELD")
	var deck := TestDecks.deck_standard_52()
	var parts := await _entrance_game(deck)
	var g : Game = parts["game"]
	var creator := SkillGridCreator.new()
	g.state.rules_deck.append(_rules_card(creator))
	await creator.on_spotlight()
	# ⚠ THE BOARD HAS TO BE GENUINELY FULL. A cell always accepts a card, so "no legal move
	# anywhere" is only true when there is no EMPTY cell left: an occupied one presents the
	# card on top of it as the target, and nothing answers for a played card. Fill 24 of the 25
	# directly (no broadcast, no scoring -- these are scenery), leaving (4,4) for the placement
	# below to close. Before the rule shipped this was vacuously true and the test passed
	# without ever making it so.
	var grid : GridData = g.state.grids[0]
	for i : int in grid.cells.size() - 1:
		var filler := TestFactories.m_card(i % 13 + 1, TestFactories.uc())
		Board.place_in_cell(g.state, filler, BoardCoord.new(0, i % 5, i / 5, 0))
	await _deal(g)  # slots 0-4 filled

	# Slot 2's card goes into the last empty cell, through the real placement path, which
	# broadcasts on_card_placed to every mod and then asks whether a refill is due.
	await g.place_card_in_grid(_held(g, 2), BoardCoord.new(0, 4, 4, 0))

	check(g.state.upper_zone[2].datas.size() == 1,
			"slot 2 refilled even though slots 0,1,3,4 still hold cards (no legal move anywhere)",
			"got %d cards in slot 2" % g.state.upper_zone[2].datas.size())
	_free_game(g)

# ==============================================================================
# TP-74 -- FIX-DECK-52: unused cards keep their slots across a refill.
# ==============================================================================
func run_refill_keeps_unused_cards_in_their_slots_test() -> void:
	behavior_section("UNUSED CARDS KEEP THEIR SLOTS ACROSS A REFILL")
	var deck := TestDecks.deck_standard_52()
	var parts := await _entrance_game(deck)
	var g : Game = parts["game"]
	var creator := SkillGridCreator.new()
	g.state.rules_deck.append(_rules_card(creator))
	await creator.on_spotlight()
	await _deal(g)

	var untouched : Array[CardData] = [
		g.state.upper_zone[0].datas[0], g.state.upper_zone[1].datas[0],
		g.state.upper_zone[3].datas[0], g.state.upper_zone[4].datas[0],
	]
	var placed_card : CardData = g.state.upper_zone[2].datas[0]
	g.state.upper_zone[2].datas.clear()
	await g.place_card_in_grid(placed_card, BoardCoord.new(0, 0, 0, 0))

	check(g.state.upper_zone[0].datas[0] == untouched[0]
			and g.state.upper_zone[1].datas[0] == untouched[1]
			and g.state.upper_zone[3].datas[0] == untouched[2]
			and g.state.upper_zone[4].datas[0] == untouched[3],
			"the 4 untouched slots kept the exact same cards across the refill",
			"one of slots 0,1,3,4 changed identity")
	_free_game(g)

# ==============================================================================
# TP-75..TP-78 -- S18: commit, silent commitment, and the lift when no legal placement
# remains. `FIX-GRID-3`.
#
# The real grid-cell acceptance rule ships in a later step (TP-73's note above), so these
# tests use a small test-double rules card that accepts a stack onto any of ONE grid's still-
# EMPTY cells (a cell_types card) and refuses a cell already holding a card -- no stacking.
# That is enough to drive commit / refuse / lift through the exact same
# on_can_place_stack / can_place_stack dispatch try_place and place_card_in_grid use, and it
# makes "every cell occupied" and "no legal placement remains" coincide (PLAN.md's Q32 note),
# so filling the grid's last empty cell is exactly the trigger TP-77 needs.
# ==============================================================================

## FIX-GRID-3 wired with a dealt Entrance and one grid whose cells the test double accepts.
## Returns the game, the Entrance headers, and the accepting grid (grid 0).
func _committable_entrance_game() -> Dictionary:
	var deck := TestDecks.deck_standard_52()
	var parts := await _entrance_game(deck)
	var g : Game = parts["game"]
	var headers : Array[TypeInput] = parts["headers"]
	var fixture := TestGridFixtures.build_fix_grid_3()
	g.state.grids = fixture.grids
	await _deal(g)
	return {"game": g, "headers": headers}

## The card held in Entrance slot `col`. It is left IN its slot: taking it out is the
## placement's own job (Board.place_in_cell lifts it), and lifting it here instead used to
## leave it in no collection at all while still stamped PLAY.
func _held(g: Game, col: int) -> CardData:
	return g.state.upper_zone[col].datas[0]

# ==============================================================================
# TP-75 -- the first placement commits the batch to that grid.
# ==============================================================================
func run_first_placement_commits_the_batch_test() -> void:
	behavior_section("THE FIRST PLACEMENT COMMITS THE BATCH TO THAT GRID")
	var parts := await _committable_entrance_game()
	var g : Game = parts["game"]
	check(g.state.committed_grid == -1, "precondition: uncommitted", "setup invariant broke")
	var card := _held(g, 0)
	await g.place_card_in_grid(card, BoardCoord.new(0, 0, 0, 0))
	check(g.state.committed_grid == 0,
			"the first placement into grid 0 committed the batch to grid 0",
			"got %d" % g.state.committed_grid)
	check(not g.state.upper_zone[0].datas.has(card),
			"...and the placement LIFTED the card out of its Entrance slot, leaving it in "
			+ "exactly one collection")
	_free_game(g)

# ==============================================================================
# TP-76 -- a placement into another grid while committed is refused: the board did not
# change and the card is still held, not merely a false return value.
# ==============================================================================
func run_placement_into_other_grid_while_committed_refused_test() -> void:
	behavior_section("A PLACEMENT INTO ANOTHER GRID WHILE COMMITTED IS REFUSED")
	var parts := await _committable_entrance_game()
	var g : Game = parts["game"]
	var first := _held(g, 0)
	await g.place_card_in_grid(first, BoardCoord.new(0, 0, 0, 0))
	check(g.state.committed_grid == 0, "precondition: committed to grid 0", "setup invariant broke")

	var other := g.state.upper_zone[1].datas[0]  # left IN the Entrance, not cleared
	await g.place_card_in_grid(other, BoardCoord.new(1, 0, 0, 0))

	check(g.state.committed_grid == 0, "the commitment did not move off grid 0",
			"got %d" % g.state.committed_grid)
	check(g.state.grids[1].cells[0].datas.is_empty(),
			"grid 1's target cell is untouched -- the board did not change",
			"got %s" % [g.state.grids[1].cells[0].datas])
	check(g.state.upper_zone[1].datas.size() == 1 and g.state.upper_zone[1].datas[0] == other,
			"the card is still held in its Entrance slot, not merely a false return value",
			"upper_zone[1]: %s" % [g.state.upper_zone[1].datas])
	_free_game(g)

# ==============================================================================
# TP-77 -- the commitment lifts when no legal placement remains in that grid. Grid 0 starts
# with every cell but two filled (no stacking, so a filled cell is never legal again); the
# first of the two remaining placements commits and the commitment holds (one legal cell
# still open), the second placement fills the last cell and the commitment lifts.
# ==============================================================================
func run_commitment_lifts_when_no_legal_placement_remains_test() -> void:
	behavior_section("THE COMMITMENT LIFTS WHEN NO LEGAL PLACEMENT REMAINS IN THAT GRID")
	var parts := await _committable_entrance_game()
	var g : Game = parts["game"]
	var grid : GridData = g.state.grids[0]
	# Fill every cell except (0,0) and (1,0) with a real card, so those two are the grid's
	# only remaining legal placements under the test double's no-stacking acceptance rule.
	for i : int in grid.cells.size():
		if i == grid.cell_index(0, 0) or i == grid.cell_index(1, 0): continue
		var filler := TestFactories.m_card(1, TestFactories.uc())
		filler.stage = CardData.Stage.PLAY
		grid.cells[i].datas.append(filler)

	var first := _held(g, 0)
	await g.place_card_in_grid(first, BoardCoord.new(0, 0, 0, 0))
	check(g.state.committed_grid == 0,
			"committed after the first placement -- cell (1,0) is still a legal spot",
			"got %d" % g.state.committed_grid)

	var second := _held(g, 1)
	await g.place_card_in_grid(second, BoardCoord.new(0, 1, 0, 0))
	check(g.state.committed_grid == -1,
			"the last empty cell just filled -- no legal placement remains, so it lifted",
			"got %d" % g.state.committed_grid)
	_free_game(g)

# ==============================================================================
# TP-78 -- undo lifts a commitment; nothing else does. Grid 0 is left mostly empty (many
# legal cells remain), so a further legal placement and a refill must NOT lift the
# commitment by themselves -- only undo does.
# ==============================================================================
func run_undo_lifts_commitment_nothing_else_does_test() -> void:
	behavior_section("UNDO LIFTS A COMMITMENT; NOTHING ELSE DOES")
	var parts := await _committable_entrance_game()
	var g : Game = parts["game"]
	g.save_state()  # baseline: uncommitted

	var first := _held(g, 0)
	await g.place_card_in_grid(first, BoardCoord.new(0, 0, 0, 0))
	check(g.state.committed_grid == 0, "precondition: committed to grid 0", "setup invariant broke")
	g.save_state()

	# An ordinary further action -- another legal placement into the SAME committed grid,
	# which also re-runs on_card_placed's refill trigger -- must NOT lift the commitment by
	# itself; grid 0 is still mostly empty, so legal cells remain.
	var second := _held(g, 1)
	await g.place_card_in_grid(second, BoardCoord.new(0, 1, 0, 0))
	check(g.state.committed_grid == 0,
			"a further placement (and its refill check) left the commitment alone",
			"got %d" % g.state.committed_grid)
	g.save_state()

	g.undo()
	check(g.state.committed_grid == 0,
			"undo rewound past the second placement; still committed to grid 0",
			"got %d" % g.state.committed_grid)

	g.undo()
	check(g.state.committed_grid == -1,
			"undo rewound past the first placement -- the commitment itself is undone",
			"got %d" % g.state.committed_grid)
	_free_game(g)

# ==============================================================================
# THE CARD EFFECT API BOUNDARY GATE.
#
# A card modifier implements its effect through CardEffectApi and NEVER reaches `Game`,
# `GameData` or `Board` directly. The rule is ENFORCED here rather than documented, because
# it was documented for a long time -- CardModifier's own comment said "State MUTATION
# should still go through Game's API" -- and 26 card files reached past it anyway.
#
# Scans every modifier under Cards/ as TEXT. A modifier is any file whose `extends` names a
# CardModifier type; the card's VISUAL node and the prop classes are not modifiers and are
# not scanned, which is also why the layer needs no `view` accessor.
# ==============================================================================

## `extends` bases that make a file a card modifier rather than a visual or a data holder.
const MODIFIER_BASES : Array[String] = [
	"CardModifier", "CardModifierSkill", "CardModifierType", "CardModifierStamp",
	"CardModifierStatus", "PipSuit", "PipRank", "ZoneAdder",
]

## What a modifier may not name. `Board` is included because a modifier reaching it still
## edits the board behind the layer, which is the thing the layer exists to prevent.
const FORBIDDEN_IN_MODIFIERS : Array[String] = ["game.", "Game.", "GameData", "Board."]

func run_effect_api_boundary_gate() -> void:
	implementation_section("CARD EFFECT API BOUNDARY")
	var scanned := 0
	var offenders : Array[String] = []
	for path : String in _all_card_scripts("res://Cards"):
		var f := FileAccess.open(path, FileAccess.READ)
		if not f: continue
		var text := f.get_as_text()
		if not _is_modifier(text): continue
		scanned += 1
		var n := 0
		for raw : String in text.split("\n"):
			n += 1
			var line := raw.strip_edges()
			# Comments explain the rule and must be free to name what they forbid.
			if line.begins_with("#"): continue
			for bad : String in FORBIDDEN_IN_MODIFIERS:
				if line.contains(bad):
					offenders.append("%s:%d: %s" % [path, n, line])
					break
	check(scanned >= 10, "the gate actually found the modifiers to scan",
			"only %d modifier scripts scanned" % scanned)
	check(offenders.is_empty(),
			"no card modifier reaches Game, GameData or Board directly -- effects go through the api",
			"\n".join(offenders))

## Does this script extend a card-modifier type?
func _is_modifier(text: String) -> bool:
	for raw : String in text.split("\n"):
		if not raw.begins_with("extends "): continue
		var base := raw.substr(8).strip_edges()
		return MODIFIER_BASES.has(base)
	return false

## Every .gd under `root`, recursively. Test-only helper.
func _all_card_scripts(root: String) -> Array[String]:
	var out : Array[String] = []
	var dirs : Array[String] = [root]
	while not dirs.is_empty():
		var d : String = dirs.pop_back()
		var dir := DirAccess.open(d)
		if not dir: continue
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if name.begins_with("."):
				name = dir.get_next()
				continue
			var full : String = d.path_join(name)
			if dir.current_is_dir(): dirs.append(full)
			elif name.ends_with(".gd"): out.append(full)
			name = dir.get_next()
		dir.list_dir_end()
	return out


# ==============================================================================
# TP-121 -- every placement is ONE undo step. Not a batch of five, not zero.
# ==============================================================================
func run_every_placement_is_one_undo_step_test() -> void:
	behavior_section("EVERY PLACEMENT IS ONE UNDO STEP")
	var parts := await _committable_entrance_game()
	var g : Game = parts["game"]
	g.save_state()   # seed a committed board, the way _start_fresh_show does
	var before := g.save_history.size()

	await g.place_card_in_grid(_held(g, 0), BoardCoord.new(0, 0, 0, 0))
	check(g.save_history.size() == before + 1,
			"one placement commits exactly one snapshot",
			"%d -> %d" % [before, g.save_history.size()])
	# The SECOND one matters as much as the first: a per-batch commit would pass the check
	# above and then add nothing here.
	await g.place_card_in_grid(_held(g, 1), BoardCoord.new(0, 1, 0, 0))
	check(g.save_history.size() == before + 2,
			"a second placement commits its own snapshot, not a shared batch one",
			"%d -> %d" % [before, g.save_history.size()])
	_free_game(g)

# ==============================================================================
# TP-122 -- undoing a placement that scored rewinds the SCORES with the board. The scores
# live on GameData, which is what a snapshot captures, so this is the assertion that the
# placement's snapshot was taken AFTER its scoring pass rather than before it.
# ==============================================================================
func run_undo_rewinds_every_score_a_placement_made_test() -> void:
	behavior_section("UNDO REWINDS EVERY SCORE A PLACEMENT MADE")
	var parts := await _committable_entrance_game()
	var g : Game = parts["game"]
	g.state.rules_deck.append(_rules_card(SkillLineDetector.new()))
	# FIX-TRIPLE: cell (2,2) completes row 2, column 2 and a diagonal at once.
	var fixture := TestGridFixtures.build_fix_triple()
	g.state.grids = fixture.grids
	g.save_state()
	var before_total := g.state.live_total()
	var before_history := g.save_history.size()

	var card := _held(g, 0)
	await g.place_card_in_grid(card, BoardCoord.new(0, 2, 2, 0))
	var scored := g.state.live_total()
	check(scored > before_total,
			"precondition: the placement into the shared cell scored",
			"%d -> %d" % [before_total, scored])
	check(g.save_history.size() == before_history + 1,
			"precondition: the placement committed", "%d snapshots" % g.save_history.size())

	g.undo()
	check(g.state.live_total() == before_total,
			"undo rewinds the scores the placement made, not just the board",
			"%d, wanted %d" % [g.state.live_total(), before_total])
	check(g.state.card_at(BoardCoord.new(0, 2, 2, 0)) == null,
			"...and the placed card is off the board again",
			str(g.state.card_at(BoardCoord.new(0, 2, 2, 0))))
	# ⚠ The rewound board must be a LEGAL board, not merely one with the right numbers on it.
	# Every placement is now a snapshot, so an undo restores one of these on every step of
	# every show -- an invariant that only breaks on the way back is still broken.
	var violations := g.state.validate()
	check(violations.is_empty(), "the rewound board still satisfies every invariant",
			"; ".join(violations.slice(0, 3)))
	_free_game(g)

# ==============================================================================
# TP-123 -- a placement that moves nothing commits nothing: no snapshot, so no undo step
# that visibly does nothing. Putting a held card back costs the player nothing.
# ==============================================================================
func run_a_placement_that_changes_nothing_commits_nothing_test() -> void:
	behavior_section("A PLACEMENT THAT CHANGES NOTHING COMMITS NOTHING")
	var prev_run : RunState = RunManager.run
	var prev_info : RunState = Main.save_info
	_with_run(suite_tag())
	var parts := await _committable_entrance_game()
	var g : Game = parts["game"]
	g.save_state()
	# Commit the batch to grid 0 first, so the refused placement below is refused for the
	# reason under test rather than for want of a grid.
	await g.place_card_in_grid(_held(g, 0), BoardCoord.new(0, 0, 0, 0))
	var before := g.save_history.size()

	# Aimed at a grid the batch is not committed to: refused outright, nothing moves.
	var held : CardData = g.state.upper_zone[1].datas[0]
	await g.place_card_in_grid(held, BoardCoord.new(1, 0, 0, 0))
	check(g.save_history.size() == before,
			"a refused placement commits no snapshot",
			"%d -> %d" % [before, g.save_history.size()])
	check(g.state.upper_zone[1].datas.has(held),
			"...and the card is still held, exactly where it was")
	# ⚠ AND NO REPLAY MARKER SURVIVES A PLACEMENT THAT DID NOT HAPPEN. The marker is cleared by
	# save_state, which a rejected placement never reaches -- so one written before the
	# placement was known to have SUCCEEDED would still be sitting there, and the next resume
	# would replay a placement the player never made.
	# Two rejections, and they leave by DIFFERENT doors: the wrong-grid one is refused by the
	# commitment before anything else happens, while an off-board coordinate gets all the way
	# to Board.place_in_cell and is refused there. Only the second can strand a marker, so
	# testing the first alone proves nothing about this.
	check(RunManager.run.pending_action == &"",
			"the commitment-refused placement leaves no pending action behind",
			str(RunManager.run.pending_action))

	var off_board : CardData = g.state.upper_zone[1].datas[0]
	await g.place_card_in_grid(off_board, BoardCoord.new(0, 99, 0, 0))
	check(g.state.upper_zone[1].datas.has(off_board),
			"precondition: an off-board coordinate is rejected and the card stays held")
	check(RunManager.run.pending_action == &"",
			"a placement rejected by the board leaves no pending action behind",
			str(RunManager.run.pending_action))
	check(RunManager.run.pending_placement_slot == -1,
			"...and no pending slot", "got %d" % RunManager.run.pending_placement_slot)
	_free_game(g)
	_without_run(suite_tag(), prev_run, prev_info)

# ==============================================================================
# S36 -- the interrupted-placement replay (TP-124..TP-126).
#
# WARNING: THE MARKER IS ONLY OBSERVABLE FROM INSIDE THE PLACEMENT. It is written before the
# mutation and cleared the instant the placement commits, so a test that looks at it before
# or after sees nothing either way. This probe reads it from an `on_card_placed` handler,
# which runs mid-placement -- the same technique the mutation-broadcast tests use.
# ==============================================================================
class PlacementMarkerProbe extends CardModifierSkill:
	var seen_action : StringName = &""
	var seen_slot : int = -99
	var seen_coord : Vector4i = Vector4i.ZERO
	func get_str() -> String: return "PlacementMarkerProbe"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func combo_key(_hook: StringName = &"") -> String: return ""
	func on_card_placed(_coord: BoardCoord) -> void:
		if RunManager.run == null: return
		seen_action = RunManager.run.pending_action
		seen_slot = RunManager.run.pending_placement_slot
		seen_coord = RunManager.run.pending_placement_coord

## A run document the marker can be written into, with the player's real save parked.
func _with_run(tag: String) -> RunState:
	backup_real_save(tag)
	var run := RunManager.new_run(TestDecks.minimal_deck(), [] as Array[CardData])
	Main.save_info = run
	return run

func _without_run(tag: String, prev_run: RunState, prev_info: RunState) -> void:
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(tag)
	RunManager.run = prev_run
	Main.save_info = prev_info

# ==============================================================================
# TP-124 -- pending_action carries the placement: which slot the card came from and where
# it was aimed, written BEFORE the board moves and cleared once it commits.
# ==============================================================================
func run_pending_marker_names_the_placement_test() -> void:
	behavior_section("THE PENDING MARKER NAMES THE PLACEMENT")
	var prev_run : RunState = RunManager.run
	var prev_info : RunState = Main.save_info
	_with_run(suite_tag())
	var parts := await _committable_entrance_game()
	var g : Game = parts["game"]
	var probe := PlacementMarkerProbe.new()
	g.state.rules_deck.append(_rules_card(probe))
	g.save_state()

	await g.place_card_in_grid(_held(g, 2), BoardCoord.new(0, 3, 1, 0))
	check(probe.seen_action == &"on_placement",
			"the marker persisted mid-placement says a PLACEMENT is resolving",
			str(probe.seen_action))
	check(probe.seen_slot == 2,
			"...and names the Entrance slot the card came from", "got %d" % probe.seen_slot)
	check(probe.seen_coord == Vector4i(0, 3, 1, 0),
			"...and the coordinate it was aimed at", str(probe.seen_coord))
	check(RunManager.run.pending_action == &"" and RunManager.run.pending_placement_slot == -1,
			"a committed placement clears the marker -- nothing is mid-resolution any more",
			"%s / %d" % [RunManager.run.pending_action, RunManager.run.pending_placement_slot])
	_free_game(g)
	_without_run(suite_tag(), prev_run, prev_info)

# ==============================================================================
# TP-125 -- replaying the marker from the PRE-placement board reproduces the placement in
# full, scoring included. FIX-CROSS: the target cell completes a row and a column at once,
# so a replay that restored the board without re-running the cascade would show it.
# ==============================================================================
func run_replay_reproduces_the_interrupted_placement_test() -> void:
	behavior_section("A REPLAY REPRODUCES THE WHOLE INTERRUPTED PLACEMENT")
	var prev_run : RunState = RunManager.run
	var prev_info : RunState = Main.save_info
	_with_run(suite_tag())
	var parts := await _committable_entrance_game()
	var g : Game = parts["game"]
	g.state.rules_deck.append(_rules_card(SkillLineDetector.new()))
	var fixture := TestGridFixtures.build_fix_cross()
	g.state.grids = fixture.grids
	g.save_state()
	# The exact board a quit would have left on disk: the last COMMITTED one.
	var pre_placement : GameData = g.save_history[-1]

	var coord := BoardCoord.new(0, 2, 2, 0)
	await g.place_card_in_grid(_held(g, 0), coord)
	var expected := TestGridFixtures.board_digest(g.state)
	check(g.state.live_total() > 0,
			"precondition: the placement completed a line and scored", str(g.state.live_total()))

	# Rewind to the pre-placement board and replay the marker, exactly as a resume does.
	g.state = g._runtime_state(pre_placement)
	g.save_history = [pre_placement]
	RunManager.run.pending_action = &"on_placement"
	RunManager.run.pending_placement_slot = 0
	RunManager.run.pending_placement_coord = Vector4i(coord.grid, coord.x, coord.y, coord.h)
	await g._replay_pending_action(&"on_placement")

	check(TestGridFixtures.board_digest(g.state) == expected,
			"the replayed placement reproduces the board it interrupted, scores and all",
			"replayed:\n%s\n---- wanted:\n%s" % [
			TestGridFixtures.board_digest(g.state), expected])
	_free_game(g)
	_without_run(suite_tag(), prev_run, prev_info)

# ==============================================================================
# TP-126 -- the refill a replayed placement triggers deals the SAME cards. The draw is a pop
# off an already-ordered deck that the snapshot carries, so there is no RNG in the path; this
# is the check that says so rather than assuming it.
# ==============================================================================
func run_replayed_refill_is_identical_test() -> void:
	behavior_section("A REPLAYED REFILL DEALS THE IDENTICAL BOARD")
	var prev_run : RunState = RunManager.run
	var prev_info : RunState = Main.save_info
	_with_run(suite_tag())
	var parts := await _committable_entrance_game()
	var g : Game = parts["game"]
	# Drain slots 1-4 first. A refill is due only when the Entrance is EMPTY (or nothing held
	# can go anywhere), so a single placement never triggers one -- the four other slots still
	# hold cards this grid would accept. It is the LAST card leaving that deals a fresh hand,
	# and that is the placement whose replay has a refill in it to reproduce.
	for slot : int in [1, 2, 3, 4]:
		await g.place_card_in_grid(_held(g, slot), BoardCoord.new(0, slot, 4, 0))
	check(g.state.upper_zone[1].datas.is_empty(),
			"precondition: draining a slot does not refill it while the Entrance still holds cards",
			"%d cards" % g.state.upper_zone[1].datas.size())
	g.save_state()
	var pre_placement : GameData = g.save_history[-1]
	var deck_before : int = g.state.draw_deck.size()

	var coord := BoardCoord.new(0, 0, 0, 0)
	await g.place_card_in_grid(_held(g, 0), coord)
	var expected := TestGridFixtures.board_digest(g.state)
	check(g.state.draw_deck.size() < deck_before,
			"precondition: emptying the Entrance dealt a fresh hand from the deck",
			"%d -> %d" % [deck_before, g.state.draw_deck.size()])

	g.state = g._runtime_state(pre_placement)
	g.save_history = [pre_placement]
	RunManager.run.pending_action = &"on_placement"
	RunManager.run.pending_placement_slot = 0
	RunManager.run.pending_placement_coord = Vector4i(coord.grid, coord.x, coord.y, coord.h)
	await g._replay_pending_action(&"on_placement")

	check(TestGridFixtures.board_digest(g.state) == expected,
			"the replay refills with the identical cards -- no RNG anywhere in the path",
			"replayed:\n%s\n---- wanted:\n%s" % [
			TestGridFixtures.board_digest(g.state), expected])
	_free_game(g)
	_without_run(suite_tag(), prev_run, prev_info)

# ==============================================================================
# THE PLAYER'S PLACEMENT PATH (design chart A: A2-A9). Owner's GAP-008 answer, verbatim:
#   "input zone allows grabbing cards from it regardless of stack.
#    can always place on a grid zone cell by default
#    these are both rules to adjust for old input zone cards, not effects that come from the
#    rules deck. I think this would have been the upper and lower input zone classes"
#
# So both rules live on the ZONE TYPE cards -- TypeInput for the Entrance, TypeGridCell for a
# cell -- and NOT on rules-deck cards the way the retired grabber and placer did. That matters
# beyond tidiness: a rules-deck card can be removed, and a deck that had lost it would be a
# deck the player cannot place from at all.
#
# These use NO test double: the real TypeInput and TypeGridCell answer, through the real
# try_grab / try_place the view calls.
# ==============================================================================

## An Entrance and one empty 5x5 grid, with nothing but the real zone cards answering.
func _placement_game() -> Game:
	var parts := await _entrance_game(TestDecks.deck_standard_52())
	var g : Game = parts["game"]
	g.state.grids = TestGridFixtures.build_fix_grid_1().grids
	await _deal(g)
	return g

## The cell zone card of grid 0 at (x, y) -- what an EMPTY cell presents as a drop target.
func _cell_card(g: Game, x: int, y: int) -> CardData:
	var grid : GridData = g.state.grids[0]
	return grid.cell_types[grid.cell_index(x, y)]

func run_entrance_grabs_regardless_of_stack_test() -> void:
	behavior_section("THE ENTRANCE GRABS REGARDLESS OF STACK")
	var g := await _placement_game()
	var bottom : CardData = g.state.upper_zone[0].datas[0]
	check(not (await g.try_grab(bottom)).is_empty(),
			"a card held in the Entrance can be grabbed")

	# Bury it. "Regardless of stack" is the whole point of the answer: the Entrance holds a
	# stack, and a covered card there is still the player's to pick up -- unlike the Entrance's
	# own PLACE rule, which does require the target to be topmost.
	var on_top := TestFactories.m_card(9, TestFactories.uc())
	Board.place_card(g.state, on_top, 0, 0)
	check(g.state.upper_zone[0].datas.size() == 2 and not g.state.upper_zone[0].datas.has(null),
			"precondition: the slot is two deep", "%d" % g.state.upper_zone[0].datas.size())
	var grabbed : Array[CardData] = await g.try_grab(bottom)
	check(grabbed == ([bottom] as Array[CardData]),
			"a COVERED Entrance card is still grabbable, and grabs only itself", str(grabbed))

	# A card that is not in the Entrance at all is not grabbable: the rule is the zone's, not
	# a blanket yes.
	var stranger := TestFactories.m_card(4, TestFactories.uc())
	check((await g.try_grab(stranger)).is_empty(),
			"a card that is not in the Entrance is not grabbable")
	_free_game(g)

func run_empty_cell_always_accepts_test() -> void:
	behavior_section("AN EMPTY GRID CELL ALWAYS ACCEPTS")
	var g := await _placement_game()
	g.save_state()
	var history_before := g.save_history.size()
	var held : CardData = g.state.upper_zone[0].datas[0]

	var placed := await g.try_place([held] as Array[CardData], _cell_card(g, 2, 3))
	check(placed, "try_place onto an empty cell's zone card is accepted")
	check(g.state.card_at(BoardCoord.new(0, 2, 3, 0)) == held,
			"...and the card actually LANDS in that cell -- not merely a true return value",
			str(g.state.card_at(BoardCoord.new(0, 2, 3, 0))))
	check(not g.state.upper_zone[0].datas.has(held),
			"...and it left the Entrance slot it came from")
	check(g.save_history.size() == history_before + 1,
			"...and the placement committed exactly one undo step",
			"%d -> %d" % [history_before, g.save_history.size()])
	check(g.state.validate().is_empty(), "the board validates after a UI placement",
			"; ".join(g.state.validate().slice(0, 3)))
	_free_game(g)

func run_occupied_cell_refuses_test() -> void:
	behavior_section("AN OCCUPIED CELL REFUSES")
	var g := await _placement_game()
	var first : CardData = g.state.upper_zone[0].datas[0]
	await g.try_place([first] as Array[CardData], _cell_card(g, 0, 0))
	check(g.state.card_at(BoardCoord.new(0, 0, 0, 0)) == first, "precondition: the cell is full")

	# An occupied cell presents the card ON TOP as the drop target, not its zone card -- the
	# same rule the refill's legality sweep uses. Nothing answers for a played card, so the
	# drop is refused: stacking is effect-only, never something the player does by hand.
	var second : CardData = g.state.upper_zone[1].datas[0]
	var placed := await g.try_place([second] as Array[CardData], first)
	check(not placed, "dropping onto the card already in a cell is refused")
	check(g.state.upper_zone[1].datas.has(second),
			"...and the refused card is still held, exactly where it was")
	check(g.state.card_at(BoardCoord.new(0, 0, 0, 1)) == null,
			"...and nothing stacked on top of the cell's card",
			str(g.state.card_at(BoardCoord.new(0, 0, 0, 1))))
	_free_game(g)

