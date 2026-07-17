extends TestSuite
# res://Tests/Map/test_persistence_fuzz.gd
# ==============================================================================
# PERSISTENCE FUZZ — chaos round-trip of the WHOLE save document through real disk
# I/O (RunManager.save_run -> ResourceSaver -> file -> ResourceLoader -> load_run).
# Each iteration builds a fully randomized RunState — random scalars, a random run
# deck (random pips, modifiers, statuses, stages, flip flags), random traveled edges,
# a random pending-action marker, and a random undo history of random GameData boards
# (random zones/columns/stacks + random BigNumber score arrays) — writes it, reads it
# back, and deep-diffs every persisted field. Anything the serializer drops shows up
# as a concrete mismatch. Any real run.tres is moved aside (backup_real_save) before the
# fuzz writes to disk and restored after, so it always runs full and never destroys a run.
# ==============================================================================

# CATEGORY MAP: all BEHAVIOR — "whatever the run contains, saving and loading loses
# nothing" is the player-facing persistence guarantee (the deep-diff is just the probe).

const ITERATIONS := 25

# Concrete modifier classes safe to instantiate with .new(); randomly attached to cards.
var _skills: Array[Callable] = [SkillExtraPoint.new, SkillHungryHippo.new, SkillEchoingTrigger.new]
var _types: Array[Callable] = [TypePaper.new, TypeHeavy.new, TypeStone.new]
var _stamps: Array[Callable] = [StampGlobal.new, StampDoubleTrigger.new, StampRevealing.new]

func suite_name() -> String:
	return "PERSISTENCE FUZZ"

func _ready() -> void:
	TestLog.line("============ PERSISTENCE FUZZ TEST PASS ============")
	behavior_section("SAVE DOCUMENT ROUND-TRIP FUZZ")
	# Always run full: move any real run.tres aside first, restore it at the end.
	backup_real_save()
	var real_run: RunState = RunManager.run
	var rng := RandomNumberGenerator.new()
	for iter in ITERATIONS:
		rng.seed = 0x5015A + iter * 2654435761
		_run_iteration(iter, rng)
	# Delete only the run doc we wrote — NOT via clear_save(), which also wipes the shared
	# map bake dir. Then restore any backed-up real run.tres.
	RunManager.run = null
	if FileAccess.file_exists(RunManagerClass.RUN_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RunManagerClass.RUN_PATH))
	restore_real_save()
	RunManager.run = real_run
	finish()

func _run_iteration(iter: int, rng: RandomNumberGenerator) -> void:
	var original := _rand_run_state(rng)
	RunManager.run = original
	RunManager.mark_deck_dirty()
	RunManager.save_run()
	if not FileAccess.file_exists(RunManagerClass.RUN_PATH):
		check(false, "fuzz iter %d wrote run.tres" % iter, "no file on disk")
		return
	var loaded := RunManager.load_run()
	var errs := _diff_run(original, loaded)
	check(errs.is_empty(), "fuzz iter %d round-trips the whole document" % iter,
			"\n    " + "\n    ".join(errs))
	# Teardown discipline (see test_leak_canary.gd): both documents are dropped here, and
	# their run decks carry CardData<->modifier RefCounted cycles Godot never collects.
	# History entries are already in saveable (unlinked) form on both sides.
	for deck: Array[CardData] in [original.card_datas, original.rule_datas,
			loaded.card_datas, loaded.rule_datas]:
		for card in deck:
			GameData.unlink_card_backrefs(card)

# =============================================================================
# RANDOM BUILDERS
# =============================================================================

func _rand_run_state(rng: RandomNumberGenerator) -> RunState:
	var rs := RunState.new()
	rs.world_seed = rng.randi_range(1, 2147483646)
	rs.current_node_id = rng.randi_range(-1, 200)
	rs.lap = rng.randi_range(0, 40)
	rs.fame = rng.randi_range(0, 1_000_000_000)
	rs.overscore_ratio_sum = rng.randf_range(0.0, 50.0)
	rs.pending_goal = rng.randi_range(0, 1_000_000)
	rs.pending_node_id = rng.randi_range(-1, 200)
	rs.game_submits = rng.randi_range(0, 3)
	rs.pending_action = [&"", &"on_run_scorer", &"on_next"][rng.randi_range(0, 2)]
	rs.card_datas = _rand_card_array(rng, rng.randi_range(0, 12), CardData.Stage.DRAW)
	rs.rule_datas = _rand_card_array(rng, rng.randi_range(0, 5), CardData.Stage.RULES)
	rs.traveled = []
	for i in rng.randi_range(0, 20):
		rs.traveled.append(Vector3i(rng.randi_range(0, 200), rng.randi_range(0, 200), rng.randi_range(0, 40)))
	# The undo history: several fully-random boards in saveable form (as Game stores them).
	rs.game_history = [] as Array[GameData]
	for i in rng.randi_range(0, 4):
		var live := _rand_game_data(rng)
		rs.game_history.append(live.to_saveable())
		live.unlink_modifier_backrefs()  # the live board is dropped here — break its cycles
	return rs

func _rand_card_array(rng: RandomNumberGenerator, n: int, stage: CardData.Stage) -> Array[CardData]:
	var out: Array[CardData] = []
	for i in n:
		out.append(_rand_card(rng, stage))
	return out

func _rand_card(rng: RandomNumberGenerator, stage: CardData.Stage) -> CardData:
	var c := CardData.new()
	c.with_rank(PipRankNumeral.new().with_value(rng.randi_range(1, 13)))
	c.with_suit(PipSuit.STANDARD[rng.randi_range(0, PipSuit.STANDARD.size() - 1)].new() as PipSuit)
	if rng.randf() < 0.6: c.with_skill(_skills[rng.randi_range(0, _skills.size() - 1)].call() as CardModifier)
	if rng.randf() < 0.5: c.with_type(_types[rng.randi_range(0, _types.size() - 1)].call() as CardModifier)
	if rng.randf() < 0.4: c.with_stamp(_stamps[rng.randi_range(0, _stamps.size() - 1)].call() as CardModifier)
	c.flipped = rng.randf() < 0.5
	# random statuses across the distinct test classes (merge-by-class means repeats fold)
	var status_scripts : Array[GDScript] = [StatusTestA, StatusTestB, StatusTestSeal]
	for s in rng.randi_range(0, 3):
		var script: GDScript = status_scripts[rng.randi_range(0, status_scripts.size() - 1)]
		c.add_status(CardModifierStatus.stacked(script, rng.randi_range(1, 100)))
	c.stage = stage
	# previous_stage is persisted independently — scramble it after the stage setter ran.
	c.previous_stage = rng.randi_range(0, CardData.Stage.size() - 1) as CardData.Stage
	return c

func _rand_game_data(rng: RandomNumberGenerator) -> GameData:
	var gs := GameData.new()
	gs.goal = rng.randi_range(1, 1_000_000_000)
	gs.total_score = rng.randi_range(0, 2_000_000_000)
	gs.mult_score = rng.randi_range(0, 1_000_000)
	gs.col_total = rng.randi_range(0, 100_000)
	gs.row_total = rng.randi_range(0, 100_000)
	gs.draw_deck = _rand_card_array(rng, rng.randi_range(0, 8), CardData.Stage.DRAW)
	gs.discard_deck = _rand_card_array(rng, rng.randi_range(0, 6), CardData.Stage.DISCARD)
	gs.rules_deck = _rand_card_array(rng, rng.randi_range(0, 4), CardData.Stage.RULES)
	var cols := rng.randi_range(0, 4)
	gs.upper_zone_type = _rand_card_array(rng, cols, CardData.Stage.ZONE)
	gs.lower_zone_type = _rand_card_array(rng, cols, CardData.Stage.ZONE)
	gs.upper_zone = _rand_zone(rng, cols)
	gs.lower_zone = _rand_zone(rng, cols)
	gs.scores_row_upper = _rand_bn_array(rng, rng.randi_range(0, 5))
	gs.scores_row_lower = _rand_bn_array(rng, rng.randi_range(0, 5))
	gs.scores_col = _rand_bn_array(rng, rng.randi_range(0, 5))
	return gs

func _rand_zone(rng: RandomNumberGenerator, cols: int) -> Array[ArrayCardData]:
	var zone: Array[ArrayCardData] = []
	for c in cols:
		var col := ArrayCardData.new()
		col.datas = _rand_card_array(rng, rng.randi_range(0, 4), CardData.Stage.PLAY)
		zone.append(col)
	return zone

func _rand_bn_array(rng: RandomNumberGenerator, n: int) -> Array[BigNumber]:
	var out: Array[BigNumber] = []
	for i in n:
		var bn := BigNumber.new()
		bn.mantissa = rng.randf_range(-9.999999, 9.999999)
		bn.exponent = rng.randi_range(-100_000, 100_000_000)
		out.append(bn)
	return out

# =============================================================================
# DEEP DIFF (returns human-readable mismatch strings; empty == identical)
# =============================================================================

func _diff_run(a: RunState, b: RunState) -> Array[String]:
	var e: Array[String] = []
	if a.world_seed != b.world_seed: e.append("world_seed %d != %d" % [a.world_seed, b.world_seed])
	if a.current_node_id != b.current_node_id: e.append("current_node_id")
	if a.lap != b.lap: e.append("lap")
	if a.fame != b.fame: e.append("fame %d != %d" % [a.fame, b.fame])
	if not is_equal_approx(a.overscore_ratio_sum, b.overscore_ratio_sum): e.append("overscore_ratio_sum")
	if a.pending_goal != b.pending_goal: e.append("pending_goal")
	if a.pending_node_id != b.pending_node_id: e.append("pending_node_id")
	if a.game_submits != b.game_submits: e.append("game_submits")
	if a.pending_action != b.pending_action: e.append("pending_action '%s' != '%s'" % [a.pending_action, b.pending_action])
	if a.traveled != b.traveled: e.append("traveled %s != %s" % [a.traveled, b.traveled])
	_diff_cards(e, "card_datas", a.card_datas, b.card_datas)
	_diff_cards(e, "rule_datas", a.rule_datas, b.rule_datas)
	# The relinked run deck must have its modifier backrefs restored to the owning card.
	for card in b.card_datas:
		for mod: CardModifier in [card.skill, card.type, card.stamp]:
			if mod and mod.data != card:
				e.append("card_datas backref not relinked on %s" % card)
	if a.game_history.size() != b.game_history.size():
		e.append("game_history size %d != %d" % [a.game_history.size(), b.game_history.size()])
	else:
		for i in a.game_history.size():
			_diff_game(e, "history[%d]" % i, a.game_history[i], b.game_history[i])
	return e

func _diff_game(e: Array[String], path: String, a: GameData, b: GameData) -> void:
	if a.goal != b.goal: e.append("%s.goal %d != %d" % [path, a.goal, b.goal])
	if a.total_score != b.total_score: e.append("%s.total_score %d != %d" % [path, a.total_score, b.total_score])
	if a.mult_score != b.mult_score: e.append("%s.mult_score" % path)
	if a.col_total != b.col_total: e.append("%s.col_total" % path)
	if a.row_total != b.row_total: e.append("%s.row_total" % path)
	_diff_cards(e, "%s.draw_deck" % path, a.draw_deck, b.draw_deck)
	_diff_cards(e, "%s.discard_deck" % path, a.discard_deck, b.discard_deck)
	_diff_cards(e, "%s.rules_deck" % path, a.rules_deck, b.rules_deck)
	_diff_cards(e, "%s.upper_zone_type" % path, a.upper_zone_type, b.upper_zone_type)
	_diff_cards(e, "%s.lower_zone_type" % path, a.lower_zone_type, b.lower_zone_type)
	_diff_zone(e, "%s.upper_zone" % path, a.upper_zone, b.upper_zone)
	_diff_zone(e, "%s.lower_zone" % path, a.lower_zone, b.lower_zone)
	# Scores persist as parallel packed arrays; compare those directly (saveable form).
	_diff_packed(e, "%s.col" % path, a.packed_col_mant, a.packed_col_exp, b.packed_col_mant, b.packed_col_exp)
	_diff_packed(e, "%s.row_upper" % path, a.packed_row_upper_mant, a.packed_row_upper_exp, b.packed_row_upper_mant, b.packed_row_upper_exp)
	_diff_packed(e, "%s.row_lower" % path, a.packed_row_lower_mant, a.packed_row_lower_exp, b.packed_row_lower_mant, b.packed_row_lower_exp)

func _diff_zone(e: Array[String], path: String, a: Array[ArrayCardData], b: Array[ArrayCardData]) -> void:
	if a.size() != b.size():
		e.append("%s columns %d != %d" % [path, a.size(), b.size()])
		return
	for c in a.size():
		if (a[c] == null) != (b[c] == null):
			e.append("%s col %d null mismatch" % [path, c])
			continue
		if a[c] == null: continue
		_diff_cards(e, "%s[%d]" % [path, c], a[c].datas, b[c].datas)

func _diff_cards(e: Array[String], path: String, a: Array[CardData], b: Array[CardData]) -> void:
	if a.size() != b.size():
		e.append("%s size %d != %d" % [path, a.size(), b.size()])
		return
	for i in a.size():
		var ca := a[i]
		var cb := b[i]
		if (ca == null) != (cb == null):
			e.append("%s[%d] null mismatch" % [path, i])
			continue
		if ca == null: continue
		# _to_string() folds suit, rank, skill, type, stamp, statuses (str+stacks), stage
		# AND previous_stage — so it already covers the status round-trip. Keep an explicit
		# size check as a cheap belt-and-braces on the Array[CardModifierStatus] field.
		if str(ca) != str(cb):
			e.append("%s[%d] '%s' != '%s'" % [path, i, ca, cb])
		if ca.flipped != cb.flipped:
			e.append("%s[%d].flipped %s != %s" % [path, i, ca.flipped, cb.flipped])
		if ca.statuses.size() != cb.statuses.size():
			e.append("%s[%d].statuses size %d != %d" % [path, i, ca.statuses.size(), cb.statuses.size()])

func _diff_packed(e: Array[String], path: String, am: PackedFloat64Array, ae: PackedInt64Array,
		bm: PackedFloat64Array, be: PackedInt64Array) -> void:
	if am.size() != bm.size() or ae.size() != be.size() or am.size() != ae.size():
		e.append("%s packed sizes m(%d/%d) e(%d/%d)" % [path, am.size(), bm.size(), ae.size(), be.size()])
		return
	for i in am.size():
		if not is_equal_approx(am[i], bm[i]) or ae[i] != be[i]:
			e.append("%s[%d] (%f,%d) != (%f,%d)" % [path, i, am[i], ae[i], bm[i], be[i]])
