extends TestSuite
# res://Tests/Map/test_run_manager.gd
# ==============================================================================
# RUN MANAGER — fame/luck/goal formulas + RunState + (guarded) disk round-trip.
# Formula tests run against a scratch RunState swapped into the RunManager autoload
# (the real run is restored afterwards). Disk tests always run full: any real run.tres is
# moved aside (backup_real_save) before the disk section and restored after, so the tests
# never depend on — nor destroy — an actual run.
#
# CATEGORY MAP:
#   BEHAVIOR — progression rules (lap direction, luck curve, goal scaling, overscore
#     inflation, fame from wins) and the save/resume guarantees.
#   IMPLEMENTATION — the packed-array score storage format; deep-copy/backref pins
#     inside the disk tests (check_impl inline).
# ==============================================================================

func suite_name() -> String:
	return "RUN MANAGER"

func _ready() -> void:
	TestLog.line("============ RUN MANAGER TEST PASS ============")
	var real_run: RunState = RunManager.run
	behavior_section("PROGRESSION FORMULAS")
	test_is_reversed()
	test_luck_curve()
	test_goal_scaling()
	test_overscore_inflation()
	test_record_win()
	implementation_section("SCORE PACKING FORMAT")
	test_scores_packing()
	behavior_section("SAVE / RESUME ON DISK")
	backup_real_save()   # move any real run.tres aside so disk tests run full, then restore
	test_disk_round_trip()
	test_game_state_round_trip()
	restore_real_save()
	RunManager.run = real_run
	finish()

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

# GameData score packing: the BigNumber score arrays flatten to PARALLEL typed packed
# arrays (mantissa float + exponent int), not an Array[Array] of pairs. Pure in-memory —
# never touches disk, so it always runs. Guards the perf-motivated storage format and the
# copy-on-write assign-back (packing must actually populate the fields).
func test_scores_packing() -> void:
	var gs := GameData.new()
	gs.scores_col = _big_numbers([[4.2, 3], [1.5, 9], [7.0, 0]])
	gs.scores_row_upper = _big_numbers([[2.5, 1]])
	gs.scores_row_lower = []
	gs.pack_scores()
	check(gs.packed_col_mant is PackedFloat64Array and gs.packed_col_exp is PackedInt64Array,
			"scores pack into typed packed arrays, not Array[Array]")
	check(gs.packed_col_mant.size() == 3 and gs.packed_col_exp.size() == 3,
			"packing populates the fields (copy-on-write assign-back)", "size=%d" % gs.packed_col_mant.size())
	check(is_equal_approx(gs.packed_col_mant[1], 1.5) and gs.packed_col_exp[1] == 9,
			"mantissa/exponent columns stay aligned")
	check(gs.packed_row_upper_mant.size() == 1 and gs.packed_row_lower_mant.is_empty(),
			"each score array packs independently (incl. empty ones)")
	# Round-trip back to runtime BigNumbers.
	gs.scores_col = []
	gs.scores_row_upper = []
	gs.unpack_scores()
	check(gs.scores_col.size() == 3 \
			and is_equal_approx(gs.scores_col[2].mantissa, 7.0) and gs.scores_col[2].exponent == 0,
			"unpack rebuilds the BigNumber arrays exactly")
	check(gs.scores_row_upper.size() == 1 and gs.scores_row_lower.is_empty(),
			"unpack restores each array independently")

func _big_numbers(pairs: Array) -> Array[BigNumber]:
	var out: Array[BigNumber] = []
	for p: Array in pairs:
		var bn := BigNumber.new()
		bn.mantissa = p[0]
		bn.exponent = p[1]
		out.append(bn)
	return out

func test_disk_round_trip() -> void:
	# REAL cards, not bare ones: modifiers carry a cyclic data backref that broke
	# ResourceSaver ("Resource was not pre cached") until RunManager unlinked it around
	# the write — always test with the full card graph.
	var cards: Array[CardData] = [
		CardData.new().with_rank(PipRankNumeral.new().with_value(3)) \
				.with_suit(PipSuitHoop.new()) \
				.with_skill(SkillExtraPoint.new()).with_type(TypePaper.new()) \
				.with_stamp(StampGlobal.new()),
	]
	var rules: Array[CardData] = TestDecks.standard_rules()
	var run := RunManager.new_run(cards, rules)
	check(run.world_seed != 0, "new_run pins a non-zero world seed")
	check_impl(run.card_datas.size() == 1 and run.card_datas[0] != cards[0],
			"new_run deep-copies the picked deck")
	check(FileAccess.file_exists(RunManagerClass.RUN_PATH), "new_run writes run.tres")
	# has_save gates on run.tres ALONE: the map bake is a regenerable cache of world_seed
	# (WorldMapController.start_run rebakes it when missing), so a run with no bake yet still
	# resumes.
	check(RunManager.has_save(), "has_save is true from the run doc alone (map bake is a cache)")
	check_impl(run.card_datas[0].skill.data == run.card_datas[0],
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
	check_impl(loaded.card_datas[0].skill.data == loaded.card_datas[0],
			"modifier backrefs are relinked after loading")
	check(loaded.rule_datas.size() == rules.size(), "rules deck survives the round trip")
	RunManager.clear_save()
	check(not FileAccess.file_exists(RunManagerClass.RUN_PATH), "clear_save deletes the run doc")
	check(RunManager.run == null, "clear_save drops the in-memory run")

# The in-progress show's FULL undo history (played boards + BigNumber scores) must survive
# a quit/resume exactly — mid-game persistence + anti-cheat (every action saved).
func test_game_state_round_trip() -> void:
	var run := RunManager.new_run([] as Array[CardData], [] as Array[CardData])
	# Build two runtime states (an undo stack of depth 2) and store them saveable.
	run.game_history = [_show_state(100), _show_state(123)] as Array[GameData]
	run.game_submits = 2
	# A Submit was mid-scoring when saved — the marker must survive so resume replays it.
	run.pending_action = &"on_run_scorer"
	RunManager.save_run()
	# Directly guards the temp-file-extension bug: a save that failed to write left no
	# run.tres on disk (so Continue was disabled). The full state MUST be on disk here.
	check(FileAccess.file_exists(RunManagerClass.RUN_PATH),
			"save_run actually writes run.tres to disk (temp file keeps a .tres extension)")

	var loaded := RunManager.load_run()
	check(loaded.game_history.size() == 2 and loaded.game_submits == 2,
			"full undo history + act count persist")
	check(loaded.pending_action == &"on_run_scorer",
			"pending-action marker persists (quit mid-scoring replays the Submit on resume)")
	var top : GameData = loaded.game_history[-1]
	# History snapshots are stored in saveable form — rebuild runtime to verify.
	top = top.duplicate_state()
	top.restore_runtime()
	check(top.goal == 500 and top.total_score == 123, "game state scalars round-trip")
	var lp: CardData = top.lower_zone[0].datas[0]
	check(lp.skill is SkillExtraPoint and lp.skill.data == lp,
			"board cards + relinked modifier backrefs survive")
	check(top.scores_col.size() == 1 \
			and is_equal_approx(top.scores_col[0].mantissa, 4.2) \
			and top.scores_col[0].exponent == 3,
			"BigNumber scores round-trip via the flattened snapshot")
	RunManager.clear_save()

# A runtime GameData with a played, modifier-carrying card and a BigNumber score, returned
# in saveable form (as Game pushes to history).
func _show_state(total: int) -> GameData:
	var gs := GameData.new()
	gs.goal = 500
	gs.total_score = total
	var played := CardData.new().with_rank(PipRankNumeral.new().with_value(7)) \
			.with_suit(PipSuitBall.new()).with_skill(SkillExtraPoint.new())
	played.stage = CardData.Stage.PLAY
	var col := ArrayCardData.new()
	col.datas = [played] as Array[CardData]
	gs.lower_zone = [col] as Array[ArrayCardData]
	var bn := BigNumber.new()
	bn.mantissa = 4.2
	bn.exponent = 3
	gs.scores_col = [bn] as Array[BigNumber]
	return gs.to_saveable()
