extends SolatroTest
# res://Tests/Engine/test_act_score.gd
# ==============================================================================
# ACT SCORE (row_total x col_total per submit) — GameData.apply_act_score
# Non-freezing checks (prints [FAIL] and continues), same pattern as test_scoring.gd.
#
# CATEGORY MAP: all BEHAVIOR — how an act pays out, what resets between acts, what
# a submit discards, and what counts as winning are the core scoring rules.
# ==============================================================================

func suite_name() -> String:
	return "ACT SCORE"

func _ready() -> void:
	print("============ ACT SCORE TEST PASS ============")
	behavior_section("ACT PAYOUT & GOAL RULES")
	test_basic_multiply()
	test_zero_side_pays_nothing()
	test_totals_reset_between_acts()
	test_scores_cleared_between_acts()
	test_accumulates_across_acts()
	test_discard_lower_board()
	test_has_met_goal()
	finish()

func test_basic_multiply() -> void:
	var state := GameData.new()
	state.row_total = 10
	state.col_total = 5
	state.apply_act_score()
	check(state.mult_score == 50, "act pays row x col", "mult=%d" % state.mult_score)
	check(state.total_score == 50, "payout lands in total_score", "total=%d" % state.total_score)

func test_zero_side_pays_nothing() -> void:
	var state := GameData.new()
	state.row_total = 40
	state.col_total = 0
	state.apply_act_score()
	check(state.total_score == 0, "no scored columns -> act pays 0")
	state.row_total = 0
	state.col_total = 40
	state.apply_act_score()
	check(state.total_score == 0, "no scored rows -> act pays 0")

func test_totals_reset_between_acts() -> void:
	var state := GameData.new()
	state.row_total = 7
	state.col_total = 3
	state.apply_act_score()
	check(state.row_total == 0 and state.col_total == 0, "row/col totals reset after the act")

func test_accumulates_across_acts() -> void:
	var state := GameData.new()
	state.row_total = 2
	state.col_total = 3
	state.apply_act_score()
	state.row_total = 4
	state.col_total = 5
	state.apply_act_score()
	check(state.total_score == 2 * 3 + 4 * 5, "acts accumulate into total_score",
			"total=%d" % state.total_score)
	check(state.mult_score == 20, "mult_score shows the latest act's payout")

func test_scores_cleared_between_acts() -> void:
	# The per-row/col BigNumber gutters must reset each act, or the next act's plus_equals
	# stacks onto the previous act's values (the "old scores on top of new" double-count).
	var state := GameData.new()
	state.scores_col = _bn_array([12.0, 3.4])
	state.scores_row_lower = _bn_array([7.0])
	state.scores_row_upper = _bn_array([1.0, 2.0, 3.0])
	state.row_total = 5
	state.col_total = 5
	state.apply_act_score()
	check(state.scores_col.is_empty() and state.scores_row_lower.is_empty()
			and state.scores_row_upper.is_empty(),
			"apply_act_score clears the row/col score gutters",
			"col=%d rl=%d ru=%d" % [state.scores_col.size(),
					state.scores_row_lower.size(), state.scores_row_upper.size()])
	check(state.total_score == 25, "act still pays row x col before clearing", "total=%d" % state.total_score)

func _bn_array(mantissas: Array) -> Array[BigNumber]:
	var out: Array[BigNumber] = []
	for m: float in mantissas:
		var bn := BigNumber.new()
		bn.mantissa = m
		out.append(bn)
	return out

func _col(cards: Array[CardData]) -> ArrayCardData:
	var col := ArrayCardData.new()
	col.datas = cards
	return col

func test_discard_lower_board() -> void:
	var state := GameData.new()
	var lower := CardData.new()
	var upper := CardData.new()
	state.lower_zone = [_col([lower] as Array[CardData])]
	state.upper_zone = [_col([upper] as Array[CardData])]
	state.discard_lower_board()
	check(state.lower_zone[0].datas.is_empty(), "submit clears the lower (performed) board")
	check(state.discard_deck.has(lower), "performed cards go to the discard pile")
	check(lower.stage == CardData.Stage.DISCARD, "discarded cards get the DISCARD stage")
	check(state.upper_zone[0].datas == ([upper] as Array[CardData]),
			"the upper Entrance zone is NOT wiped")

func test_has_met_goal() -> void:
	var state := GameData.new()
	state.goal = 100
	state.total_score = 99
	check(not state.has_met_goal(), "below goal -> not met (loss)")
	state.total_score = 100
	check(state.has_met_goal(), "exactly at goal -> met (win)")
	state.total_score = 250
	check(state.has_met_goal(), "overscore -> met")
