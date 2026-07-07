extends Node
# res://Tests/Engine/test_act_score.gd
# ==============================================================================
# ACT SCORE (row_total x col_total per submit) — GameData.apply_act_score
# Non-freezing checks (prints [FAIL] and continues), same pattern as test_scoring.gd.
# ==============================================================================

var _pass := 0
var _fail := 0

func _ready() -> void:
	print("============ ACT SCORE TEST PASS ============")
	test_basic_multiply()
	test_zero_side_pays_nothing()
	test_totals_reset_between_acts()
	test_accumulates_across_acts()
	test_discard_lower_board()
	test_has_met_goal()
	print("act_score: %d passed, %d failed" % [_pass, _fail])

func check(ok: bool, ctx: String, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  [PASS] ", ctx)
	else:
		_fail += 1
		printerr("[FAIL] ", ctx, "" if detail.is_empty() else (" -- " + detail))

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
