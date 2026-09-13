extends TestSuite
# res://Tests/Engine/test_board_plan.gd

#A mark IS the existing `cell_types[i]` card with a rank or a suit printed on it -- no second array
#and no flag. CATEGORY MAP: what a mark copies is BEHAVIOR, while the predicate, the backrefs and
#every `validate()` claim are IMPLEMENTATION pins on a debug invariant checker.
func suite_name() -> String:
	return "BOARD PLAN"

func _ready() -> void:
	TestLog.line("============ BOARD PLAN TEST PASS ============")
	implementation_section("THE MARK PREDICATE")
	test_is_marked_asks_rank_or_suit()
	behavior_section("WRITING AND CLEARING A MARK")
	test_write_mark_copies_every_printed_slot()
	implementation_section("A MARK'S BACKREFS POINT AT THE MARK")
	test_write_mark_relinks_the_copied_backrefs()
	behavior_section("THE PLANNER SHIPS IN THE RULES DECK")
	test_fresh_show_carries_one_localised_planner()
	implementation_section("I6: A DEALT MARK NAMES A CARD THE STATE HOLDS")
	test_i6_fails_a_mark_the_deck_never_had()
	test_i6_exempts_a_granted_mark()
	test_i6_passes_a_mark_the_deck_prints()
	test_i6_accepts_a_printer_in_a_lower_zone_column()
	test_i6_refuses_a_printer_that_is_a_zone_header()
	behavior_section("THE DEAL, THROUGH A REAL SHOW START")
	await test_a_fresh_show_marks_every_cell()
	await test_a_three_grid_show_marks_every_grid()
	await test_the_same_node_deals_the_same_board()
	behavior_section("THE DEAL'S CARD BUDGET")
	test_twenty_cards_over_twenty_five_cells()
	test_nothing_repeats_while_a_card_is_unused()
	test_two_grids_draw_fifty_distinct_cards()
	behavior_section("THE DEAL READS ITS OWN GENERATOR ONLY")
	test_the_global_generator_cannot_move_the_deal()
	test_the_cell_walk_is_shuffled()
	test_two_copies_may_share_a_row()
	behavior_section("A BOARD THAT GROWS AFTER THE DEAL")
	test_a_grid_added_mid_show_deals_its_own_marks()
	await test_grids_appended_to_a_planned_board_are_dealt()
	test_a_cell_added_to_a_grid_takes_a_mark()
	test_a_card_minted_after_the_deal_gets_no_mark()
	behavior_section("THE REROLL, GRANT AND SWAP SURFACE")
	test_mark_at_reads_the_cells_own_card()
	test_a_reroll_draws_from_the_deals_own_pool()
	test_every_cell_rerolls_to_a_new_identity()
	test_a_reroll_with_nothing_on_offer_keeps_the_mark()
	test_a_reroll_repeats_for_one_plan_seed()
	test_grant_marks_a_card_the_deck_never_had()
	test_swap_exchanges_two_marks_whole()
	await test_a_reroll_under_a_placed_card_is_live()
	behavior_section("A PLAN SURVIVES A SAVE, AND A PLAN-LESS SAVE STILL PLAYS")
	test_a_dealt_plan_survives_a_round_trip()
	await test_a_plan_less_save_resumes_and_plays()
	finish()

## A 5x5 board with the plan deck in draw -- the state every check below starts from.
func make_state() -> GameData:
	return plan_state(TestDecks.plan_deck(), 1)

## A board of `grid_count` empty 5x5 grids with `deck` in draw; the fixtures ship 1 and 3.
func plan_state(deck: Array[CardData], grid_count: int) -> GameData:
	var state := TestGridFixtures.build_fix_grid_3()
	state.grids.resize(grid_count)
	state.draw_deck = deck
	for card : CardData in state.draw_deck:
		card.stage = CardData.Stage.DRAW
	return state

## The deal on its own, seeded: the rows that exercise the algorithm rather than the wiring.
func deal_onto(state: GameData, plan_seed: int) -> void:
	state.plan_seed = plan_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = plan_seed
	BoardPlan.deal(state, rng)

## Marks grid 0's first cell with exactly the pips I6's fixtures need, which no deck card prints.
func mark_first_cell(state: GameData, rank_value: float, suit: GDScript) -> CardData:
	var mark : CardData = state.grids[0].cell_types[0]
	mark.rank = PipRankNumeral.new().with_value(rank_value)
	mark.suit = suit.new() as PipSuit
	return mark

## A source wearing every printed slot plus a runtime status, so one write covers each slot and the refusal to copy a status.
func decorated_source() -> CardData:
	return TestDecks.plan_deck()[2].with_skill(SkillExtraPoint.new()) \
			.with_stamp(StampDoubleTrigger.new()) \
			.with_status(StatusBurning.new())

#TP-11: a mark is a faithful picture of what its card PRINTS, and a status is a runtime condition
#rather than a print -- so it is the one thing that never crosses.
func test_write_mark_copies_every_printed_slot() -> void:
	var state := make_state()
	var source := decorated_source()
	var mark : CardData = state.grids[0].cell_types[0]
	BoardPlan.write_mark(mark, source, true)
	check(PipComparator.printed_same(mark.rank, source.rank),
			"TP-11: the mark prints the source's rank")
	check(PipComparator.printed_same(mark.suit, source.suit),
			"TP-11: the mark prints the source's suit")
	check(mark.skill != null and is_same(mark.skill.get_script(), source.skill.get_script()),
			"TP-11: the mark carries the source's skill", "got %s" % mark.skill)
	check(mark.stamp != null and is_same(mark.stamp.get_script(), source.stamp.get_script()),
			"TP-11: the mark carries the source's stamp", "got %s" % mark.stamp)
	check(mark.statuses.is_empty(), "TP-11: a status never crosses onto a mark",
			"got %d" % mark.statuses.size())
	check((mark.type as TypeGridCell).granted,
			"TP-11: write_mark records the granted argument it was passed")
	check(mark.rank != source.rank and mark.suit != source.suit
			and mark.skill != source.skill and mark.stamp != source.stamp,
			"TP-11: every copied slot is a fresh instance the source does not share")
	source.rank.value = 9
	check(not PipComparator.printed_same(mark.rank, source.rank),
			"TP-11: changing the source's rank afterwards leaves the mark alone")
	BoardPlan.clear_mark(mark)
	check(not BoardPlan.is_marked(mark) and mark.skill == null and mark.stamp == null
			and not (mark.type as TypeGridCell).granted,
			"TP-11: clear_mark leaves a bare cell type behind")

#TP-12: `duplicate_deep` does not carry a WeakRef backref, so without the relink every copied
#modifier answers for no card at all and a hook reading `data` reads null.
func test_write_mark_relinks_the_copied_backrefs() -> void:
	var state := make_state()
	var source := decorated_source()
	var mark : CardData = state.grids[0].cell_types[0]
	BoardPlan.write_mark(mark, source, false)
	var strays : Array[String] = []
	for mod : CardModifier in [mark.skill, mark.type, mark.stamp, mark.suit]:
		if mod and mod.data and mod.data != mark: strays.append(mod.get_str())
	check(strays.is_empty(), "TP-12: no modifier on the mark answers for another card",
			"stray: %s" % ", ".join(strays))
	check(mark.skill.data == mark and mark.suit.data == mark,
			"TP-12: the copied skill and suit both resolve to the mark itself")

## Only `validate()`'s I6 lines -- every other invariant is another suite's claim.
func i6_violations(state: GameData) -> Array[String]:
	var out : Array[String] = []
	for violation : String in state.validate():
		if violation.begins_with("I6:"): out.append(violation)
	return out

## The predicate IS the definition of marked: either printed pip on its own is enough.
func test_is_marked_asks_rank_or_suit() -> void:
	var state := make_state()
	var bare : CardData = state.grids[0].cell_types[0]
	check(not BoardPlan.is_marked(bare), "a freshly built cell type is not marked")
	var ranked : CardData = state.grids[0].cell_types[1]
	ranked.rank = PipRankNumeral.new().with_value(3)
	check(BoardPlan.is_marked(ranked), "a rank alone marks a cell")
	var suited : CardData = state.grids[0].cell_types[2]
	suited.suit = PipSuitHoop.new()
	check(BoardPlan.is_marked(suited), "a suit alone marks a cell")

## TP-16: a dealt mark of a card no playing card prints cannot have come from the deal.
func test_i6_fails_a_mark_the_deck_never_had() -> void:
	var state := make_state()
	mark_first_cell(state, 9, PipSuitHoop)
	var reported := i6_violations(state)
	check(reported.size() == 1 and reported[0].contains("(0,0)"),
			"TP-16: I6 reports cell (0,0)'s rank 9 mark, which the 1-5 deck never prints",
			"I6 said: %s" % ", ".join(reported))

## TP-16: both halves run on ONE state, so the pass is the flag's doing and not a quiet board.
func test_i6_exempts_a_granted_mark() -> void:
	var state := make_state()
	var mark := mark_first_cell(state, 9, PipSuitHoop)
	check(not i6_violations(state).is_empty(),
			"TP-16: the dealt form of this mark is reported")
	(mark.type as TypeGridCell).granted = true
	check(i6_violations(state).is_empty(),
			"TP-16: ...and setting granted exempts the very same mark",
			"I6 said: %s" % ", ".join(i6_violations(state)))

## TP-16: the membership test in the other direction -- a mark the deck DOES print passes.
func test_i6_passes_a_mark_the_deck_prints() -> void:
	var state := make_state()
	mark_first_cell(state, 3, PipSuitHoop)
	check(i6_violations(state).is_empty(),
			"TP-16: a dealt mark of the 3 of Hoops, which the deck holds, passes I6",
			"I6 said: %s" % ", ".join(i6_violations(state)))

#TP-16: the lower zone carries no grid coordinate, so a walk built from coordinates cannot reach it
#-- and a card sitting there prints a mark's face exactly as one anywhere else on the board does.
func test_i6_accepts_a_printer_in_a_lower_zone_column() -> void:
	var state := make_state()
	mark_first_cell(state, 9, PipSuitHoop)
	var printer := CardData.new()
	printer.rank = PipRankNumeral.new().with_value(9)
	printer.with_suit(PipSuitHoop.new())
	printer.stage = CardData.Stage.PLAY
	state.lower_zone = [TestFactories.col([printer] as Array[CardData])] as Array[ArrayCardData]
	var header := CardData.new()
	header.stage = CardData.Stage.ZONE
	state.lower_zone_type = [header] as Array[CardData]
	check(i6_violations(state).is_empty(),
			"TP-16: a mark whose only printer sits in a lower-zone column passes I6",
			"I6 said: %s" % ", ".join(i6_violations(state)))

#TP-16: a zone header is not a card the deal could ever have marked, so its print is no defence --
#the other half of the membership test, and what keeps the walk from widening into every card held.
func test_i6_refuses_a_printer_that_is_a_zone_header() -> void:
	var state := make_state()
	mark_first_cell(state, 9, PipSuitHoop)
	var header := CardData.new()
	header.rank = PipRankNumeral.new().with_value(9)
	header.with_suit(PipSuitHoop.new())
	header.stage = CardData.Stage.ZONE
	state.lower_zone = [ArrayCardData.new()] as Array[ArrayCardData]
	state.lower_zone_type = [header] as Array[CardData]
	check(i6_violations(state).size() == 1,
			"TP-16: a zone header printing the mark's face leaves the mark reported",
			"I6 said: %s" % ", ".join(i6_violations(state)))

## A fresh show's rules deck, built by the real `Game.add_deck` from the mirror of shipped `rules1`.
func fresh_show_rules() -> Array[CardData]:
	var g := Game.new()
	CardEnvironment.CURRENT = g
	var previous : RunState = Main.save_info
	var run := RunState.new()
	run.card_datas = TestDecks.plan_deck()
	run.rule_datas = TestDecks.standard_rules()
	Main.save_info = run
	g.add_deck()
	var rules : Array[CardData] = g.state.rules_deck
	Main.save_info = previous
	CardEnvironment.CURRENT = null
	g.free()
	return rules

#The planner has to sit AFTER the allotment card: `on_game_start` reaches the rules deck in array
#order, and the allotment's creators build their grids on the sweep that follows it, so an earlier
#planner would deal onto a board with no grids at all.
func test_fresh_show_carries_one_localised_planner() -> void:
	var rules := fresh_show_rules()
	var planner : CardModifier = null
	var planner_at := -1
	var allotment_at := -1
	var planners := 0
	for i : int in rules.size():
		var skill : CardModifier = rules[i].skill
		if skill is SkillBoardPlanner:
			planner = skill
			planner_at = i
			planners += 1
		if skill is SkillGridAllotment: allotment_at = i
	check(planners == 1, "S3: a fresh show's rules deck holds exactly one board planner",
			"rules: %s" % ", ".join(TestDecks.rules_skill_names(rules)))
	check(allotment_at != -1 and planner_at > allotment_at,
			"S3: the planner is dealt after the grid allotment card, which is the hook order",
			"allotment at %d, planner at %d" % [allotment_at, planner_at])
	var planner_name := TRANSLATION.find(&"BOARD_PLANNER_CARD")
	var planner_description := TRANSLATION.find(&"BOARD_PLANNER_CARD_DESCRIPTION")
	check(planner_name != "" and planner_name != "BOARD_PLANNER_CARD",
			"S3: the planner's name is localised, not the bare key", "got '%s'" % planner_name)
	check(planner_description != "" and planner_description != "BOARD_PLANNER_CARD_DESCRIPTION",
			"S3: the planner's description is localised, not the bare key",
			"got '%s'" % planner_description)
	check(planner != null and planner.get_str() == planner_name
			and planner.get_description() == planner_description,
			"S3: the card reads both strings through the localisation table")

const ROUND_TRIP_PATH := "user://board_plan_round_trip_test.tres"
const PLAN_LESS_PATH := "user://board_plan_plan_less_test.tres"
## The global generator's seed for a show start, so two shows on one node shuffle one deck order.
const SHUFFLE_SEED := 424242

## The run document the app was holding, put back by `free_show`.
var _real_run : RunState = Main.save_info

## The run document the show starts from: one world seed, so only the node id varies.
func run_doc(deck: Array[CardData], node_id: int) -> RunState:
	var run := RunState.new()
	run.world_seed = 4242
	run.current_node_id = node_id
	run.card_datas = deck
	run.rule_datas = TestDecks.standard_rules()
	return run

#THE real show start, `Game._start_fresh_show()` itself: `add_deck` deals the run's deck, both
#spotlight sweeps run and the Entrance refills. ⚠ Seeded, because the deck's order is an input to
#the deal and `add_deck` shuffles through `Array.shuffle()`, which no generator argument reaches.
func start_show(deck: Array[CardData], node_id: int) -> Game:
	seed(SHUFFLE_SEED)
	var g := Game.new()
	CardEnvironment.CURRENT = g
	Main.save_info = run_doc(deck, node_id)
	await g._start_fresh_show()
	return g

#The same board the game builds, minus the planner: five Entrance adders and one empty grid, which
#is what a save written before this feature holds.
func plan_less_show(deck: Array[CardData]) -> Game:
	var g := Game.new()
	var state := plan_state(deck, 1)
	var rules : Array[CardData] = []
	for _i : int in 5:
		var card := CardData.new().with_skill(SkillAdderInputUpper.new())
		card.stage = CardData.Stage.RULES
		rules.append(card)
	state.rules_deck = rules
	g.state = state
	CardEnvironment.CURRENT = g
	await g.skill_spotlight_check()
	return g

## Undoes a show: both the environment and the run document are process-wide.
func free_show(g: Game) -> void:
	CardEnvironment.CURRENT = null
	Main.save_info = _real_run
	g.free()

## Every mark on the board, in grid order then row-major.
func marks_of(state: GameData) -> Array[CardData]:
	var out : Array[CardData] = []
	for grid : GridData in state.grids:
		for type_card : CardData in grid.cell_types:
			if BoardPlan.is_marked(type_card): out.append(type_card)
	return out

## How many cells of each grid carry a mark: WHICH grids the deal reached, not just how many marks.
func marks_per_grid(state: GameData) -> Array[int]:
	var out : Array[int] = []
	for grid : GridData in state.grids:
		var marked := 0
		for type_card : CardData in grid.cell_types:
			if BoardPlan.is_marked(type_card): marked += 1
		out.append(marked)
	return out

## One mark's printed identity as text: the four slots a mark copies, and "-" for a bare cell.
func mark_print(type_card: CardData) -> String:
	if not BoardPlan.is_marked(type_card): return "-"
	var skill : CardModifier = type_card.skill
	var stamp : CardModifier = type_card.stamp
	return "%s|%s|%s|%s" % [type_card.rank.get_str() if type_card.rank else "",
			type_card.suit.get_str() if type_card.suit else "",
			skill.get_str() if skill else "", stamp.get_str() if stamp else ""]

## One grid's plan as a comparable string, cell by cell in row-major order.
func grid_signature(state: GameData, index: int) -> String:
	var parts : Array[String] = []
	for type_card : CardData in state.grids[index].cell_types:
		parts.append(mark_print(type_card))
	return " ".join(parts)

## The whole board's plan as one comparable string.
func plan_signature(state: GameData) -> String:
	var parts : Array[String] = []
	for i : int in state.grids.size():
		parts.append(grid_signature(state, i))
	return " / ".join(parts)

## How many marks name each printed identity, largest count first.
func copy_histogram(state: GameData) -> Array[int]:
	var seen : Array[CardData] = []
	var counts : Array[int] = []
	for mark : CardData in marks_of(state):
		var at := -1
		for i : int in seen.size():
			if PipComparator.printed_card_same(seen[i], mark): at = i
		if at == -1:
			seen.append(mark)
			counts.append(1)
		else:
			counts[at] += 1
	counts.sort()
	counts.reverse()
	return counts

## Grid 0's cells whose mark another cell also carries, by row-major index.
func repeated_cells(state: GameData) -> Array[int]:
	var out : Array[int] = []
	var types : Array[CardData] = state.grids[0].cell_types
	for i : int in types.size():
		for j : int in types.size():
			if i != j and PipComparator.printed_card_same(types[i], types[j]):
				out.append(i)
				break
	return out

## True when one row of grid 0 carries the same printed identity twice.
func row_holds_a_repeat(state: GameData) -> bool:
	var grid : GridData = state.grids[0]
	for y : int in grid.grid_height:
		for x : int in grid.grid_width:
			for other : int in range(x + 1, grid.grid_width):
				if PipComparator.printed_card_same(grid.cell_types[grid.cell_index(x, y)],
						grid.cell_types[grid.cell_index(other, y)]):
					return true
	return false

## Every cell type's `granted` flag in board order -- a dealt mark's is false.
func granted_flags(state: GameData) -> Array[bool]:
	var out : Array[bool] = []
	for grid : GridData in state.grids:
		for type_card : CardData in grid.cell_types:
			out.append((type_card.type as TypeGridCell).granted)
	return out

## Every card the Entrance holds, left to right, bottom of stack first.
func entrance_cards(state: GameData) -> Array[CardData]:
	var out : Array[CardData] = []
	for column : ArrayCardData in state.upper_zone:
		out.append_array(column.datas)
	return out

## The Entrance cards whose printed face no mark on the board carries, named for the failure text.
func unmarked_entrance_cards(state: GameData) -> Array[String]:
	var out : Array[String] = []
	for card : CardData in entrance_cards(state):
		var printed := false
		for mark : CardData in marks_of(state):
			if PipComparator.printed_card_same(mark, card): printed = true
		if not printed: out.append(card.log_str())
	return out

## Every modifier on a mark that answers for some other card -- the WeakRef trap, named.
func stray_backrefs(state: GameData) -> Array[String]:
	var out : Array[String] = []
	for mark : CardData in marks_of(state):
		for mod : CardModifier in [mark.suit, mark.skill, mark.stamp, mark.type]:
			if mod and mod.data != mark: out.append(mod.get_str())
	return out

#TP-01: the wiring is the claim. The planner's hook fires inside the game's own game-start walk,
#after the creators built the grid and before the Entrance takes a card out of the deck.
func test_a_fresh_show_marks_every_cell() -> void:
	var g := await start_show(TestDecks.plan_deck(), 7)
	check(g.state.grids.size() == 1, "TP-01: the 20-card plan deck allots one grid",
			"got %d grids" % g.state.grids.size())
	check(g.state.plan_seed != 0, "TP-01: the planner stored the seed it dealt from",
			"got %d" % g.state.plan_seed)
	check(marks_of(g.state).size() == 25,
			"TP-01: the show start left no cell of the 5x5 grid bare",
			"marked %d of 25" % marks_of(g.state).size())
	check(not granted_flags(g.state).has(true),
			"TP-01: a dealt mark is not a granted one")
	check(entrance_cards(g.state).size() > 0,
			"TP-01: precondition: the show start refilled the Entrance out of the same deck",
			"%d cards" % entrance_cards(g.state).size())
	check(unmarked_entrance_cards(g.state).is_empty(),
			"TP-01: the deal ran BEFORE that refill -- every card the Entrance holds is printed by a mark",
			"unmarked: %s" % ", ".join(unmarked_entrance_cards(g.state)))
	check(g.state.validate().is_empty(), "TP-01: the dealt board breaks no invariant",
			", ".join(g.state.validate()))
	free_show(g)

#TP-01, TP-04: three grids through the real show start -- the opening deal covers every grid the
#allotment unlocked, from the ONE stock, and not just the first.
func test_a_three_grid_show_marks_every_grid() -> void:
	var st := SettingsManager.settings
	check(st.grid_cards_per_unlock == 52 and st.grid_max_count >= 3,
			"TP-04: precondition: 105 cards unlock three grids under these settings",
			"per unlock %d, max %d" % [st.grid_cards_per_unlock, st.grid_max_count])
	var g := await start_show(TestDecks.deck_105(), 9)
	check(g.state.grids.size() == 3, "TP-04: the 105-card deck allots three grids",
			"got %d grids" % g.state.grids.size())
	check(marks_per_grid(g.state) == ([25, 25, 25] as Array[int]),
			"TP-04: one deal left no cell of any of the three grids bare",
			"per grid %s of 25 each" % str(marks_per_grid(g.state)))
	var hist := copy_histogram(g.state)
	check(hist.size() == 52 and hist[0] == 2 and hist.count(1) == 29,
			"TP-04: the 105 cards print 52 identities, so 75 marks are one full pass plus 23 of a"
			+ " second -- 29 identities marked once, 23 twice, nothing higher", str(hist))
	check(g.state.validate().is_empty(), "TP-04: the three-grid board breaks no invariant",
			", ".join(g.state.validate()))
	free_show(g)

#TP-07: the seed is the run's own plus the node being played, so the show a player re-enters is the
#show they left, and the node next door is a different board.
func test_the_same_node_deals_the_same_board() -> void:
	var first := await start_show(TestDecks.plan_deck(), 7)
	var dealt := plan_signature(first.state)
	var dealt_seed := first.state.plan_seed
	free_show(first)
	var again := await start_show(TestDecks.plan_deck(), 7)
	check(again.state.plan_seed == dealt_seed, "TP-07: the same node seeds the same plan",
			"%d vs %d" % [again.state.plan_seed, dealt_seed])
	check(plan_signature(again.state) == dealt,
			"TP-07: two shows started on one node deal the same board, cell for cell",
			plan_signature(again.state))
	free_show(again)
	var elsewhere := await start_show(TestDecks.plan_deck(), 8)
	check(elsewhere.state.plan_seed != dealt_seed, "TP-07: another node seeds another plan",
			"%d vs %d" % [elsewhere.state.plan_seed, dealt_seed])
	check(plan_signature(elsewhere.state) != dealt,
			"TP-07: ...and deals a different board")
	free_show(elsewhere)

#TP-02: the deck runs out before the board does, so the deal keeps going round it -- and the second
#pass starts only once every card has been marked.
func test_twenty_cards_over_twenty_five_cells() -> void:
	var state := plan_state(TestDecks.plan_deck(), 1)
	deal_onto(state, 101)
	var hist := copy_histogram(state)
	check(hist.size() == 20, "TP-02: all 20 cards of the deck are marked somewhere",
			"got %d distinct" % hist.size())
	check(hist.count(1) == 15 and hist.count(2) == 5,
			"TP-02: 15 cards are marked once and 5 twice over 25 cells", str(hist))
	check(hist[0] == 2, "TP-02: no card is marked three times", str(hist))

#TP-03: with cards to spare there is no reason to repeat one, and the deal never does.
func test_nothing_repeats_while_a_card_is_unused() -> void:
	var state := plan_state(TestDecks.deck_standard_52().slice(0, 30), 1)
	deal_onto(state, 202)
	var hist := copy_histogram(state)
	check(hist.size() == 25 and hist[0] == 1,
			"TP-03: 25 cells of a 30-card deck take 25 distinct cards and repeat nothing", str(hist))

#TP-04: the promise is the whole BOARD's, not each grid's -- two grids share one stock and neither
#re-uses what the other took.
func test_two_grids_draw_fifty_distinct_cards() -> void:
	var state := plan_state(TestDecks.deck_standard_52(), 2)
	deal_onto(state, 303)
	var hist := copy_histogram(state)
	check(marks_of(state).size() == 50, "TP-04: both grids are fully marked",
			"marked %d of 50" % marks_of(state).size())
	check(hist.size() == 50 and hist[0] == 1,
			"TP-04: 50 cells across two grids draw 50 distinct cards of the 52", str(hist))

#TP-08: `Array.shuffle()` and every other global-generator call would make the deal move with the
#global state instead of with the plan seed. Moving that state under one seed catches a global call
#anywhere on the path; holding it still under two seeds catches a deal that ignores its own seed.
func test_the_global_generator_cannot_move_the_deal() -> void:
	seed(12345)
	var first := plan_state(TestDecks.plan_deck(), 1)
	deal_onto(first, 111)
	seed(98765)
	var mirrored := plan_state(TestDecks.plan_deck(), 1)
	deal_onto(mirrored, 111)
	check(plan_signature(mirrored) == plan_signature(first),
			"TP-08: one plan seed deals one board however far the global generator has moved",
			plan_signature(mirrored))
	seed(12345)
	var second := plan_state(TestDecks.plan_deck(), 1)
	deal_onto(second, 222)
	check(plan_signature(first) != plan_signature(second),
			"TP-08: with the global generator in one state, two plan seeds still deal two boards",
			plan_signature(first))
	randomize()

#TP-09: an unshuffled walk would run out of unused cards at the same cells every time -- the last
#five in row-major order -- so those would carry a repeat in every deal. A shuffled walk spreads the
#repeats over all 25 cells, which puts each near 40% and none near the 100% a fixed walk gives.
func test_the_cell_walk_is_shuffled() -> void:
	var deals := 200
	var hits : Array[int] = []
	hits.resize(25)
	hits.fill(0)
	for s : int in deals:
		var state := plan_state(TestDecks.plan_deck(), 1)
		deal_onto(state, s + 1)
		for index : int in repeated_cells(state):
			hits[index] += 1
	var worst : int = hits.max()
	check(worst < deals * 0.6,
			"TP-09: no cell carries a repeated mark in more than 60% of 200 seeded deals",
			"worst cell took %d of %d deals: %s" % [worst, deals, str(hits)])

#TP-10: a lucky deal is a good one to aim at, so two copies of a card sharing a row is allowed --
#nothing rejects it and nothing re-rolls it.
func test_two_copies_may_share_a_row() -> void:
	var found := 0
	for s : int in 200:
		var state := plan_state(TestDecks.plan_deck(), 1)
		deal_onto(state, s + 1)
		if row_holds_a_repeat(state):
			found = s + 1
			break
	check(found != 0,
			"TP-10: a repeat is free to share a row -- one turned up within 200 seeded deals",
			"none in 200 deals")

#TP-04, TP-14: a grid arriving after the deal deals its own cells and continues the cycle the whole
#board is already in. With cards to spare it takes only unused ones; with none it takes another copy
#of the cards carrying fewest, so the copy counts stay within one of each other.
func test_a_grid_added_mid_show_deals_its_own_marks() -> void:
	var state := plan_state(TestDecks.plan_deck(), 1)
	deal_onto(state, 505)
	var first_grid := grid_signature(state, 0)
	var g := Game.new()
	g.state = state
	CardEnvironment.CURRENT = g
	g.effect_api.add_grid(GridData.new())
	check(state.grids.size() == 2 and marks_of(state).size() == 50,
			"TP-14: the grid added through the effect api came up fully marked",
			"%d grids, %d marks" % [state.grids.size(), marks_of(state).size()])
	check(grid_signature(state, 0) == first_grid,
			"TP-14: the first grid's marks are untouched -- a dealt cell is never re-dealt")
	var hist := copy_histogram(state)
	check(hist.size() == 20 and hist[-1] >= 2,
			"TP-14: the deck was cycled before anything repeated -- every card is marked twice over",
			str(hist))
	check(hist[0] == 3 and hist.count(3) == 10 and hist.count(2) == 10,
			"TP-14: 50 marks over 20 cards is two full passes plus ten cells of a third -- ten cards"
			+ " at three copies, ten at two, and nothing higher", str(hist))
	CardEnvironment.CURRENT = null
	g.free()

	var wide := plan_state(TestDecks.deck_standard_52(), 1)
	deal_onto(wide, 606)
	var g2 := Game.new()
	g2.state = wide
	CardEnvironment.CURRENT = g2
	g2.effect_api.add_grid(GridData.new())
	var wide_hist := copy_histogram(wide)
	check(wide_hist.size() == 50 and wide_hist[0] == 1,
			"TP-04: with 52 cards the added grid takes 25 cards no mark had used yet", str(wide_hist))
	CardEnvironment.CURRENT = null
	g2.free()

#TP-14: `Board.add_grid` is the mutator EVERY appearance goes through -- the effect api above, a
#fixture standing three grids up, a visual probe -- so a board that shows three grids never shows
#marks on the first one only.
func test_grids_appended_to_a_planned_board_are_dealt() -> void:
	var g := await start_show(TestDecks.deck_standard_52(), 11)
	check(g.state.grids.size() == 1 and marks_of(g.state).size() == 25,
			"TP-14: precondition: a 52-card show opens with one fully marked grid",
			"%d grids, %d marks" % [g.state.grids.size(), marks_of(g.state).size()])
	var opening := grid_signature(g.state, 0)
	Board.add_grid(g.state, GridData.new())
	Board.add_grid(g.state, GridData.new())
	check(marks_per_grid(g.state) == ([25, 25, 25] as Array[int]),
			"TP-14: two grids appended through the board's own mutator came up fully marked",
			"per grid %s of 25 each" % str(marks_per_grid(g.state)))
	check(grid_signature(g.state, 0) == opening,
			"TP-14: ...and the opening grid's marks are untouched")
	check(g.state.validate().is_empty(), "TP-14: the grown board breaks no invariant",
			", ".join(g.state.validate()))
	free_show(g)

#TP-15: a cell added past the grid's own block is dealt like any other unmarked cell, and with every
#card already used its mark is a repeat.
func test_a_cell_added_to_a_grid_takes_a_mark() -> void:
	var state := plan_state(TestDecks.deck_standard_52().slice(0, 25), 1)
	deal_onto(state, 707)
	check(copy_histogram(state)[0] == 1,
			"TP-15: precondition: 25 cards fill 25 cells with no repeat", str(copy_histogram(state)))
	var grid : GridData = state.grids[0]
	grid.cells.append(ArrayCardData.new())
	var extra := CardData.new().with_type(TypeGridCell.new())
	extra.stage = CardData.Stage.ZONE
	grid.cell_types.append(extra)
	deal_onto(state, 707)
	check(BoardPlan.is_marked(extra), "TP-15: the added 26th cell takes a mark of its own")
	var hist := copy_histogram(state)
	check(hist.size() == 25 and hist[0] == 2 and hist.count(2) == 1,
			"TP-15: every card was used, so the 26th cell repeats exactly one of them", str(hist))

#TP-13: the plan is dealt from the deck as it stood and never looks again, so a card minted later is
#unplanned and moving one to the discard changes nothing.
func test_a_card_minted_after_the_deal_gets_no_mark() -> void:
	var state := plan_state(TestDecks.plan_deck(), 1)
	deal_onto(state, 404)
	var dealt := plan_signature(state)
	var minted := CardData.new()
	minted.rank = PipRankNumeral.new().with_value(9)
	minted.with_suit(PipSuitHoop.new())
	minted.stage = CardData.Stage.DRAW
	state.draw_deck.append(minted)
	var named := false
	for mark : CardData in marks_of(state):
		if PipComparator.printed_card_same(mark, minted): named = true
	check(plan_signature(state) == dealt, "TP-13: minting a card mid-show changes no mark")
	check(not named, "TP-13: ...and nothing on the board names the new card")
	var spent : CardData = state.draw_deck[0]
	state.draw_deck.erase(spent)
	spent.stage = CardData.Stage.DISCARD
	state.discard_deck.append(spent)
	check(plan_signature(state) == dealt,
			"TP-13: discarding a marked card's source leaves its mark exactly where it was")
	check(state.validate().is_empty(),
			"TP-13: a discarded source still counts as a card the state holds",
			", ".join(state.validate()))

## A dealt 5x5 board behind a live game -- what the effect api's mark surface is asked through.
func planned_game(plan_seed: int) -> Game:
	var state := make_state()
	deal_onto(state, plan_seed)
	var g := Game.new()
	g.state = state
	CardEnvironment.CURRENT = g
	return g

## How many marks other than the one on `skip` name what `card` prints.
func copies_apart_from(state: GameData, card: CardData, skip: CardData) -> int:
	var copies := 0
	for mark : CardData in marks_of(state):
		if mark != skip and PipComparator.printed_card_same(mark, card): copies += 1
	return copies

## The deck identities a redraw of `skip` may offer: the fewest-copied prints with `skip` still marked, less `skip`'s own.
func redraw_offer(state: GameData, skip: CardData) -> Array[CardData]:
	var lowest := -1
	for card : CardData in state.draw_deck:
		var copies := copies_apart_from(state, card, null)
		if lowest == -1 or copies < lowest: lowest = copies
	var out : Array[CardData] = []
	for card : CardData in state.draw_deck:
		if copies_apart_from(state, card, null) == lowest \
				and not PipComparator.printed_card_same(card, skip):
			out.append(card)
	return out

## Does any card of `offer` print what `card` prints?
func offer_holds(offer: Array[CardData], card: CardData) -> bool:
	for offered : CardData in offer:
		if PipComparator.printed_card_same(offered, card): return true
	return false

#TP-52: a mark lives ON the cell's own card, so the surface hands that card over rather than a copy
#-- an effect reading a mark and the board scoring it are looking at one object.
func test_mark_at_reads_the_cells_own_card() -> void:
	var g := planned_game(909)
	check(g.effect_api.mark_at(BoardCoord.new(0, 2, 1, 0)) == g.state.grids[0].cell_types[7],
			"TP-52: mark_at hands back the cell's own zone card")
	check(g.effect_api.mark_at(BoardCoord.new(0, 9, 9, 0)) == null,
			"TP-52: mark_at answers null for a coordinate that names no cell")
	free_show(g)

#TP-52: a reroll IS the deal at one cell, with the identity it replaces taken OUT of the offer --
#the fewest-copies pool counted while the cell is still marked, so what it drew is one of the cards
#the board carries fewest copies of and is never the face it replaced.
func test_a_reroll_draws_from_the_deals_own_pool() -> void:
	var g := planned_game(909)
	var target := BoardCoord.new(0, 2, 1, 0)
	var mark := g.effect_api.mark_at(target)
	var before := mark_print(mark)
	var offer := redraw_offer(g.state, mark)
	g.effect_api.reroll_mark(target)
	check(BoardPlan.is_marked(mark) and marks_of(g.state).size() == 25,
			"TP-52: the rerolled cell comes back marked and no other cell lost its mark",
			"%d marks" % marks_of(g.state).size())
	check(mark_print(mark) != before,
			"TP-52: the cell prints an identity other than the one the reroll replaced",
			"%s -> %s" % [before, mark_print(mark)])
	check(offer_holds(offer, mark),
			"TP-52: the reroll drew one of the fewest-copies identities other than that one",
			"%s -> %s, out of %d on offer" % [before, mark_print(mark), offer.size()])
	check(not (mark.type as TypeGridCell).granted,
			"TP-52: a rerolled mark is a dealt one, not a granted one")
	check(g.state.validate().is_empty(), "TP-52: the rerolled board breaks no invariant",
			", ".join(g.state.validate()))
	free_show(g)

#TP-52: "redraw" means the face CHANGES. With 20 cards over 25 cells the offer always holds another
#identity, so every cell of the board rerolls to one -- the row that catches a reroll offered the
#identity it just cleared, which on a fewest-copies pool is the one that always wins.
func test_every_cell_rerolls_to_a_new_identity() -> void:
	var g := planned_game(909)
	var unchanged : Array[String] = []
	for i : int in g.state.grids[0].cell_types.size():
		var mark : CardData = g.state.grids[0].cell_types[i]
		var before := mark_print(mark)
		g.effect_api.reroll_mark(g.state.cell_type_coord(mark))
		if mark_print(mark) == before: unchanged.append("%d %s" % [i, before])
	check(unchanged.is_empty(),
			"TP-52: each of the 25 cells rerolls to a printed identity other than its own",
			"%d cells came back the same: %s" % [unchanged.size(), ", ".join(unchanged)])
	check(marks_of(g.state).size() == 25 and g.state.validate().is_empty(),
			"TP-52: ...and 25 rerolls leave every cell marked and no invariant broken",
			"%d marks; %s" % [marks_of(g.state).size(), ", ".join(g.state.validate())])
	free_show(g)

#TP-52: the cell is cleared only once a replacement is in hand, so a reroll with nothing left to
#offer -- an empty draw pile late in a show -- leaves the mark it cannot replace standing rather
#than deleting it.
func test_a_reroll_with_nothing_on_offer_keeps_the_mark() -> void:
	var g := planned_game(913)
	var target := BoardCoord.new(0, 2, 1, 0)
	var mark := g.effect_api.mark_at(target)
	var before := mark_print(mark)
	g.state.draw_deck.clear()
	g.effect_api.reroll_mark(target)
	check(BoardPlan.is_marked(mark) and mark_print(mark) == before,
			"TP-52: an empty draw pile leaves the cell marked with the identity it had",
			"%s -> %s" % [before, mark_print(mark)])
	free_show(g)

#TP-52: the reroll rolls a generator seeded from the plan's own stored seed, so the cell a resumed
#show rerolls comes back the same card. Moving the global generator between the two catches a deal
#that reached for it instead.
func test_a_reroll_repeats_for_one_plan_seed() -> void:
	seed(31337)
	var first := planned_game(909)
	first.effect_api.reroll_mark(BoardCoord.new(0, 2, 1, 0))
	var rerolled := plan_signature(first.state)
	free_show(first)
	seed(4242)
	var again := planned_game(909)
	again.effect_api.reroll_mark(BoardCoord.new(0, 2, 1, 0))
	check(plan_signature(again.state) == rerolled,
			"TP-52: one plan seed rerolls one cell to one card, wherever the global generator stands",
			plan_signature(again.state))
	free_show(again)
	randomize()

#TP-52: this is how a level poisons or blesses a board -- the source may print a card the deck never
#had, and the granted flag is what the membership invariant exempts (TP-16 proves that exemption).
func test_grant_marks_a_card_the_deck_never_had() -> void:
	var g := planned_game(910)
	var target := BoardCoord.new(0, 0, 0, 0)
	var mark := g.effect_api.mark_at(target)
	BoardPlan.write_mark(mark, decorated_source(), false)
	var outsider := CardData.new().with_type(TypePaper.new()) \
			.with_rank(PipRankNumeral.new().with_value(9)) \
			.with_suit(PipSuitHoop.new())
	g.effect_api.grant_mark(target, outsider)
	check(mark.rank.value == 9 and is_same(mark.suit.get_script(), PipSuitHoop),
			"TP-52: the cell prints the granted card's rank 9, which no deck card prints",
			mark_print(mark))
	check(mark.skill == null and mark.stamp == null,
			"TP-52: the mark it replaced left no slot of its own behind", mark_print(mark))
	check((mark.type as TypeGridCell).granted,
			"TP-52: ...and the cell records the mark as granted")
	check(g.state.validate().is_empty(),
			"TP-52: a granted mark of a card outside the deck breaks no invariant",
			", ".join(g.state.validate()))
	(mark.type as TypeGridCell).granted = false
	check(i6_violations(g.state).size() == 1,
			"TP-52: the same mark unflagged is what I6 reports, so the flag is doing the work",
			"I6 said: %s" % ", ".join(i6_violations(g.state)))
	free_show(g)

#TP-52: a swap moves everything a mark IS -- all four printed slots, each copied modifier's backref
#and the granted flag -- so a board swapped twice over is the board it was.
func test_swap_exchanges_two_marks_whole() -> void:
	var g := planned_game(911)
	var left := BoardCoord.new(0, 0, 0, 0)
	var right := BoardCoord.new(0, 4, 4, 0)
	var mark_left := g.effect_api.mark_at(left)
	var mark_right := g.effect_api.mark_at(right)
	BoardPlan.write_mark(mark_left, decorated_source(), true)
	var digest := TestGridFixtures.board_digest(g.state)
	var was_left := mark_print(mark_left)
	var was_right := mark_print(mark_right)
	g.effect_api.swap_marks(left, right)
	check(mark_print(mark_left) == was_right and mark_print(mark_right) == was_left,
			"TP-52: the two cells exchanged every printed slot",
			"%s / %s" % [mark_print(mark_left), mark_print(mark_right)])
	check(not (mark_left.type as TypeGridCell).granted
			and (mark_right.type as TypeGridCell).granted,
			"TP-52: ...and each granted flag travelled with the mark it belonged to",
			str(granted_flags(g.state)))
	check(stray_backrefs(g.state).is_empty(),
			"TP-52: every copied modifier answers for the cell it now lives on",
			", ".join(stray_backrefs(g.state)))
	check(g.state.validate().is_empty(), "TP-52: the swapped board breaks no invariant",
			", ".join(g.state.validate()))
	g.effect_api.swap_marks(left, right)
	check(TestGridFixtures.board_digest(g.state) == digest,
			"TP-52: swapping the same two cells back restores the board it was")
	free_show(g)

#TP-52: the match is derived on every ask, so a reroll under a card already standing there changes
#what that card matches with no cache to invalidate. The deck prints no 9, so the rank match cannot
#survive the reroll and only the suit can still agree.
func test_a_reroll_under_a_placed_card_is_live() -> void:
	var g := planned_game(912)
	var target := BoardCoord.new(0, 2, 2, 0)
	var mark := g.effect_api.mark_at(target)
	var standing := CardData.new().with_type(TypePaper.new()) \
			.with_rank(PipRankNumeral.new().with_value(9)) \
			.with_suit(PipSuitHoop.new())
	standing.stage = CardData.Stage.PLAY
	g.effect_api.grant_mark(target, standing)
	Board.place_in_cell(g.state, standing, target)
	var before : int = await MarkMatch.matches_at(g.state, standing, target)
	check(before == (MarkMatch.Property.RANK | MarkMatch.Property.SUIT),
			"TP-52: precondition: the card standing on the cell matches the mark under it",
			"matched %d" % before)
	g.effect_api.reroll_mark(target)
	var expected : int = MarkMatch.Property.SUIT if is_same(mark.suit.get_script(), PipSuitHoop) else 0
	var after : int = await MarkMatch.matches_at(g.state, standing, target)
	check(after == expected and after != before,
			"TP-52: the match re-derives from the NEW mark under the placed card",
			"a %s standing on %s: matched %d, the new mark allows %d"
			% [standing.log_str(), mark_print(mark), after, expected])
	check(g.state.validate().is_empty(),
			"TP-52: rerolling under a placed card leaves the board consistent",
			", ".join(g.state.validate()))
	free_show(g)

#TP-17: the deal result IS what persists, so every copy path has to carry the marks -- including
#each copied modifier's backref, which a deep copy does not remap and a save does not carry.
func test_a_dealt_plan_survives_a_round_trip() -> void:
	var state := plan_state(TestDecks.plan_deck(), 1)
	deal_onto(state, 808)
	var dealt := plan_signature(state)
	var copy := state.duplicate_state()
	check(plan_signature(copy) == dealt, "TP-17: duplicate_state carries every mark",
			plan_signature(copy))
	check(stray_backrefs(copy).is_empty(),
			"TP-17: ...and the copy's marks answer for the copy's own cells",
			", ".join(stray_backrefs(copy)))
	state.pack_scores()
	state.unpack_scores()
	check(plan_signature(state) == dealt,
			"TP-17: packing and unpacking the scores leaves the plan alone")
	var err := ResourceSaver.save(state.to_saveable(), ROUND_TRIP_PATH)
	check_impl(err == OK, "TP-17: the dealt board wrote to disk", "err=%d" % err)
	if err != OK: return
	var loaded : GameData = ResourceLoader.load(ROUND_TRIP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	loaded.restore_runtime()
	check(plan_signature(loaded) == dealt,
			"TP-17: a save round-trip restores the plan cell for cell", plan_signature(loaded))
	check(granted_flags(loaded) == granted_flags(state) and not granted_flags(loaded).has(true),
			"TP-17: ...and each cell comes back dealt rather than granted", str(granted_flags(loaded)))
	check(stray_backrefs(loaded).is_empty(),
			"TP-17: ...and every restored mark's modifiers point at the restored cell",
			", ".join(stray_backrefs(loaded)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ROUND_TRIP_PATH))

#TP-18: a run in flight was saved before this feature existed, so its cells are bare and its plan
#seed is 0. Nothing re-deals such a board -- the planner fires at game start, which a resume never
#reaches -- and it plays exactly as it did before.
func test_a_plan_less_save_resumes_and_plays() -> void:
	var g := await plan_less_show(TestDecks.plan_deck())
	check(marks_of(g.state).is_empty() and g.state.plan_seed == 0,
			"TP-18: precondition: a board built with no planner carries no plan",
			"%d marks, seed %d" % [marks_of(g.state).size(), g.state.plan_seed])
	var err := ResourceSaver.save(g.state.to_saveable(), PLAN_LESS_PATH)
	check_impl(err == OK, "TP-18: the plan-less board wrote to disk", "err=%d" % err)
	free_show(g)
	if err != OK: return
	var loaded : GameData = ResourceLoader.load(PLAN_LESS_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	loaded.restore_runtime()
	var resumed := Game.new()
	resumed.state = loaded
	CardEnvironment.CURRENT = resumed
	check(marks_of(loaded).is_empty() and loaded.plan_seed == 0,
			"TP-18: the restored board comes up with no mark anywhere",
			"%d marks" % marks_of(loaded).size())
	check(loaded.validate().is_empty(), "TP-18: ...and a plan-less board is a consistent one",
			", ".join(loaded.validate()))
	await resumed.refill_entrance_if_due()
	var held : CardData = loaded.upper_zone[0].datas[0]
	var target := BoardCoord.new(0, 0, 0, 0)
	await resumed.place_card_in_grid(held, target)
	check(loaded.card_at(target) == held,
			"TP-18: the board accepted a placement onto a plan-less cell",
			"cell holds %s" % loaded.card_at(target))
	check(marks_of(loaded).is_empty(), "TP-18: ...and nothing dealt a plan behind the placement")
	CardEnvironment.CURRENT = null
	resumed.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PLAN_LESS_PATH))
