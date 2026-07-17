extends TestSuite
# res://Tests/Engine/test_leak_canary.gd
# ==============================================================================
# MEMORY-LEAK CANARY (owner-approved 2026-07-17, AUDIT_PROPOSALS_HANDOFF.md
# NEXT STEPS 3): CardData<->modifier backrefs are RefCounted CYCLES that Godot
# never collects — any card built and dropped without unlink_card_backrefs leaks
# until exit. This suite pins the containment discipline: build + tear down a
# full headless Game N times and assert Performance.OBJECT_COUNT returns to
# baseline. If a future card/modifier slot (or teardown path) breaks the cycle
# discipline, the growth check fails here instead of silently inflating the
# ~18k residual exit-leak figure.
#
# ⚠️ Runs LAST and ALONE: OBJECT_COUNT is engine-global, so any concurrent suite
# would make the numbers meaningless. See the SUITE ORDERING chain in
# test_base.gd — every earlier waiter excludes "LEAK CANARY".
# ==============================================================================

# CATEGORY MAP: all IMPLEMENTATION — object counts pin HOW memory behaves, not a
# player-visible rule.

func suite_name() -> String:
	return "LEAK CANARY"

const CYCLES := 10

func _ready() -> void:
	await await_siblings_except([])
	TestLog.line("============ LEAK CANARY TEST PASS ============")
	implementation_section("REFCOUNT-CYCLE CANARY")

	# 0. Prove the canary CAN catch the known pattern: build a fixture and drop it
	# WITHOUT unlinking. The cycle keeps every CardData+modifier alive, so the
	# global object count must NOT return to its prior level. (This deliberately
	# leaks one small fixture for the rest of the process — done before the
	# baseline snapshot so it can't pollute the growth check below.)
	await _settle()
	var before_leak := _object_count()
	var leaked := _make_game()
	CardEnvironment.CURRENT = null
	leaked.free()  # frees the Game NODE; state's card cycles survive — that's the leak
	leaked = null
	await _settle()
	check_impl(_object_count() > before_leak,
			"canary detects a deliberate drop-without-unlink leak",
			"before %d, after %d" % [before_leak, _object_count()])

	# 1. Warm-up cycle: first build touches lazy one-time allocations (deck
	# caches, static registries) that must not count against the loop.
	_clean_cycle()
	await _settle()
	var baseline := _object_count()

	# 2. N clean build/teardown cycles must return to the warm baseline.
	for i in range(CYCLES):
		_clean_cycle()
	await _settle()
	var after := _object_count()
	check_impl(after <= baseline,
			"OBJECT_COUNT returns to baseline after %d clean Game build/free cycles" % CYCLES,
			"baseline %d, after %d (growth %d)" % [baseline, after, after - baseline])
	if after > baseline:
		# Orphan NODES only (RefCounted cycles won't show here, but stray nodes will).
		print_orphan_nodes()

	finish()

func _object_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_COUNT))

## Two idle frames so queued deletions/refcount releases settle before counting.
func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

## One full lifecycle with the documented teardown discipline: unlink every
## card's modifier backrefs (breaking the RefCounted cycles), then free the Game.
func _clean_cycle() -> void:
	var g := _make_game()
	g.state.unlink_modifier_backrefs()
	CardEnvironment.CURRENT = null
	g.free()

func _rules_card(skill: CardModifierSkill) -> CardData:
	var c := CardData.new().with_skill(skill)
	c.stage = CardData.Stage.RULES
	skill.active = true
	return c

## Same minimal-but-real headless fixture as test_game_headless.make_game():
## rules deck with the classic skills + two zones of typed 2-card columns —
## every modifier slot the unlink helpers cover is exercised.
func _make_game() -> Game:
	var g := Game.new()
	var s := GameData.new()
	s.rules_deck = [
		_rules_card(SkillGrabberOgLower.new()),
		_rules_card(SkillPlacerOgLower.new()),
		_rules_card(SkillScorerCascadeLower.new()),
		_rules_card(SkillEvalPokerBest.new()),
	] as Array[CardData]
	for zone_x in 2:
		var types: Array[CardData] = []
		var cols: Array[ArrayCardData] = []
		for c in 2:
			var h := TestFactories.m_card(1, TestFactories.uc()); h.stage = CardData.Stage.ZONE
			types.append(h)
			var card_lo := TestFactories.m_card(3, TestFactories.uc())
			var card_hi := TestFactories.m_card(4, TestFactories.uc())
			card_lo.stage = CardData.Stage.PLAY
			card_hi.stage = CardData.Stage.PLAY
			cols.append(TestFactories.col([card_lo, card_hi] as Array[CardData]))
		if zone_x == 0:
			s.upper_zone_type = types
			s.upper_zone = cols
		else:
			s.lower_zone_type = types
			s.lower_zone = cols
	g.state = s
	CardEnvironment.CURRENT = g
	return g
