extends TestSuite
# res://Tests/Engine/test_combo.gd
# ==============================================================================
# COMBO (SCORING_MATH_PLAN §15a) — class-key derivation, the act payout with the
# combo multiplier, snapshot/undo carriage of the combo set, and register_combo
# semantics (idempotence, empty-key opt-out, δ duplicate-class lever).
#
# CATEGORY MAP: all BEHAVIOR — what counts as a distinct combo class, how U pays
# out, and what undo restores are player-facing scoring rules.
# ==============================================================================

func suite_name() -> String:
	return "COMBO"

func _ready() -> void:
	TestLog.line("============ COMBO TEST PASS ============")
	behavior_section("CLASS KEY DERIVATION")
	test_class_key_table()
	behavior_section("ACT PAYOUT WITH COMBO")
	test_apply_act_score_combo()
	behavior_section("SNAPSHOT / UNDO CARRIAGE")
	test_snapshot_carries_combo()
	behavior_section("REGISTER + δ LEVER")
	await test_register_combo()
	finish()

## A Scoring.Result with the given structural types / sub-hand size / copy count.
## Meld cards are irrelevant to class_key — left empty.
func _result(types: Array[Scoring.MELD_TYPE], copy_size: int, copies: int,
		score: int = 10) -> Scoring.Result:
	var r := Scoring.Result.create("test", [] as Array[CardData], score, 0.0, types)
	r.copy_size = copy_size
	r.copies_count = copies
	return r

func _key(types: Array[Scoring.MELD_TYPE], copy_size: int, copies: int) -> String:
	return Scoring.class_key(_result(types, copy_size, copies))

func test_class_key_table() -> void:
	var xk : Array[Scoring.MELD_TYPE] = [Scoring.MELD_TYPE.X_OF_KIND]
	check(_key(xk, 2, 1) == "XKIND:2x1", "pair -> XKIND:2x1")
	check(_key(xk, 3, 1) == "XKIND:3x1", "trips -> XKIND:3x1")
	check(_key(xk, 4, 1) == "XKIND:4x1", "quad -> XKIND:4x1")
	check(_key([Scoring.MELD_TYPE.X_OF_KIND, Scoring.MELD_TYPE.MULTI], 4, 2) == "XKIND:4x2",
			"2x quad -> XKIND:4x2")
	var five := _key([Scoring.MELD_TYPE.X_OF_KIND, Scoring.MELD_TYPE.MULTI], 2, 5)
	var ten := _key([Scoring.MELD_TYPE.X_OF_KIND, Scoring.MELD_TYPE.MULTI], 2, 10)
	check(five == "XKIND:2x5" and ten == "XKIND:2x10" and five != ten
			and five != _key(xk, 2, 1),
			"copy count differentiates: 1x pair != 5x pair != 10x pair")
	var st : Array[Scoring.MELD_TYPE] = [Scoring.MELD_TYPE.STRAIGHT]
	check(_key(st, 5, 1) == "STRAIGHT:5x1" and _key(st, 6, 1) == "STRAIGHT:6x1"
			and _key(st, 5, 1) != _key(st, 6, 1),
			"sub-hand size differentiates: 5-straight != 6-straight")
	check(_key([Scoring.MELD_TYPE.STRAIGHT, Scoring.MELD_TYPE.FLUSH,
			Scoring.MELD_TYPE.ALL_SAME_SUIT], 5, 1) == "STRAIGHT:5x1:FF",
			"straight flush -> STRAIGHT:5x1:FF")
	check(_key([Scoring.MELD_TYPE.FULL_HOUSE, Scoring.MELD_TYPE.FLUSH,
			Scoring.MELD_TYPE.ALL_SAME_SUIT], 5, 1) == "HOUSE:5x1:FF",
			"flush house -> HOUSE:5x1:FF")
	check(_key([Scoring.MELD_TYPE.X_OF_KIND, Scoring.MELD_TYPE.MULTI,
			Scoring.MELD_TYPE.FLUSH], 3, 2) == "XKIND:3x2:MF",
			"suited multi-set -> XKIND:3x2:MF")
	check(_key([Scoring.MELD_TYPE.FLUSH, Scoring.MELD_TYPE.ALL_SAME_SUIT], 5, 1) == "FLUSH:5x1:FF",
			"pure flush keeps its own archetype")
	check(_key([Scoring.MELD_TYPE.HIGH_CARD], 1, 1) == "HIGH:1x1",
			"lone high card derives a key (excluded from U at the game layer, not here)")
	# Rank independence: class_key never reads the meld cards, so two pairs of different
	# ranks are the SAME class by construction.
	var pair_a := Scoring.Result.create("Pair", [CardData.new().with_rank(
			PipRankNumeral.new().with_value(2))] as Array[CardData], 2, 2.0, xk)
	pair_a.copy_size = 2
	var pair_b := Scoring.Result.create("Pair", [CardData.new().with_rank(
			PipRankNumeral.new().with_value(9))] as Array[CardData], 2, 9.0, xk)
	pair_b.copy_size = 2
	check(Scoring.class_key(pair_a) == Scoring.class_key(pair_b),
			"rank does not differentiate (pair of 2s == pair of 9s)")

func test_apply_act_score_combo() -> void:
	var state := GameData.new()
	state.row_total = 10
	state.col_total = 5
	state.combo_classes = ["a", "b", "c"] as Array[String]
	state.apply_act_score()
	check(state.mult_score == 65, "act pays int(R x C x (1 + 0.1U)): 50 x 1.3 = 65",
			"mult=%d" % state.mult_score)
	check(state.combo_classes.is_empty(), "combo set resets with the act payout")
	check(state.row_total == 0 and state.col_total == 0, "totals reset after the act")
	# Rounding happens ONCE on the whole product.
	state.row_total = 7
	state.col_total = 3
	state.combo_classes = ["a"] as Array[String]
	state.apply_act_score()
	check(state.mult_score == 23, "rounds once per act: int(21 x 1.1) = int(23.1) = 23",
			"mult=%d" % state.mult_score)
	# Empty set: exact legacy payout.
	state.row_total = 10
	state.col_total = 5
	state.apply_act_score()
	check(state.mult_score == 50, "empty combo set pays exactly row x col")
	# combo_step is a live settings knob (shared resource — restore after).
	var saved_step : float = SettingsManager.settings.combo_step
	SettingsManager.settings.combo_step = 0.2
	state.row_total = 10
	state.col_total = 5
	state.combo_classes = ["a", "b"] as Array[String]
	state.apply_act_score()
	check(state.mult_score == 70, "combo_step knob is live: 50 x (1 + 0.2x2) = 70",
			"mult=%d" % state.mult_score)
	SettingsManager.settings.combo_step = saved_step
	# score_additive TEST variant: payout = (R + C) x combo (ships off; restore after).
	var saved_additive : bool = SettingsManager.settings.score_additive
	SettingsManager.settings.score_additive = true
	state.row_total = 10
	state.col_total = 5
	state.combo_classes = ["a", "b"] as Array[String]
	state.apply_act_score()
	check(state.mult_score == 18, "additive variant pays int((R+C) x combo): 15 x 1.2 = 18",
			"mult=%d" % state.mult_score)
	state.row_total = 40
	state.col_total = 0
	state.apply_act_score()
	check(state.mult_score == 40, "additive variant: a one-sided act still pays (no x0 rule)")
	SettingsManager.settings.score_additive = saved_additive

func test_snapshot_carries_combo() -> void:
	var state := GameData.new()
	state.combo_classes = ["XKIND:2x1"] as Array[String]
	var copy := state.duplicate_state()
	check(copy.combo_classes == (["XKIND:2x1"] as Array[String]),
			"duplicate_state copies the combo set")
	state.combo_classes.append("STRAIGHT:5x1")
	check(copy.combo_classes.size() == 1,
			"the copy is independent (undo restores the pre-act set)")

func test_register_combo() -> void:
	var g := Game.new()
	CardEnvironment.CURRENT = g
	var emissions : Array[int] = []
	g.combo_changed.connect(func(count: int) -> void: emissions.append(count))
	check(g.register_combo("a"), "a new key registers (returns true)")
	check(not g.register_combo("a"), "a duplicate key is rejected (returns false)")
	check(not g.register_combo(""), "an empty key never registers (engine mod opt-out)")
	check(g.state.combo_classes == (["a"] as Array[String]) and emissions == ([1] as Array[int]),
			"U holds one class and combo_changed fired once", "emissions=%s" % str(emissions))
	# δ lever: with duplicate_class_scale < 1, a SECOND meld of an already-seen class banks
	# a scaled score; the first always pays full. Shared settings resource — restore after.
	var saved_delta : float = SettingsManager.settings.duplicate_class_scale
	SettingsManager.settings.duplicate_class_scale = 0.5
	var pair := _result([Scoring.MELD_TYPE.X_OF_KIND] as Array[Scoring.MELD_TYPE], 2, 1, 10)
	await g.score_line(pair, true, g.state.upper_zone, 0)
	check(g.state.row_total == 10, "first meld of a class banks its full score",
			"row_total=%d" % g.state.row_total)
	await g.score_line(pair, true, g.state.upper_zone, 1)
	check(g.state.row_total == 15, "duplicate-class meld banks int(score x 0.5)",
			"row_total=%d" % g.state.row_total)
	check(g.state.combo_classes.size() == 2, "the pair class joined U exactly once")
	# High cards never enter U (and never δ-scale).
	var high := _result([Scoring.MELD_TYPE.HIGH_CARD] as Array[Scoring.MELD_TYPE], 1, 1, 1)
	await g.score_line(high, true, g.state.upper_zone, 2)
	await g.score_line(high, true, g.state.upper_zone, 3)
	check(g.state.combo_classes.size() == 2, "lone high cards never enter U")
	check(g.state.row_total == 17, "high cards bank full score (no δ)",
			"row_total=%d" % g.state.row_total)
	SettingsManager.settings.duplicate_class_scale = saved_delta
	CardEnvironment.CURRENT = null
	g.free()
