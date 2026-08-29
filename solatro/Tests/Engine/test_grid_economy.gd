extends TestSuite
# res://Tests/Engine/test_grid_economy.gd
# Phase 3 of the poker-patience board: the per-grid score buckets and how a scored line
# reaches one (TP-47..TP-50). Each grid keeps three buckets that combine into its own score
# -- row, col, and ONE special bucket every diagonal and every future non-directional meld
# shares. Height-0 buckets are flat per grid; raised levels are indexed by height.

## This suite spells its own entry-point names in the registration gate, so the gate skips it.
const SELF_PATH := "res://Tests/Engine/test_grid_economy.gd"

func suite_name() -> String:
	return "GRID ECONOMY"

func _ready() -> void:
	TestLog.line("============ GRID ECONOMY TEST PASS ============")
	check_all_tests_registered()
	run_buckets_are_independent_test()
	await run_diagonals_share_one_special_bucket_test()
	run_pack_unpack_round_trip_test()
	run_duplicate_state_copies_by_hand_test()
	run_cell_buckets_test()
	await run_cell_bucket_from_a_real_stack_test()
	run_cell_bucket_persistence_test()
	run_worked_example_test()
	run_rows_without_diagonal_test()
	run_empty_grid_scores_zero_test()
	run_zero_valued_bucket_excluded_test()
	run_board_total_is_the_sum_test()
	run_terms_aggregate_their_levels_test()
	await run_played_scores_survive_the_save_path_test()
	run_retired_identifiers_grep_gate()
	run_no_resurrected_act_count_test()
	finish()
# ==============================================================================
# Helpers: the real detector in the rules deck, and a Game that records what banked.
# ==============================================================================
class RecordingGame extends Game:
	var banked : Array[int] = []
	func add_line_score(section : ScoringSection, amount : int) -> void:
		banked.append(amount)
		super(section, amount)

func rules_card(skill: CardModifierSkill) -> CardData:
	var c := CardData.new().with_skill(skill)
	c.stage = CardData.Stage.RULES
	skill.spotlit = true
	return c

func detector_game(state: GameData) -> RecordingGame:
	var g := RecordingGame.new()
	state.rules_deck = [rules_card(SkillLineDetector.new())] as Array[CardData]
	g.state = state
	CardEnvironment.CURRENT = g
	return g

func free_game(g: Game) -> void:
	CardEnvironment.CURRENT = null
	g.free()

## Value of a per-grid bucket, 0 when it does not exist yet.
## A grid's TOTAL for one bucket. ⚠ GAP-015 re-keyed row/col to `(grid, index, height)`, so "grid
## i's row bucket" is now the SUM of that grid's entries — which is exactly what `_row_term`
## multiplies, so these checks still describe the economy they always did.
func bucket_value(bucket: Dictionary[Vector3i, BigNumber], grid: int) -> float:
	var total := 0.0
	for key : Vector3i in bucket:
		if key.x == grid: total += bucket[key].to_float()
	return total

## The per-grid Array form, still used by `score_special`.
func special_value(bucket: Array[BigNumber], i: int) -> float:
	if i >= bucket.size(): return 0.0
	return bucket[i].to_float()

# ==============================================================================
# TP-47 -- row, col and special buckets exist per grid and are INDEPENDENT: writing one
# grid's bucket must not move another grid's, and writing row must not move col or
# special. FIX-GRID-3.
# ==============================================================================
func run_buckets_are_independent_test() -> void:
	behavior_section("BUCKETS ARE INDEPENDENT")
	var state := TestGridFixtures.build_fix_grid_3()
	state.resize_grid_bucket(state.score_special, 3)

	state.bank_line_score(state.scores_row, 1, 0, 0, 10)
	check(bucket_value(state.scores_row, 1) == 10.0,
			"a grid's row bucket takes the score written to it",
			"got %f" % bucket_value(state.scores_row, 1))
	check(bucket_value(state.scores_row, 0) == 0.0 and bucket_value(state.scores_row, 2) == 0.0,
			"writing grid 1's row bucket leaves the OTHER grids' row buckets alone",
			"grid0 %f grid2 %f" % [bucket_value(state.scores_row, 0), bucket_value(state.scores_row, 2)])
	check(bucket_value(state.scores_col, 1) == 0.0 and special_value(state.score_special, 1) == 0.0,
			"and leaves the SAME grid's col and special buckets alone",
			"col %f special %f" % [bucket_value(state.scores_col, 1), special_value(state.score_special, 1)])

	state.bank_line_score(state.scores_col, 1, 0, 0, 5)
	state.score_special[1].plus_equals(2)
	check(bucket_value(state.scores_row, 1) == 10.0,
			"writing col and special does not disturb the row bucket already written",
			"got %f" % bucket_value(state.scores_row, 1))
	check(bucket_value(state.scores_col, 1) == 5.0 and special_value(state.score_special, 1) == 2.0,
			"all three buckets hold their own value at once",
			"col %f special %f" % [bucket_value(state.scores_col, 1), special_value(state.score_special, 1)])

	# ⚠ GAP-015: a raised level is not a separate CONTAINER, it is another HEIGHT KEY in the same
	# bucket. So the claim is that writing height 2 leaves height 0 alone — not that two containers
	# exist.
	state.bank_line_score(state.scores_row, 1, 0, 2, 7)
	check(state.line_score(state.scores_row, 1, 0, 2) == 7.0,
			"a raised row bucket takes its own score")
	check(state.line_score(state.scores_row, 1, 0, 0) == 10.0,
			"...and the height-0 entry of the same row is untouched — heights are separate keys",
			"height-0 row now %f" % state.line_score(state.scores_row, 1, 0, 0))
	check(bucket_value(state.scores_row, 1) == 17.0,
			"...while the GRID's row term is their sum, which is what `_row_term` multiplies",
			"grid row term %f" % bucket_value(state.scores_row, 1))
	check(state.line_score(state.scores_row, 0, 0, 2) == 0.0
			and state.line_score(state.scores_row, 1, 0, 1) == 0.0,
			"and is independent across both grid and height")

# ==============================================================================
# TP-48 -- every diagonal banks into the ONE special bucket. FIX-TRIPLE: filling the
# shared cell completes a row, a column and BOTH diagonals at once, so if the two
# diagonals went anywhere separate this would show it.
# ==============================================================================
func run_diagonals_share_one_special_bucket_test() -> void:
	behavior_section("DIAGONALS SHARE ONE SPECIAL BUCKET")
	var state := TestGridFixtures.build_fix_triple()
	var g := detector_game(state)
	var card := TestFactories.m_card(7, TestFactories.uc())
	await g.place_card_in_grid(card, BoardCoord.new(0, 2, 2, 0))

	check(state.score_special.size() >= 1,
			"the special bucket exists for grid 0 once a diagonal scored",
			"size %d" % state.score_special.size())
	var special := special_value(state.score_special, 0)
	check(special > 0.0, "both diagonals banked something into the special bucket",
			"special %f" % special)
	check(bucket_value(state.scores_row, 0) > 0.0,
			"the row that completed banked into the ROW bucket, not the special one")
	check(bucket_value(state.scores_col, 0) > 0.0,
			"and the column into the COL bucket")
	# The special bucket holds the sum of BOTH diagonals, not one of them: the two are
	# equal-length lines through the same fixture, so a single diagonal would read lower.
	check(special >= bucket_value(state.scores_row, 0),
			"the one special bucket carries BOTH diagonals, not just the last one to score",
			"special %f vs one row line %f" % [special, bucket_value(state.scores_row, 0)])
	free_game(g)

# ==============================================================================
# TP-49 -- buckets survive a pack_scores / unpack_scores round trip. BigNumber is
# RefCounted and never serialized directly; the disk form is the packed_* arrays.
# FIX-GRID-3.
# ==============================================================================
func run_pack_unpack_round_trip_test() -> void:
	behavior_section("PACK UNPACK ROUND TRIP")
	var state := TestGridFixtures.build_fix_grid_3()
	state.resize_grid_bucket(state.score_special, 3)
	state.bank_line_score(state.scores_row, 0, 0, 0, 11)
	state.bank_line_score(state.scores_row, 2, 0, 0, 33)
	state.bank_line_score(state.scores_col, 1, 0, 0, 22)
	state.score_special[2].plus_equals(44)
	# Deliberately RAGGED: grid 0 has three levels, grid 1 has two, grid 2 has none. A
	# flattening that loses the per-grid lengths cannot rebuild this.
	state.bank_line_score(state.scores_row, 0, 0, 1, 55)
	state.bank_line_score(state.scores_row, 1, 0, 2, 66)

	state.pack_scores()
	# Wipe the runtime side entirely, so unpack has to rebuild from the packed arrays alone.
	state.scores_row = {}
	state.scores_col = {}
	state.score_special = []
	state.unpack_scores()

	check(state.line_score(state.scores_row, 0, 0, 0) == 11.0
			and state.line_score(state.scores_row, 2, 0, 0) == 33.0,
			"height-0 row entries survive the round trip with their values",
			"got %f and %f" % [state.line_score(state.scores_row, 0, 0, 0),
			state.line_score(state.scores_row, 2, 0, 0)])
	check(state.line_score(state.scores_col, 1, 0, 0) == 22.0, "height-0 col entries survive",
			"got %f" % state.line_score(state.scores_col, 1, 0, 0))
	check(special_value(state.score_special, 2) == 44.0, "the special bucket survives",
			"got %f" % special_value(state.score_special, 2))
	check(state.line_score_levels(state.scores_row, 1) == 3,
			"a grid's raised levels come back — GAP-015 keys height into the bucket itself, so the "
			+ "deepest key is what says how many label rows the gutter owes",
			"got %d" % state.line_score_levels(state.scores_row, 1))
	check(state.line_score(state.scores_row, 0, 0, 1) == 55.0
			and state.line_score(state.scores_row, 1, 0, 2) == 66.0,
			"raised buckets come back at the SAME grid and height they went in at")

# ==============================================================================
# TP-50 -- duplicate_state() copies the BigNumber buckets BY HAND. BigNumber is
# RefCounted and invisible to duplicate_deep, so a missed container would leave the copy
# sharing its scores with the live state -- undo would rewind the board and not the score.
# ⚠ Asserting equality right after the copy proves nothing. Mutate the ORIGINAL afterwards
# and assert the copy did not move. FIX-GRID-3.
# ==============================================================================
func run_duplicate_state_copies_by_hand_test() -> void:
	behavior_section("DUPLICATE STATE COPIES BY HAND")
	var state := TestGridFixtures.build_fix_grid_3()
	state.resize_grid_bucket(state.score_special, 3)
	state.bank_line_score(state.scores_row, 0, 0, 0, 10)
	state.bank_line_score(state.scores_col, 0, 0, 0, 20)
	state.score_special[0].plus_equals(30)
	state.bank_line_score(state.scores_row, 0, 0, 1, 40)
	state.bank_line_score(state.scores_col, 0, 0, 1, 50)

	var copy := state.duplicate_state()
	check(copy.line_score(copy.scores_row, 0, 0, 0) == 10.0,
			"the copy starts with the original's values",
			"got %f" % copy.line_score(copy.scores_row, 0, 0, 0))

	# THE REAL CHECK: move the original and confirm the copy stayed put.
	state.bank_line_score(state.scores_row, 0, 0, 0, 1000)
	state.bank_line_score(state.scores_col, 0, 0, 0, 1000)
	state.score_special[0].plus_equals(1000)
	state.bank_line_score(state.scores_row, 0, 0, 1, 1000)
	state.bank_line_score(state.scores_col, 0, 0, 1, 1000)

	# ⚠ The grid's whole row TERM, so this covers every height at once: the copy holds 10 at height
	# 0 and 40 at height 1, and the original has since grown by 2000 across the two.
	check(bucket_value(copy.scores_row, 0) == 50.0,
			"the copy's row bucket did NOT follow the original -- it is a real copy, at every height",
			"copy now %f" % bucket_value(copy.scores_row, 0))
	check(copy.line_score(copy.scores_col, 0, 0, 0) == 20.0,
			"nor the col bucket", "copy now %f" % copy.line_score(copy.scores_col, 0, 0, 0))
	check(special_value(copy.score_special, 0) == 30.0,
			"nor the special bucket", "copy now %f" % special_value(copy.score_special, 0))
	check(copy.line_score(copy.scores_row, 0, 0, 1) == 40.0,
			"nor the raised row bucket -- a coordinate-keyed bucket is copied entry by entry",
			"copy now %f" % copy.line_score(copy.scores_row, 0, 0, 1))
	check(copy.line_score(copy.scores_col, 0, 0, 1) == 50.0,
			"nor the raised col bucket",
			"copy now %f" % copy.line_score(copy.scores_col, 0, 0, 1))

# ==============================================================================
# The per-CELL bucket: a vertical stack banks into its own cell's bucket -- the number
# behind the height score label that sits above that stack. Keyed by coordinate rather
# than shaped as a 2-D array, because a grid's shape can change under an effect.
# ==============================================================================
func run_cell_buckets_test() -> void:
	behavior_section("PER-CELL BUCKETS")
	var state := TestGridFixtures.build_fix_grid_3()
	check(state.cell_score(0, Vector2i(1, 1)) == 0.0,
			"a cell that has never scored reads 0, not an error")

	state.bank_cell_score(0, Vector2i(1, 1), 10)
	check(state.cell_score(0, Vector2i(1, 1)) == 10.0,
			"a cell's bucket takes the score banked into it",
			"got %f" % state.cell_score(0, Vector2i(1, 1)))
	check(state.cell_score(0, Vector2i(1, 2)) == 0.0
			and state.cell_score(0, Vector2i(2, 1)) == 0.0,
			"the NEIGHBOURING cells' buckets are untouched -- one bucket per cell")
	check(state.cell_score(1, Vector2i(1, 1)) == 0.0,
			"and the SAME cell of another grid is a different bucket entirely")

	# Every payout of one stack accumulates into that stack's single bucket: a stack of 10
	# pays at height 5 and again at height 10, and both land in the same place.
	state.bank_cell_score(0, Vector2i(1, 1), 25)
	check(state.cell_score(0, Vector2i(1, 1)) == 35.0,
			"a second payout of the same stack accumulates into the same cell bucket",
			"got %f" % state.cell_score(0, Vector2i(1, 1)))

	# A coordinate key, not a fixed 2-D shape: a cell outside the grid's CURRENT bounds
	# still banks and reads back, which is what survives a grid changing shape.
	state.bank_cell_score(0, Vector2i(9, 9), 7)
	check(state.cell_score(0, Vector2i(9, 9)) == 7.0,
			"a cell beyond the grid's current bounds still keys its own bucket",
			"got %f" % state.cell_score(0, Vector2i(9, 9)))

## A real vertical stack, built through the real detector, banks into its own cell.
func run_cell_bucket_from_a_real_stack_test() -> void:
	behavior_section("CELL BUCKET FROM A REAL STACK")
	var state := TestGridFixtures.build_fix_grid_1()
	var g := detector_game(state)
	# Five cards into one cell: the fifth completes the vertical line and pays.
	for i in 5:
		g._begin_act()
		var card := TestFactories.m_card(i + 2, TestFactories.uc())
		await g.place_card_in_grid(card, BoardCoord.new(0, 3, 2, 0))
	var here := state.cell_score(0, Vector2i(3, 2))
	check(here > 0.0,
			"the completed stack banked into ITS OWN cell's bucket", "got %f" % here)
	check(state.cell_score(0, Vector2i(0, 0)) == 0.0,
			"no other cell's bucket moved")
	# It is NOT the special bucket, and not a row or column bucket.
	check(special_value(state.score_special, 0) == 0.0,
			"a vertical stack does NOT bank into the special bucket",
			"special %f" % special_value(state.score_special, 0))
	check(bucket_value(state.scores_row, 0) == 0.0
			and bucket_value(state.scores_col, 0) == 0.0,
			"nor into the row or column buckets",
			"row %f col %f" % [bucket_value(state.scores_row, 0), bucket_value(state.scores_col, 0)])
	free_game(g)

## The cell buckets survive a pack/unpack round trip and are hand-copied by duplicate_state.
func run_cell_bucket_persistence_test() -> void:
	behavior_section("CELL BUCKET PERSISTENCE")
	var state := TestGridFixtures.build_fix_grid_3()
	state.bank_cell_score(0, Vector2i(1, 1), 11)
	state.bank_cell_score(2, Vector2i(4, 0), 22)

	state.pack_scores()
	state.scores_cell = {}
	state.unpack_scores()
	check(state.cell_score(0, Vector2i(1, 1)) == 11.0
			and state.cell_score(2, Vector2i(4, 0)) == 22.0,
			"cell buckets come back from the packed form at the same coordinates",
			"got %f and %f" % [state.cell_score(0, Vector2i(1, 1)), state.cell_score(2, Vector2i(4, 0))])

	var copy := state.duplicate_state()
	state.bank_cell_score(0, Vector2i(1, 1), 1000)
	check(copy.cell_score(0, Vector2i(1, 1)) == 11.0,
			"a duplicated state's cell buckets do NOT follow the original",
			"copy now %f" % copy.cell_score(0, Vector2i(1, 1)))

# ==============================================================================
# TP-51 -- THE OWNER'S WORKED EXAMPLE, VERBATIM.
#
#   "row + col + diag = 0 + 0 + 0. Row gets 10 score. it is now 10 + 0 + 0 = 10. Col gets 5
#    score. It is now 10 * 5 + 0 = 50. Diag gets 2 score. It is now 10 * 5 * 2 = 100."
#
# The point of the example is that a term which has NOT scored ADDS 0 -- it never multiplies
# by 0. So the sequence 0, 10, 50, 100 is asserted step by step, not just the final 100: an
# implementation that multiplied by zero would give 0, 0, 0, 100 and still land on 100.
# ==============================================================================
func run_worked_example_test() -> void:
	behavior_section("THE WORKED EXAMPLE")
	var state := TestGridFixtures.build_fix_grid_1()
	state.resize_grid_bucket(state.score_special, 1)

	check(state.grid_score(0) == 0.0,
			"row + col + special = 0 + 0 + 0", "got %f" % state.grid_score(0))
	state.bank_line_score(state.scores_row, 0, 0, 0, 10)
	check(state.grid_score(0) == 10.0,
			"Row gets 10 score. it is now 10 + 0 + 0 = 10", "got %f" % state.grid_score(0))
	state.bank_line_score(state.scores_col, 0, 0, 0, 5)
	check(state.grid_score(0) == 50.0,
			"Col gets 5 score. It is now 10 * 5 + 0 = 50", "got %f" % state.grid_score(0))
	state.score_special[0].plus_equals(2)
	check(state.grid_score(0) == 100.0,
			"Diag gets 2 score. It is now 10 * 5 * 2 = 100", "got %f" % state.grid_score(0))

# ==============================================================================
# TP-52 -- a grid with rows scored and no diagonal pays its rows, NOT zero. The whole
# reason an unscored bucket adds rather than multiplies.
# ==============================================================================
func run_rows_without_diagonal_test() -> void:
	behavior_section("ROWS WITHOUT A DIAGONAL")
	var state := TestGridFixtures.build_fix_grid_1()
	state.bank_line_score(state.scores_row, 0, 0, 0, 40)
	check(state.grid_score(0) == 40.0,
			"a grid that scored only rows pays its rows, not zero",
			"got %f" % state.grid_score(0))
	state.resize_grid_bucket(state.score_special, 1)
	check(state.grid_score(0) == 40.0,
			"and the untouched col and special buckets existing changes nothing",
			"got %f" % state.grid_score(0))

# ==============================================================================
# TP-53 -- a grid with NO bucket scored contributes 0, not 1. An empty product must not
# fall out as the multiplicative identity.
# ==============================================================================
func run_empty_grid_scores_zero_test() -> void:
	behavior_section("EMPTY GRID SCORES ZERO")
	var state := TestGridFixtures.build_fix_grid_1()
	check(state.grid_score(0) == 0.0,
			"a grid with no buckets at all contributes 0, not 1",
			"got %f" % state.grid_score(0))
	state.resize_grid_bucket(state.score_special, 1)
	check(state.grid_score(0) == 0.0,
			"and a grid whose buckets all exist but read 0 still contributes 0",
			"got %f" % state.grid_score(0))

# ==============================================================================
# TP-54 -- A BUCKET WHOSE VALUE IS 0 IS EXCLUDED FROM THE PRODUCT, even when its line
# genuinely completed and scored 0. Owner: "if score is 0 do not multiply regardless of if
# 0 is somehow a returned actual score from something."
#
# ⚠ THE TEST IS THE VALUE, NEVER TOUCHED-NESS. This forces a line to complete and bank
# exactly 0, then asserts the grid still pays its other buckets. An implementation that
# tracked "has this bucket been written to" would multiply by that 0 and pay 0.
# ==============================================================================
func run_zero_valued_bucket_excluded_test() -> void:
	behavior_section("A ZERO-VALUED BUCKET IS EXCLUDED")
	var state := TestGridFixtures.build_fix_grid_1()
	state.resize_grid_bucket(state.score_special, 1)
	state.bank_line_score(state.scores_row, 0, 0, 0, 10)
	state.bank_line_score(state.scores_col, 0, 0, 0, 5)
	# The special bucket is WRITTEN TO, with a real banked score that happens to be 0.
	state.score_special[0].plus_equals(0)
	check(state.score_special[0].to_float() == 0.0,
			"the special bucket was genuinely banked into and its VALUE is 0",
			"got %f" % state.score_special[0].to_float())
	check(state.grid_score(0) == 50.0,
			"a bucket worth 0 is excluded from the product even though its line scored",
			"got %f, wanted 10 * 5" % state.grid_score(0))

# ==============================================================================
# TP-55 -- board_total is the sum of the grid scores. FIX-GRID-3.
# ==============================================================================
func run_board_total_is_the_sum_test() -> void:
	behavior_section("BOARD TOTAL IS THE SUM")
	var state := TestGridFixtures.build_fix_grid_3()
	state.bank_line_score(state.scores_row, 0, 0, 0, 10)
	state.bank_line_score(state.scores_col, 0, 0, 0, 2)      # grid 0 -> 20
	state.bank_line_score(state.scores_row, 2, 0, 0, 7)      # grid 2 -> 7 (col unscored, so it adds nothing)
	check(state.grid_score(0) == 20.0, "grid 0 scores 10 * 2", "got %f" % state.grid_score(0))
	check(state.grid_score(1) == 0.0, "grid 1 scored nothing", "got %f" % state.grid_score(1))
	check(state.grid_score(2) == 7.0, "grid 2 scores its row alone", "got %f" % state.grid_score(2))
	check(state.board_total() == 27.0,
			"board_total is the SUM of the grid scores, not their product",
			"got %f, wanted 20 + 0 + 7" % state.board_total())

# ==============================================================================
# The height scores fold into the SPECIAL term, and raised row/col scores fold into their
# own row/col terms -- storage stays granular for the labels, scoring aggregates.
# ==============================================================================
func run_terms_aggregate_their_levels_test() -> void:
	behavior_section("TERMS AGGREGATE THEIR LEVELS")
	var state := TestGridFixtures.build_fix_grid_1()
	state.resize_grid_bucket(state.score_special, 1)
	state.bank_line_score(state.scores_row, 0, 0, 0, 4)
	state.bank_line_score(state.scores_row, 0, 0, 2, 6)
	state.bank_line_score(state.scores_col, 0, 0, 0, 2)
	check(state.grid_score(0) == 20.0,
			"a raised row score adds into the ROW term, not a term of its own",
			"got %f, wanted (4 + 6) * 2" % state.grid_score(0))

	# A vertical stack folds into the SPECIAL term, alongside the diagonals.
	state.score_special[0].plus_equals(3)
	state.bank_cell_score(0, Vector2i(1, 1), 7)
	check(state.grid_score(0) == 200.0,
			"a cell's height score adds into the SPECIAL term, alongside the diagonal",
			"got %f, wanted (4 + 6) * 2 * (3 + 7)" % state.grid_score(0))
	# Still THREE factors, however many buckets fed them.
	state.bank_cell_score(0, Vector2i(2, 2), 10)
	check(state.grid_score(0) == 400.0,
			"a second stack adds to the same special term rather than multiplying again",
			"got %f, wanted (4 + 6) * 2 * (3 + 7 + 10)" % state.grid_score(0))

	# And a cell bucket in ANOTHER grid never leaks into this grid's special term.
	state.bank_cell_score(1, Vector2i(0, 0), 1000)
	check(state.grid_score(0) == 400.0,
			"another grid's cell bucket does not reach this grid's special term",
			"got %f" % state.grid_score(0))

# ==============================================================================
# TP-60 -- GREP GATE: every retired identifier has ZERO readers in code.
#
# Reads the source tree as TEXT, the way the score_line signature gate does, because a
# retired identifier leaves no compile error behind once its last reader is gone -- the
# only way to know it is really gone is to look.
#
# ⚠ CARD_CATALOG.csv is deliberately NOT scanned. It is a catalogue of design IDEAS, many
# of which describe cards that were never built, and the plan's own documentation phase
# handles it separately with the rule "mark impossible rows superseded, never delete".
# ==============================================================================
const RETIRED_IDENTIFIERS : Array[String] = [
	"MAX_SUBMITS", "submits_used", "game_submits",
	"score_additive", "duplicate_class_scale",
	"patience", "patience_max", "patience_track_uniques", "patience_reset_uniques_on_act",
]

func run_retired_identifiers_grep_gate() -> void:
	implementation_section("RETIRED IDENTIFIERS GREP GATE")
	var offenders : Array[String] = []
	var scanned := 0
	for path : String in _all_source_files("res://"):
		if path == SELF_PATH: continue
		var f := FileAccess.open(path, FileAccess.READ)
		if not f: continue
		scanned += 1
		var n := 0
		for raw : String in f.get_as_text().split("\n"):
			n += 1
			# The PROJECT is called poker-patience, so its own name is not a reader of the
			# retired patience feature. Remove it before looking for the identifiers.
			var line := raw.replace("poker-patience", "")
			for id : String in RETIRED_IDENTIFIERS:
				if line.contains(id):
					offenders.append("%s:%d: %s" % [path, n, raw.strip_edges()])
					break
	check(scanned > 50, "the gate actually scanned the source tree",
			"only %d files scanned" % scanned)
	check(offenders.is_empty(),
			"every retired identifier has zero readers left in code",
			"\n".join(offenders))

## Every .gd and .tscn under `root`, recursively. Test-only helper.
func _all_source_files(root: String) -> Array[String]:
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
			elif name.ends_with(".gd") or name.ends_with(".tscn"): out.append(full)
			name = dir.get_next()
		dir.list_dir_end()
	return out

# ==============================================================================
# TP-61 -- undo across a Submit-era save does not resurrect the act count.
#
# There is NO save migration, by owner ruling. An old save simply carries a property
# nothing reads. What must hold is that the property is genuinely GONE from the type -- a
# leftover declaration would let an old snapshot quietly repopulate it -- and that undo
# still rewinds the per-show state that REPLACED it.
# ==============================================================================
func run_no_resurrected_act_count_test() -> void:
	behavior_section("NO RESURRECTED ACT COUNT")
	var fresh := GameData.new()
	var names : Array[String] = []
	for prop : Dictionary in fresh.get_property_list():
		var pname : String = prop["name"]
		names.append(pname)
	check(not names.has("submits_used"),
			"GameData declares no submits_used for an old snapshot to repopulate")
	check(not names.has("patience"),
			"nor patience")
	check(names.has("show_ended"),
			"the per-show flag that replaced it IS declared, so undo has something to rewind")

	# And the replacement genuinely rewinds with the board, which is the property the act
	# count was kept on GameData for in the first place.
	var g := Game.new()
	CardEnvironment.CURRENT = g
	g.state = GameData.new()
	g.save_state()
	g.state.revision += 1
	g.save_state()
	g.end_show()
	check(g.state.show_ended, "precondition: the show is ended")
	g.undo()
	check(not g.state.show_ended,
			"undo rewinds the show back to live -- the flag travels with the snapshot")
	CardEnvironment.CURRENT = null
	g.free()

# ==============================================================================
# TP-129 -- scores made by REAL PLAY survive a save and reload with their values.
#
# WARNING: THE ROUND-TRIP TESTS ABOVE DO NOT COVER THIS, and the difference is where the bugs
# live. They call pack_scores()/unpack_scores() directly on values written by hand. The actual
# save path is to_saveable(), which packs and then CLEARS every runtime bucket -- so a bucket
# that packs correctly but is not on to_saveable's clear-and-restore list round-trips
# perfectly here and comes back empty in a real reload. This drives the buckets through
# scoring, then through the real path, and compares the SCORE, which is what the player sees.
# FIX-TRIPLE: cell (2,2) completes a row, a column and a diagonal at once, so all three
# per-grid buckets are non-empty and grid_score is a genuine three-term product.
# ==============================================================================
func run_played_scores_survive_the_save_path_test() -> void:
	behavior_section("PLAYED SCORES SURVIVE THE SAVE PATH")
	var g := detector_game(TestGridFixtures.build_fix_triple())
	var card := TestFactories.m_card(7, TestFactories.uc())
	await g.place_card_in_grid(card, BoardCoord.new(0, 2, 2, 0))

	var played := g.state.live_total()
	check(played > 0, "precondition: the placement scored", str(played))
	var digest := TestGridFixtures.board_digest(g.state)

	# The real path a quit takes: to_saveable() for the disk form, then duplicate_state() +
	# restore_runtime() to build the live state back out of it.
	var saved := g.state.to_saveable()
	var reloaded : GameData = saved.duplicate_state()
	reloaded.restore_runtime()

	check(reloaded.live_total() == played,
			"the reloaded board scores exactly what the played one did",
			"%d, wanted %d" % [reloaded.live_total(), played])
	check(TestGridFixtures.board_digest(reloaded) == digest,
			"...and every individual bucket came back, not just a total that happens to match",
			"reloaded:\n%s\n---- wanted:\n%s" % [
			TestGridFixtures.board_digest(reloaded), digest])
	free_game(g)

