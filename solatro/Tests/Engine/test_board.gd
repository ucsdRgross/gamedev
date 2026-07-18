extends TestSuite
# res://Tests/Engine/test_board.gd
# Board / move-logic suite (UNIT_TESTS_PLAN.md §1) against the CURRENT
# Game.move_data_to_coord, using GameData.validate() after every action.
# Uses a bare Game.new() that is never added to the tree (its state setter and
# pure board functions are tree-safe); CardEnvironment.CURRENT is only set
# manually for the event-dispatch section.
#
# Since the §5 anchor rewrite (Board.move_stack, 2026-07-02) rejected moves return
# error codes and provably leave the board untouched — covered in section 5.
#
# CATEGORY MAP (see TestSuite):
#   BEHAVIOR — topmost rules, every move outcome (cross/same-column, rejections,
#     clamps, no-ops), draw/discard. These are the solitaire rules of the game.
#   IMPLEMENTATION — locate/coordinate lookup internals, the mod-event dispatch
#     contract, duplicate_state instance/backref separation.

func suite_name() -> String:
	return "BOARD"

func _ready() -> void:
	TestLog.line("============ BOARD / MOVE LOGIC TEST PASS ============")
	await run_locate_tests()
	await run_topmost_tests()
	await run_cross_column_moves()
	await run_same_column_moves()
	await run_degenerate_moves()
	await run_event_tests()
	await run_draw_discard_tests()
	await run_undo_duplicate_tests()
	finish()


# ==============================================================================
# FIXTURE: two zones, 3 columns each, sizes {0, 1, 4} + headers + small decks
# ==============================================================================

func header(label: int) -> CardData:
	var h := TestFactories.m_card(label, TestFactories.uc())
	h.stage = CardData.Stage.ZONE
	return h

func make_game() -> Game:
	var g := Game.new()
	var s := GameData.new()
	for zone_x in 2:
		var types : Array[CardData] = []
		var cols : Array[ArrayCardData] = []
		for c in 3:
			types.append(header(100 + zone_x * 10 + c))
			var size : int = [0, 1, 4][c]
			var col_cards : Array[CardData] = []
			for r in size:
				col_cards.append(TestFactories.m_card(r + 1, TestFactories.uc()))
			cols.append(TestFactories.col(col_cards))
		if zone_x == 0:
			s.upper_zone_type = types
			s.upper_zone = cols
		else:
			s.lower_zone_type = types
			s.lower_zone = cols
	for i in 3:
		var d := TestFactories.m_card(i + 1, TestFactories.uc())
		d.stage = CardData.Stage.DRAW
		s.draw_deck.append(d)
	g.state = s
	return g

func free_game(g: Game) -> void:
	g.free()

func validate_ok(g: Game, ctx: String) -> void:
	var v := g.state.validate()
	check(v.is_empty(), ctx + " -> validate()", str(v))

## Identity snapshot of both zones (+decks) for board-unchanged assertions.
func snap(g: Game) -> Array:
	var out := []
	for zone : Array[ArrayCardData] in [g.state.upper_zone, g.state.lower_zone]:
		var z := []
		for c in zone:
			z.append(c.datas.duplicate())
		out.append(z)
	out.append(g.state.draw_deck.duplicate())
	out.append(g.state.discard_deck.duplicate())
	return out

func total_cards(g: Game) -> int:
	return g.state.all_card_datas().size()

func col_datas(g: Game, x: int, y: int) -> Array[CardData]:
	return g.get_zone_from_vec3(Vector3i(x, y, 0))[y].datas


# ==============================================================================
# SECTION 1: locate (find_data_vec3 / find_vec3_data)
# IMPLEMENTATION: internal coordinate-lookup contract (Vector3i encoding, MIN
# sentinel, header z == -1) — only meaningful while this representation exists.
# ==============================================================================
func run_locate_tests() -> void:
	implementation_section("SECTION 1: LOCATE")
	var g := make_game()
	validate_ok(g, "fresh fixture")

	var c := col_datas(g, 0, 2)[3]
	check(g.find_data_vec3(c) == Vector3i(0, 2, 3), "upper card -> (0,2,3)")
	c = col_datas(g, 1, 1)[0]
	check(g.find_data_vec3(c) == Vector3i(1, 1, 0), "lower card -> (1,1,0)")
	check(g.find_data_vec3(g.state.upper_zone_type[1]) == Vector3i(0, 1, -1),
			"upper header -> z == -1")
	check(g.find_data_vec3(g.state.lower_zone_type[2]) == Vector3i(1, 2, -1),
			"lower header -> z == -1")
	check(g.find_data_vec3(g.state.draw_deck[0]) == Vector3i.MIN,
			"draw-deck card is not a board position -> MIN")
	check(g.find_data_vec3(TestFactories.m_card(1, 1)) == Vector3i.MIN,
			"card in no collection -> MIN")

	check(g.find_vec3_data(Vector3i(0, 2, 3)) == col_datas(g, 0, 2)[3], "find_vec3_data roundtrip")
	check(g.find_vec3_data(Vector3i(0, 9, 0)) == null, "out-of-range col -> null (S2)")
	check(g.find_vec3_data(Vector3i(0, 0, 5)) == null, "out-of-range row -> null (S2)")
	check(g.find_vec3_data(Vector3i(0, 1, -1)) == null, "negative row -> null (S2)")

	#B4 regression: more columns than headers must not crash locate.
	#Raw append = a mutation, so it bumps revision per the MUTATION GUIDELINES
	#(the §5.4 position index and compare cache both key on it).
	g.state.upper_zone.append(TestFactories.col([TestFactories.m_card(9, TestFactories.uc())]))
	g.state.revision += 1
	var extra := g.state.upper_zone[3].datas[0]
	check(g.find_data_vec3(extra) == Vector3i(0, 3, 0),
			"B4: locate works with more columns than headers")
	free_game(g)


# ==============================================================================
# SECTION 2: is_data_topmost
# BEHAVIOR: which card is interactable (grabbable / a legal drop target) is a
# rule of the game the player sees directly.
# ==============================================================================
func run_topmost_tests() -> void:
	behavior_section("SECTION 2: TOPMOST")
	var g := make_game()

	check(g.is_data_topmost(col_datas(g, 0, 2)[3]), "last card of column is topmost")
	check(not g.is_data_topmost(col_datas(g, 0, 2)[1]), "middle card is not topmost")
	check(g.is_data_topmost(col_datas(g, 1, 1)[0]), "single card of column is topmost")
	check(g.is_data_topmost(g.state.upper_zone_type[0]), "upper header, empty column -> topmost")
	check(not g.is_data_topmost(g.state.upper_zone_type[2]), "upper header, full column -> not")
	check(g.is_data_topmost(g.state.lower_zone_type[0]), "lower header, empty column -> topmost")
	check(not g.is_data_topmost(g.state.lower_zone_type[2]), "lower header, full column -> not")
	check(not g.is_data_topmost(g.state.draw_deck[0]), "deck card is not topmost")
	check(not g.is_data_topmost(TestFactories.m_card(1, 1)), "off-board card is not topmost")
	free_game(g)


# ==============================================================================
# SECTION 3: CROSS-COLUMN MOVES
# BEHAVIOR: what actually happens to the board when a stack moves — order
# preserved, source emptied, card count conserved.
# ==============================================================================
func run_cross_column_moves() -> void:
	behavior_section("SECTION 3: CROSS-COLUMN MOVES")
	var g := make_game()
	var big : Array[CardData] = col_datas(g, 0, 2).duplicate() # [a,b,c,d]

	#single card onto top of another column
	await g.move_data_to_coord(big[3], Vector3i(0, 1, 1), 1, false)
	check((col_datas(g, 0, 1).back() == big[3] and col_datas(g, 0, 2).size() == 3) as bool,
			"single card onto top of another column")
	validate_ok(g, "after single-card move")

	#onto empty column (ColumnEnd, z = -1)
	await g.move_data_to_coord(big[3], Vector3i(0, 0, -1), 1, false)
	check(col_datas(g, 0, 0) == [big[3]], "onto empty column via z = -1")
	validate_ok(g, "after empty-column move")

	#stack of 3 onto another column, order preserved
	await g.move_data_to_coord(big[0], Vector3i(0, 0, 1), 3, false)
	check(col_datas(g, 0, 0) == [big[3], big[0], big[1], big[2]],
			"stack of 3 moved, order preserved", str(col_datas(g, 0, 0)))
	check(col_datas(g, 0, 2).is_empty(), "source column emptied but still present")
	validate_ok(g, "after stack move")

	#whole column (count -1) onto another column
	await g.move_data_to_coord(big[3], Vector3i(0, 2, -1), -1, false)
	check(col_datas(g, 0, 2) == [big[3], big[0], big[1], big[2]] \
			and col_datas(g, 0, 0).is_empty(), "whole column via count = -1")
	validate_ok(g, "after whole-column move")

	#upper -> lower and lower -> upper
	await g.move_data_to_coord(big[2], Vector3i(1, 0, -1), 1, false)
	check(col_datas(g, 1, 0) == [big[2]], "upper -> lower")
	await g.move_data_to_coord(big[2], Vector3i(0, 0, -1), 1, false)
	check(col_datas(g, 0, 0) == [big[2]], "lower -> upper")
	validate_ok(g, "after cross-zone moves")

	#ColumnStart insert (TypeInput 'under everything' path, z = 0) on occupied column
	await g.move_data_to_coord(big[2], Vector3i(0, 2, 0), 1, false)
	check(col_datas(g, 0, 2)[0] == big[2] and col_datas(g, 0, 2).size() == 4,
			"ColumnStart insert on occupied column")
	validate_ok(g, "after ColumnStart insert")

	check(total_cards(g) == 19, "card count conserved through all moves")
	free_game(g)


# ==============================================================================
# SECTION 4: SAME-COLUMN MOVES (S3 danger zone)
# BEHAVIOR: chosen move policies (rejections, clamps, no-ops) are game rules.
# ==============================================================================
func run_same_column_moves() -> void:
	behavior_section("SECTION 4: SAME-COLUMN MOVES")
	var g := make_game()
	var a := col_datas(g, 0, 2)[0]; var b := col_datas(g, 0, 2)[1]
	var c := col_datas(g, 0, 2)[2]; var d := col_datas(g, 0, 2)[3]

	#move card DOWN within its column (src.row < dest)
	await g.move_data_to_coord(b, Vector3i(0, 2, 3), 1, false) # onto c
	check(col_datas(g, 0, 2) == [a, c, b, d],
			"move down within column (onto card below)", str(col_datas(g, 0, 2)))
	validate_ok(g, "after down move")

	#move card UP within its column (src.row > dest)
	await g.move_data_to_coord(b, Vector3i(0, 2, 1), 1, false) # back onto a
	check(col_datas(g, 0, 2) == [a, b, c, d],
			"move up within column (onto card above)", str(col_datas(g, 0, 2)))
	validate_ok(g, "after up move")

	#move onto the card directly beneath itself -> board unchanged (regression for
	#the z_dist == 0 swap bug fixed 2026-07-02)
	var before := snap(g)
	await g.move_data_to_coord(d, Vector3i(0, 2, 3), 1, false)
	check(snap(g) == before, "no-op drop onto own position leaves board unchanged",
			str(col_datas(g, 0, 2)))
	validate_ok(g, "after no-op drop")

	#dest anchor inside the moving stack -> §5 policy: ERR_DEST_INSIDE_STACK, unchanged
	#(replaced the old silent "cap stack to before dest" clamp)
	before = snap(g)
	await g.move_data_to_coord(a, Vector3i(0, 2, 2), -1, false) # dest is b, inside a's stack
	check(snap(g) == before,
			"dest inside moving stack -> rejected, board unchanged (§5 policy)",
			str(col_datas(g, 0, 2)))
	validate_ok(g, "after inside-stack rejection")

	#count larger than available -> clamped to the remainder
	await g.move_data_to_coord(c, Vector3i(0, 0, -1), 99, false)
	check(col_datas(g, 0, 0) == [c, d] \
			and col_datas(g, 0, 2) == [a, b],
			"oversized count clamps to remaining stack")
	validate_ok(g, "after clamped move")

	#count = -1 within same column onto a card in the stack -> also rejected
	before = snap(g)
	await g.move_data_to_coord(c, Vector3i(0, 0, 1), -1, false) # anchor c is in own stack
	check(snap(g) == before,
			"count -1 same column onto own stack -> rejected, board unchanged",
			str(col_datas(g, 0, 0)))
	validate_ok(g, "after same-column count -1")
	free_game(g)


# ==============================================================================
# SECTION 5: DEGENERATE INPUTS
# BEHAVIOR: illegal moves are rejected and provably change nothing.
# ==============================================================================
func run_degenerate_moves() -> void:
	behavior_section("SECTION 5: DEGENERATE")
	var g := make_game()

	#count = 0 -> pin: nothing moves
	var before := snap(g)
	var c := col_datas(g, 0, 2)[1]
	await g.move_data_to_coord(c, Vector3i(0, 1, -1), 0, false)
	check(snap(g) == before, "PIN: count = 0 moves nothing, board unchanged")
	validate_ok(g, "after count 0")

	#move from a 1-card column: column empties, header flips topmost
	var lone := col_datas(g, 0, 1)[0]
	check(not g.is_data_topmost(g.state.upper_zone_type[1]), "header covered before")
	await g.move_data_to_coord(lone, Vector3i(0, 2, -1), 1, false)
	check(col_datas(g, 0, 1).is_empty() and g.is_data_topmost(g.state.upper_zone_type[1]),
			"1-card column empties; header becomes topmost")
	validate_ok(g, "after emptying column")

	#error paths (all newly testable since the §5 rewrite): rejected, board unchanged
	var before2 := snap(g)
	var off_board := TestFactories.m_card(1, 1)
	await g.move_data_to_coord(off_board, Vector3i(0, 0, -1), 1, false)
	check(snap(g) == before2, "moving an off-board card -> rejected, unchanged")

	await g.move_data_to_coord(g.state.upper_zone_type[0], Vector3i(0, 0, -1), 1, false)
	check(snap(g) == before2, "moving a zone header -> rejected, unchanged")

	var some_card := col_datas(g, 0, 2)[0]
	await g.move_data_to_coord(some_card, Vector3i(0, 9, -1), 1, false)
	check(snap(g) == before2, "destination column out of bounds -> rejected, unchanged")

	await g.move_stack(some_card, 1, Board.Anchor.on_top(off_board), false)
	check(snap(g) == before2, "OnTop anchor not on board -> rejected, unchanged")

	await g.move_stack(some_card, 1, null, false)
	check(snap(g) == before2, "null anchor -> rejected, unchanged")
	validate_ok(g, "after rejected moves")
	free_game(g)


# ==============================================================================
# SECTION 6: EVENT DISPATCH (Phase-4 contract, via spy mod)
# IMPLEMENTATION: the internal mod-hook contract (which hooks fire, with what
# args, in which zone direction) — pins the architecture, not a player rule.
# ==============================================================================

class SpyEvents extends CardModifierType:
	var dropped_on_calls : Array = [] #[onto, stack]
	var stack_calls : Array = []      #[stack]
	func get_str() -> String: return "SpyEvents"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_card_dropped_on(onto: CardData, stack: Array[CardData]) -> void:
		dropped_on_calls.append([onto, stack.duplicate()])
	func on_stack_cards(stack: Array[CardData]) -> void:
		stack_calls.append(stack.duplicate())

func run_event_tests() -> void:
	implementation_section("SECTION 6: EVENTS")
	var g := make_game()
	var spy := SpyEvents.new()
	col_datas(g, 1, 2)[0].with_type(spy) #spy rides a lower-zone card
	CardEnvironment.CURRENT = g

	#upper -> lower onto a card: on_card_dropped_on fires with the anchor card
	var moving := col_datas(g, 0, 2)[3]
	var anchor := col_datas(g, 1, 2)[3]
	await g.move_data_ontop_data(moving, anchor, 1, true)
	check((spy.dropped_on_calls.size() == 1 
			and spy.dropped_on_calls[0][0] == anchor 
			and spy.dropped_on_calls[0][1] == [moving]) as bool,
			"on_card_dropped_on(anchor, stack) fired for upper->lower",
			str(spy.dropped_on_calls))
	check(spy.stack_calls.size() == 1, "on_stack_cards fired once")
	validate_ok(g, "after event move")

	#lower -> upper: no on_card_dropped_on
	await g.move_data_to_coord(moving, Vector3i(0, 2, -1), 1, true)
	check(spy.dropped_on_calls.size() == 1, "lower->upper does NOT fire on_card_dropped_on")
	check(spy.stack_calls.size() == 2, "on_stack_cards still fires")

	#trigger_mods = false -> zero hooks
	await g.move_data_to_coord(moving, Vector3i(1, 2, -1), 1, false)
	check(spy.dropped_on_calls.size() == 1 and spy.stack_calls.size() == 2,
			"trigger_mods = false fires zero hooks")

	#ColumnEnd (z = -1) drop now reports the actual landing card as `onto`
	#(§5 fix: the old code always passed null for z = -1 appends)
	await g.move_data_to_coord(moving, Vector3i(0, 0, -1), 1, false)
	await g.move_data_to_coord(moving, Vector3i(1, 2, -1), 1, true)
	check(spy.dropped_on_calls.size() == 2 and spy.dropped_on_calls[1][0] == anchor as bool,
			"ColumnEnd drop fires on_card_dropped_on with the landing card",
			str(spy.dropped_on_calls))
	validate_ok(g, "after ColumnEnd event move")

	CardEnvironment.CURRENT = null
	free_game(g)


# ==============================================================================
# SECTION 7: DRAW / DISCARD
# BEHAVIOR: drawing and discarding are player-visible actions.
# ==============================================================================
func run_draw_discard_tests() -> void:
	behavior_section("SECTION 7: DRAW / DISCARD")
	var g := make_game()

	var top := g.state.draw_deck[-1]
	var drawn := g.draw_card()
	check(drawn == top and drawn.stage == CardData.Stage.PLAY \
			and g.state.draw_deck.size() == 2, "draw_card returns last card, stage PLAY")

	g.state.draw_deck.clear()
	check(g.draw_card() == null, "draw_card on empty deck -> null")

	#discard a mid-stack card: cards above shift down, discard pile gets it
	var mid := col_datas(g, 0, 2)[1]
	await g.discard_data(mid)
	check(col_datas(g, 0, 2).size() == 3 and not col_datas(g, 0, 2).has(mid) \
			and g.state.discard_deck == [mid] \
			and mid.stage == CardData.Stage.DISCARD,
			"discard mid-stack card: removed, appended to discard, stage DISCARD")
	validate_ok(g, "after discard")
	free_game(g)


# ==============================================================================
# SECTION 8: duplicate_state / UNDO SEPARATION (B11 regression)
# IMPLEMENTATION: instance identity, modifier backrefs, BigNumber copying — the
# machinery under undo. (The player-facing undo behavior itself is covered in
# test_game_headless.)
# ==============================================================================
func run_undo_duplicate_tests() -> void:
	implementation_section("SECTION 8: DUPLICATE / UNDO")
	var g := make_game()
	#give some cards mods so back-references exist to check
	var modded := col_datas(g, 0, 2)[0].with_type(SpyEvents.new())
	col_datas(g, 1, 2)[2].with_type(SpyEvents.new())
	g.state.scores_col = [BigNumber.new(), BigNumber.new(), BigNumber.new()] as Array[BigNumber]
	g.state.scores_col[0].mantissa = 4.2
	g.state.scores_col[0].exponent = 3

	var copy := g.state.duplicate_state()
	validate_ok(g, "original after duplicate")

	#complete separation: no shared CardData instances
	var orig_set := {}
	for card in g.state.all_card_datas(): orig_set[card] = true
	var shared := false
	for card in copy.all_card_datas():
		if orig_set.has(card): shared = true
	check(not shared, "B11: copy shares NO CardData instances with original")

	#back-references remapped into the copy
	var backrefs_ok := true
	for card in copy.all_card_datas():
		for mod : CardModifier in [card.type, card.stamp, card.skill]:
			if mod and mod.data != card:
				backrefs_ok = false
	check(backrefs_ok, "B11: every mod.data points at the COPY's card")

	#BigNumbers: values equal, instances distinct
	check(copy.scores_col.size() == 3 \
			and copy.scores_col[0].mantissa == 4.2 and copy.scores_col[0].exponent == 3 \
			and copy.scores_col[0] != g.state.scores_col[0],
			"BigNumber scores copied by value, distinct instances")

	#history separation: mutate the current board, the snapshot must not change
	#(BEHAVIOR: this is the guarantee that makes undo trustworthy)
	var copy_col_size := copy.upper_zone[2].datas.size()
	await g.move_data_to_coord(modded, Vector3i(0, 0, -1), -1, false)
	check_behavior(copy.upper_zone[2].datas.size() == copy_col_size,
			"mutating live state leaves the snapshot untouched")
	var v := copy.validate()
	check(v.is_empty(), "snapshot itself validates", str(v))
	free_game(g)
