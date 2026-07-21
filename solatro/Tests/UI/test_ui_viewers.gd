extends TestSuite
# res://Tests/UI/test_ui_viewers.gd
# ==============================================================================
# UI VIEWERS — regression tests for the playtest bugs of 2026-07:
#   * DeckViewer stacking (Enter on a still-focused button opened endless copies)
#   * ControlCards not keyboard-focusable (arrow keys dead in viewers)
#   * ChoiceViewer take-all wiring + deferred population
#   * CardVisual partial-card rendering (rank-only colored / suit-only art square)
#   * describe_card inspector text
#
# CATEGORY MAP: all BEHAVIOR — every check here is something the player saw go
# wrong in a playtest (stacked viewers, dead keyboard, broken card art/text).
# ==============================================================================

func suite_name() -> String:
	return "UI VIEWERS"

func _ready() -> void:
	TestLog.line("============ UI VIEWERS TEST PASS ============")
	behavior_section("VIEWER & CARD RENDERING REGRESSIONS")
	await test_deck_viewer_singleton()
	await test_control_card_focus()
	test_describe_card()
	await test_choice_viewer_take_all()
	await test_partial_card_rendering()
	await test_booster_rerolls()
	await test_booster_pool_comes_from_settings()
	finish()

## A dummy pack. It overrides create_one_choice so a roll needs no RunManager.run (the real one
## goes through luck(), which dereferences a null run in a bare test), while still driving the
## REAL on_map_picked -> ChoiceViewer path — which is where booster_reroll_pool is read.
class StubBooster extends BoosterTemplate:
	func get_str() -> String: return "StubPack"
	func get_description() -> String: return "a test pack"
	func get_frame() -> int: return 3
	func get_possible_ranks() -> Array[PipRank]: return [] as Array[PipRank]
	func get_possible_suits() -> Array[PipSuit]: return [] as Array[PipSuit]
	func get_possible_stamps() -> Array[CardModifierStamp]: return [] as Array[CardModifierStamp]
	func get_possible_skills() -> Array[CardModifierSkill]: return [] as Array[CardModifierSkill]
	func get_possible_types() -> Array[CardModifierType]: return [] as Array[CardModifierType]
	func create_one_choice() -> CardData:
		return CardData.new().with_rank(PipRankNumeral.new().with_value(5))

func _card() -> CardData:
	return CardData.new().with_rank(PipRankNumeral.new().with_value(5)) \
			.with_suit(PipSuitKnife.new())

func _count_viewers() -> int:
	var n := 0
	for child in get_children():
		if child is DeckViewer and not child.is_queued_for_deletion():
			n += 1
	return n

func test_deck_viewer_singleton() -> void:
	var deck: Array[CardData] = [_card()]
	DeckViewer.show_deck(self, deck)
	DeckViewer.show_deck(self, deck)
	DeckViewer.show_deck(self, deck)
	await get_tree().process_frame
	check(_count_viewers() == 1, "repeated show_deck replaces instead of stacking",
			"live viewers: %d" % _count_viewers())
	if is_instance_valid(DeckViewer._open):
		DeckViewer._open.queue_free()
	await get_tree().process_frame

func test_control_card_focus() -> void:
	var control := ControlCard.add_child_control_card(
		self, _card(), CardVisual.DisplayContext.DECK_VIEWER)
	await get_tree().process_frame
	check(control.focus_mode == Control.FOCUS_ALL, "preview cards are keyboard-focusable")
	control.grab_focus()
	await get_tree().process_frame
	check(control.child != null and control.child.focused,
			"focusing a card lights its visual like a mouse hover")
	control.queue_free()
	await get_tree().process_frame

func test_describe_card() -> void:
	# Use TypeHeavy (a NAMED type) — TypePaper's get_str() is "" and describe_card skips
	# nameless modifiers, so it can't be asserted with contains().
	var data := _card().with_skill(SkillExtraPoint.new()).with_stamp(StampGlobal.new()) \
			.with_type(TypeHeavy.new())
	var text := ControlCard.describe_card(data)
	check(text.contains(SkillExtraPoint.new().get_str()) \
			and text.contains(StampGlobal.new().get_str()) \
			and text.contains(TypeHeavy.new().get_str()),
			"describe_card names every modifier", text)
	check(text.contains(SkillExtraPoint.new().get_description()),
			"describe_card includes the modifier descriptions")
	# Nameless types must not add a blank " — " line. Suitless card so the (now described)
	# suit line doesn't introduce a legitimate "—" and confound the assertion.
	var paper := CardData.new().with_type(TypePaper.new())
	check(not ControlCard.describe_card(paper).contains("—"),
			"nameless type produces no blank modifier line")

func test_choice_viewer_take_all() -> void:
	var viewer : ChoiceViewer = await ChoiceViewer.add_to_scene(self, _card, 5, 0)
	await get_tree().process_frame
	await get_tree().process_frame  # population is deferred one frame (fly-in fix)
	var cards := 0
	for child in viewer.flex_container.get_children():
		if child is ControlCard:
			cards += 1
	check(cards == 5, "viewer shows every generated card", "cards: %d" % cards)
	# GDScript lambdas capture locals by VALUE — `got = taken` inside the lambda would not
	# escape. Mutate the shared array in place (arrays are reference-typed) so the outer
	# `got` sees the result.
	var got: Array[CardData] = []
	viewer.confirmed.connect(func(taken: Array[CardData]) -> void: got.assign(taken))
	viewer._on_confirm_pressed()
	check(got.size() == 5, "Take all confirms every card")
	check(viewer.is_queued_for_deletion(), "viewer frees itself after confirming")
	await get_tree().process_frame

## Booster rerolls (2026-07-20): a pack opens with a SHARED pool of free rerolls; each slot's
## Reroll re-rolls that slot through the same generator, spending from the one pool, and the
## buttons gray out at zero. Driven through the data API (reroll()) — the buttons are thin
## wrappers over it.
func test_booster_rerolls() -> void:
	# A stub generator that marks every card it makes, so a rerolled slot is identifiable.
	var made : Array[CardData] = []
	var generate := func() -> CardData:
		var c := _card().with_type(TypeHeavy.new())
		made.append(c)
		return c
	var viewer : ChoiceViewer = await ChoiceViewer.add_to_scene(self, generate, 3, 0, 2)
	await get_tree().process_frame
	await get_tree().process_frame
	check(viewer.data.rerolls == 2, "the viewer opens with the pool it was given",
			str(viewer.data.rerolls))
	var original : CardData = viewer.data.current_choices[0]
	check(await viewer.reroll(0), "reroll(0) succeeds while the pool has charges")
	check(viewer.data.current_choices[0] != original and viewer.data.current_choices[0] == made[-1],
			"the slot now holds a card fresh from create_one_choice")
	check(viewer.data.rerolls == 1, "a reroll spends one from the pool", str(viewer.data.rerolls))
	check(viewer.data.current_choices.size() == 3, "rerolling replaces, never adds or drops")
	# the pool is SHARED: a different slot draws from the same counter, then it is empty
	check(await viewer.reroll(2), "another slot spends the SAME shared pool")
	check(viewer.data.rerolls == 0, "the shared pool is now empty", str(viewer.data.rerolls))
	check(not await viewer.reroll(1), "reroll fails once the pool is empty")
	await get_tree().process_frame
	var all_disabled := true
	for button : Button in viewer._reroll_buttons:
		if not button.disabled: all_disabled = false
	check(all_disabled, "every Reroll button grays out at zero")
	check(not await viewer.reroll(99), "an out-of-range slot index is rejected")
	viewer.queue_free()
	await get_tree().process_frame

## The pool is owner-tunable, not a hardcoded 5: on_map_picked must read
## settings.booster_reroll_pool. Driven at a NON-default value and at 0 (rerolls switched off
## entirely — every button dead from the moment the pack opens).
func test_booster_pool_comes_from_settings() -> void:
	backup_real_settings()
	# scoped to "booster_": the live settings are shared with the suites running alongside us
	var snap := snapshot_settings("booster_")
	var pack := StubBooster.new()
	SettingsManager.settings.booster_reroll_pool = 4
	var viewer : ChoiceViewer = await pack.on_map_picked(self)
	await get_tree().process_frame
	await get_tree().process_frame
	check(viewer.data.rerolls == 4, "on_map_picked seeds the pool from booster_reroll_pool",
			str(viewer.data.rerolls))
	check(viewer.data.current_choices.size() == pack.get_frame(),
			"the pack still shows get_frame() cards", str(viewer.data.current_choices.size()))
	viewer.queue_free()
	await get_tree().process_frame
	SettingsManager.settings.booster_reroll_pool = 0
	var viewer0 : ChoiceViewer = await pack.on_map_picked(self)
	await get_tree().process_frame
	await get_tree().process_frame
	check(viewer0.data.rerolls == 0, "a 0 pool opens with no rerolls", str(viewer0.data.rerolls))
	check(not await viewer0.reroll(0), "reroll is refused outright at a 0 pool")
	var all_disabled := true
	for button : Button in viewer0._reroll_buttons:
		if not button.disabled: all_disabled = false
	check(all_disabled, "every Reroll button is disabled from the start at a 0 pool")
	viewer0.queue_free()
	await get_tree().process_frame
	restore_settings_snapshot(snap)
	restore_real_settings()

func test_partial_card_rendering() -> void:
	# Rank-only (suitless) preview cards must render uncolored; suit-only (rankless)
	# cards must not show the art polygon (it degenerates to a colored square).
	var rank_only := ControlCard.add_child_control_card(
		self, CardData.new().with_rank(PipRankNumeral.new().with_value(4)),
		CardVisual.DisplayContext.DECK_VIEWER)
	var suit_only := ControlCard.add_child_control_card(
		self, CardData.new().with_suit(PipSuitKnife.new()),
		CardVisual.DisplayContext.DECK_VIEWER)
	await get_tree().process_frame
	await get_tree().process_frame
	rank_only.child.show_front = true
	suit_only.child.show_front = true
	check(rank_only.child.rank.material == null, "suitless card renders its rank uncolored")
	check(not suit_only.child.art.visible, "rankless card shows no art polygon")
	rank_only.queue_free()
	suit_only.queue_free()
	await get_tree().process_frame
