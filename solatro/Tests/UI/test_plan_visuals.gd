extends TestSuite
# res://Tests/UI/test_plan_visuals.gd

# THE MARK'S LOOK, and the opening reveal that deals it. A mark is printed on the cell's OWN zone
# card, so what is asserted here is that it costs the tree nothing, that its grey never rides
# `modulate`, and that a covered mark is still named by the cell it is under.

# CATEGORY MAP: BEHAVIOR -- what the player sees (a grey mark, a card on top untinted, a cell that
# still names what it was marked for, a plan dealt cell by cell). IMPLEMENTATION -- the node count
# the binding costs, and which shader uniform carries the grey.

# ⚠ NO GREEN CHECK HERE IS EVIDENCE ABOUT PIXELS. The look itself is verified by eye against a
# rendered PNG (`Tests/Visual/plan_reveal_shot.tscn`); these rows pin the mechanism under it.

# Ordering: hosts a real PlayArea over `CardEnvironment.CURRENT` and awaits frames, so it takes the
# HEAD of the serialized UI chain -- it excludes every suite after it and none waits on nothing.

const PLAY_AREA_SCENE := preload("res://UI/play_area.tscn")
const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")
const WATCHDOG_SECS := 15.0

func suite_name() -> String:
	return "PLAN VISUALS"

func _ready() -> void:
	await await_siblings_except(["INTERACTION", "UI PROPS", "VISUAL LAYERS", "GRID LAYOUT",
			"GRID VIEW", "SETTINGS RANGE", "E2E RUN", "LEAK CANARY", "WALL PAUSE"])
	TestLog.line("============ PLAN VISUALS TEST PASS ============")
	implementation_section("A MARK COSTS THE TREE NOTHING")
	await test_a_mark_adds_no_node_to_the_tree()
	behavior_section("THE GREY IS THE PALETTE AND THE RIM, NEVER modulate")
	await test_no_mark_path_writes_modulate()
	behavior_section("A COVERED MARK IS STILL THERE, AND STILL NAMED")
	await test_a_covered_mark_is_named_by_its_cell()
	behavior_section("THE OPENING REVEAL DEALS CELL BY CELL")
	await test_the_reveal_deals_the_marks_in_the_deals_own_order()
	await test_a_show_with_no_view_deals_its_board_and_reveals_nothing()
	await test_a_reveal_outlives_the_screen_that_holds_the_environment()
	behavior_section("A HELD CARD LIGHTS EVERY MARK IT WOULD AGREE WITH")
	await setup_view()
	await test_holding_a_card_lights_the_marks_it_agrees_with()
	await test_the_highlight_lights_elements_rather_than_tinting_the_cell()
	await test_a_card_agreeing_with_nothing_says_nothing()
	behavior_section("A LANDED CARD WEARS THE ACTIVATED RIM UNTIL UNDO")
	await test_a_landing_that_matched_activates_the_elements_that_agreed()
	await teardown_view()
	finish()

# ==============================================================================
# FIXTURES
# ==============================================================================

# One 5x5 grid with `CardEnvironment.CURRENT` pointed at it, which is what every PlayArea read
# resolves its board through.
func make_grid_game() -> Game:
	var g := Game.new()
	g.state = TestGridFixtures.build_fix_grid_1()
	g._begin_act()
	CardEnvironment.CURRENT = g
	return g

# A real board window. The overview is latched because a one-grid board would otherwise open
# FOCUSED and zoom, which none of these claims is about.
func make_play_area() -> PlayArea:
	var pa : PlayArea = PLAY_AREA_SCENE.instantiate()
	add_child(pa)
	pa.size = Vector2(1152, 648)
	pa._show_view_opened = true
	pa.open_zoomed_out()
	return pa

# Marks every cell of grid 0 from the standing plan deck, the same way the deal does, and returns
# the cells in the order they were marked.
func mark_every_cell(state: GameData) -> Array[CardData]:
	var deck := TestDecks.plan_deck()
	var grid : GridData = state.grids[0]
	var marked : Array[CardData] = []
	for i : int in grid.cell_types.size():
		var type_card : CardData = grid.cell_types[i]
		BoardPlan.write_mark(type_card, deck[i % deck.size()], false)
		marked.append(type_card)
	return marked

# Every claim here reads a card's own state rather than where it sits, so the board's LAYOUT never
# has to settle -- only its visuals have to exist.
func settle(pa: PlayArea) -> void:
	var waited := 0.0
	while not pa.visuals_ready() and waited < WATCHDOG_SECS:
		await get_tree().process_frame
		waited += get_process_delta_time()

func cleanup(g: Game, pa: PlayArea) -> void:
	pa.queue_free()
	CardEnvironment.CURRENT = null
	await get_tree().process_frame
	g.free()

# Every node under `root`, itself included -- the count a mark must not move.
func descendants(root: Node) -> int:
	var total := 1
	for child in root.get_children():
		total += descendants(child)
	return total

# One INT shader uniform of one of a card's five polygons, read off the live material rather than
# off anything the test wrote. -1 is no material at all, which is a card drawing no rim.
func uniform_of(poly: Polygon2D, key: StringName) -> int:
	var mat := poly.material as ShaderMaterial
	if not mat: return -1
	var value : int = mat.get_shader_parameter(key)
	return value

# ==============================================================================
# TP-60 -- the mark rides the binding that already happens
# ==============================================================================

# The cell's zone card is bound into a slot control whether it is marked or not, so marking the
# whole board may not add a node to the tree or a child to a slot.
func test_a_mark_adds_no_node_to_the_tree() -> void:
	var g := make_grid_game()
	var pa := make_play_area()
	await settle(pa)
	var bare_cell : CardData = g.state.grids[0].cell_types[0]
	var bare_control : Control = pa.data_ui[bare_cell]
	var bare_slot : Control = bare_control.get_parent()
	var bare_tree := get_tree().get_node_count()
	var bare_slot_children := bare_slot.get_child_count()
	var bare_visual := descendants(pa.data_card[bare_cell])

	mark_every_cell(g.state)
	g.state.revision += 1
	pa.set_card_zones()
	await settle(pa)
	var marked_cell : CardData = g.state.grids[0].cell_types[0]
	var marked_control : Control = pa.data_ui[marked_cell]
	var marked_slot : Control = marked_control.get_parent()

	check_impl(BoardPlan.is_marked(marked_cell),
			"TP-60: precondition: the board this measures is marked")
	check_impl(marked_slot == bare_slot and marked_control == bare_control,
			"TP-60: a marked cell binds into the very slot control the bare cell used")
	check_impl(marked_slot.get_child_count() == bare_slot_children,
			"TP-60: the slot holds the same number of controls marked as bare",
			"bare %d, marked %d" % [bare_slot_children, marked_slot.get_child_count()])
	check_impl(descendants(pa.data_card[marked_cell]) == bare_visual,
			"TP-60: the cell's card visual gained no node for its mark",
			"bare %d, marked %d" % [bare_visual, descendants(pa.data_card[marked_cell])])
	check_impl(get_tree().get_node_count() == bare_tree,
			"TP-60: marking all 25 cells added nothing to the tree",
			"bare %d, marked %d" % [bare_tree, get_tree().get_node_count()])
	await cleanup(g, pa)

# ==============================================================================
# TP-61 -- a mark is a card with no rim, and nothing else
# ==============================================================================

# `modulate` is the focus highlight and it propagates to a CanvasItem's children, so a mark marked
# with it would mark the real card stacked on it too. A mark is the outline style's width instead.
func test_no_mark_path_writes_modulate() -> void:
	var g := make_grid_game()
	var marked := mark_every_cell(g.state)
	var grid : GridData = g.state.grids[0]
	var cover := TestDecks.plan_deck()[7]
	cover.stage = CardData.Stage.PLAY
	grid.cells[grid.cell_index(0, 0)].datas.append(cover)
	g.state.revision += 1
	var pa := make_play_area()
	await settle(pa)

	var mark : CardData = marked[0]
	var mark_visual : CardVisual = pa.data_card[mark]
	var cover_visual : CardVisual = pa.data_card[cover]

	check(uniform_of(mark_visual.type, &"u_outline_width") == 0
			and uniform_of(mark_visual.rank, &"u_outline_width") == 0
			and uniform_of(mark_visual.suit, &"u_outline_width") == 0
			and uniform_of(mark_visual.art, &"u_outline_width") == 0,
			"TP-61: a marked cell draws no rim at all, on any of its elements",
			"frame %d, rank %d" % [uniform_of(mark_visual.type, &"u_outline_width"),
			uniform_of(mark_visual.rank, &"u_outline_width")])
	check(uniform_of(mark_visual.rank, &"u_fill_index") == mark.suit.palette_role(),
			"TP-61: and its rank pip in its own suit's colour, exactly as a played card does",
			"got %d, suit role %d" % [uniform_of(mark_visual.rank, &"u_fill_index"),
			mark.suit.palette_role()])
	check(uniform_of(mark_visual.suit, &"u_fill_mode") == CardOutline.Fill.TEXTURE,
			"TP-61: and its suit pip in the sheet's own colours, which is the played card's rule too")
	check(mark_visual.modulate == Color(1.0, 1.0, 1.0, 1.0),
			"TP-61: the mark's own visual never had modulate written",
			"got %s" % str(mark_visual.modulate))
	check(pa.data_ui[mark].modulate == Color(1.0, 1.0, 1.0, 1.0),
			"TP-61: the cell control the mark binds into never had modulate written",
			"got %s" % str(pa.data_ui[mark].modulate))
	check(mark_visual.visual.modulate == Color(1.0, 1.0, 1.0, 1.0)
			and mark_visual.visual.self_modulate == Color(1.0, 1.0, 1.0, 1.0),
			"TP-61: nor the node every face polygon hangs from")

	check(cover_visual.modulate == Color(1.0, 1.0, 1.0, 1.0),
			"TP-61: the real card stacked on the mark is untinted",
			"got %s" % str(cover_visual.modulate))
	check(uniform_of(cover_visual.type, &"u_outline_width") == CardOutline.STYLE.width
			and CardOutline.STYLE.width > 0,
			"TP-61: and it keeps the rim a played card has, which is the only difference on show",
			"cover %d, shipped %d" % [uniform_of(cover_visual.type, &"u_outline_width"),
			CardOutline.STYLE.width])
	check(uniform_of(cover_visual.type, &"u_outline_index")
			== CardOutline.STYLE.outline_index,
			"TP-61: in the shipped ink")
	await cleanup(g, pa)

# ==============================================================================
# TP-62 -- inspection reaches a covered mark
# ==============================================================================

# A covered mark is reduced to a sliver by the stack sizing, so the cell's own description is what
# carries its identity -- the one surface every inspector reads.
func test_a_covered_mark_is_named_by_its_cell() -> void:
	var g := make_grid_game()
	var grid : GridData = g.state.grids[0]
	var bare_cell : CardData = grid.cell_types[1]
	var bare_text := bare_cell.type.get_description()
	var marked := mark_every_cell(g.state)
	var mark : CardData = marked[0]
	var cover := TestDecks.plan_deck()[11]
	cover.stage = CardData.Stage.PLAY
	grid.cells[grid.cell_index(0, 0)].datas.append(cover)
	g.state.revision += 1
	var pa := make_play_area()
	await settle(pa)

	var text : String = mark.type.get_description()
	check(BoardPlan.is_marked(mark),
			"TP-62: the mark under the placed card is still in the data")
	check(g.state.card_at(BoardCoord.new(0, 0, 0, 0)) == cover,
			"TP-62: precondition: a real card covers that cell")
	check(text.contains(mark.suit.get_str()),
			"TP-62: the covered cell's description names the mark's suit", text)
	check(text.contains(mark.rank.get_str()),
			"TP-62: the covered cell's description names the mark's rank", text)
	check(text != bare_text,
			"TP-62: and an unmarked cell still reads as the bare cell it is", bare_text)
	check(not bare_text.contains(mark.suit.get_str()),
			"TP-62: precondition: the bare description names no mark at all", bare_text)
	await cleanup(g, pa)

# ==============================================================================
# TP-70 -- the reveal
# ==============================================================================

# The reveal walks the order the DEAL walked, not row-major, and holds every mark back until its
# own turn. Sampled every frame: what is asserted is the sequence, not a duration.
func test_the_reveal_deals_the_marks_in_the_deals_own_order() -> void:
	var g := make_grid_game()
	var marked := mark_every_cell(g.state)
	var order : Array[BoardCoord] = []
	for i : int in range(marked.size() - 1, -1, -1):
		order.append(g.state.cell_type_coord(marked[i]))
	g.state.plan_reveal_order = order
	var expected : Array[CardData] = []
	for coord : BoardCoord in order:
		expected.append(g.state.cell_type_at(coord))
	var pa := make_play_area()
	await settle(pa)

	var running : Array[bool] = [false]
	_reveal(pa, running)
	var sizes : Array[int] = []
	var order_held := true
	var flags_held := true
	var waited := 0.0
	while running[0] and waited < WATCHDOG_SECS:
		var left : int = pa._plan_reveal_pending.size()
		if sizes.is_empty() or sizes[sizes.size() - 1] != left: sizes.append(left)
		for i : int in expected.size():
			var revealed : bool = i < expected.size() - left
			if pa.data_card[expected[i]].mark_drawn != revealed: flags_held = false
			if i >= expected.size() - left and pa._plan_reveal_pending[i - (expected.size() - left)] \
					!= expected[i]: order_held = false
		await get_tree().process_frame
		waited += get_process_delta_time()

	check(not running[0], "TP-70a: the reveal finished", "waited %.1fs" % waited)
	check(sizes.size() >= 5,
			"TP-70a: the plan was dealt cell by cell rather than all at once",
			"%d distinct pending counts: %s" % [sizes.size(), str(sizes)])
	check(order_held,
			"TP-70a: every cell still waiting is the deal's own order, not row-major")
	check(flags_held,
			"TP-70a: a cell's mark is drawn exactly once the reveal has reached it")
	check(pa._plan_reveal_pending.is_empty() and g.state.plan_reveal_order.is_empty(),
			"TP-70a: the order is consumed once, so a rebuild after it draws every mark")
	var all_drawn := true
	for mark : CardData in expected:
		if not pa.data_card[mark].mark_drawn: all_drawn = false
	check(all_drawn, "TP-70a: every mark is printed when the reveal ends")
	await cleanup(g, pa)

# Drives `reveal_plan` alongside the sampling loop above and reports when it returns, which is what
# makes a reveal that never finishes a FAILING test rather than a hung run.
func _reveal(pa: PlayArea, running: Array[bool]) -> void:
	running[0] = true
	await pa.reveal_plan()
	running[0] = false

# Every effect in this project runs headless. A show with no view deals its board and animates
# nothing, and the bounded wait is what catches a reveal that awaited a timer anyway.
func test_a_show_with_no_view_deals_its_board_and_reveals_nothing() -> void:
	var previous : RunState = Main.save_info
	seed(424242)
	var g := Game.new()
	CardEnvironment.CURRENT = g
	var run := RunState.new()
	run.world_seed = 4242
	run.current_node_id = 11
	run.card_datas = TestDecks.plan_deck()
	run.rule_datas = TestDecks.standard_rules()
	Main.save_info = run

	var running : Array[bool] = [true]
	_start_show(g, running)
	var waited := 0.0
	while running[0] and waited < WATCHDOG_SECS:
		await get_tree().process_frame
		waited += get_process_delta_time()

	check(not running[0], "TP-70: a show start with no view returns rather than awaiting a reveal",
			"waited %.1fs" % waited)
	check(g.view == null, "TP-70: precondition: this show has no view")
	var marks := 0
	for type_card : CardData in g.state.grids[0].cell_types:
		if BoardPlan.is_marked(type_card): marks += 1
	check(marks == 25, "TP-70: the board is dealt regardless", "%d of 25 marked" % marks)
	check(g.state.plan_reveal_order.size() == marks,
			"TP-70: the walk order is recorded and left unconsumed, since nothing consumed it",
			"%d recorded" % g.state.plan_reveal_order.size())
	CardEnvironment.CURRENT = null
	Main.save_info = previous
	g.free()

# The real show start, reported the same way the reveal is: a fresh deal that never returns is a
# failed check here instead of a run that stops printing.
func _start_show(g: Game, running: Array[bool]) -> void:
	await g._start_fresh_show()
	running[0] = false

# ==============================================================================
# TP-76 -- the reveal is paced by the board that started it
# ==============================================================================

# ANY screen entering and leaving the tree takes `CardEnvironment.CURRENT` with it, and a suite
# running beside this one does exactly that -- so a reveal awaiting between cells wakes up on a
# board hosted without a Game, and the cells it had left must still be dealt.
func test_a_reveal_outlives_the_screen_that_holds_the_environment() -> void:
	var g := make_grid_game()
	var marked := mark_every_cell(g.state)
	var order : Array[BoardCoord] = []
	for mark : CardData in marked:
		order.append(g.state.cell_type_coord(mark))
	g.state.plan_reveal_order = order
	var pa := make_play_area()
	await settle(pa)

	var running : Array[bool] = [false]
	_reveal(pa, running)
	var dealt : int = marked.size() - pa._plan_reveal_pending.size()
	var passing := FakeEnvironment.new()
	add_child(passing)
	remove_child(passing)
	passing.free()

	check(CardEnvironment.get_current_game() == null,
			"TP-76: precondition: the board is now hosted without a Game")
	check(dealt > 0 and not pa._plan_reveal_pending.is_empty(),
			"TP-76: precondition: the reveal lost it mid-deal, with cells still to come",
			"%d dealt, %d pending" % [dealt, pa._plan_reveal_pending.size()])
	var waited := 0.0
	while running[0] and waited < WATCHDOG_SECS:
		await get_tree().process_frame
		waited += get_process_delta_time()

	check(not running[0],
			"TP-76: the reveal finishes on the board it started on, with no environment to read",
			"waited %.1fs" % waited)
	var all_drawn := true
	for mark : CardData in marked:
		if not pa.data_card[mark].mark_drawn: all_drawn = false
	check(all_drawn, "TP-76: every mark is printed, the cells after the loss included")
	CardEnvironment.CURRENT = g
	await cleanup(g, pa)

# ==============================================================================
# THE HELD-CARD FIXTURE -- one real GameView, driven by synthesized device input
# ==============================================================================

# A REAL GameView, because what is claimed is what a PLAYER picking a card up sees: the pick-up has
# to travel the platform's own route -- a viewport, an input action -- and not a call to a handler.
var view : GameView
var game : Game
var pa : PlayArea
var picture_vp : SubViewport
var input : TestInput
var prev_run : RunState
var prev_save_info : RunState
## The Entrance card this fixture picks up, and the three cells marked against it.
var held_card : CardData
var rank_cell : BoardCoord
var both_cell : BoardCoord
var miss_cell : BoardCoord

func setup_view() -> void:
	backup_real_save(suite_tag())
	prev_run = RunManager.run
	prev_save_info = Main.save_info
	var run := RunManager.new_run(TestDecks.deck_standard_52(), rules_with_no_planner())
	Main.save_info = run
	run.pending_goal = 1
	run.pending_node_id = 2
	view = GAME_VIEW_SCENE.instantiate()
	picture_vp = TestGameViewHost.host(self, view)
	input = TestInput.driving(self, picture_vp)
	await get_tree().process_frame
	await get_tree().process_frame
	game = view.game
	pa = view.play_area
	await game.next()
	await game.next()
	pa.flush_rebuild()
#⚠ ZOOM IN FIRST. A show opens on the all-grids view, where a click on a grid is orientation and
#places nothing; a card is picked up and put down only once a grid is focused.
	pa.focus_grid(0)
	held_card = an_entrance_card()
	await settle_on(held_card)
	mark_three_cells()
	await settle_on(held_card)

func teardown_view() -> void:
	input.queue_free()
	picture_vp.queue_free()
	await get_tree().process_frame
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = prev_run
	Main.save_info = prev_save_info

# THE BOARD THIS FIXTURE NEEDS IS THE ONE IT MARKS ITSELF: with the planner in the rules row every
# cell carries a dealt mark, and what a held card agrees with is then a property of the shuffle.
func rules_with_no_planner() -> Array[CardData]:
	var out : Array[CardData] = []
	for card : CardData in TestDecks.standard_rules():
		if not (card.skill is SkillBoardPlanner): out.append(card)
	return out

# The card this fixture picks up: one the board offers as a focus target in the Entrance, which is
# what a pointer or a focus ring can actually reach.
func an_entrance_card() -> CardData:
	for control : Control in pa.ui_data:
		var data : CardData = pa.ui_data[control]
		if control.focus_mode != Control.FOCUS_ALL or not control.is_visible_in_tree(): continue
		if game.state.grid_position_of(data).is_entrance(): return data
	return null

# THREE MARKS AGAINST THE HELD CARD -- one agreeing on its rank alone, one on rank and suit, one on
# nothing -- and every other cell left bare, so the highlight has a shape it can fail to have.
func mark_three_cells() -> void:
	rank_cell = BoardCoord.new(0, 0, 0, 0)
	both_cell = BoardCoord.new(0, 1, 0, 0)
	miss_cell = BoardCoord.new(0, 2, 0, 0)
	for type_card : CardData in game.state.grids[0].cell_types:
		BoardPlan.clear_mark(type_card)
	game.effect_api.grant_mark(rank_cell, mark_source(held_card.rank, another_suit(held_card.suit)))
	game.effect_api.grant_mark(both_cell, mark_source(held_card.rank, held_card.suit))
	game.effect_api.grant_mark(miss_cell,
			mark_source(another_rank(held_card.rank), another_suit(held_card.suit)))
	pa.flush_rebuild()

# A card that exists only to be copied onto a cell. Its pips are DUPLICATES: `with_suit` rebinds the
# suit's backref to the card it is handed to, so a live card's own pip would lose the board.
func mark_source(rank: PipRank, suit: PipSuit) -> CardData:
	var source := CardData.new()
	source.with_rank(rank.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as PipRank)
	source.with_suit(suit.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as PipSuit)
	return source

# A suit that does NOT agree with this one, so a mark built from it can agree on rank alone.
func another_suit(suit: PipSuit) -> PipSuit:
	var knife := PipSuitKnife.new()
	if not PipComparator.printed_same(suit, knife): return knife
	return PipSuitHoop.new()

# A rank that does NOT agree with this one, for the cell that has to agree with nothing.
func another_rank(rank: PipRank) -> PipRank:
	var two : PipRank = PipRankNumeral.new().with_value(2)
	if not PipComparator.printed_same(rank, two): return two
	return PipRankNumeral.new().with_value(7)

# Wait until the control this fixture CLICKS stops moving: the board eases into its focused zoom,
# and a click landing mid-ease lands where the control was rather than where it is.
func settle_on(card: CardData) -> void:
	var last := Vector2(INF, INF)
	var waited := 0.0
	while waited < WATCHDOG_SECS:
		await get_tree().process_frame
		waited += get_process_delta_time()
		var now : Vector2 = centre_of(card)
		if now.is_equal_approx(last): return
		last = now

# Bounded by the watchdog, so a placement that never commits fails a check instead of hanging a run.
func wait_for(predicate: Callable) -> bool:
	var waited := 0.0
	while not (predicate.call() as bool) and waited < WATCHDOG_SECS:
		await get_tree().process_frame
		waited += get_process_delta_time()
	return predicate.call() as bool

func centre_of(card: CardData) -> Vector2:
	return (pa.data_ui[card] as Control).get_global_rect().get_center()

func mark_visual(coord: BoardCoord) -> CardVisual:
	return pa.data_card[game.state.cell_type_at(coord)]

# WHAT THE SHADER WAS ACTUALLY HANDED, as a `MarkMatch.Property` mask: which of a card's four
# elements draw their rim in `palette_index`. Never a flag the refresh wrote down.
func rimmed_properties(visual: CardVisual, palette_index: int) -> int:
	var drawn := 0
	if uniform_of(visual.rank, &"u_outline_index") == palette_index:
		drawn |= MarkMatch.Property.RANK
	if uniform_of(visual.suit, &"u_outline_index") == palette_index:
		drawn |= MarkMatch.Property.SUIT
	if uniform_of(visual.art, &"u_outline_index") == palette_index:
		drawn |= MarkMatch.Property.TALENT
	if uniform_of(visual.stamp, &"u_outline_index") == palette_index:
		drawn |= MarkMatch.Property.HAT
	return drawn

# Every marked cell whose drawn rims disagree with what the match test says about `tested`, which is
# the whole claim: the view asks, and the answer is the board's rather than the view's own idea.
func cells_disagreeing(tested: CardData, palette_index: int) -> Array[String]:
	var out : Array[String] = []
	var grid : GridData = game.state.grids[0]
	for ci : int in grid.cell_types.size():
		var mark : CardData = grid.cell_types[ci]
		if not BoardPlan.is_marked(mark): continue
		var coord := BoardCoord.new(0, ci % grid.grid_width, ci / grid.grid_width, 0)
		var expected := 0
		if tested: expected = await MarkMatch.matches_at(game.state, tested, coord)
		var drawn := rimmed_properties(mark_visual(coord), palette_index)
		if drawn != expected:
			out.append("(%d,%d) match %d drew %d" % [coord.x, coord.y, expected, drawn])
	return out

# The highlight has to be up in the same breath as the pick-up -- a board answering a frame later
# would flicker under a drag. Bounded by the board's OWN step, never by a wall-clock number.
func time_to_light(coord: BoardCoord) -> float:
	var waited := 0.0
	while waited < game.get_delay():
		if rimmed_properties(mark_visual(coord), PaletteDB.ROLES.match_rim) != 0: return waited
		await get_tree().process_frame
		waited += get_process_delta_time()
	return waited

# ==============================================================================
# TP-63 -- holding a card lights exactly the cells the match test reports
# ==============================================================================

# Driven through the viewport in BOTH the modes that can pick a card up, because a highlight wired
# to one route only is a highlight half the players never see.
func test_holding_a_card_lights_the_marks_it_agrees_with() -> void:
	var here := await MarkMatch.matches_at(game.state, held_card, both_cell)
	var nowhere := await MarkMatch.matches_at(game.state, held_card, miss_cell)
	check(here != 0 and nowhere == 0,
			"TP-63: precondition: one marked cell agrees with this card and one does not",
			"%d and %d" % [here, nowhere])

	await input.click(centre_of(held_card))
	check(pa.selected_cards.has(held_card), "TP-63: precondition: the mouse picked the card up",
			str(pa.selected_cards.size()))
	var took := await time_to_light(both_cell)
	check(took < game.get_delay(),
			"TP-63: the highlight is up within the board's own step of the pick-up",
			"%.3f s of a %.3f s step" % [took, game.get_delay()])
	var wrong := await cells_disagreeing(held_card, PaletteDB.ROLES.match_rim)
	check(wrong.is_empty(),
			"TP-63: a mouse pick-up lights exactly the cells the match test reports", str(wrong))

	await input.click(centre_of(held_card), MOUSE_BUTTON_RIGHT)
	check(pa.selected_cards.is_empty(), "TP-63: precondition: right-click released the card")
	var released := await cells_disagreeing(null, PaletteDB.ROLES.match_rim)
	check(released.is_empty(), "TP-63: releasing the card clears every highlight", str(released))

	(pa.data_ui[held_card] as Control).grab_focus()
	await get_tree().process_frame
	await input.key_tap(KEY_ENTER)
	check(pa.selected_cards.has(held_card),
			"TP-63: precondition: ui_accept picked the same card up", str(pa.selected_cards.size()))
	var keyed := await cells_disagreeing(held_card, PaletteDB.ROLES.match_rim)
	check(keyed.is_empty(),
			"TP-63: a keyboard pick-up lights the same cells a mouse one does", str(keyed))
	(pa.data_ui[held_card] as Control).grab_focus()
	await get_tree().process_frame
	await input.key_tap(KEY_ESCAPE)
	check(pa.selected_cards.is_empty(), "TP-63: ui_cancel drops the card")
	var cancelled := await cells_disagreeing(null, PaletteDB.ROLES.match_rim)
	check(cancelled.is_empty(), "TP-63: and clears the highlight with it", str(cancelled))

# ==============================================================================
# TP-64 -- the highlight is the ELEMENTS' outlines, never a tint
# ==============================================================================

# A tint would be `modulate`, which is the focus highlight and reaches every child -- so it would
# also tint whatever is stacked on the mark. Each agreeing element takes its own rim instead.
func test_the_highlight_lights_elements_rather_than_tinting_the_cell() -> void:
	var visual := mark_visual(rank_cell)
	var control : Control = pa.data_ui[game.state.cell_type_at(rank_cell)]
	var control_was := control.modulate
	var visual_was := visual.modulate
	await input.click(centre_of(held_card))
	check(pa.selected_cards.has(held_card), "TP-64: precondition: the card is held")
	var agreed := await MarkMatch.matches_at(game.state, held_card, rank_cell)
	check(agreed == MarkMatch.Property.RANK,
			"TP-64: precondition: this cell's mark agrees on rank alone", str(agreed))

	check(rimmed_properties(visual, PaletteDB.ROLES.match_rim) == MarkMatch.Property.RANK,
			"TP-64: the rank pip takes the match rim and the suit pip does not",
			"rank ink %d, suit ink %d" % [uniform_of(visual.rank, &"u_outline_index"),
			uniform_of(visual.suit, &"u_outline_index")])
	check(uniform_of(visual.rank, &"u_outline_width") == CardOutline.STYLE.width
			and uniform_of(visual.suit, &"u_outline_width") == 0,
			"TP-64: the element that agrees takes a rim back, on a mark that draws none",
			"rank %d, suit %d" % [uniform_of(visual.rank, &"u_outline_width"),
			uniform_of(visual.suit, &"u_outline_width")])
	check(uniform_of(visual.type, &"u_outline_width") == 0,
			"TP-64: the cell frame under them stays rimless, so the mark still reads as a mark")
	check(control.modulate == control_was and visual.modulate == visual_was,
			"TP-64: and nothing was tinted -- modulate is what it was on the control and the visual",
			"%s / %s" % [str(control.modulate), str(visual.modulate)])
	await input.click(centre_of(held_card), MOUSE_BUTTON_RIGHT)

# ==============================================================================
# TP-65 -- a card agreeing with nothing says nothing
# ==============================================================================

# No popup, no alert, no rim: the absence is the whole feature, so it is measured as an absence --
# the view's node count, the alert kind the shader was handed, and the rims that stayed off.
func test_a_card_agreeing_with_nothing_says_nothing() -> void:
	var visual := mark_visual(miss_cell)
	var before := descendants(view)
	await input.click(centre_of(held_card))
	check(pa.selected_cards.has(held_card), "TP-65: precondition: the card is held")
	var agreed := await MarkMatch.matches_at(game.state, held_card, miss_cell)
	check(agreed == 0,
			"TP-65: precondition: this cell's mark agrees with the held card on nothing", str(agreed))

	check(rimmed_properties(visual, PaletteDB.ROLES.match_rim) == 0
			and rimmed_properties(visual, PaletteDB.ROLES.match_rim_active) == 0,
			"TP-65: no element of it is rimmed in either match ink")
	check(uniform_of(visual.rank, &"u_outline_width") == 0
			and uniform_of(visual.suit, &"u_outline_width") == 0,
			"TP-65: it still draws no rim at all, which is what a mark at rest looks like")
	check(uniform_of(visual.rank, &"u_alert_kind") == CardOutline.Alert.NONE
			and uniform_of(pa.data_card[held_card].rank, &"u_alert_kind") == CardOutline.Alert.NONE,
			"TP-65: neither the mark nor the held card declares an outline alert")
	check(descendants(view) == before,
			"TP-65: and holding a card over it adds no node to the view -- no popup, no label",
			"%d before, %d held" % [before, descendants(view)])
	await input.click(centre_of(held_card), MOUSE_BUTTON_RIGHT)

# ==============================================================================
# TP-83 -- the landing feedback, derived and un-derived
# ==============================================================================

# The activated rim is DERIVED on every refresh from the same match test the highlight asks, so it
# survives a rebuild and an undo takes it away with nothing to un-persist.
func test_a_landing_that_matched_activates_the_elements_that_agreed() -> void:
	var agreed := await MarkMatch.matches_at(game.state, held_card, both_cell)
	check(agreed & MarkMatch.Property.RANK and agreed & MarkMatch.Property.SUIT,
			"TP-83: precondition: the cell it lands on agrees on rank and suit", str(agreed))
	await input.click(centre_of(held_card))
	await input.click(centre_of(game.state.cell_type_at(both_cell)))
	var landed := await wait_for(func() -> bool:
			return not game.processing and game.state.card_at(both_cell) == held_card)
	check(landed, "TP-83: precondition: the card was placed on the marked cell")
	pa.flush_rebuild()
	await get_tree().process_frame

	var visual : CardVisual = pa.data_card[held_card]
	check(rimmed_properties(visual, PaletteDB.ROLES.match_rim_active) == agreed,
			"TP-83: the landed card's agreeing elements read the activated rim",
			"drew %d of %d" % [rimmed_properties(visual, PaletteDB.ROLES.match_rim_active), agreed])
	check(uniform_of(visual.stamp, &"u_outline_index") == CardOutline.STYLE.outline_index
			and uniform_of(visual.type, &"u_outline_index") == CardOutline.STYLE.outline_index,
			"TP-83: the elements that agreed with nothing keep the card's ordinary rim",
			"stamp %d, frame %d" % [uniform_of(visual.stamp, &"u_outline_index"),
			uniform_of(visual.type, &"u_outline_index")])
	check(rimmed_properties(visual, PaletteDB.ROLES.match_rim) == 0,
			"TP-83: and none of them is still wearing the held card's own highlight")

	await game.undo()
	pa.flush_rebuild()
	await get_tree().process_frame
	check(game.state.card_at(both_cell) == null,
			"TP-83: precondition: undo took the card back off the cell")
#Asked of the WHOLE board rather than of that one card: an undo puts a placed card back where it was
#drawn from, so a check aimed at the card alone would pass by looking at nothing.
	var still_active : Array[String] = []
	for card : CardData in pa.data_card:
		if rimmed_properties(pa.data_card[card], PaletteDB.ROLES.match_rim_active) != 0:
			still_active.append(str(card))
	check(still_active.is_empty(),
			"TP-83: after undo no element anywhere on the board reads the activated rim",
			str(still_active))
