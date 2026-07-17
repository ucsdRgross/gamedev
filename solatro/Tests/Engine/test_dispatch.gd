extends TestSuite
# res://Tests/Engine/test_dispatch.gd
# Dispatch / CardEnvironment suite (UNIT_TESTS_PLAN.md §3): run_all_mods ordering,
# skill_active_check activation edges, on_anything non-recursion, first-result
# semantics, CURRENT lifecycle. Uses FakeEnvironment + spy modifiers.
#
# CATEGORY MAP: this whole suite is IMPLEMENTATION — it pins the internal mod
# dispatch machinery (call order, hook gating, first-result semantics, CURRENT
# policy). Nothing here is a rule a player sees; failures after a dispatcher
# refactor may just mean the pinned policy legitimately changed.
#
# NOTE on skills under FakeEnvironment: CardModifier.is_active() only returns true
# outside a Game for rules cards / StampGlobal — so skill carriers here are
# registered in env.rules as well, exactly like rules_deck cards in-game.

var env : FakeEnvironment

func suite_name() -> String:
	return "DISPATCH"

func _ready() -> void:
	TestLog.line("============ DISPATCH TEST PASS ============")
	env = FakeEnvironment.new()
	add_child(env)
	await run_order_tests()
	await run_on_anything_tests()
	await run_active_check_tests()
	await run_first_result_tests()
	env.queue_free()
	await run_current_lifecycle_tests()
	finish()

func reset_env() -> void:
	env.card_collections.clear()
	env.rules.clear()


# ==============================================================================
# SPIES — shared call log so cross-mod ordering is observable
# ==============================================================================

class SpyType extends CardModifierType:
	var log : Array
	var tag : String
	func get_str() -> String: return "SpyT:" + tag
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_ping() -> void: log.append(tag)
	func on_anything() -> void: log.append(tag + ".anything")

class SpyStamp extends CardModifierStamp:
	var log : Array
	var tag : String
	func get_str() -> String: return "SpyS:" + tag
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_ping() -> void: log.append(tag)

class SpySkill extends CardModifierSkill:
	var log : Array
	var tag : String
	var active_calls := 0
	var deactive_calls := 0
	func get_str() -> String: return "SpyK:" + tag
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_ping() -> void: log.append(tag)
	func on_active() -> void: active_calls += 1
	func on_deactive() -> void: deactive_calls += 1

class SpyFirst extends CardModifierType:
	var compare_result := NAN
	var array_result : Array[CardData] = []
	var compare_calls := 0
	var array_calls := 0
	func get_str() -> String: return "SpyF"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_compare_test() -> float:
		compare_calls += 1
		return compare_result
	func on_array_test() -> Array[CardData]:
		array_calls += 1
		return array_result

func spy_type(log: Array, tag: String) -> SpyType:
	var s := SpyType.new()
	s.log = log
	s.tag = tag
	return s

func spy_stamp(log: Array, tag: String) -> SpyStamp:
	var s := SpyStamp.new()
	s.log = log
	s.tag = tag
	return s

func spy_skill(log: Array, tag: String) -> SpySkill:
	var s := SpySkill.new()
	s.log = log
	s.tag = tag
	return s


# ==============================================================================
# SECTION 1: DISPATCH ORDER (type, stamp, skill per card, iterator order)
# ==============================================================================
func run_order_tests() -> void:
	implementation_section("SECTION 1: ORDER")
	reset_env()
	var log := []
	var c1 := CardData.new() \
			.with_type(spy_type(log, "c1.type")) \
			.with_stamp(spy_stamp(log, "c1.stamp")) \
			.with_skill(spy_skill(log, "c1.skill"))
	var c2 := CardData.new().with_type(spy_type(log, "c2.type"))
	var cards : Array[CardData] = [c1, c2]
	env.card_collections.append(cards)
	env.rules.append_array(cards) #keeps c1.skill active through skill_active_check

	await env.run_all_mods(&"on_ping")
	#the trailing entries are the passive on_anything pass (spy types implement it)
	check(log == ["c1.type", "c1.stamp", "c1.skill", "c2.type",
			"c1.type.anything", "c2.type.anything"],
			"type, stamp, skill per card, in iterator order (+ on_anything pass)", str(log))

	#hook nobody implements: no error, and (P1 owner ruling 2026-07-16) the passive
	#on_anything tail is SKIPPED — no mod ran, so nothing could have changed
	log.clear()
	await env.run_all_mods(&"on_unimplemented_hook")
	check(log == [],
			"unimplemented hook -> no calls, no error, on_anything skipped", str(log))

	#skill with active == false is skipped even if it implements the hook
	log.clear()
	env.rules.clear() #out of rules -> is_active false -> skill_active_check turns it off
	await env.run_all_mods(&"on_ping")
	check("c1.skill" not in log and "c1.type" in log,
			"inactive skill skipped; types/stamps still dispatched", str(log))


# ==============================================================================
# SECTION 2: on_anything passive pass
# ==============================================================================
func run_on_anything_tests() -> void:
	implementation_section("SECTION 2: ON_ANYTHING")
	reset_env()
	var log := []
	var c := CardData.new().with_type(spy_type(log, "c"))
	var cards : Array[CardData] = [c]
	env.card_collections.append(cards)

	await env.run_all_mods(&"on_ping")
	check(log == ["c", "c.anything"], "on_anything fires exactly once, after the hook", str(log))

	log.clear()
	await env.run_all_mods(&"on_anything")
	check(log == ["c.anything"],
			"run_all_mods(on_anything) does not recurse (fires once)", str(log))


# ==============================================================================
# SECTION 3: skill_active_check edges
# ==============================================================================
func run_active_check_tests() -> void:
	implementation_section("SECTION 3: ACTIVE CHECK")
	reset_env()
	var log := []
	var skill := spy_skill(log, "k")
	var c := CardData.new().with_skill(skill)
	var cards : Array[CardData] = [c]
	env.card_collections.append(cards)

	#activation edge: card enters rules -> on_active exactly once, not per check
	env.rules.append(c)
	skill.active = false
	await env.skill_active_check()
	await env.skill_active_check()
	check(skill.active and skill.active_calls == 1,
			"activation edge fires on_active exactly once",
			"active_calls %d" % skill.active_calls)

	#deactivation edge: card leaves rules -> on_deactive exactly once
	env.rules.clear()
	await env.skill_active_check()
	await env.skill_active_check()
	check(not skill.active and skill.deactive_calls == 1,
			"deactivation edge fires on_deactive exactly once",
			"deactive_calls %d" % skill.deactive_calls)


# ==============================================================================
# SECTION 4: return_first_* semantics
# ==============================================================================
func run_first_result_tests() -> void:
	implementation_section("SECTION 4: FIRST-RESULT")
	reset_env()
	var first := SpyFirst.new()
	var second := SpyFirst.new()
	var cards : Array[CardData] = [CardData.new().with_type(first),
			CardData.new().with_type(second)]
	env.card_collections.append(cards)

	#first implementing mod wins, later mods NOT called — even when it returns NAN
	#(pin: compare dispatch takes the FIRST result verbatim; NAN fall-through is
	#PipComparator's job, not the dispatcher's)
	first.compare_result = 5.0
	var r := await env.return_first_compare_mod_result(&"on_compare_test")
	check(r == 5.0 and second.compare_calls == 0, "compare: first mod wins, second not called")
	first.compare_result = NAN
	r = await env.return_first_compare_mod_result(&"on_compare_test")
	check(is_nan(r) and second.compare_calls == 0,
			"PIN: compare dispatch returns first mod's NAN verbatim (no fall-through here)")

	r = await env.return_first_compare_mod_result(&"on_nobody_implements")
	check(is_nan(r), "compare: no implementers -> NAN")

	#array dispatch: empty results are SKIPPED, first non-empty wins
	var winner := TestFactories.m_card(1, 1)
	first.array_result = []
	second.array_result = [winner] as Array[CardData]
	var arr := await env.return_first_data_array_result(&"on_array_test")
	check(arr == [winner] and first.array_calls == 1,
			"array: empty result skipped, first non-empty wins")

	second.array_result = []
	arr = await env.return_first_data_array_result(&"on_array_test")
	check(arr == [], "array: all empty -> []")


# ==============================================================================
# SECTION 5: CURRENT lifecycle (review D4 — pin current policy)
# ==============================================================================
func run_current_lifecycle_tests() -> void:
	implementation_section("SECTION 5: CURRENT LIFECYCLE")
	var a := FakeEnvironment.new()
	var b := FakeEnvironment.new()
	add_child(a)
	check(CardEnvironment.CURRENT == a, "first environment becomes CURRENT")
	add_child(b)
	check(CardEnvironment.CURRENT == b, "second environment takes over CURRENT")
	remove_child(b)
	b.free()
	#PIN (review D4): exiting does NOT restore the previous environment — it nulls.
	check(CardEnvironment.CURRENT == null,
			"PIN: removing top environment sets CURRENT to null (no restore stack)")
	remove_child(a)
	a.free()
	check(CardEnvironment.CURRENT == null, "removing non-CURRENT env leaves null")
