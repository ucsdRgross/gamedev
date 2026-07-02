extends Node
# res://Tests/test_comparator.gd
# PipComparator suite (UNIT_TESTS_PLAN.md §4): default comparisons without an
# environment, then mod overrides through a FakeEnvironment.
# Non-freezing checks, every coroutine awaited (SC1 convention).

var _pass := 0
var _fail := 0

func _ready() -> void:
	print("============ PIP COMPARATOR TEST PASS ============")
	await run_no_environment_tests()
	await run_predicate_tests()
	await run_scorable_tests()
	await run_mod_override_tests()
	_print_summary()

func check(ok: bool, ctx: String, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  [PASS] ", ctx)
	else:
		_fail += 1
		printerr("[FAIL] ", ctx, "" if detail.is_empty() else (" -- " + detail))

func _print_summary() -> void:
	var total := _pass + _fail
	if _fail == 0:
		print("============ COMPARATOR: ALL %d CHECKS PASSED ============" % total)
	else:
		printerr("============ COMPARATOR: %d passed, %d FAILED (of %d) ============" % [_pass, _fail, total])


# ==============================================================================
# TEST DOUBLES
# ==============================================================================

## Suit outside the PipSuitStandard match arm — compare_suits must return NAN for these.
class WeirdSuit extends PipSuit:
	func get_str() -> String: return "?"
	func set_texture(_p: Polygon2D) -> void: pass
	func set_art_texture(_p: Polygon2D, _r: PipRank) -> void: pass
	func with_random() -> PipSuit: return self

## Rank outside PipRankNumeral — still has `value`, so compare_ranks falls to the
## "value in both" arm and compares numerically (pinned below).
class WeirdRank extends PipRank:
	func get_str() -> String: return "?"
	func set_texture(_p: Polygon2D) -> void: pass
	func with_random() -> PipRank: return self

## Spy: records calls and echoes a canned result. Type mod = always dispatched.
class SpyCompare extends CardModifierType:
	var rank_result := NAN
	var suit_result := NAN
	var rank_calls := 0
	var suit_calls := 0
	var last_rank_args : Array = []
	func get_str() -> String: return "Spy"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_compare_ranks(r1: PipRank, r2: PipRank) -> float:
		rank_calls += 1
		last_rank_args = [r1, r2]
		return rank_result
	func on_compare_suits(_s1: PipSuit, _s2: PipSuit) -> float:
		suit_calls += 1
		return suit_result


# ==============================================================================
# SECTION 1: DEFAULTS, NO ENVIRONMENT (CURRENT == null -> mods skipped)
# ==============================================================================
func run_no_environment_tests() -> void:
	print("\n--- SECTION 1: DEFAULT COMPARISONS (NO ENV) ---")
	check(CardEnvironment.CURRENT == null, "precondition: no CardEnvironment.CURRENT",
			str(CardEnvironment.CURRENT))

	var r7 := PipRankNumeral.new().with_value(7)
	var r5 := PipRankNumeral.new().with_value(5)
	var s1 := PipSuitStandard.new().with_value(1)
	var s3 := PipSuitStandard.new().with_value(3)

	check(await PipComparator.compare_ranks(r7, r5) == 2.0, "compare_ranks 7 vs 5 == 2")
	check(await PipComparator.compare_ranks(r5, r7) == -2.0, "compare_ranks antisymmetric")
	check(is_nan(await PipComparator.compare_ranks(null, r5)), "compare_ranks null r1 -> NAN")
	check(is_nan(await PipComparator.compare_ranks(r5, null)), "compare_ranks null r2 -> NAN")

	check(await PipComparator.compare_suits(s3, s1) == 2.0, "compare_suits 3 vs 1 == 2")
	check(is_nan(await PipComparator.compare_suits(null, s1)), "compare_suits null -> NAN")
	check(is_nan(await PipComparator.compare_suits(WeirdSuit.new(), s1)),
			"compare_suits non-standard suit -> NAN")
	check(is_nan(await PipComparator.compare_suits(WeirdSuit.new(), WeirdSuit.new())),
			"compare_suits two non-standard suits -> NAN")

	#pin: non-numeral ranks still compare via the generic `value` arm
	var w4 : PipRank = WeirdRank.new().with_value(4)
	check(await PipComparator.compare_ranks(w4, r5) == -1.0,
			"compare_ranks non-numeral rank with value compares numerically (pinned)")


# ==============================================================================
# SECTION 2: PREDICATES (is_rank_same / next_to / suit_same / is_ace)
# ==============================================================================
func run_predicate_tests() -> void:
	print("\n--- SECTION 2: PREDICATES ---")
	var a := PipRankNumeral.new().with_value(9)
	var b := PipRankNumeral.new().with_value(9)
	var c := PipRankNumeral.new().with_value(8)

	check(await PipComparator.is_rank_same(a, a), "is_rank_same identity")
	check(await PipComparator.is_rank_same(a, b), "is_rank_same equal values, distinct objects")
	check(not await PipComparator.is_rank_same(a, c), "is_rank_same 9 vs 8 false")
	check(not await PipComparator.is_rank_same(null, a), "is_rank_same null false")

	check(await PipComparator.is_rank_next_to(a, c), "is_rank_next_to 9,8 (diff +1) true")
	check(not await PipComparator.is_rank_next_to(c, a), "is_rank_next_to 8,9 (diff -1) false")
	check(not await PipComparator.is_rank_next_to(a,
			PipRankNumeral.new().with_value(7)), "is_rank_next_to diff 2 false")
	check(not await PipComparator.is_rank_next_to(a, null), "is_rank_next_to null false")

	var h1 := PipSuitStandard.new().with_value(2)
	var h2 := PipSuitStandard.new().with_value(2)
	check(PipComparator.is_suit_same(h1, h1), "is_suit_same identity")
	check(PipComparator.is_suit_same(h1, h2), "is_suit_same equal values")
	check(not PipComparator.is_suit_same(h1, PipSuitStandard.new().with_value(3)),
			"is_suit_same 2 vs 3 false")
	check(not PipComparator.is_suit_same(null, h1), "is_suit_same null false")
	var wa := WeirdSuit.new()
	check(PipComparator.is_suit_same(wa, wa), "is_suit_same non-standard identity true")
	check(not PipComparator.is_suit_same(WeirdSuit.new(), WeirdSuit.new()),
			"is_suit_same distinct non-standard false")

	check(PipComparator.is_ace(PipRankNumeral.new().with_value(1)), "is_ace value 1 true")
	check(PipComparator.is_ace(PipRankNumeral.new().with_value(1.0)), "is_ace 1.0 float true")
	check(not PipComparator.is_ace(PipRankNumeral.new().with_value(14)),
			"is_ace value 14 false (SC3)")
	check(not PipComparator.is_ace(PipRankNumeral.new().with_value(13)), "is_ace king false")


# ==============================================================================
# SECTION 3: SCORABLE VALUES (SCORING_AUDIT G2 — ace-high coverage)
# ==============================================================================
func run_scorable_tests() -> void:
	print("\n--- SECTION 3: SCORABLE VALUES ---")
	var ace := PipRankNumeral.new().with_value(1)
	var ten := PipRankNumeral.new().with_value(10)

	check(PipComparator.get_scorable_value(ace, true) == 14.0,
			"ace with wrap_ace_high -> 14")
	check(PipComparator.get_scorable_value(ace, false) == 1.0,
			"ace without wrap_ace_high -> 1")
	check(PipComparator.get_scorable_value(ten, true) == 10.0,
			"non-ace unaffected by wrap_ace_high")
	check(PipComparator.get_scorable_value(null) == -INF, "null rank -> -INF")

	check(PipComparator.is_scorable(TestFactories.m_card(5, 2)), "full card scorable")
	check(not PipComparator.is_scorable(TestFactories.m_stone()), "stone (no pips) not scorable")
	check(not PipComparator.is_scorable(null), "null card not scorable")
	var rankless := CardData.new()
	rankless.suit = PipSuitStandard.new().with_value(1)
	check(not PipComparator.is_scorable(rankless), "null rank not scorable")


# ==============================================================================
# SECTION 4: MOD OVERRIDES VIA FakeEnvironment
# ==============================================================================
func run_mod_override_tests() -> void:
	print("\n--- SECTION 4: MOD OVERRIDES (FakeEnvironment) ---")
	var env := FakeEnvironment.new()
	add_child(env)
	check(CardEnvironment.CURRENT == env, "FakeEnvironment installs as CURRENT")

	var spy := SpyCompare.new()
	var carrier := CardData.new().with_type(spy)
	var cards : Array[CardData] = [carrier]
	env.card_collections.append(cards)

	var r9 := PipRankNumeral.new().with_value(9)
	var r2 := PipRankNumeral.new().with_value(2)

	#override wins over default math
	spy.rank_result = 0.0
	check(await PipComparator.compare_ranks(r9, r2) == 0.0, "mod override: ranks 9,2 -> 0")
	check(await PipComparator.is_rank_same(r9, r2), "is_rank_same true under 'all same' mod")
	check((spy.last_rank_args.size() == 2 and spy.last_rank_args[0] == r9 and spy.last_rank_args[1] == r2) as bool,
			"hook receives TWO pip args, not one array (vararg regression)",
			str(spy.last_rank_args))

	#NAN from the mod falls through to the default compare (pin fall-through)
	spy.rank_result = NAN
	check(await PipComparator.compare_ranks(r9, r2) == 7.0,
			"mod returning NAN falls through to default compare (pinned)")

	#suits too
	spy.suit_result = 5.0
	check(await PipComparator.compare_suits(PipSuitStandard.new().with_value(1),
			PipSuitStandard.new().with_value(1)) == 5.0, "mod override: suits -> 5")

	#nulls short-circuit BEFORE mods run (pinned: mods never see null pips)
	spy.rank_calls = 0
	check(is_nan(await PipComparator.compare_ranks(null, r2)) and spy.rank_calls == 0,
			"null pips short-circuit before mod dispatch (pinned)")

	#precedence: first card in iterator order wins, later spies not called
	var spy2 := SpyCompare.new()
	spy2.rank_result = 99.0
	cards.append(CardData.new().with_type(spy2))
	spy.rank_result = 3.0
	spy2.rank_calls = 0
	var diff := await PipComparator.compare_ranks(r9, r2)
	check(diff == 3.0 and spy2.rank_calls == 0,
			"first implementing mod wins; later mods not called",
			"diff %s spy2 calls %d" % [diff, spy2.rank_calls])

	#skills only dispatch while their `active` flag is set
	env.card_collections.clear()
	var skill_spy := SpySkillCompare.new()
	var skill_carrier := CardData.new().with_skill(skill_spy)
	var arr2 : Array[CardData] = [skill_carrier]
	env.card_collections.append(arr2)
	skill_spy.active = false
	check(await PipComparator.compare_ranks(r9, r2) == 7.0 \
			and skill_spy.rank_calls == 0, "inactive skill mod not dispatched")
	skill_spy.active = true
	skill_spy.rank_result = -1.0
	check(await PipComparator.compare_ranks(r9, r2) == -1.0 and skill_spy.rank_calls == 1,
			"active skill mod dispatched")

	remove_child(env)
	env.free()
	check(CardEnvironment.CURRENT == null, "removing FakeEnvironment restores CURRENT = null")

## Skill-flavored spy for the active-flag gate.
class SpySkillCompare extends CardModifierSkill:
	var rank_result := NAN
	var rank_calls := 0
	func get_str() -> String: return "SpySkill"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_compare_ranks(_r1: PipRank, _r2: PipRank) -> float:
		rank_calls += 1
		return rank_result
