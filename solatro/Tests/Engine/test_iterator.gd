extends TestSuite
# res://Tests/Engine/test_iterator.gd
# CardDataIterator suite: every case compares the iterator's
# output to a naive flatten oracle (1D in order; 2D row-major across columns).
#
# CATEGORY MAP: this whole suite is IMPLEMENTATION — it pins the iterator's internal
# traversal order and live-mutation policy (B10). No player-visible rule lives here.

var env : FakeEnvironment
# Every card the suite ever builds.
var _made : Array[CardData] = []

func suite_name() -> String:
	return "ITERATOR"

func _ready() -> void:
	TestLog.line("============ CARD DATA ITERATOR TEST PASS ============")
	env = FakeEnvironment.new()
	add_child(env)
	run_shape_tests()
	run_mixed_tests()
	run_reuse_and_mutation_tests()
	run_grid_tests()
	env.queue_free()
	finish()


# ==============================================================================
# ORACLE + HELPERS
# ==============================================================================

## Naive flatten: 1D arrays in order; 2D collections row-major (row 0 of every
## column, then row 1, ...). Must match CardDataIterator exactly.
func oracle(collections: Array[Variant]) -> Array[CardData]:
	var out: Array[CardData] = []
	for coll: Variant in collections:
		if not coll:
			continue
		if coll is Array[ArrayCardData]:
			var max_rows := 0
			for c: ArrayCardData in coll:
				max_rows = max(max_rows, c.datas.size())
			for row in max_rows:
				for c: ArrayCardData in coll:
					if row < c.datas.size():
						out.append(c.datas[row])
		elif coll is Array[CardData]:
			out.append_array(coll as Array[CardData])
	return out

func iterate() -> Array[CardData]:
	var out: Array[CardData] = []
	for data: CardData in CardDataIterator.new():
		out.append(data)
	return out

func assert_matches_oracle(ctx: String) -> void:
	var got := iterate()
	var want := oracle(env.card_collections)
	check(got == want, ctx, "got %d cards %s / want %d %s" % [got.size(), got, want.size(), want])

func cards(n: int) -> Array[CardData]:
	var out: Array[CardData] = []
	for i in n:
		out.append(TestFactories.m_card(i + 1, TestFactories.uc()))
	_made.append_array(out)
	return out

func zone(col_sizes: Array[int]) -> Array[ArrayCardData]:
	var out: Array[ArrayCardData] = []
	for s in col_sizes:
		out.append(TestFactories.col(cards(s)))
	return out


# ==============================================================================
# SECTION 1: COLLECTION SHAPES
# ==============================================================================
func run_shape_tests() -> void:
	implementation_section("SECTION 1: SHAPES")

	env.card_collections = []
	check(iterate().is_empty(), "no collections -> empty")

	env.card_collections = [null, null]
	check(iterate().is_empty(), "null collection entries skipped")

	var empty_1d : Array[CardData] = []
	env.card_collections = [empty_1d]
	check(iterate().is_empty(), "single empty 1D collection -> empty")

	env.card_collections = [cards(3)]
	assert_matches_oracle("single 1D collection, in order")

	env.card_collections = [cards(2), cards(4)]
	assert_matches_oracle("two 1D collections, concatenated")

	env.card_collections = [zone([2, 2])]
	assert_matches_oracle("2D uniform columns, row-major")

	env.card_collections = [zone([0, 3, 1, 0, 2])]
	assert_matches_oracle("2D ragged columns {0,3,1,0,2}, row-major")

	env.card_collections = [zone([0, 0, 0])]
	check(iterate().is_empty(), "2D with ALL columns empty (is_row_empty break path)")

	var empty_2d : Array[ArrayCardData] = []
	env.card_collections = [empty_2d, cards(1)]
	assert_matches_oracle("empty 2D collection skipped, next collection still visited")

	env.card_collections = [42, "junk", Vector2.ONE, cards(2)]
	var got := iterate()
	check(got.size() == 2, "unrecognized collection types skipped without error", str(got))


# ==============================================================================
# SECTION 2: MIXED (GAME-SHAPED) COLLECTION SETS
# ==============================================================================
func run_mixed_tests() -> void:
	implementation_section("SECTION 2: MIXED")

	#mirror of Game.get_card_collections: 1D deck, two 2D zones, 1D discard/type/rules
	env.card_collections = [
		cards(5),               #draw
		zone([3, 0, 1]),        #upper
		zone([2, 2]),           #lower
		cards(2),               #discard
		cards(3),               #upper types
		cards(2),               #lower types
		cards(1),               #rules
	]
	assert_matches_oracle("game-shaped mixed collection set")

	#every card visited exactly once (no duplicates by identity)
	var got := iterate()
	var seen := {}
	var dup := false
	for c in got:
		if seen.has(c): dup = true
		seen[c] = true
	check(not dup, "no card visited twice")


# ==============================================================================
# SECTION 3: RE-USE + LIVE-MUTATION PIN (review B10 — live iteration BY DESIGN)
# ==============================================================================
func run_reuse_and_mutation_tests() -> void:
	implementation_section("SECTION 3: RE-USE / MUTATION")

	env.card_collections = [cards(4)]
	var it := CardDataIterator.new()
	var first: Array[CardData] = []
	for d: CardData in it: first.append(d)
	var second: Array[CardData] = []
	for d: CardData in it: second.append(d)
	check(first == second and first.size() == 4, "same iterator instance re-usable")

	#B10 PIN: iteration reads the LIVE collection (owner: by design). Removing an
	#upcoming card mid-iteration means it is never visited; the rest still are.
	var pool := cards(4) # [a, b, c, d]
	var a := pool[0]; var b := pool[1]; var c := pool[2]; var d := pool[3]
	env.card_collections = [pool]
	var visited: Array[CardData] = []
	for cur: CardData in CardDataIterator.new():
		visited.append(cur)
		if cur == b:
			pool.erase(c) #a mod discarding a not-yet-visited card
	var expected: Array[CardData] = [a, b, d]
	check(visited == expected,
			"B10 pin: live mutation skips removed upcoming card, visits the rest",
			"visited %s" % [visited])


# ==============================================================================
# SECTION 4: GRID WALK (PLAN.md §1.10) -- TP-15..TP-17
# ==============================================================================

## Independent oracle for a grid's cell array: `GridData.cells` is already stored row-major
## (`cell_index`), and each cell's stack is already stored bottom to top (append order) --
## so a flat read of the raw storage IS the row-major/bottom-to-top order, no computation
## borrowed from CardDataIterator.
func _grid_cells_flat(grid: GridData) -> Array[CardData]:
	var out : Array[CardData] = []
	for cell : ArrayCardData in grid.cells:
		out.append_array(cell.datas)
	return out

func run_grid_tests() -> void:
	implementation_section("SECTION 4: GRID WALK")
	run_tp15_grid_order_test()
	run_tp16_grid_stack_order_test()
	run_tp17_sparse_grid_test()

## TP-15: draw_deck first, then the board, row-major within a grid. FIX-MIXED-H.
func run_tp15_grid_order_test() -> void:
	var state := TestGridFixtures.build_fix_mixed_h()
	var draw := cards(2)
	state.draw_deck = draw
	env.card_collections = state.get_card_collections()

	var expected : Array[CardData] = []
	expected.append_array(draw)
	for grid : GridData in state.grids:
		expected.append_array(_grid_cells_flat(grid))
	for grid : GridData in state.grids:
		expected.append_array(grid.cell_types)

	var got := iterate()
	check(got == expected,
			"TP-15: draw_deck first, then the board, row-major within a grid",
			"got %d cards / want %d" % [got.size(), expected.size()])

## TP-16: within a cell the walk is bottom to top. FIX-STACK-5.
func run_tp16_grid_stack_order_test() -> void:
	var state := TestGridFixtures.build_fix_stack_5()
	env.card_collections = state.get_card_collections()

	var grid : GridData = state.grids[0]
	var expected : Array[CardData] = []
	expected.append_array(_grid_cells_flat(grid))
	expected.append_array(grid.cell_types)

	var got := iterate()
	check(got == expected,
			"TP-16: within a cell the walk is bottom to top",
			"got %d cards %s / want %d %s" % [got.size(), got, expected.size(), expected])

## TP-17 -- THE PHASE-1 GATE: a sparse grid, cards only in row 3, is walked completely. Built
## from FIX-GRID-1 (one empty 5x5 grid) with row 3 stocked HERE, independently of any fixture
## helper, so the expected sequence owes nothing to production code.
func run_tp17_sparse_grid_test() -> void:
	var state := TestGridFixtures.build_fix_grid_1()
	var grid : GridData = state.grids[0]
	var row3 : Array[CardData] = []
	for x in grid.grid_width:
		var idx := grid.cell_index(x, 3)
		var card := TestFactories.m_card(1, TestFactories.uc())
		card.stage = CardData.Stage.PLAY
		grid.cells[idx].datas.append(card)
		row3.append(card)
	env.card_collections = state.get_card_collections()

	var expected : Array[CardData] = []
	expected.append_array(row3)
	expected.append_array(grid.cell_types)

	var got := iterate()
	check(got == expected,
			"TP-17: a sparse grid (cards only in row 3) is walked completely",
			"got %d cards %s / want %d %s" % [got.size(), got, expected.size(), expected])
