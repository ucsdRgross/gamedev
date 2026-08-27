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
	run_registration_gate()
	run_buckets_are_independent_test()
	await run_diagonals_share_one_special_bucket_test()
	run_pack_unpack_round_trip_test()
	run_duplicate_state_copies_by_hand_test()
	finish()

# ==============================================================================
# REGISTRATION GATE: every `func run_*` this file defines must actually be CALLED from
# _ready. Six planned tests once shipped defined-but-never-invoked while the banner read
# ALL CHECKS PASSED, which is indistinguishable from them passing.
# ==============================================================================
func run_registration_gate() -> void:
	implementation_section("REGISTRATION GATE")
	var f := FileAccess.open(SELF_PATH, FileAccess.READ)
	check(f != null, "the gate can read its own source", SELF_PATH)
	if not f: return
	var lines := f.get_as_text().split("\n")
	var ready_body := ""
	var in_ready := false
	for raw : String in lines:
		if raw.begins_with("func _ready("):
			in_ready = true
			continue
		if in_ready:
			if raw.begins_with("func "): break
			ready_body += raw + "\n"
	var defined : Array[String] = []
	for raw : String in lines:
		if not raw.begins_with("func run_"): continue
		defined.append(raw.substr(5, raw.find("(") - 5))
	var unregistered : Array[String] = []
	for name : String in defined:
		if name == "run_registration_gate": continue
		if not ready_body.contains(name + "()"): unregistered.append(name)
	check(defined.size() >= 4, "the gate actually found this suite's tests",
			"only found %d" % defined.size())
	check(unregistered.is_empty(),
			"every run_* test defined in this file is called from _ready",
			"never called: %s" % ", ".join(unregistered))

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
func bucket_value(bucket: Array[BigNumber], i: int) -> float:
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
	state.resize_grid_bucket(state.scores_row, 3)
	state.resize_grid_bucket(state.scores_col, 3)
	state.resize_grid_bucket(state.score_special, 3)

	state.scores_row[1].plus_equals(10)
	check(bucket_value(state.scores_row, 1) == 10.0,
			"a grid's row bucket takes the score written to it",
			"got %f" % bucket_value(state.scores_row, 1))
	check(bucket_value(state.scores_row, 0) == 0.0 and bucket_value(state.scores_row, 2) == 0.0,
			"writing grid 1's row bucket leaves the OTHER grids' row buckets alone",
			"grid0 %f grid2 %f" % [bucket_value(state.scores_row, 0), bucket_value(state.scores_row, 2)])
	check(bucket_value(state.scores_col, 1) == 0.0 and bucket_value(state.score_special, 1) == 0.0,
			"and leaves the SAME grid's col and special buckets alone",
			"col %f special %f" % [bucket_value(state.scores_col, 1), bucket_value(state.score_special, 1)])

	state.scores_col[1].plus_equals(5)
	state.score_special[1].plus_equals(2)
	check(bucket_value(state.scores_row, 1) == 10.0,
			"writing col and special does not disturb the row bucket already written",
			"got %f" % bucket_value(state.scores_row, 1))
	check(bucket_value(state.scores_col, 1) == 5.0 and bucket_value(state.score_special, 1) == 2.0,
			"all three buckets hold their own value at once",
			"col %f special %f" % [bucket_value(state.scores_col, 1), bucket_value(state.score_special, 1)])

	# Raised levels are a separate bucket again, per grid and per height.
	state.resize_grid_levels(state.scores_row_h, 3, 3)
	(state.scores_row_h[1][2] as BigNumber).plus_equals(7)
	check((state.scores_row_h[1][2] as BigNumber).to_float() == 7.0,
			"a raised row bucket takes its own score")
	check(bucket_value(state.scores_row, 1) == 10.0,
			"a raised row bucket is NOT the height-0 row bucket",
			"height-0 row now %f" % bucket_value(state.scores_row, 1))
	check((state.scores_row_h[0][2] as BigNumber).to_float() == 0.0
			and (state.scores_row_h[1][1] as BigNumber).to_float() == 0.0,
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
	var special := bucket_value(state.score_special, 0)
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
	state.resize_grid_bucket(state.scores_row, 3)
	state.resize_grid_bucket(state.scores_col, 3)
	state.resize_grid_bucket(state.score_special, 3)
	state.scores_row[0].plus_equals(11)
	state.scores_row[2].plus_equals(33)
	state.scores_col[1].plus_equals(22)
	state.score_special[2].plus_equals(44)
	# Deliberately RAGGED: grid 0 has three levels, grid 1 has two, grid 2 has none. A
	# flattening that loses the per-grid lengths cannot rebuild this.
	state.resize_grid_levels(state.scores_row_h, 3, 3)
	(state.scores_row_h[0][1] as BigNumber).plus_equals(55)
	(state.scores_row_h[1][2] as BigNumber).plus_equals(66)

	state.pack_scores()
	# Wipe the runtime side entirely, so unpack has to rebuild from the packed arrays alone.
	state.scores_row = []
	state.scores_col = []
	state.score_special = []
	state.scores_row_h = []
	state.scores_col_h = []
	state.unpack_scores()

	check(bucket_value(state.scores_row, 0) == 11.0 and bucket_value(state.scores_row, 2) == 33.0,
			"flat row buckets survive the round trip with their values",
			"got %f and %f" % [bucket_value(state.scores_row, 0), bucket_value(state.scores_row, 2)])
	check(bucket_value(state.scores_col, 1) == 22.0, "flat col buckets survive",
			"got %f" % bucket_value(state.scores_col, 1))
	check(bucket_value(state.score_special, 2) == 44.0, "the special bucket survives",
			"got %f" % bucket_value(state.score_special, 2))
	check(state.scores_row_h.size() == 3,
			"the raised array comes back with one entry per grid",
			"got %d" % state.scores_row_h.size())
	check((state.scores_row_h[0][1] as BigNumber).to_float() == 55.0
			and (state.scores_row_h[1][2] as BigNumber).to_float() == 66.0,
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
	state.resize_grid_bucket(state.scores_row, 3)
	state.resize_grid_bucket(state.scores_col, 3)
	state.resize_grid_bucket(state.score_special, 3)
	state.resize_grid_levels(state.scores_row_h, 3, 2)
	state.resize_grid_levels(state.scores_col_h, 3, 2)
	state.scores_row[0].plus_equals(10)
	state.scores_col[0].plus_equals(20)
	state.score_special[0].plus_equals(30)
	(state.scores_row_h[0][1] as BigNumber).plus_equals(40)
	(state.scores_col_h[0][1] as BigNumber).plus_equals(50)

	var copy := state.duplicate_state()
	check(bucket_value(copy.scores_row, 0) == 10.0,
			"the copy starts with the original's values",
			"got %f" % bucket_value(copy.scores_row, 0))

	# THE REAL CHECK: move the original and confirm the copy stayed put.
	state.scores_row[0].plus_equals(1000)
	state.scores_col[0].plus_equals(1000)
	state.score_special[0].plus_equals(1000)
	(state.scores_row_h[0][1] as BigNumber).plus_equals(1000)
	(state.scores_col_h[0][1] as BigNumber).plus_equals(1000)

	check(bucket_value(copy.scores_row, 0) == 10.0,
			"the copy's row bucket did NOT follow the original -- it is a real copy",
			"copy now %f" % bucket_value(copy.scores_row, 0))
	check(bucket_value(copy.scores_col, 0) == 20.0,
			"nor the col bucket", "copy now %f" % bucket_value(copy.scores_col, 0))
	check(bucket_value(copy.score_special, 0) == 30.0,
			"nor the special bucket", "copy now %f" % bucket_value(copy.score_special, 0))
	check((copy.scores_row_h[0][1] as BigNumber).to_float() == 40.0,
			"nor the raised row bucket -- the 2-D container is copied level by level",
			"copy now %f" % (copy.scores_row_h[0][1] as BigNumber).to_float())
	check((copy.scores_col_h[0][1] as BigNumber).to_float() == 50.0,
			"nor the raised col bucket",
			"copy now %f" % (copy.scores_col_h[0][1] as BigNumber).to_float())
