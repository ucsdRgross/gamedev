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
	finish()

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
	var viewer := ChoiceViewer.add_to_scene(self, _card, 5, 0)
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
