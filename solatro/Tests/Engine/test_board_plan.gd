extends TestSuite
# res://Tests/Engine/test_board_plan.gd

#A mark IS the existing `cell_types[i]` card with a rank or a suit printed on it -- no second
#array, no flag -- so these checks write those two fields directly. CATEGORY MAP: all
#IMPLEMENTATION, like every other `validate()` claim; it is a debug invariant checker.
func suite_name() -> String:
	return "BOARD PLAN"

func _ready() -> void:
	TestLog.line("============ BOARD PLAN TEST PASS ============")
	implementation_section("THE MARK PREDICATE")
	test_is_marked_asks_rank_or_suit()
	implementation_section("I6: A DEALT MARK NAMES A CARD THE STATE HOLDS")
	test_i6_fails_a_mark_the_deck_never_had()
	test_i6_exempts_a_granted_mark()
	test_i6_passes_a_mark_the_deck_prints()
	finish()

## A 5x5 board with the plan deck in draw -- the state every check below starts from.
func make_state() -> GameData:
	var state := TestGridFixtures.build_fix_grid_1()
	state.draw_deck = TestDecks.plan_deck()
	for card : CardData in state.draw_deck:
		card.stage = CardData.Stage.DRAW
	return state

## Marks grid 0's first cell by hand: `BoardPlan.write_mark` does not exist yet.
func mark_first_cell(state: GameData, rank_value: float, suit: GDScript) -> CardData:
	var mark : CardData = state.grids[0].cell_types[0]
	mark.rank = PipRankNumeral.new().with_value(rank_value)
	mark.suit = suit.new() as PipSuit
	return mark

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
