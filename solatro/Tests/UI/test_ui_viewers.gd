extends TestSuite
# res://Tests/UI/test_ui_viewers.gd
# ==============================================================================
# UI VIEWERS — regression tests for the playtest bugs of 2026-07:

# * DeckViewer stacking (Enter on a still-focused button opened endless copies)
# * ControlCards not keyboard-focusable (arrow keys dead in viewers)
# * ChoiceViewer take-all wiring + deferred population

# * CardVisual partial-card rendering (rank-only colored / suit-only art square)
# * describe_card inspector text

# CATEGORY MAP: all BEHAVIOR — every check here is something the player saw go
# wrong in a playtest (stacked viewers, dead keyboard, broken card art/text).
# ==============================================================================

func suite_name() -> String:
	return "UI VIEWERS"

func _ready() -> void:
	TestLog.line("============ UI VIEWERS TEST PASS ============")
	check_all_tests_registered()
	_focus_window = _open_focus_window()
	behavior_section("VIEWER & CARD RENDERING REGRESSIONS")
	await test_deck_viewer_singleton()
	await test_control_card_focus()
	test_describe_card()
	await test_choice_viewer_take_all()
	await test_partial_card_rendering()
	await test_booster_rerolls()
	await test_booster_pool_comes_from_settings()
	await test_pack_click_selects()
	await test_take_ignores_the_selection()
	behavior_section("THE VIEWER IS MODAL: HOVER DESCRIBES, A CLICK STICKS")
	await test_a_hover_describes_a_viewer_card_and_a_click_sticks_it()
	await test_a_later_hover_borrows_the_description_and_gives_it_back()
	await test_a_sticky_description_puts_the_packs_buttons_beyond_reach()
	await test_a_click_on_a_listed_card_never_closes_the_viewer()
	await test_cancel_unsticks_before_it_closes()
	await test_an_arrow_off_the_lists_edge_never_reaches_the_screen_beneath()
	await test_an_edge_arrow_asks_for_the_sidebar_only_while_a_card_is_stuck()
	await test_the_same_opener_pressed_again_closes_the_viewer()
	await test_a_viewer_opened_over_another_leaves_it_open_beneath()
	await test_the_pack_chooser_passes_a_cancel_on_once_nothing_is_stuck()
	await test_a_viewer_opens_with_nothing_focused_and_nothing_published()
	await test_the_first_navigation_press_enters_the_list()
	await test_the_pack_chooser_draws_only_a_square_window()
	await test_a_sixth_card_wraps_to_a_centred_row_of_its_own()
	await test_a_wrapped_row_lies_below_the_reroll_buttons_above()
	await test_the_window_shows_five_rows_then_scrolls()
	await test_each_reroll_text_centres_under_its_drawn_card()
	await test_a_deck_viewer_carries_a_close_tab_and_the_pack_chooser_none()
	behavior_section("A VIEWER SPACES ITS CARDS AS THE BOARD DOES, IN THE PLAYER'S WINDOW")
	await test_the_viewers_gap_is_the_boards_at_their_card_scale()
	await test_the_deck_viewers_list_is_whole_columns_centred()
	await test_a_deck_viewers_rows_stand_the_gap_inside_its_window()
	_focus_window.queue_free()
	finish()

## The window the rows that read a focus across a frame host their cards in.
var _focus_window : Window = null

# GUI focus is one per WINDOW: a grab in any viewport of the root window, a SubViewport-booted Main
# of a suite running alongside included, clears every other focus there. Outside the root's rect it
# shows nothing and no pointer lands in it; unfocusable, it never takes the root's keys.
func _open_focus_window() -> Window:
	var window := Window.new()
	window.unfocusable = true
	window.size = get_tree().root.size
	window.position = -window.size
	add_child(window)
	return window

## Every deck viewer carries its close tab; the pack chooser carries none, Take being its only way out.
func test_a_deck_viewer_carries_a_close_tab_and_the_pack_chooser_none() -> void:
	var published : Array[String] = []
	var viewer := _two_card_viewer(published)
	await get_tree().process_frame
	var tab := viewer.get_node_or_null(^"%CloseTab") as Button
	check(tab != null and tab.is_visible_in_tree(), "a deck viewer carries a visible close tab")
	var tab_text := tab.text if tab else ""
	await _drop_viewer(viewer)
	var chooser : ChoiceViewer = await ChoiceViewer.add_to_scene(self, _card, 3, 0)
	await get_tree().process_frame
	var named : Array[String] = []
	for button : Node in chooser.find_children("*", "Button", true, false):
		named.append((button as Button).text)
	check(chooser.find_children("CloseTab", "", true, false).is_empty()
			and not named.has(tab_text),
			"...and the pack chooser carries none", str(named))
	chooser.queue_free()
	await get_tree().process_frame

## A viewer opens with no card focused and nothing published: a focus is a highlight, and a highlight would hold the sidebar against the HUD the player still has to reach.
func test_a_viewer_opens_with_nothing_focused_and_nothing_published() -> void:
	var published : Array[String] = []
	var viewer := _two_card_viewer(published)
	await get_tree().process_frame
	await get_tree().process_frame
	check(published.is_empty(), "opening a viewer publishes no description at all", str(published))
	var focused := 0
	for control : ControlCard in viewer._cards.controls:
		if control.has_focus(): focused += 1
	check(focused == 0, "...and leaves no listed card focused", str(focused))
	await _drop_viewer(viewer)

## The first navigation press is what enters the list -- it lands on the first card, and the list keeps the press.
func test_the_first_navigation_press_enters_the_list() -> void:
	var published : Array[String] = []
	var viewer := _two_card_viewer(published)
	await get_tree().process_frame
	check(viewer._cards.modal_verdict(_action_event(&"ui_right")) == CardsViewer.Modal.KEEP,
			"the first arrow is kept by the viewer")
	check(viewer._cards.controls[0].has_focus(),
			"...and lands on its first card", str(viewer._cards.controls[0].has_focus()))
	check(published.size() == 1, "...which publishes that card, once", str(published))
	viewer._cards.controls[1].grab_focus()
	await get_tree().process_frame
	check(not viewer._cards.focus_first(),
			"a later arrow never drags the focus back to the first card")
	await _drop_viewer(viewer)

## The pack chooser draws only its square window, so the picture around it shows through; harness-scale only.
func test_the_pack_chooser_draws_only_a_square_window() -> void:
	var viewer : ChoiceViewer = await ChoiceViewer.add_to_scene(self, _card, 3, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	var drawn : Array[String] = []
	for child : Node in viewer.get_children():
		if child is CanvasItem: drawn.append(String(child.name))
	check(drawn == ["Layout"], "the chooser draws nothing but its window", str(drawn))
	var picture := viewer.get_viewport_rect()
	viewer.fit_beside(picture)
	await get_tree().process_frame
	var window := (viewer.get_node(^"Layout") as Control).get_global_rect()
	check(is_equal_approx(window.size.x, window.size.y) and picture.encloses(window)
			and window.size.x < picture.size.y,
			"fitted to a picture with room, the window is a square smaller than it",
			"%s in %s" % [window, picture])
	var rerolls := viewer.rerolls_label.get_global_rect()
	var take := viewer.confirm_button.get_global_rect()
	check(absf(rerolls.get_center().y - take.get_center().y) < 0.5
			and rerolls.end.x <= take.position.x and window.encloses(rerolls),
			"Rerolls sits beside Take in the window's one foot row", "%s vs %s" % [rerolls, take])
	viewer.queue_free()
	await get_tree().process_frame

## Half a pixel either side: a container places its children on whole pixels.
const CENTRED_TOLERANCE_PX := 1.0

## The chooser's window holds one full row of cards; a sixth wraps to a row of its own, centred like the rest, and Rerolls and Take centre as a pair; harness-scale only.
func test_a_sixth_card_wraps_to_a_centred_row_of_its_own() -> void:
	var viewer : ChoiceViewer = await ChoiceViewer.add_to_scene(self, _card, 6, 0)
	await get_tree().process_frame
	viewer.fit_beside(viewer.get_viewport_rect())
	await get_tree().process_frame
	await get_tree().process_frame
	var window := (viewer.get_node(^"Layout") as Control).get_global_rect()
	var rects : Array[Rect2] = []
	for control : ControlCard in viewer._cards.controls:
		rects.append(control.get_global_rect())
	var first_row := rects[0]
	for i : int in range(1, 5):
		first_row = first_row.merge(rects[i])
	check(rects.size() == 6 and is_equal_approx(first_row.size.y, rects[0].size.y)
			and rects[5].position.y > first_row.end.y - 0.5,
			"five cards fill the first row and the sixth wraps below it", str(rects))
	for row : Rect2 in [first_row, rects[5]] as Array[Rect2]:
		check(absf(row.get_center().x - window.get_center().x) <= CENTRED_TOLERANCE_PX,
				"...each row centred in the window", "%s in %s" % [row, window])
	var pair := viewer.rerolls_label.get_global_rect().merge(viewer.confirm_button.get_global_rect())
	check(absf(pair.get_center().x - window.get_center().x) <= CENTRED_TOLERANCE_PX,
			"Rerolls and Take centre in the window as a pair", "%s in %s" % [pair, window])
	viewer.queue_free()
	await get_tree().process_frame

## A wrapped row starts below the Reroll buttons hanging under the row above, never over them; harness-scale only.
func test_a_wrapped_row_lies_below_the_reroll_buttons_above() -> void:
	var viewer := await _fitted_chooser(ChoiceViewer.ROW_CARDS + 1, Rect2(Vector2.ZERO, Vector2.ONE * 4000.0))
	var wrapped := viewer._cards.controls[ChoiceViewer.ROW_CARDS].get_global_rect()
	for index : int in ChoiceViewer.ROW_CARDS:
		var reroll := viewer._reroll_buttons[index].get_global_rect()
		check(wrapped.position.y >= reroll.end.y - 0.5,
				"the wrapped row starts below slot %d's Reroll button above it" % index,
				"%s vs %s" % [wrapped, reroll])
	viewer.queue_free()
	await get_tree().process_frame

## Half a window pixel either side: at content scale 1 a UI pixel is one window pixel.
const REROLL_CENTRED_TOLERANCE_PX := 0.5

## Each slot's Reroll text sits centred under its card as the card is DRAWN, its art, not its slot; harness-scale only.
func test_each_reroll_text_centres_under_its_drawn_card() -> void:
	var viewer := await _fitted_chooser(ChoiceViewer.ROW_CARDS + 1, get_tree().root.get_visible_rect())
	for index : int in viewer._cards.controls.size():
		var drawn := _drawn_card_in_window((viewer._cards.controls[index] as ControlCard).child)
		var text := _button_text_in_window(viewer._reroll_buttons[index])
		check(absf(text.get_center().x - drawn.get_center().x) <= REROLL_CENTRED_TOLERANCE_PX,
				"slot %d's Reroll text centres under its drawn card" % index,
				"text %s vs drawn card %s" % [text, drawn])
	viewer.queue_free()
	await get_tree().process_frame

## A card's drawn box in window pixels: its type polygon's own points through its canvas transform.
func _drawn_card_in_window(card: CardVisual) -> Rect2:
	var to_window := get_tree().root.get_final_transform() * card.type.get_global_transform_with_canvas()
	var points := to_window * card.type.polygon
	var box := Rect2(points[0], Vector2.ZERO)
	for point : Vector2 in points:
		box = box.expand(point)
	return box

## A button's text as the engine lays it out, in window pixels: the font's string width, centred in the content box its stylebox leaves.
func _button_text_in_window(button: Button) -> Rect2:
	assert(button.alignment == HORIZONTAL_ALIGNMENT_CENTER)
	var style := button.get_theme_stylebox(&"normal")
	var content := Rect2(Vector2(style.get_margin(SIDE_LEFT), 0.0),
			button.size - Vector2(style.get_margin(SIDE_LEFT) + style.get_margin(SIDE_RIGHT), 0.0))
	var width := button.get_theme_font(&"font").get_string_size(button.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size(&"font_size")).x
	var local := Rect2(content.get_center().x - width / 2.0, 0.0, width, button.size.y)
	return get_tree().root.get_final_transform() * button.get_global_transform_with_canvas() * local

## With room, the window grows to show ROWS_SHOWN full rows; one more row scrolls inside the same window, and a space too short for them cuts the window to it with the rest scrolling -- five cards to a row throughout; harness-scale only.
func test_the_window_shows_five_rows_then_scrolls() -> void:
	var room := Rect2(Vector2.ZERO, Vector2.ONE * 4000.0)
	var full := ChoiceViewer.ROW_CARDS * ChoiceViewer.ROWS_SHOWN
	var five := await _fitted_chooser(full, room)
	var shown := five._scroll.get_global_rect().grow(0.5)
	check(five._cards.controls.all(func(card: ControlCard) -> bool: return shown.encloses(card.get_global_rect())),
			"%d cards show whole in the window, nothing to scroll" % full, str(shown))
	check(_cards_in_the_first_row(five) == ChoiceViewer.ROW_CARDS,
			"...five of them to a row", str(_cards_in_the_first_row(five)))
	var six := await _fitted_chooser(full + 1, room)
	var scroll := six._scroll
	var last := six._cards.controls[full]
	check(is_equal_approx(scroll.size.y, five._scroll.size.y)
			and not scroll.get_global_rect().grow(0.5).encloses(last.get_global_rect()),
			"a sixth row leaves the window at five rows' height, the new row out of view",
			"%s vs %s, last %s" % [scroll.size, five._scroll.size, last.get_global_rect()])
	scroll.scroll_vertical = int(six.flow_container.size.y)
	await get_tree().process_frame
	await get_tree().process_frame
	check(scroll.get_global_rect().grow(0.5).encloses(last.get_global_rect()),
			"...and scrolling the window brings it into view", str(last.get_global_rect()))
	var cut := await _fitted_chooser(full, Rect2(Vector2.ZERO, Vector2(4000.0, 500.0)))
	var window := (cut.get_node(^"Layout") as Control).get_global_rect()
	check(window.size.y <= 500.0 + 0.5 and cut.flow_container.size.y > cut._scroll.size.y
			and _cards_in_the_first_row(cut) == ChoiceViewer.ROW_CARDS,
			"a space too short for five rows cuts the window to it, five to a row, the rest scrolling",
			"%s, content %s in %s" % [window, cut.flow_container.size, cut._scroll.size])
	for viewer : ChoiceViewer in [five, six, cut] as Array[ChoiceViewer]:
		viewer.queue_free()
	await get_tree().process_frame

## A container places its children on whole canvas pixels, which the window's UI scale can carry a fraction of a window pixel off.
const GAP_TOLERANCE_PX := 0.5

# Measured in the ROOT window: no suite resizes the OS window the others share, and the run keeps it at
# the project's base size, content scale 1 as in a SubViewport. Other window sizes are shots.
## The gap between two listed cards, a row's and a column's, is the board's gap in art units at the card's own drawn scale -- in the deck viewer and in the pack chooser, where it sits below each row's Reroll band; harness-scale only.
func test_the_viewers_gap_is_the_boards_at_their_card_scale() -> void:
	var size := get_tree().root.size
	var visible := get_tree().root.get_visible_rect()
	var viewer := await _fitted_deck_viewer(20, visible)
	var cards := viewer.cards().controls
	var per_row := _cards_in_the_first_row_of(cards)
	var first := _in_window(cards[0])
	var gap := PlayArea.BOARD_SEPARATION * first.size.x / CardVisual.CARD_SIZE.x
	check(per_row >= 2 and cards.size() > per_row,
			"sanity: the deck viewer at %s shows a row and a second below it" % size, str(per_row))
	var across := _in_window(cards[1]).position.x - first.end.x
	var down := _in_window(cards[per_row]).position.y - first.end.y
	check(absf(across - gap) <= GAP_TOLERANCE_PX and absf(down - gap) <= GAP_TOLERANCE_PX,
			"the deck viewer's cards stand the board's gap apart, across and down, at its card scale (%s)" % size,
			"across %.2f down %.2f vs %.2f window px" % [across, down, gap])
	await _drop_viewer(viewer)
	var chooser := await _fitted_chooser(ChoiceViewer.ROW_CARDS + 1, visible)
	var slot := _in_window(chooser._cards.controls[0])
	var beside := _in_window(chooser._cards.controls[1]).position.x - slot.end.x
	var under_band := _in_window(chooser._cards.controls[ChoiceViewer.ROW_CARDS]).position.y \
			- _in_window(chooser._reroll_buttons[0]).end.y
	check(absf(beside - gap) <= GAP_TOLERANCE_PX and absf(under_band - gap) <= GAP_TOLERANCE_PX,
			"the chooser's cards stand the board's gap apart, and a wrapped row the same gap under the Reroll band above (%s)" % size,
			"beside %.2f under the band %.2f vs %.2f window px" % [beside, under_band, gap])
	chooser.queue_free()
	await get_tree().process_frame

# Measured in the ROOT window, at content scale 1 like the rows above; other window sizes are shots.
## The deck viewer's list is the widest whole number of columns its margins leave room for, centred where it rests: no strip narrower than a card is left on one side, beside a sidebar or over the whole picture; harness-scale only.
func test_the_deck_viewers_list_is_whole_columns_centred() -> void:
	var size := get_tree().root.size
	var visible := get_tree().root.get_visible_rect()
	var strip := Vector2(visible.size.x / 3.0, 0.0)
	var beside_a_strip := Rect2(visible.position + strip, visible.size - strip)
	for remaining : Rect2 in [visible, beside_a_strip] as Array[Rect2]:
		var viewer := await _fitted_deck_viewer(52, remaining)
		var where := "%s resting in %s" % [size, remaining]
		var cards := viewer.cards().controls
		var columns := _cards_in_the_first_row_of(cards)
		var row := _in_window(cards[0]).merge(_in_window(cards[columns - 1]))
		var list := _in_window(viewer.flow_container)
		check(absf(list.size.x - row.size.x) <= GAP_TOLERANCE_PX,
				"the deck viewer's list is exactly its whole columns wide (%s)" % where,
				"list %.2f vs %d columns %.2f window px" % [list.size.x, columns, row.size.x])
		var scale := get_tree().root.get_final_transform().get_scale().x
		var resting := get_tree().root.get_final_transform() * remaining
		var bar := viewer._scroll.get_v_scroll_bar()
		var shown := row.grow_side(SIDE_RIGHT, _in_window(bar).size.x if bar.visible else 0.0)
		check(absf(shown.get_center().x - resting.get_center().x) <= CENTRED_TOLERANCE_PX * scale,
				"...its cards, and the scrollbar beside them, centred where it rests (%s)" % where,
				"%s in %s" % [shown, resting])
		var room := resting.size.x - scale * (2.0 * viewer._authored_margins[&"margin_left"]
				+ 2.0 * viewer.flow_container.position.x)
		var column := (CardVisual.preview_window_px().x + PlayArea.viewer_separation_px()) * scale
		check(shown.size.x <= room + GAP_TOLERANCE_PX and room - shown.size.x < column,
				"...the widest whole number of columns inside the authored margins (%s)" % where,
				"%.2f shown of %.2f, a column %.2f" % [shown.size.x, room, column])
		await _drop_viewer(viewer)

## The watchdog on a smooth scroll that follows the focus coming to rest; the wait ends on arrival.
const SCROLL_SETTLE_TIMEOUT_SEC := 5.0

# Measured in the ROOT window, at content scale 1 like the rows above; other window sizes are shots.
## A deck viewer's first row stands the board's gap below its window's top, and its last row, scrolled to by the keys, the same gap above the bottom; a short list sits at the top with that gap; each side is at least the gap; harness-scale only.
func test_a_deck_viewers_rows_stand_the_gap_inside_its_window() -> void:
	var visible := get_tree().root.get_visible_rect()
	var strip := Vector2(visible.size.x / 3.0, 0.0)
	var remaining := Rect2(visible.position + strip, visible.size - strip)
	var scale := get_tree().root.get_final_transform().get_scale().x
	var gap := PlayArea.viewer_separation_px() * scale
	for count : int in [52, 3]:
		var viewer := await _fitted_deck_viewer(count, remaining)
		var cards := viewer.cards().controls
		var window := _in_window(viewer.margin_container.get_node(^"ColorRect") as Control)
		var first := _in_window(cards[0])
		var columns := _cards_in_the_first_row_of(cards)
		var row := first.merge(_in_window(cards[columns - 1]))
		var bar := viewer._scroll.get_v_scroll_bar()
		var right_end := _in_window(bar).end.x if bar.visible else row.end.x
		var where := "%d cards" % count
		check(absf(first.position.y - window.position.y - gap) <= GAP_TOLERANCE_PX,
				"the first row stands the gap below the window's top (%s)" % where,
				"%.2f vs %.2f window px" % [first.position.y - window.position.y, gap])
		check(row.position.x - window.position.x >= gap - GAP_TOLERANCE_PX
				and window.end.x - right_end >= gap - GAP_TOLERANCE_PX,
				"...and at least the gap at each side (%s)" % where,
				"left %.2f right %.2f vs %.2f" % [row.position.x - window.position.x,
				window.end.x - right_end, gap])
		(cards[cards.size() - 1] as Control).grab_focus()
		check(await _scrolled_to_rest(cards[cards.size() - 1], window),
				"sanity: the list came to rest with its last card in the window (%s)" % where)
		var last := _in_window(cards[cards.size() - 1])
		var below := window.end.y - last.end.y
		if bar.visible:
			check(absf(below - gap) <= GAP_TOLERANCE_PX,
					"the last row, scrolled to by the keys, stands the gap above the window's bottom (%s)" % where,
					"%.2f vs %.2f window px" % [below, gap])
		else:
			check(below >= gap - GAP_TOLERANCE_PX, "a short list leaves at least the gap below it (%s)" % where,
					"%.2f vs %.2f window px" % [below, gap])
		await _drop_viewer(viewer)

## Waits until `card` lies inside `window` and a frame moves it no more; false when the watchdog ran out first.
func _scrolled_to_rest(card: Control, window: Rect2) -> bool:
	var waited := 0.0
	var was := _in_window(card)
	while waited < SCROLL_SETTLE_TIMEOUT_SEC:
		await get_tree().process_frame
		waited += get_process_delta_time()
		var now := _in_window(card)
		if now.is_equal_approx(was) and window.encloses(now): return true
		was = now
	return false

## A control's rect in the OS window's own pixels, its canvas layer and the window's UI scale applied.
func _in_window(control: Control) -> Rect2:
	return get_tree().root.get_final_transform() * control.get_global_transform_with_canvas() \
			* Rect2(Vector2.ZERO, control.size)

## A deck viewer of `count` cards opened through the product's entry, the catcher over the whole picture and the list in `remaining`, fitted twice: the host fits on open and again only on container_rect_changed.
func _fitted_deck_viewer(count: int, remaining: Rect2) -> DeckViewer:
	_test_opener = Button.new()
	add_child(_test_opener)
	var deck : Array[CardData] = []
	for index : int in count:
		deck.append(_card())
	var viewer := DeckViewer.show_deck(self, deck, _test_opener, &"viewer_deck")
	for fit : int in 2:
		viewer.fit_catcher(get_tree().root.get_visible_rect())
		viewer.fit_beside(remaining)
		for frame : int in 3:
			await get_tree().process_frame
	return viewer

func _cards_in_the_first_row_of(cards: Array[Control]) -> int:
	var top := cards[0].get_global_rect().position.y
	return cards.filter(func(card: Control) -> bool:
			return is_equal_approx(card.get_global_rect().position.y, top)).size()

## A chooser of `count` cards opened through the product's entry and fitted to `remaining`.
func _fitted_chooser(count: int, remaining: Rect2) -> ChoiceViewer:
	var viewer : ChoiceViewer = await ChoiceViewer.add_to_scene(self, _card, count, 0)
	await get_tree().process_frame
	viewer.fit_beside(remaining)
	await get_tree().process_frame
	await get_tree().process_frame
	return viewer

func _cards_in_the_first_row(viewer: ChoiceViewer) -> int:
	return _cards_in_the_first_row_of(viewer._cards.controls)

## The button a test viewer was opened from, kept so the toggle can press the SAME one again.
var _test_opener : Button = null

# A viewer opened the way every screen opens one, with two cards so a highlight can MOVE, and its
# published entries collected: what the sidebar would be reading, without booting one.
func _two_card_viewer(published: Array[String]) -> DeckViewer:
	_test_opener = Button.new()
	add_child(_test_opener)
	var deck : Array[CardData] = [_card(), _card().with_type(TypeHeavy.new())]
	var viewer := DeckViewer.show_deck(_focus_window, deck, _test_opener, &"viewer_deck")
	viewer.info_requested.connect(func(entry: InfoEntry) -> void:
		published.append(entry.title)
		if entry.visual: entry.visual.queue_free())
	return viewer

func _drop_viewer(viewer: DeckViewer) -> void:
	if is_instance_valid(viewer): viewer.queue_free()
	if is_instance_valid(_test_opener): _test_opener.queue_free()
	_test_opener = null
	await get_tree().process_frame

## An `InputEventAction` for one action, which is what a viewer's own modal verdict reads.
func _action_event(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event

## Hovering a listed card describes it; only a CLICK makes the sidebar keep it.
func test_a_hover_describes_a_viewer_card_and_a_click_sticks_it() -> void:
	var published : Array[String] = []
	var viewer := _two_card_viewer(published)
	await get_tree().process_frame
	var cards := viewer._cards.controls
	cards[0].mouse_entered.emit()
	check(not published.is_empty(), "a hover publishes the card it landed on", str(published))
	check(viewer._cards.sticky == null, "...and sticks nothing")
	_click(cards[0])
	check(viewer._cards.sticky == (cards[0] as ControlCard).child.data, "a click sticks the sidebar to that card")
	await _drop_viewer(viewer)

## A later hover BORROWS the description while it lasts; letting go gives it back to the stuck card, so a long one can be read in the sidebar.
func test_a_later_hover_borrows_the_description_and_gives_it_back() -> void:
	var published : Array[String] = []
	var viewer := _two_card_viewer(published)
	await get_tree().process_frame
	var cards := viewer._cards.controls
	_click(cards[0])
	var after_the_click := published.size()
	var gave_back : Array[int] = [0]
	viewer._cards.highlight_left.connect(func() -> void: gave_back[0] += 1)
	cards[1].mouse_entered.emit()
	check(published.size() > after_the_click,
			"a hover over another card does show that card while it lasts",
			"%d vs %d" % [published.size(), after_the_click])
	check(viewer._cards.sticky == (cards[0] as ControlCard).child.data,
			"...and the clicked card is still the stuck one")
	cards[1].mouse_exited.emit()
	check(gave_back[0] == 1,
			"the pointer leaving every listed card hands the sidebar back to the stuck one",
			str(gave_back[0]))
	cards[0].mouse_entered.emit()
	cards[1].mouse_entered.emit()
	cards[0].mouse_exited.emit()
	check(gave_back[0] == 1,
			"...and it is only the LAST card leaving that does, however many were hovered between",
			str(gave_back[0]))
	await _drop_viewer(viewer)

## A sticky description is being read, so nothing in the pack can be pressed until it is cancelled -- by pointer or by pad.
func test_a_sticky_description_puts_the_packs_buttons_beyond_reach() -> void:
	var viewer : ChoiceViewer = await ChoiceViewer.add_to_scene(self, _card, 3, 0, 2)
	await get_tree().process_frame
	await get_tree().process_frame
	check(not viewer.confirm_button.disabled, "sanity: Take is live with nothing picked")
	_click(viewer._cards.controls[0])
	check(viewer.confirm_button.disabled,
			"Take cannot be pressed while a sticky description is up")
	check(viewer.confirm_button.focus_mode == Control.FOCUS_NONE,
			"...and a pad cannot reach it either", str(viewer.confirm_button.focus_mode))
	var reachable := 0
	for button : Button in viewer._reroll_buttons:
		if not button.disabled or button.focus_mode != Control.FOCUS_NONE: reachable += 1
	check(reachable == 0, "...nor any Reroll button", str(reachable))
	viewer._cards.unstick()
	check(not viewer.confirm_button.disabled
			and viewer.confirm_button.focus_mode == Control.FOCUS_ALL,
			"cancelling the description puts Take back within reach")
	viewer.queue_free()
	await get_tree().process_frame

## A click on a listed card is the card's own act: the catcher behind the list never sees it.
func test_a_click_on_a_listed_card_never_closes_the_viewer() -> void:
	var published : Array[String] = []
	var viewer := _two_card_viewer(published)
	await get_tree().process_frame
	_click(viewer._cards.controls[0])
	await get_tree().process_frame
	check(not viewer.is_queued_for_deletion(), "the viewer is still open after a click on a card")
	await _drop_viewer(viewer)

## ONE cancel unsticks and closes together -- there is no two-press ladder out of a viewer.
func test_cancel_unsticks_before_it_closes() -> void:
	var published : Array[String] = []
	var viewer := _two_card_viewer(published)
	await get_tree().process_frame
	_click(viewer._cards.controls[0])
	check(viewer._cards.sticky != null, "sanity: a card is stuck")
	check(viewer._cards.modal_verdict(_action_event(&"ui_cancel")) == CardsViewer.Modal.CLOSE,
			"the FIRST cancel with a card stuck already reads as a close")
	await _drop_viewer(viewer)

## An arrow that walked off the list's own edge is KEPT, so the map or board beneath never answers it.
func test_an_arrow_off_the_lists_edge_never_reaches_the_screen_beneath() -> void:
	var published : Array[String] = []
	var viewer := _two_card_viewer(published)
	await get_tree().process_frame
	for action : StringName in CardsViewer.NAVIGATION:
		check(viewer._cards.modal_verdict(_action_event(action)) == CardsViewer.Modal.KEEP,
				"%s is kept by the open viewer" % action)
	await _drop_viewer(viewer)

## The X lives in another viewport, so the edge arrow ASKS for it -- and only while a stuck card has put one there.
func test_an_edge_arrow_asks_for_the_sidebar_only_while_a_card_is_stuck() -> void:
	var published : Array[String] = []
	var viewer := _two_card_viewer(published)
	await get_tree().process_frame
	var asked : Array[int] = [0]
	viewer._cards.sidebar_requested.connect(func() -> void: asked[0] += 1)
	viewer._cards.modal_verdict(_action_event(&"ui_up"))
	check(asked[0] == 0, "an edge arrow with nothing stuck asks for nothing", str(asked[0]))
	_click(viewer._cards.controls[0])
	viewer._cards.modal_verdict(_action_event(&"ui_up"))
	check(asked[0] == 1, "...and with a card stuck it hands the focus to the sidebar",
			str(asked[0]))
	await _drop_viewer(viewer)

## The Deck button TOGGLES: pressed again it closes the viewer it opened, and opens nothing.
func test_the_same_opener_pressed_again_closes_the_viewer() -> void:
	var published : Array[String] = []
	var viewer := _two_card_viewer(published)
	await get_tree().process_frame
	check(is_instance_valid(viewer) and not viewer.is_queued_for_deletion(),
			"sanity: the first press opened a viewer")
	var again := DeckViewer.show_deck(self, [_card()] as Array[CardData], _test_opener, &"viewer_deck")
	check(again == null, "the same opener pressed again opens nothing", str(again))
	check(viewer.is_queued_for_deletion(), "...and closes the viewer it had opened")
	await _drop_viewer(viewer)
	var other := Button.new()
	add_child(other)
	var first := _two_card_viewer(published)
	await get_tree().process_frame
	var swapped := DeckViewer.show_deck(self, [_card()] as Array[CardData], other, &"viewer_deck")
	check(swapped != null and swapped != first,
			"a DIFFERENT opener still replaces the open viewer rather than closing it")
	if swapped: swapped.queue_free()
	other.queue_free()
	await _drop_viewer(first)

## A viewer opened OVER another leaves it open beneath; its own opener pressed again closes it alone, and the one beneath is on top again.
func test_a_viewer_opened_over_another_leaves_it_open_beneath() -> void:
	var published : Array[String] = []
	var under := _two_card_viewer(published)
	var other := Button.new()
	add_child(other)
	var over := DeckViewer.show_deck(self, [_card()] as Array[CardData], other, &"viewer_deck", true)
	await get_tree().process_frame
	check(over != null and over != under and not under.is_queued_for_deletion(),
			"a viewer opened over another leaves it open beneath")
	check(DeckViewer._open == over, "...and is the one on top", str(DeckViewer._open))
	var again := DeckViewer.show_deck(self, [_card()] as Array[CardData], other, &"viewer_deck", true)
	check(again == null and over.is_queued_for_deletion() and not under.is_queued_for_deletion(),
			"its own opener pressed again closes it alone")
	check(DeckViewer._open == under, "...and the one beneath is on top again", str(DeckViewer._open))
	other.queue_free()
	await _drop_viewer(under)

## A cancel over the pack first lets its stuck card go and stops there; with nothing stuck it passes on to the wall, the pack still open behind it.
func test_the_pack_chooser_passes_a_cancel_on_once_nothing_is_stuck() -> void:
	var viewer : ChoiceViewer = await ChoiceViewer.add_to_scene(_focus_window, _card, 3, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	_click(viewer._cards.controls[0])
	_focus_window.push_input(_action_event(&"ui_cancel"))
	check(viewer.cards().sticky == null, "a cancel lets the pack's picked card go")
	check(_focus_window.is_input_handled(), "...and goes no further than the pack")
	check(not viewer.is_queued_for_deletion(), "...and the pack itself is still open")
	check(not viewer.confirm_button.disabled, "...with Take back within reach")
	_focus_window.push_input(_action_event(&"ui_cancel"))
	check(not _focus_window.is_input_handled(),
			"the next cancel, nothing stuck, passes on to the wall behind the pack")
	check(not viewer.is_queued_for_deletion(), "...and the pack is still open")
	viewer.queue_free()
	await get_tree().process_frame

## A dummy pack. It overrides create_one_choice so a roll needs no RunManager.run (the real one goes through luck(), which dereferences a null run in a bare test), while still driving the REAL on_map_picked -> ChoiceViewer path — which is where booster_reroll_pool is read.
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
	for child : Node in get_children():
		if child is DeckViewer and not child.is_queued_for_deletion():
			n += 1
	return n

# THE DETAIL LINE FOR AN INTERMITTENT seen once in ~24 runs. RULED OUT: another suite hijacking the
# static `DeckViewer._open` -- the three `show_deck` calls have no `await` between them. So this
# prints OUR OWN children: every DeckViewer here with its queued flag, and who `_open` points at.
func _viewer_detail() -> String:
	var parts : Array[String] = []
	for child : Node in get_children():
		if child is DeckViewer:
			parts.append("%s(queued=%s)" % [child.name, child.is_queued_for_deletion()])
	var open_desc := "<null>"
	if is_instance_valid(DeckViewer._open):
		open_desc = "%s(mine=%s)" % [DeckViewer._open.name, DeckViewer._open.get_parent() == self]
	return "live %d | children: [%s] | _open=%s" % [_count_viewers(), ", ".join(parts), open_desc]

func test_deck_viewer_singleton() -> void:
	var deck: Array[CardData] = [_card()]
	var opener := Button.new()
	add_child(opener)
	DeckViewer.show_deck(self, deck, opener, &"viewer_deck")
	DeckViewer.show_deck(self, deck, opener, &"viewer_deck")
	DeckViewer.show_deck(self, deck, opener, &"viewer_deck")
	await get_tree().process_frame
	check(_count_viewers() == 1, "repeated show_deck replaces instead of stacking",
			_viewer_detail())
	if is_instance_valid(DeckViewer._open):
		DeckViewer._open.queue_free()
	opener.queue_free()
	await get_tree().process_frame

func test_control_card_focus() -> void:
	var control := ControlCard.add_child_control_card(
		_focus_window, _card(), CardVisual.DisplayContext.DECK_VIEWER)
	await get_tree().process_frame
	check(control.focus_mode == Control.FOCUS_ALL, "preview cards are keyboard-focusable")
	control.grab_focus()
	await get_tree().process_frame
	check(control.child != null and control.child.focused,
			"focusing a card lights its visual like a mouse hover")
	control.queue_free()
	await get_tree().process_frame

func test_describe_card() -> void:
# Use TypeHeavy (a type WITH an effect): describe_card gives TypePaper no block, so it can't be
# asserted with contains().
	var data := _card().with_skill(SkillExtraPoint.new()).with_stamp(StampGlobal.new()) \
			.with_type(TypeHeavy.new())
	var text := ControlCard.describe_card(data)
	check(text.contains(SkillExtraPoint.new().get_str()) \
			and text.contains(StampGlobal.new().get_str()) \
			and text.contains(TypeHeavy.new().get_str()),
			"describe_card names every modifier", text)
	check(text.contains(SkillExtraPoint.new().get_description()),
			"describe_card includes the modifier descriptions")
# A type with no effect must not add a block: a card's description explains effects, and it has
# none to explain.
	var paper := CardData.new().with_type(TypePaper.new())
	check(not ControlCard.describe_card(paper).contains("[font_size="),
			"a type with no effect produces no effect block")

func test_choice_viewer_take_all() -> void:
	var viewer : ChoiceViewer = await ChoiceViewer.add_to_scene(self, _card, 5, 0)
	await get_tree().process_frame
# population is deferred one frame (fly-in fix)
	await get_tree().process_frame
	var cards := 0
	for child : Node in viewer.flow_container.get_children():
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

## Booster rerolls: a pack opens with a SHARED pool of free rerolls; each slot's Reroll re-rolls that slot through the same generator, spending from the one pool, and the buttons gray out at zero. Driven through the data API (reroll()) — the buttons are thin wrappers over it.
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

## The pool is owner-tunable, not a hardcoded 5: on_map_picked must read settings.booster_reroll_pool. Driven at a NON-default value and at 0 (rerolls switched off entirely — every button dead from the moment the pack opens).
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

## The palette index a card's outer rim is ACTUALLY drawn in, read back off the polygon's own material rather than from the decision that wrote it.
func _rim_index(control: ControlCard) -> int:
	return CardOutline.material_of(control.child.type).get_shader_parameter(&"u_outline_index")

## A real left press on the control, through the signal Godot's own GUI pass fires -- not the handler by name.
func _click(control: Control) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	control.gui_input.emit(press)

## Clicking a listed card picks it, in its own ink; one at a time; and the moving focus takes the rim back for as long as it is there.
func test_pack_click_selects() -> void:
	var viewer : ChoiceViewer = await ChoiceViewer.add_to_scene(_focus_window, _card, 3, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	var first : ControlCard = viewer._cards.controls[0]
	var second : ControlCard = viewer._cards.controls[1]
	var resting := _rim_index(first)
	check(viewer.cards().sticky == null, "a pack opens with nothing picked")
	_click(first)
	await get_tree().process_frame
	check(viewer.cards().sticky == first.child.data, "a click picks the card it landed on")
	check(first.child.selected and not second.child.selected,
			"exactly one listed card is picked at a time")
	check(first.has_focus(),
			"the click also focuses the card it picked, so the sidebar can stay on it",
			str(first.get_viewport().gui_get_focus_owner()))
	check(_rim_index(first) == PaletteDB.ROLES.match_rim,
			"the moving focus takes the rim while it is on the picked card", str(_rim_index(first)))
	second.grab_focus()
	await get_tree().process_frame
	check(_rim_index(first) == PaletteDB.ROLES.selected_rim,
			"the picked card's rim is drawn in the selection ink once the focus moves off",
			str(_rim_index(first)))
	check(_rim_index(first) != resting and PaletteDB.ROLES.selected_rim != PaletteDB.ROLES.match_rim,
			"the selection ink is neither the resting ink nor the focus ink")
	_click(first)
	await get_tree().process_frame
	check(viewer.cards().sticky == first.child.data, "a second click on the picked card keeps it")
	_click(second)
	await get_tree().process_frame
	check(viewer.cards().sticky == second.child.data and not first.child.selected,
			"clicking another card moves the pick")
	check(_rim_index(first) == resting, "the card that lost the pick goes back to its own ink")
	viewer.queue_free()
	await get_tree().process_frame

## Take adds the WHOLE pack whatever is picked: the pick is what the player is pointing at, never what they get.
func test_take_ignores_the_selection() -> void:
	for pick : int in [-1, 1]:
		var viewer : ChoiceViewer = await ChoiceViewer.add_to_scene(self, _card, 5, 0)
		await get_tree().process_frame
		await get_tree().process_frame
		if pick >= 0: _click(viewer._cards.controls[pick])
		await get_tree().process_frame
		check(viewer.confirm_button.disabled == (pick >= 0),
				"Take is live with nothing picked, and held behind a sticky description with %s"
						% ("a card picked" if pick >= 0 else "nothing picked"))
		viewer._cards.unstick()
		await get_tree().process_frame
		var got : Array[CardData] = []
		viewer.confirmed.connect(func(taken: Array[CardData]) -> void: got.assign(taken))
		viewer.confirm_button.pressed.emit()
		check(got.size() == 5, "Take adds all 5 cards with %s picked"
				% ("a card" if pick >= 0 else "nothing"), str(got.size()))
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
# "Uncolored" used to mean `material == null`, and it cannot any more: every element on a card wears
# the outline material, so a null there would mean the pip lost its RIM — and because these polygons
# are pooled, it would lose it only on whichever cards happened to land on a recycled node. The claim

# is now made against the fill MODE, which is the thing that was ever actually being asserted.
	var rank_mat := rank_only.child.rank.material as ShaderMaterial
	var rank_fill := -1
	if rank_mat: rank_fill = rank_mat.get_shader_parameter(&"u_fill_mode")
	check(rank_mat != null and rank_fill == int(CardOutline.Fill.TEXTURE),
			"suitless card renders its rank uncolored (its sheet's own colours, no palette flatten)")
	check(not suit_only.child.art.visible, "rankless card shows no art polygon")
	rank_only.queue_free()
	suit_only.queue_free()
	await get_tree().process_frame
