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
