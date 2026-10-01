extends TestSuite
# The shipped rules cards and modifiers, driven through a real headless Game wired the way the
# rules deck wires them. BEHAVIOR throughout; the internal pins are the inline check_impl rows.

func suite_name() -> String:
	return "MODS"

func _ready() -> void:
	TestLog.line("============ RULES MODS TEST PASS ============")
	check_all_tests_registered()
# These tests build private Games; make sure no stray run receives their saves.
	var real_run: RunState = RunManager.run
	RunManager.run = null
	await run_grabber_tests()
	await run_placer_tests()
	await run_type_input_place_tests()
	await run_type_input_refill_tests()
	await run_zone_adder_tests()
	await run_trigger_tests()
	run_booster_tests()
	await run_shuffle_tests()
	run_implementer_cache_tests()
	await run_attach_mid_walk_test()
	RunManager.run = real_run
	finish()


# ==============================================================================
# FIXTURE
# ==============================================================================

func rules_card(skill: CardModifierSkill) -> CardData:
	var c := CardData.new().with_skill(skill)
	c.stage = CardData.Stage.RULES
	skill.spotlit = true
	return c

func play_card(rank: int, suit: int) -> CardData:
	var c := TestFactories.m_card(rank, suit)
	c.stage = CardData.Stage.PLAY
	return c

func header() -> CardData:
	var h := TestFactories.m_card(1, TestFactories.uc())
	h.stage = CardData.Stage.ZONE
	return h

## A game with the given rules cards and one zone layout: `upper`/`lower` are arrays of columns, each column an Array[CardData] already staged PLAY. Plain headers.
func make_game(rules: Array[CardData], upper: Array, lower: Array) -> Game:
	var g := Game.new()
	var s := GameData.new()
	s.rules_deck = rules
	var upper_types: Array[CardData] = []
	var upper_cols: Array[ArrayCardData] = []
	for col: Array in upper:
		upper_types.append(header())
		var cards: Array[CardData] = []
		cards.assign(col)
		upper_cols.append(TestFactories.col(cards))
	var lower_types: Array[CardData] = []
	var lower_cols: Array[ArrayCardData] = []
	for col: Array in lower:
		lower_types.append(header())
		var cards: Array[CardData] = []
		cards.assign(col)
		lower_cols.append(TestFactories.col(cards))
	s.upper_zone_type = upper_types
	s.upper_zone = upper_cols
	s.lower_zone_type = lower_types
	s.lower_zone = lower_cols
	g.state = s
	CardEnvironment.CURRENT = g
	return g

func done(g: Game) -> void:
	CardEnvironment.CURRENT = null
	g.free()

func lower_col(g: Game, i: int) -> Array[CardData]:
	return g.state.lower_zone[i].datas


# ==============================================================================
# SECTION 1: GRABBER (SkillGrabberOgLower) — what the player may pick up
# ==============================================================================
func run_grabber_tests() -> void:
	behavior_section("SECTION 1: GRABBER RULES")
	var rules: Array[CardData] = [rules_card(SkillGrabberOgLower.new())]

#ascending run, all suits distinct -> the whole stack is grabbable from its base
	var run3: Array = [[play_card(3, 1), play_card(4, 2), play_card(5, 3)]]
	var g := make_game(rules, [[]], run3)
	var grabbed := await g.try_grab(lower_col(g, 0)[0])
	check(grabbed == lower_col(g, 0), "ascending distinct-suit run: whole stack grabs")
	check((await g.try_grab(lower_col(g, 0)[2])).size() == 1,
			"topmost card alone is always a (size-1) legal grab")
	done(g)

#descending run also grabs (the rule is |rank step| == 1 with changing suits)
	g = make_game(rules, [[]], [[play_card(9, 1), play_card(8, 2), play_card(7, 1)]])
	check((await g.try_grab(lower_col(g, 0)[0])).size() == 3, "descending run grabs")
	done(g)

#zigzag run: current rule permits ANY +-1 steps, not one monotone direction —
#each adjacent pair only needs |rank diff| == 1 and a suit change
	g = make_game(rules, [[]], [[play_card(3, 1), play_card(4, 2), play_card(3, 3)]])
	check((await g.try_grab(lower_col(g, 0)[0])).size() == 3,
			"zigzag +-1 run grabs (rule is per-pair, not monotone)")
	done(g)

#repeated suit breaks the run
	g = make_game(rules, [[]], [[play_card(3, 1), play_card(4, 1)]])
	check((await g.try_grab(lower_col(g, 0)[0])).is_empty(), "repeated suit: no grab")
	done(g)

#rank gap breaks the run
	g = make_game(rules, [[]], [[play_card(3, 1), play_card(5, 2)]])
	check((await g.try_grab(lower_col(g, 0)[0])).is_empty(), "rank gap of 2: no grab")
	done(g)

#the grabber only works the lower zone
	g = make_game(rules, [[play_card(3, 1)]], [[]])
	check((await g.try_grab(g.state.upper_zone[0].datas[0])).is_empty(),
			"upper-zone card: lower grabber refuses")
	done(g)


# ==============================================================================
# SECTION 2: PLACER (SkillPlacerOgLower) — where a held stack may land
# ==============================================================================
func run_placer_tests() -> void:
	behavior_section("SECTION 2: PLACER RULES")
	var rules: Array[CardData] = [rules_card(SkillPlacerOgLower.new())]

#rank +-1, different suit, topmost target -> legal; the whole stack moves over
	var g := make_game(rules,
			[[]], [[play_card(4, 1), play_card(3, 2)], [play_card(5, 3)]])
#4 then 3
	var moving: Array[CardData] = [lower_col(g, 0)[0], lower_col(g, 0)[1]]
	check(await g.try_place(moving, lower_col(g, 1)[0]), "rank 4 onto 5, new suit: placed")
	check(lower_col(g, 1) == [lower_col(g, 1)[0], moving[0], moving[1]] \
			and lower_col(g, 0).is_empty(),
			"stack lands in order on the target column")
	check(g.state.validate().is_empty(), "board validates after the place")
	done(g)

#equal rank -> illegal
	g = make_game(rules, [[]], [[play_card(5, 1)], [play_card(5, 2)]])
	check(not await g.try_place([lower_col(g, 0)[0]] as Array[CardData], lower_col(g, 1)[0]),
			"equal rank: rejected")
	done(g)

#same suit -> illegal even with rank +-1
	g = make_game(rules, [[]], [[play_card(4, 7)], [play_card(5, 7)]])
	check(not await g.try_place([lower_col(g, 0)[0]] as Array[CardData], lower_col(g, 1)[0]),
			"same suit: rejected")
	done(g)

#covered (non-topmost) target -> illegal
	g = make_game(rules, [[]], [[play_card(4, 1)], [play_card(5, 2), play_card(6, 3)]])
	check(not await g.try_place([lower_col(g, 0)[0]] as Array[CardData], lower_col(g, 1)[0]),
			"covered target: rejected")
	done(g)

#upper-zone target -> this placer only serves the lower zone
	g = make_game(rules, [[play_card(5, 2)]], [[play_card(4, 1)]])
	check(not await g.try_place([lower_col(g, 0)[0]] as Array[CardData],
			g.state.upper_zone[0].datas[0]), "upper-zone target: rejected")
	done(g)


# ==============================================================================
# SECTION 3: TypeInput placement — anything may be placed on an OPEN input slot
# ==============================================================================
func run_type_input_place_tests() -> void:
	behavior_section("SECTION 3: INPUT-SLOT PLACEMENT")
	var g := make_game([], [[]], [[], [play_card(9, 1)]])
	var input_header := g.state.lower_zone_type[0].with_type(TypeInput.new())
	var card := play_card(2, 2)
	g.state.lower_zone[1].datas.append(card)
	g.state.revision += 1

#empty input column: its header is topmost -> accepts any stack
	check(await g.try_place([card] as Array[CardData], input_header),
			"open input slot accepts a card")
	check(lower_col(g, 0).has(card), "card landed in the input column")
	check(g.state.validate().is_empty(), "board validates after input placement")

#occupied input column: header covered -> refuses
	var second := play_card(3, 3)
	g.state.lower_zone[1].datas.append(second)
	g.state.revision += 1
	check(not await g.try_place([second] as Array[CardData], input_header),
			"occupied input slot refuses (header covered)")

#a plain header without TypeInput never accepts
	check(not await g.try_place([second] as Array[CardData], g.state.lower_zone_type[1]),
			"plain zone header refuses stacks")
	done(g)


# ==============================================================================
# SECTION 4: TypeInput refill — the Entrance fills its own empty slots, left to right
# ==============================================================================
func run_type_input_refill_tests() -> void:
	behavior_section("SECTION 4: ENTRANCE REFILL")
# Two Entrance slots, both empty, and two cards waiting in the deck. No grids at all,
# which is deliberate: with nowhere to place a card, the refill trigger is satisfied
# every time and the only thing under test is which slot each card lands in.
	var g := make_game([], [[], []], [])
	for header_card : CardData in g.state.upper_zone_type:
		header_card.with_type(TypeInput.new())
	var d1 := TestFactories.m_card(7, TestFactories.uc())
	var d2 := TestFactories.m_card(8, TestFactories.uc())
	for d : CardData in [d1, d2]:
		d.stage = CardData.Stage.DRAW
	g.state.entrance_stocks()[0].datas.append_array([d1, d2] as Array[CardData])
	g.deal_stocks()

	await g.next()
	check(g.state.upper_zone[0].datas == ([d1] as Array[CardData]),
			"the leftmost Entrance slot takes the top of its own stock",
			str(g.state.upper_zone[0].datas))
	check(g.state.upper_zone[1].datas == ([d2] as Array[CardData]),
			"the next slot right takes the top of its own", str(g.state.upper_zone[1].datas))
	check(g.state.stocks_are_empty() and d1.stage == CardData.Stage.PLAY 			and d2.stage == CardData.Stage.PLAY,
			"both drawn cards left the stocks and entered play")
	check(g.state.validate().is_empty(), "board validates after the refill")

# An empty deck: the refill is still asked for and simply finds nothing to draw.
	g.state.upper_zone[0].datas.clear()
	await g.next()
	check(g.state.upper_zone[0].datas.is_empty() 			and g.state.upper_zone[1].datas == ([d2] as Array[CardData]),
			"a refill with an empty deck leaves the slot empty; no crash, nothing invented",
			str(g.state.upper_zone[0].datas))
	check(g.state.validate().is_empty(), "board validates after the empty-deck refill")
	done(g)


# ==============================================================================
# SECTION 5: ZoneAdder (SkillAdderInputLower) — columns in lockstep
# ==============================================================================
func run_zone_adder_tests() -> void:
	behavior_section("SECTION 5: ZONE ADDER")
	var adder := SkillAdderInputLower.new()
	var adder_card := CardData.new().with_skill(adder)
	adder_card.stage = CardData.Stage.RULES
#so the activation edge below fires on_spotlight
	adder.spotlit = false
	var g := make_game([adder_card], [[]], [[]])

	var cols_before := g.state.lower_zone.size()
	await g.skill_spotlight_check()
	check(adder.spotlit, "rules-deck adder activates")
	check(g.state.lower_zone.size() == cols_before + 1 \
			and g.state.lower_zone_type.size() == g.state.lower_zone.size(),
			"activation adds one column, zone and type arrays in lockstep")
	check(g.state.lower_zone_type[-1].type is TypeInput,
			"the added column's header is an input slot")
	check(g.state.validate().is_empty(), "board validates after zone add")

#deactivation removes the column and discards whatever sat in it.
#The card must stay in SOME collection (here: the discard pile) — a card in no
#collection is never visited, so its deactivation edge could never fire.
	var stranded := play_card(8, 1)
	g.state.lower_zone[-1].datas.append(stranded)
	g.state.revision += 1
	g.state.rules_deck.erase(adder_card)
	g.state.discard_deck.append(adder_card)
	adder_card.stage = CardData.Stage.DISCARD
	g.state.revision += 1
	await g.skill_spotlight_check()
	check(not adder.spotlit, "adder deactivates when it leaves the rules deck")
	check(g.state.lower_zone.size() == cols_before \
			and g.state.lower_zone_type.size() == cols_before,
			"deactivation removes exactly its column, lockstep kept")
	check(g.state.discard_deck.has(stranded) and stranded.stage == CardData.Stage.DISCARD,
			"cards stranded in the removed column go to the discard pile")
	check(g.state.validate().is_empty(), "board validates after zone remove")

#Pin: deactivating when the column is ALREADY gone must not eat another column
	g.state.discard_deck.erase(adder_card)
	g.state.rules_deck.append(adder_card)
	adder_card.stage = CardData.Stage.RULES
	g.state.revision += 1
#re-activate: adds a column again
	await g.skill_spotlight_check()
	var manual := g.state.lower_zone_type.find(adder.card_data)
	Board.remove_column(g.state, g.state.lower_zone, g.state.lower_zone_type, manual)
	var cols_now := g.state.lower_zone.size()
	g.state.rules_deck.erase(adder_card)
	g.state.discard_deck.append(adder_card)
	adder_card.stage = CardData.Stage.DISCARD
	g.state.revision += 1
	await g.skill_spotlight_check()
	check_impl(g.state.lower_zone.size() == cols_now,
			"B6: deactivate after the column was already removed is a no-op",
			"cols %d -> %d" % [cols_now, g.state.lower_zone.size()])
	check_impl(g.state.validate().is_empty(), "board still validates after B6 path")
	done(g)


# ==============================================================================
# SECTION 6: TRIGGER STAMPS/SKILLS — double trigger, echo, termination
# ==============================================================================

## A skill that counts its firings and reports each one to the trigger system, exactly like SkillExtraPoint's on_score does.
class SpyTriggerSkill extends CardModifierSkill:
	var calls := 0
	func get_str() -> String: return "SpyTrigger"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func fire() -> void:
		calls += 1
		if env:
			await env.on_mod_triggered(data, fire)

func run_trigger_tests() -> void:
	behavior_section("SECTION 6: TRIGGER REPETITION")

#StampDoubleTrigger: the card's effect runs exactly twice per scoring pass
	var spy := SpyTriggerSkill.new()
	var carrier := rules_card(spy).with_stamp(StampDoubleTrigger.new())
	var g := make_game([carrier], [[]], [[]])
	await spy.fire()
	check(spy.calls == 2, "double trigger: effect runs exactly twice", "calls %d" % spy.calls)
	await g.run_all_mods(&"on_after_score")
	await spy.fire()
	check(spy.calls == 4, "double trigger resets after scoring (twice again)",
			"calls %d" % spy.calls)
	done(g)

#SkillEchoingTrigger: every OTHER skill's trigger repeats once per pass
	spy = SpyTriggerSkill.new()
	var echo_card := rules_card(SkillEchoingTrigger.new())
	g = make_game([echo_card, rules_card(spy)], [[]], [[]])
	await spy.fire()
	check(spy.calls == 2, "echoing trigger: effect echoed once", "calls %d" % spy.calls)
	await spy.fire()
	check(spy.calls == 3, "already-echoed card is not echoed again within the pass",
			"calls %d" % spy.calls)
	await g.run_all_mods(&"on_after_score")
	await spy.fire()
	check(spy.calls == 5, "echo memory clears after scoring", "calls %d" % spy.calls)
	done(g)

#PIN: echo + double trigger on the same board terminates (no infinite loop) and
#lands on exactly 3 firings: 1 direct + 1 double + 1 echo.
	spy = SpyTriggerSkill.new()
	var both := rules_card(spy).with_stamp(StampDoubleTrigger.new())
	g = make_game([rules_card(SkillEchoingTrigger.new()), both], [[]], [[]])
	await spy.fire()
	check_impl(spy.calls == 3,
			"PIN: echo + double trigger terminate at 3 total firings",
			"calls %d" % spy.calls)
	done(g)


# ==============================================================================
# SECTION 7: BOOSTER GENERATION (TypeBoosterBasic)
# ==============================================================================
func run_booster_tests() -> void:
	behavior_section("SECTION 7: BOOSTER GENERATION")
#RunManager.run is null here -> luck 0 -> no lucky extras, base type only
	var booster := TypeBoosterBasic.new()
	var all_valid := true
	var no_lucky_extras := true
	for i in 20:
		var card : CardData = await booster.create_one_choice()
		if not (card.rank is PipRankNumeral and card.rank.value >= 1 and card.rank.value <= 13 \
				and card.suit is PipSuit and PipSuit.STANDARD.has(card.suit.get_script())):
			all_valid = false
		if card.stamp != null or card.skill != null or not (card.type is TypePaper):
			no_lucky_extras = false
	check(all_valid, "every generated card is a playable rank 1-13 / standard-suit card")
	check(no_lucky_extras, "at luck 0 cards carry only the base type, no stamp/skill")


# ==============================================================================
# SECTION 8: SHUFFLE (Game.shuffle_deck) — determinism + on_append contract
# ==============================================================================

## Type mod that counts on_append dispatches and keeps its own card on top of the deck (Heavy-card style reordering through the sanctioned hook).
class SpyAppendFront extends CardModifierType:
	var append_calls := 0
	func get_str() -> String: return "SpyAppend"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_append(deck: Array[CardData], appended: CardData) -> void:
		append_calls += 1
		if appended == data:
			deck.erase(data)
			deck.insert(0, data)

func run_shuffle_tests() -> void:
	behavior_section("SECTION 8: SHUFFLE")
	var g := make_game([], [[]], [[]])
	for i in 10:
		var c := TestFactories.m_card(i + 1, TestFactories.uc())
		c.stage = CardData.Stage.DRAW
		g.state.entrance_stocks()[0].datas.append(c)
	var deck := g.stock_for_slot(0)
	var original := deck.duplicate()

#same seed -> same order (a seeded shuffle is reproducible for debugging/replays)
	seed(777)
	await g.shuffle_deck(deck)
	var first_order := deck.duplicate()
	deck.assign(original)
	seed(777)
	await g.shuffle_deck(deck)
	check(deck == first_order, "same seed shuffles to the same order")
	check(deck.size() == 10, "shuffle preserves deck size")

#an on_append mod may reorder the deck as it rebuilds: the spy pins its card on top
	var spy := SpyAppendFront.new()
	deck[5].with_type(spy)
	var modded := deck[5]
	g.state.revision += 1
	await g.shuffle_deck(deck)
	check(deck[0] == modded, "on_append mod controls its card's final spot")
	check(spy.append_calls == 10, "on_append fires once per appended card",
			"calls %d" % spy.append_calls)
	var seen := {}
	var dup := false
	for c in deck:
		if seen.has(c): dup = true
		seen[c] = true
	check(deck.size() == 10 and not dup,
			"reordering mod keeps the deck duplicate-free and complete")
	done(g)

# ==============================================================================
# SECTION 9: THE IMPLEMENTER CACHE - a modifier attached with no board mutation is seen
# ==============================================================================

const PROBE_HOOK := &"on_cache_probe"

class ProbeSkill extends CardModifierSkill:
	func get_str() -> String: return "ProbeSkill"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_cache_probe() -> void: pass

class ProbeType extends CardModifierType:
	var calls : int = 0
	var drops : CardModifierStatus = null
	func get_str() -> String: return "ProbeType"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_cache_probe() -> void:
		calls += 1
		if drops: data.add_status(drops)

class ProbeStamp extends CardModifierStamp:
	func get_str() -> String: return "ProbeStamp"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_cache_probe() -> void: pass

class ProbeStatus extends CardModifierStatus:
	var calls : int = 0
	func get_str() -> String: return "ProbeStatus"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_cache_probe() -> void: calls += 1

#Asked right after one attach or removal, with the hook's list already built at this revision by the
#ask before it, so only that one change can move the answer.
func check_the_next_ask(g: Game, mod: CardModifier, listed: bool, revision: int, what: String) -> void:
	check_impl(g.active_implementers(PROBE_HOOK).has(mod) == listed,
			"%s is %s by the next ask for its hook" % [what, "seen" if listed else "dropped"])
	check_impl(g.state.revision == revision,
			"%s never bumps the board revision" % what,
			"revision %d, was %d" % [g.state.revision, revision])

#⚠ The revision stays put across every step: a bump mid-cascade rebuilds the board, so the cache
#has to notice a modifier arriving or leaving on its own.
func run_implementer_cache_tests() -> void:
	implementation_section("SECTION 9: THE IMPLEMENTER CACHE")
	var card := play_card(5, 1)
	var g := make_game([], [[]], [[card]])
	var revision := g.state.revision
	check_impl(g.active_implementers(PROBE_HOOK).is_empty(),
			"a plain board has no implementer of the probe hook, and that answer is now cached")
	var probe_skill := ProbeSkill.new()
	probe_skill.spotlit = true
	card.with_skill(probe_skill)
	check_the_next_ask(g, probe_skill, true, revision, "a skill set on a board card")
	var probe_type := ProbeType.new()
	card.with_type(probe_type)
	check_the_next_ask(g, probe_type, true, revision, "a type set on a board card")
	var probe_stamp := ProbeStamp.new()
	card.with_stamp(probe_stamp)
	check_the_next_ask(g, probe_stamp, true, revision, "a stamp set on a board card")
	var probe_status := ProbeStatus.new()
	card.add_status(probe_status)
	check_the_next_ask(g, probe_status, true, revision, "a status added to a board card")
	card.remove_status(probe_status)
	check_the_next_ask(g, probe_status, false, revision, "a status removed from a board card")
	done(g)

#The first card's handler attaches a status to its own card while the broadcast is still walking:
#that walk asks the modifiers each card had when it reached it, and the next ask lists the newcomer.
func run_attach_mid_walk_test() -> void:
	implementation_section("SECTION 9: AN ATTACH DURING THE WALK")
	var first := play_card(5, 1)
	var second := play_card(6, 2)
	var g := make_game([], [[]], [[first, second]])
	var dropper := ProbeType.new()
	var late := ProbeStatus.new()
	dropper.drops = late
	first.with_type(dropper)
	var witness := ProbeType.new()
	second.with_type(witness)
	await g.run_all_mods(PROBE_HOOK)
	check_impl(dropper.calls == 1 and witness.calls == 1,
			"a status attached by a handler leaves the walk in progress whole: each card asked once",
			"dropper %d witness %d" % [dropper.calls, witness.calls])
	check_impl(late.calls == 0,
			"the walk that attached the status does not ask it", "calls %d" % late.calls)
	check_impl(g.active_implementers(PROBE_HOOK).has(late),
			"the status attached during the walk is listed by the next ask")
	done(g)
