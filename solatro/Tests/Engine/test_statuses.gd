extends SolatroTest
# res://Tests/Engine/test_statuses.gd
# ==============================================================================
# Status-effect foundation (SUIT_PROPS_PLAN Phase 2 / STATUS_EFFECTS_PLAN Steps 1-7):
# CardData.statuses as an Array[CardModifierStatus], merge-by-class stacking,
# self-scope dispatch, expiry, the data backref through duplicate/save, and
# self-removal mid-dispatch not skipping sibling mods.
#
# CATEGORY MAP: stacking/coexistence/expiry/self-scope are BEHAVIOR (rules a
# designer relies on). Backref-through-save and self-removal-mid-pass are
# IMPLEMENTATION (they pin serialization plumbing + the snapshot-dispatch policy).
#
# Uses the Tests/Support status classes (StatusTestA/B/Seal/Scored) — Phase 2 ships
# no gameplay statuses yet (StatusJuggling/StatusBurning land in Phase 3).
# ==============================================================================

var env : FakeEnvironment

func suite_name() -> String:
	return "STATUSES"

func _ready() -> void:
	print("============ STATUSES TEST PASS ============")
	env = FakeEnvironment.new()
	add_child(env)
	test_merge_stacking()
	test_heterogeneous_coexist()
	test_non_merge_override()
	test_expiry_at_zero()
	test_shared_instance_defensive_dup()
	await test_self_scope_guard()
	await test_self_removal_mid_pass()
	env.queue_free()
	test_backref_through_duplicate()
	test_save_roundtrip()
	finish()

# ------------------------------------------------------------------ BEHAVIOR

func test_merge_stacking() -> void:
	behavior_section("MERGE-BY-CLASS STACKING")
	var c := CardData.new()
	c.add_status(StatusTestA.new())                       # stacks 1
	c.add_status(CardModifierStatus.stacked(StatusTestA, 2))
	check(c.statuses.size() == 1, "same-class statuses merge into one entry",
			str(c.statuses))
	check(c.statuses[0].stacks == 3, "merged stacks add (1 + 2 == 3)",
			str(c.statuses[0].stacks))

func test_heterogeneous_coexist() -> void:
	behavior_section("HETEROGENEOUS COEXISTENCE")
	var c := CardData.new()
	c.add_status(StatusTestA.new())
	c.add_status(StatusTestB.new())
	check(c.statuses.size() == 2, "different-class statuses coexist as two entries",
			str(c.statuses))

func test_non_merge_override() -> void:
	behavior_section("NON-MERGE OVERRIDE (can_merge_with)")
	var c := CardData.new()
	c.add_status(StatusTestSeal.new())
	c.add_status(StatusTestSeal.new())
	check(c.statuses.size() == 2, "a status refusing to merge stays two entries",
			str(c.statuses))

func test_expiry_at_zero() -> void:
	behavior_section("EXPIRY AT ZERO STACKS")
	var c := CardData.new()
	var changed : Array[int] = [0]
	c.data_changed.connect(func() -> void: changed[0] += 1)
	c.add_status(StatusTestA.new())   # 1 change (append)
	c.statuses[0].stacks -= 1         # -> 0: setter removes + emits data_changed
	check(c.statuses.is_empty(), "status at 0 stacks removes itself from the card")
	check(changed[0] >= 2, "removal fires data_changed", str(changed[0]))

# ---------------------------------------------------------- IMPLEMENTATION

func test_shared_instance_defensive_dup() -> void:
	implementation_section("S7 SHARED-INSTANCE DEFENSIVE DUPLICATE")
	var owner_card := CardData.new()
	var shared := StatusTestA.new()
	owner_card.add_status(shared)     # binds shared.data = owner_card
	var other := CardData.new()
	other.add_status(shared)          # arrives with a foreign .data -> must be duplicated
	check(other.statuses[0] != shared, "a status with a foreign .data is duplicated on apply")
	check(other.statuses[0].data == other, "the duplicate is bound to the new card")
	other.statuses[0].stacks = 9
	check(shared.stacks == 1, "the two cards do not share one stacks field")

func test_self_scope_guard() -> void:
	implementation_section("SELF-SCOPE GUARD (targeted on_score)")
	var scored := StatusTestScored.new()
	var carrier := CardData.new().with_status(scored)
	var other := CardData.new()
	var cards : Array[CardData] = [carrier, other]
	env.card_collections.clear()
	env.card_collections.append(cards)
	# scoring the OTHER card must not consume the carrier's charge
	await env.run_all_mods(&"on_score", other)
	check(scored.hits == 0 and scored.stacks == 1,
			"scoring another card leaves a self-scoped status untouched",
			"hits=%d stacks=%d" % [scored.hits, scored.stacks])
	# scoring the carrier itself consumes it
	await env.run_all_mods(&"on_score", carrier)
	check(scored.hits == 1, "scoring the carrier fires its own status", str(scored.hits))
	check(carrier.statuses.is_empty(), "the one-shot status is consumed to 0 and removed")

func test_self_removal_mid_pass() -> void:
	implementation_section("SELF-REMOVAL MID-PASS DOESN'T SKIP SIBLINGS (B10/C2)")
	var scored := StatusTestScored.new()             # removes itself on score
	var witness := SpyStatus.new()                   # records that IT still fired
	var carrier := CardData.new()
	carrier.add_status(scored)
	carrier.add_status(witness)
	var cards : Array[CardData] = [carrier]
	env.card_collections.clear()
	env.card_collections.append(cards)
	await env.run_all_mods(&"on_score", carrier)
	check(scored.hits == 1 and carrier.statuses.size() == 1,
			"the self-removing status fired and left only its sibling",
			str(carrier.statuses))
	check(witness.hits == 1,
			"a sibling status still fires after an earlier one removed itself (snapshot dispatch)")

func test_backref_through_duplicate() -> void:
	implementation_section("DATA BACKREF SURVIVES DEEP DUPLICATE (undo path)")
	var state := _state_with_status(5)
	var copy := state.duplicate_state()   # DEEP_DUPLICATE_ALL — mirrors undo
	var card := copy.upper_zone[0].datas[0]
	check(card.statuses.size() == 1 and card.statuses[0].data == card,
			"duplicate_state remaps status.data to the copied card")
	check(card.statuses[0] != state.upper_zone[0].datas[0].statuses[0],
			"the copy's status is a distinct instance (no aliasing)")

func test_save_roundtrip() -> void:
	implementation_section("STATUS SURVIVES SAVE ROUND-TRIP (unlink/relink)")
	var state := _state_with_status(7)
	var saveable := state.to_saveable()
	var saved_card := saveable.upper_zone[0].datas[0]
	check(saved_card.statuses[0].data == null,
			"to_saveable unlinks the status.data backref (ResourceSaver can't write the cycle)")
	var restored := saveable.duplicate_state()
	restored.restore_runtime()
	var r_card := restored.upper_zone[0].datas[0]
	check(r_card.statuses.size() == 1 and r_card.statuses[0].stacks == 7,
			"restore keeps the status and its stack count", str(r_card.statuses))
	check(r_card.statuses[0].data == r_card, "restore relinks the status backref to its card")

# ------------------------------------------------------------------ helpers

## Minimal board: one upper-zone column with a single card carrying StatusTestA(stacks).
func _state_with_status(stacks: int) -> GameData:
	var card := TestFactories.m_card(5, TestFactories.uc())
	card.stage = CardData.Stage.PLAY
	card.add_status(CardModifierStatus.stacked(StatusTestA, stacks))
	var header := TestFactories.m_card(1, TestFactories.uc())
	header.stage = CardData.Stage.ZONE
	var s := GameData.new()
	s.upper_zone_type = [header] as Array[CardData]
	s.upper_zone = [TestFactories.col([card] as Array[CardData])]
	return s

## Self-scoped status that only records it fired (never removes itself) — the sibling that
## must still run after StatusTestScored removes itself earlier in the same pass.
class SpyStatus extends CardModifierStatus:
	var hits : int = 0
	func get_str() -> String: return "Spy"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_score(target: CardData) -> void:
		if target != data: return
		hits += 1
