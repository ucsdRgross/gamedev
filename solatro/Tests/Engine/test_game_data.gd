extends SolatroTest
# res://Tests/Engine/test_game_data.gd
# ==============================================================================
# GameData as the source of truth (Plan 2 §6.1). Non-freezing checks (print
# [PASS]/[FAIL] and continue), same pattern as test_act_score.gd.
# Deliberately exercises EDGE cases layered on top of defaults (packed round-trip
# with non-trivial exponents, injected invariant violations, deep-copy aliasing)
# so a future regression in the data layer trips a specific check.
#
# CATEGORY MAP: all IMPLEMENTATION — saveable-form internals (backref unlinking,
# packed score arrays, deep-copy aliasing, validate() plumbing). The player-facing
# guarantee these support ("a save restores the run exactly") is covered as
# BEHAVIOR in test_run_manager / test_persistence_fuzz / the E2E suite.
# ==============================================================================

func suite_name() -> String:
	return "GAME DATA"

func _ready() -> void:
	print("============ GAME DATA TEST PASS ============")
	implementation_section("SAVEABLE FORM / COPY / VALIDATE INTERNALS")
	test_saveable_roundtrip_preserves_gutters()
	test_saveable_unlinks_backrefs_restore_relinks()
	test_duplicate_state_aliasing()
	test_validate_clean_board()
	test_validate_reports_injected_violations()
	test_pack_unpack_edge_values()
	finish()

func _bn(m: float, e: int) -> BigNumber:
	var bn := BigNumber.new()
	bn.mantissa = m
	bn.exponent = e
	return bn

# A small but non-degenerate board: 2 paired columns per zone, a card carrying a modifier
# (so backref relinking has something to prove), and gutters with non-zero exponents.
func make_state() -> GameData:
	var s := GameData.new()
	# attach a real modifier so mod.data backref round-trips (SkillPlacerOgLower has no state)
	var modded := CardData.new().with_skill(SkillPlacerOgLower.new())
	modded.stage = CardData.Stage.PLAY
	var plain := TestFactories.m_card(5, TestFactories.uc())
	plain.stage = CardData.Stage.PLAY
	var up_h := TestFactories.m_card(1, TestFactories.uc()); up_h.stage = CardData.Stage.ZONE
	var lo_h := TestFactories.m_card(2, TestFactories.uc()); lo_h.stage = CardData.Stage.ZONE
	s.upper_zone_type = [up_h] as Array[CardData]
	s.upper_zone = [TestFactories.col([plain] as Array[CardData])]
	s.lower_zone_type = [lo_h] as Array[CardData]
	s.lower_zone = [TestFactories.col([modded] as Array[CardData])]
	s.scores_row_upper = [_bn(4.2, 3)] as Array[BigNumber]
	s.scores_row_lower = [_bn(1.0, 0), _bn(9.99, 7)] as Array[BigNumber]
	s.scores_col = [_bn(2.5, 12)] as Array[BigNumber]
	s.goal = 314
	s.total_score = 271
	return s

func test_saveable_roundtrip_preserves_gutters() -> void:
	var s := make_state()
	var saveable := s.to_saveable()
	# saveable form drops the RefCounted BigNumber arrays and keeps only packed primitives
	check(saveable.scores_col.is_empty() and saveable.scores_row_lower.is_empty(),
			"to_saveable() clears the runtime BigNumber arrays")
	check(saveable.packed_col_mant.size() == 1 and saveable.packed_col_exp[0] == 12,
			"to_saveable() packs the col gutter (mantissa+exponent)",
			str(saveable.packed_col_exp))
	# rebuild a live runtime state the way Game._runtime_state does
	var restored := saveable.duplicate_state()
	restored.restore_runtime()
	check(restored.scores_col.size() == 1
			and is_equal_approx(restored.scores_col[0].mantissa, 2.5)
			and restored.scores_col[0].exponent == 12,
			"restore_runtime() rebuilds the col gutter exactly",
			"m=%f e=%d" % [restored.scores_col[0].mantissa, restored.scores_col[0].exponent])
	check(restored.scores_row_lower.size() == 2
			and restored.scores_row_lower[1].exponent == 7,
			"restore_runtime() rebuilds a multi-entry row gutter")
	check(restored.goal == 314 and restored.total_score == 271,
			"scalar stages survive the round-trip")

func test_saveable_unlinks_backrefs_restore_relinks() -> void:
	var s := make_state()
	var modded := s.lower_zone[0].datas[0]
	check(modded.skill.data == modded, "precondition: modifier backref points at its card")
	var saveable := s.to_saveable()
	# the saveable copy is a SEPARATE resource; its cards' backrefs are unlinked for ResourceSaver
	var saved_card := saveable.lower_zone[0].datas[0]
	check(saved_card.skill.data == null,
			"to_saveable() unlinks modifier .data backrefs (cyclic refs ResourceSaver can't write)")
	check(modded.skill.data == modded, "the ORIGINAL state's backref is left intact")
	var restored := saveable.duplicate_state()
	restored.restore_runtime()
	var r_card := restored.lower_zone[0].datas[0]
	check(r_card.skill and r_card.skill.data == r_card,
			"restore_runtime() relinks each backref to the restored card")

func test_duplicate_state_aliasing() -> void:
	var s := make_state()
	var copy := s.duplicate_state()
	# no shared CardData instances (history separation)
	var orig := {}
	for c in s.all_card_datas(): orig[c] = true
	var shared := false
	for c in copy.all_card_datas():
		if orig.has(c): shared = true
	check(not shared, "duplicate_state() shares no CardData instances")
	# BigNumbers copied by value, distinct instances (RefCounted -> manual copy)
	check(copy.scores_col[0] != s.scores_col[0]
			and copy.scores_col[0].exponent == 12,
			"duplicate_state() copies BigNumber gutters by value, distinct instances")
	# mutating the copy's gutter does not touch the original
	copy.scores_col[0].exponent = 99
	check(s.scores_col[0].exponent == 12, "copy and original gutters are independent")

func test_validate_clean_board() -> void:
	var s := make_state()
	var v := s.validate()
	check(v.is_empty(), "a well-formed board validates clean", str(v))

func test_validate_reports_injected_violations() -> void:
	# I2: zone / zone_type length mismatch
	var s1 := make_state()
	s1.upper_zone.append(TestFactories.col([] as Array[CardData]))  # col with no matching header
	check(s1.validate().any(func(x: String) -> bool: return x.begins_with("I2")),
			"validate() reports an I2 zone/type size mismatch")
	# I1: the same card instance living in two collections
	var s2 := make_state()
	var dupe := s2.lower_zone[0].datas[0]
	s2.draw_deck.append(dupe)
	check(s2.validate().any(func(x: String) -> bool: return x.begins_with("I1")),
			"validate() reports an I1 duplicate-card violation")

func test_pack_unpack_edge_values() -> void:
	# round-trip an empty array and a large-exponent value through the packed form. Read back
	# BigNumber's OWN stored mantissa/exponent (it may normalize on assignment) and require the
	# packed round-trip to reproduce exactly those stored values.
	var s := GameData.new()
	s.scores_col = [] as Array[BigNumber]
	s.scores_row_upper = [_bn(3.14, 300)] as Array[BigNumber]
	var want_mant := s.scores_row_upper[0].mantissa
	var want_exp := s.scores_row_upper[0].exponent
	s.pack_scores()
	s.scores_col = [_bn(0, 0)] as Array[BigNumber]  # clobber to prove unpack overwrites
	s.scores_row_upper = [] as Array[BigNumber]
	s.unpack_scores()
	check(s.scores_col.is_empty(), "unpack of an empty gutter yields an empty array")
	check(s.scores_row_upper.size() == 1
			and s.scores_row_upper[0].exponent == want_exp
			and is_equal_approx(s.scores_row_upper[0].mantissa, want_mant),
			"pack/unpack reproduces a large-exponent gutter value exactly",
			"m=%f e=%d" % [s.scores_row_upper[0].mantissa, s.scores_row_upper[0].exponent])
