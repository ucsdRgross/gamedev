extends Node
# res://Tests/Map/test_run_manager.gd
# ==============================================================================
# RUN MANAGER — fame/luck/goal formulas + RunState + (guarded) disk round-trip.
# Formula tests run against a scratch RunState swapped into the RunManager autoload
# (the real run is restored afterwards). Disk tests are SKIPPED whenever a real save
# exists at user://run_save/ so running tests can never destroy an actual run.
# ==============================================================================

var _pass := 0
var _fail := 0

func _ready() -> void:
	print("============ RUN MANAGER TEST PASS ============")
	var real_run: RunState = RunManager.run
	test_is_reversed()
	test_luck_curve()
	test_goal_scaling()
	test_overscore_inflation()
	test_record_win()
	test_disk_round_trip()
	test_game_state_round_trip()
	RunManager.run = real_run
	print("run_manager: %d passed, %d failed" % [_pass, _fail])

func check(ok: bool, ctx: String, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  [PASS] ", ctx)
	else:
		_fail += 1
		printerr("[FAIL] ", ctx, "" if detail.is_empty() else (" -- " + detail))

func _fresh_run() -> RunState:
	var run := RunState.new()
	RunManager.run = run
	return run

func test_is_reversed() -> void:
	var run := RunState.new()
	check(not run.is_reversed(), "lap 0 runs forward")
	run.lap = 1
	check(run.is_reversed(), "lap 1 runs reversed")
	run.lap = 2
	check(not run.is_reversed(), "lap 2 runs forward again")

func test_luck_curve() -> void:
	var run := _fresh_run()
	check(RunManager.luck() == 0.0, "no fame -> no luck")
	run.fame = int(RunManagerClass.FAME_HALF)
	check(absf(RunManager.luck() - RunManagerClass.LUCK_CAP / 2.0) < 0.001,
			"luck is half the cap at FAME_HALF", "luck=%f" % RunManager.luck())
	var mid := RunManager.luck()
	run.fame = 100_000_000
	check(RunManager.luck() < RunManagerClass.LUCK_CAP, "luck never reaches the cap")
	check(RunManager.luck() > mid, "luck grows monotonically with fame")

func test_goal_scaling() -> void:
	var _run := _fresh_run()
	var g0 := RunManager.goal_for(0, 0, false)
	check(g0 == RunManagerClass.BASE_GOAL, "lap 0 origin-adjacent goal = BASE_GOAL", "g=%d" % g0)
	check(RunManager.goal_for(5, 0, false) > RunManager.goal_for(2, 0, false),
			"goal grows with progress along the lap")
	check(RunManager.goal_for(3, 1, false) > RunManager.goal_for(3, 0, false),
			"goal grows with the lap counter (endless scaling)")
	check(RunManager.goal_for(3, 0, true) == int(RunManager.goal_for(3, 0, false) * RunManagerClass.BOSS_MULT)
			or RunManager.goal_for(3, 0, true) > RunManager.goal_for(3, 0, false),
			"boss goal exceeds the normal goal at the same spot")
	check(RunManager.goal_for(20, 1000, true) > 0, "extreme laps stay positive (overflow cap)")

func test_overscore_inflation() -> void:
	var run := _fresh_run()
	var base := RunManager.goal_for(4, 0, false)
	RunManager.record_win(200, 100)  # overscore ratio 1.0
	var once := RunManager.goal_for(4, 0, false)
	check(once > base, "overscoring inflates future goals", "%d -> %d" % [base, once])
	RunManager.record_win(200, 100)  # ratio sum 2.0
	var twice := RunManager.goal_for(4, 0, false)
	check(twice - once > once - base,
			"inflation is nonlinear (accelerating)", "%d, %d, %d" % [base, once, twice])
	run.overscore_ratio_sum = 0.0
	RunManager.record_win(80, 100)  # under goal never happens in play, but must not deflate
	check(RunManager.goal_for(4, 0, false) == base, "no overscore -> no inflation")

func test_record_win() -> void:
	var run := _fresh_run()
	RunManager.record_win(150, 100)
	check(run.fame == 150, "fame gains the FULL score including overscore", "fame=%d" % run.fame)
	check(absf(run.overscore_ratio_sum - 0.5) < 0.001,
			"overscore ratio tracks overscore/goal", "sum=%f" % run.overscore_ratio_sum)

func test_disk_round_trip() -> void:
	if FileAccess.file_exists(RunManagerClass.RUN_PATH):
		print("  [SKIP] disk round-trip: a real run save exists; not touching it")
		return
	# REAL cards, not bare ones: modifiers carry a cyclic data backref that broke
	# ResourceSaver ("Resource was not pre cached") until RunManager unlinked it around
	# the write — always test with the full card graph.
	var cards: Array[CardData] = [
		CardData.new().with_rank(PipRankNumeral.new().with_value(3)) \
				.with_suit(PipSuitStandard.new().with_value(1)) \
				.with_skill(SkillExtraPoint.new()).with_type(TypePaper.new()) \
				.with_stamp(StampGlobal.new()),
	]
	var rules: Array[CardData] = Deck.new().get_rules()
	var run := RunManager.new_run(cards, rules)
	check(run.world_seed != 0, "new_run pins a non-zero world seed")
	check(run.card_datas.size() == 1 and run.card_datas[0] != cards[0],
			"new_run deep-copies the picked deck")
	check(FileAccess.file_exists(RunManagerClass.RUN_PATH), "new_run writes run.tres")
	check(not RunManager.has_save(), "has_save also requires the map bake")
	check(run.card_datas[0].skill.data == run.card_datas[0],
			"modifier backrefs are relinked after saving")
	run.fame = 777
	run.traveled.append(Vector3i(1, 2, 0))
	# Resume markers: a show is in progress on node 4.
	run.pending_node_id = 4
	run.pending_goal = 350
	RunManager.save_run()
	var loaded := RunManager.load_run()
	check(loaded.fame == 777 and loaded.traveled == run.traveled \
			and loaded.world_seed == run.world_seed,
			"save/load round-trips the run document")
	check(loaded.pending_node_id == 4 and loaded.pending_goal == 350,
			"pending show markers persist (quit mid-game resumes into that show)")
	check(loaded.card_datas[0].skill is SkillExtraPoint \
			and loaded.card_datas[0].stamp is StampGlobal \
			and loaded.card_datas[0].type is TypePaper,
			"modifiers survive the round trip")
	check(loaded.card_datas[0].skill.data == loaded.card_datas[0],
			"modifier backrefs are relinked after loading")
	check(loaded.rule_datas.size() == rules.size(), "rules deck survives the round trip")
	RunManager.clear_save()
	check(not FileAccess.file_exists(RunManagerClass.RUN_PATH), "clear_save deletes the run doc")
	check(RunManager.run == null, "clear_save drops the in-memory run")

# An in-progress show (GameData with a played board + BigNumber scores) must survive a
# quit/resume exactly — the whole point of mid-game persistence.
func test_game_state_round_trip() -> void:
	if FileAccess.file_exists(RunManagerClass.RUN_PATH):
		print("  [SKIP] game_state round-trip: a real run save exists; not touching it")
		return
	var run := RunManager.new_run([] as Array[CardData], [] as Array[CardData])
	var gs := GameData.new()
	gs.goal = 500
	gs.total_score = 123
	# A card on the board (lower zone) carrying a modifier (cyclic backref path).
	var played := CardData.new().with_rank(PipRankNumeral.new().with_value(7)) \
			.with_suit(PipSuitStandard.new().with_value(3)).with_skill(SkillExtraPoint.new())
	played.stage = CardData.Stage.PLAY
	var col := ArrayCardData.new()
	col.datas = [played] as Array[CardData]
	gs.lower_zone = [col] as Array[ArrayCardData]
	# A BigNumber score (RefCounted — the part ResourceSaver can't write directly).
	var bn := BigNumber.new()
	bn.mantissa = 4.2
	bn.exponent = 3
	gs.scores_col = [bn] as Array[BigNumber]
	run.game_state = gs
	run.game_submits = 2
	RunManager.save_run()

	var loaded := RunManager.load_run()
	check(loaded.game_state != null and loaded.game_submits == 2,
			"in-progress show + act count persist")
	check(loaded.game_state.goal == 500 and loaded.game_state.total_score == 123,
			"game state scalars round-trip")
	var lp: CardData = loaded.game_state.lower_zone[0].datas[0]
	check(lp.skill is SkillExtraPoint and lp.skill.data == lp,
			"board cards + relinked modifier backrefs survive")
	check(loaded.game_state.scores_col.size() == 1 \
			and is_equal_approx(loaded.game_state.scores_col[0].mantissa, 4.2) \
			and loaded.game_state.scores_col[0].exponent == 3,
			"BigNumber scores round-trip via the flattened snapshot")
	RunManager.clear_save()
