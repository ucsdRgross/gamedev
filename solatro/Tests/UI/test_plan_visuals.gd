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
## Stretches the deal so a once-a-frame sampler sees one cell at a time, not the whole cascade.
const OBSERVABLE_REVEAL_MULTIPLIER := 10.0

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
	behavior_section("THE OPENING REVEAL IS A CASCADE OVER ONE TUNABLE DURATION")
	await test_the_reveal_cascades_over_one_tunable_duration()
	behavior_section("A CARD PUT DOWN MID-DEAL IS STILL AN UNDO STEP")
	await test_a_placement_during_the_reveal_can_be_undone()
	behavior_section("A HELD CARD LIGHTS EVERY MARK IT WOULD AGREE WITH")
	await setup_view()
	await test_holding_a_card_lights_the_marks_it_agrees_with()
	await test_a_committed_show_lights_only_the_grid_it_can_place_in()
	await test_the_highlight_lights_elements_rather_than_tinting_the_cell()
	await test_a_card_agreeing_with_nothing_says_nothing()
	behavior_section("A LANDED CARD WEARS THE ACTIVATED RIM UNTIL UNDO")
	await test_a_landing_that_matched_activates_the_elements_that_agreed()
	behavior_section("EVERY SHIMMER ON THE BOARD DRIFTS TOGETHER")
	await test_every_shimmer_on_the_board_reads_one_phase()
	behavior_section("THE LAYER VIEW DRAWS THE MARKS AND REFUSES THE BOARD")
	await test_the_layer_view_refuses_a_placement()
	await test_the_layer_view_opens_focused_and_in_the_overview()
	await test_the_layer_view_focuses_and_inspects_the_mark()
	await test_the_layer_toggle_is_reachable_by_every_input_mode()
	await test_the_layer_view_peeks_while_the_face_button_is_held()
	await test_the_layer_view_closes_on_a_board_mutation()
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

	var snapshot := snapshot_settings("plan_")
	SettingsManager.settings.plan_reveal_multiplier = OBSERVABLE_REVEAL_MULTIPLIER
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
	restore_settings_snapshot(snapshot)
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

	var snapshot := snapshot_settings("plan_")
	SettingsManager.settings.plan_reveal_multiplier = OBSERVABLE_REVEAL_MULTIPLIER
	var running : Array[bool] = [false]
	_reveal(pa, running)
#The cascade deals its first cell on the frame after it is scheduled, so the loss is staged once the
#deal is under way -- which is the case this is about.
	await get_tree().process_frame
	await get_tree().process_frame
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
	restore_settings_snapshot(snapshot)
	CardEnvironment.CURRENT = g
	await cleanup(g, pa)

# ==============================================================================
# TP-92 -- the reveal is a cascade over one tunable duration
# ==============================================================================

## The pacing this measures at: a stagger of a few milliseconds cannot be sampled once a frame.
const CASCADE_DELAY := 1.0
## Deliberately NOT the shipped default, so a reveal that ignored the knob would measure differently.
const CASCADE_MULTIPLIER := 2.0

# THE WHOLE deal takes one multiple of the delay whatever the cell count, so the cells START that
# span apart and a cell is still spinning when the ones after it arrive -- a cascade, not a queue.
func test_the_reveal_cascades_over_one_tunable_duration() -> void:
	var plan_snapshot := snapshot_settings("plan_")
	var delay_snapshot := snapshot_settings("base_delay")
	SettingsManager.settings.base_delay = CASCADE_DELAY
	SettingsManager.settings.plan_reveal_multiplier = CASCADE_MULTIPLIER
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

	var delay := g.get_delay()
	var total := CASCADE_MULTIPLIER * delay
	var stagger := total / float(expected.size())
	var starts : Array[float] = []
	var overlaps := 0
	var order_held := true
	var running : Array[bool] = [false]
	_reveal(pa, running)
	var began := Time.get_ticks_msec()
	var waited := 0.0
#Sampled until every start is in rather than until the coroutine returns: the last cell starts on
#the very frame the cascade ends, so a loop keyed on the return misses it.
	while starts.size() < expected.size() and waited < WATCHDOG_SECS:
		var dealt : int = expected.size() - pa._plan_reveal_pending.size()
		while starts.size() < dealt:
			var k := starts.size()
			starts.append(float(Time.get_ticks_msec() - began) / 1000.0)
			if not pa.data_card[expected[k]].mark_drawn: order_held = false
			if k > 0 and _is_spinning(pa.data_card[expected[k - 1]]): overlaps += 1
		await get_tree().process_frame
		waited += get_process_delta_time()
	var spinning := true
	while spinning and waited < WATCHDOG_SECS:
		spinning = false
		for mark : CardData in expected:
			if _is_spinning(pa.data_card[mark]): spinning = true
		if spinning:
			await get_tree().process_frame
			waited += get_process_delta_time()
	var finished_at := float(Time.get_ticks_msec() - began) / 1000.0
#Read off `anim_spin` itself rather than retyping the fraction it turns a delay into, so the bound
#below cannot drift away from the spin it is about.
	var spin_secs : float = pa.data_card[expected[0]].anim_spin(delay)
	restore_settings_snapshot(plan_snapshot)
	restore_settings_snapshot(delay_snapshot)

	check(starts.size() == expected.size(),
			"TP-92: precondition: every cell's start was sampled",
			"%d of %d sampled after %.1fs" % [starts.size(), expected.size(), waited])
	check(spin_secs > 0.0, "TP-92: precondition: a spin has a length of its own",
			"%.3f s" % spin_secs)
	check(not running[0], "TP-92: the cascade dealt every cell", "waited %.1fs" % waited)
	check(order_held,
			"TP-92: each cell that starts is the next one in the deal's own walk order")
#The probe samples once a frame and a scheduled start lands on the frame after its deadline, so a
#start is read a frame or two late -- one whole stagger of slack, still an order tighter than the
#half-a-delay per cell this replaced.
	var tolerance := stagger
	var worst := 0.0
	var worst_cell := 0
	for k : int in starts.size():
		var drift := absf(starts[k] - float(k) * stagger)
		if drift > worst:
			worst = drift
			worst_cell = k
	check(worst <= tolerance,
			"TP-92: cell k starts k shares of the whole duration in, the knob setting that duration",
			"stagger %.3f s, worst drift %.3f s at cell %d" % [stagger, worst, worst_cell])
	var last_start : float = starts[starts.size() - 1] if not starts.is_empty() else INF
	check(last_start < total,
			"TP-92: the last cell has started before the whole duration is up",
			"last start %.3f s of %.3f s" % [last_start, total])
	check(overlaps > 0,
			"TP-92: a cell starts while the cell before it is still spinning",
			"%d of %d starts overlapped the previous spin" % [overlaps, starts.size()])
	check(finished_at <= total + spin_secs + tolerance,
			"TP-92: the whole deal is over within that duration plus one spin",
			"last spin ended %.2f s, budget %.2f s"
			% [finished_at, total + spin_secs + tolerance])
	await cleanup(g, pa)

# A spin is IN FLIGHT while its own tween still turns the card, which is the state the overlap claim
# is about -- a wall clock alone cannot see it.
func _is_spinning(visual: CardVisual) -> bool:
	var spin := visual.spin_tween
	return spin != null and spin.is_valid() and spin.is_running()

# ==============================================================================
# TP-94 -- a card put down while the plan is still dealing
# ==============================================================================

## A goal no opening placement can reach, so the show cannot resolve while the deal is running.
const UNREACHED_GOAL := 1_000_000_000
## The seed this show is dealt at, so the board a card lands on is the same board every run.
const MID_DEAL_SEED := 20260913

# THE BOARD IS LIVE WHILE THE DEAL DRAWS -- nothing locks input for it -- so a card can go down
# before the last mark is printed, and that placement has to be an undo step with the opening board
# underneath it to come back to.
func test_a_placement_during_the_reveal_can_be_undone() -> void:
	var tag := suite_tag() + "_mid_deal"
	var outer_run : RunState = RunManager.run
	var outer_save_info : RunState = Main.save_info
	var snapshot := snapshot_settings("plan_")
	SettingsManager.settings.plan_reveal_multiplier = OBSERVABLE_REVEAL_MULTIPLIER
	var booted : GameView = await TestGameViewHost.boot_show(self, tag,
			TestDecks.deck_standard_52(), TestDecks.standard_rules(), UNREACHED_GOAL, 2,
			MID_DEAL_SEED)
	var g : Game = booted.game
	var board : PlayArea = booted.play_area
	var dealing := await wait_for(func() -> bool:
			return not board._plan_reveal_pending.is_empty() 					and _topmost_entrance_card(g.state) != null)
	check(dealing, "TP-94: precondition: the Entrance is filled while cells are still to be dealt",
			"%d cells pending" % board._plan_reveal_pending.size())
	var coord := _first_marked_cell(g.state)
	check(not coord.is_nowhere(), "TP-94: precondition: the deal marked a cell to land on")

	var card : CardData = _topmost_entrance_card(g.state)
	var stack : Array[CardData] = await g.try_grab(card)
	var placed := await g.try_place(stack, g.state.cell_type_at(coord))
	var landed := await wait_for(func() -> bool:
			return not g.processing and g.state.card_at(coord) == card)
	check(placed and landed,
			"TP-94: precondition: the card went down mid-deal, through the board's own path",
			"try_place %s, landed %s" % [str(placed), str(landed)])
	var dealt := await wait_for(func() -> bool: return board._plan_reveal_pending.is_empty())
	check(dealt, "TP-94: precondition: the deal finished",
			"%d cells pending" % board._plan_reveal_pending.size())
	await get_tree().process_frame

	check(g.save_history.size() == 2,
			"TP-94: the opening board is history's first snapshot and the placement its second",
			"%d snapshots" % g.save_history.size())
	await g.undo()
	check(g.state.card_at(coord) == null,
			"TP-94: undo hands the card back, because the opening board was committed before the deal",
			str(g.state.card_at(coord)))
	check(BoardPlan.is_marked(g.state.cell_type_at(coord)),
			"TP-94: and the cell it came off still wears the mark the deal printed there")

	restore_settings_snapshot(snapshot)
	booted.queue_free()
	await get_tree().process_frame
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(tag)
	RunManager.run = outer_run
	Main.save_info = outer_save_info

# The card a player can actually pick up mid-deal: the topmost of the first filled Entrance slot.
# Null until the opening refill has run, which is what tells this row the deal has got that far.
func _topmost_entrance_card(state: GameData) -> CardData:
	for column : ArrayCardData in state.upper_zone:
		if not column.datas.is_empty(): return column.datas.back()
	return null

# A cell the deal marked, read off the board rather than marked by this row: what the undo claim is
# about is the mark the SHOW printed. NOWHERE when the deal marked nothing, which fails a check.
func _first_marked_cell(state: GameData) -> BoardCoord:
	for type_card : CardData in state.grids[0].cell_types:
		if BoardPlan.is_marked(type_card): return state.cell_type_coord(type_card)
	return BoardCoord.NOWHERE

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
	await mark_against_a_fresh_card()

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

# THE THREE MARKS AND THE CARD THEY ARE BUILT AGAINST, re-derived from the board as it stands
# now: an undo replaces the whole state with a duplicate, so the card this fixture held before
# one is not a card on the board after it.
func mark_against_a_fresh_card() -> void:
	held_card = entrance_card_besides(null)
	await settle_on(held_card)
	mark_three_cells()
	await settle_on(held_card)

# THE BOARD THIS FIXTURE NEEDS IS THE ONE IT MARKS ITSELF: with the planner in the rules row every
# cell carries a dealt mark, and what a held card agrees with is then a property of the shuffle.
func rules_with_no_planner() -> Array[CardData]:
	var out : Array[CardData] = []
	for card : CardData in TestDecks.standard_rules():
		if not (card.skill is SkillBoardPlanner): out.append(card)
	return out

# The card this fixture picks up: one the board offers as a focus target in the Entrance, which is
# what a pointer or a focus ring can actually reach. `kept` is the card a caller is already holding,
# so a placement made to commit the show is made with a card the fixture still needs in hand.
func entrance_card_besides(kept: CardData) -> CardData:
	for control : Control in pa.ui_data:
		var data : CardData = pa.ui_data[control]
		if data == kept: continue
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
	return properties_pushing(visual, &"u_outline_index", palette_index)

# Which of a card's four elements are pushing `value` for `uniform` -- THE one place this suite reads
# a per-element uniform, so the rim's ink and the rim's alert are asked the same question.
func properties_pushing(visual: CardVisual, uniform: StringName, value: int) -> int:
	var drawn := 0
	if uniform_of(visual.rank, uniform) == value:
		drawn |= MarkMatch.Property.RANK
	if uniform_of(visual.suit, uniform) == value:
		drawn |= MarkMatch.Property.SUIT
	if uniform_of(visual.art, uniform) == value:
		drawn |= MarkMatch.Property.TALENT
	if uniform_of(visual.stamp, uniform) == value:
		drawn |= MarkMatch.Property.HAT
	return drawn

# THE PHASE ONE ELEMENT IS ACTUALLY CARRYING, read off the live material. `uniform_of`'s twin: that
# one narrows to int for the palette indices every other row asks about.
func phase_of(poly: Polygon2D) -> float:
	var mat := poly.material as ShaderMaterial
	var phase : float = mat.get_shader_parameter(&"u_alert_clock")
	return phase

# Every DISTINCT phase any shimmering element anywhere on the board is carrying. One entry is the
# whole claim: the census is taken over the board rather than over two named cards, so a third card
# drifting on a clock of its own cannot hide behind them.
func shimmer_phases() -> Array[float]:
	var out : Array[float] = []
	for card : CardData in pa.data_card:
		var visual : CardVisual = pa.data_card[card]
		for poly : Polygon2D in [visual.rank, visual.suit, visual.art, visual.stamp]:
			if uniform_of(poly, &"u_alert_kind") != CardOutline.Alert.SHIMMER: continue
			if not out.has(phase_of(poly)): out.append(phase_of(poly))
	return out

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

# A SECOND GRID, appended the way a rule card appends one mid-show, carrying one mark the held card
# agrees with. Returns that cell -- the one a committed show may no longer light.
func add_a_second_marked_grid() -> BoardCoord:
	game.effect_api.add_grid(GridData.new())
	var added : GridData = game.state.grids[1]
	for type_card : CardData in added.cell_types:
		BoardPlan.clear_mark(type_card)
	var coord := BoardCoord.new(1, 0, 0, 0)
	game.effect_api.grant_mark(coord, mark_source(held_card.rank, held_card.suit))
	pa.flush_rebuild()
	pa.focus_grid(0)
	return coord

# THE COMMITMENT IS MADE THE WAY A PLAYER MAKES IT: another Entrance card, picked up and put down
# through the viewport, so `held_card` is still in hand afterwards with its own marks untouched.
# It lands on the far corner cell, which no mark and no card of this fixture is on.
func commit_the_show_to_grid_0() -> bool:
	var grid : GridData = game.state.grids[0]
	var bare := BoardCoord.new(0, grid.grid_width - 1, grid.grid_height - 1, 0)
	var other := entrance_card_besides(held_card)
	await settle_on(other)
	return await land_on(bare, other)

# A PLACEMENT MADE THE PLAYER'S OWN WAY -- the card picked up and the cell clicked through the
# viewport -- and whether the board took it. The rebuild is flushed, so the caller reads the board
# after the landing rather than the board mid-rebuild.
func land_on(coord: BoardCoord, card: CardData) -> bool:
	await input.click(centre_of(card))
	await input.click(centre_of(game.state.cell_type_at(coord)))
	var landed := await wait_for(func() -> bool:
			return not game.processing and game.state.card_at(coord) == card)
	pa.flush_rebuild()
	await get_tree().process_frame
	return landed

# ==============================================================================
# TP-63 -- and only in the grid the show can still place into
# ==============================================================================

# The Entrance commits to one grid at its first placement and every other grid refuses silently, so
# a rim there would promise a placement the board drops. Both halves discriminate: an uncommitted
# board lights both grids, and the SAME card lights only the committed one afterwards.
func test_a_committed_show_lights_only_the_grid_it_can_place_in() -> void:
	var second_cell := add_a_second_marked_grid()
	await settle_on(held_card)
	check(game.state.committed_grid == -1,
			"TP-63: precondition: nothing is placed yet, so the show is committed to no grid",
			str(game.state.committed_grid))
	var here := await MarkMatch.matches_at(game.state, held_card, both_cell)
	var there := await MarkMatch.matches_at(game.state, held_card, second_cell)
	check(here != 0 and there != 0,
			"TP-63: precondition: one mark in each grid agrees with the card",
			"%d and %d" % [here, there])
	check(mark_visual(second_cell) != null,
			"TP-63: precondition: the second grid's mark is drawn")

	await input.click(centre_of(held_card))
	check(pa.selected_cards.has(held_card),
			"TP-63: precondition: the card is held", str(pa.selected_cards.size()))
	await time_to_light(both_cell)
	check(rimmed_properties(mark_visual(both_cell), PaletteDB.ROLES.match_rim) == here
			and rimmed_properties(mark_visual(second_cell), PaletteDB.ROLES.match_rim) == there,
			"TP-63: uncommitted, the card lights its agreeing elements in BOTH grids",
			"grid 0 drew %d of %d, grid 1 drew %d of %d" % [
			rimmed_properties(mark_visual(both_cell), PaletteDB.ROLES.match_rim), here,
			rimmed_properties(mark_visual(second_cell), PaletteDB.ROLES.match_rim), there])
	await input.click(centre_of(held_card), MOUSE_BUTTON_RIGHT)
	check(pa.selected_cards.is_empty(), "TP-63: precondition: the card went back down")

	var committed := await commit_the_show_to_grid_0()
	check(committed and game.state.committed_grid == 0,
			"TP-63: precondition: a real placement committed the show to grid 0",
			"landed %s, committed %d" % [str(committed), game.state.committed_grid])

	await settle_on(held_card)
	await input.click(centre_of(held_card))
	check(pa.selected_cards.has(held_card),
			"TP-63: precondition: the same card is held again", str(pa.selected_cards.size()))
	await time_to_light(both_cell)
	check(rimmed_properties(mark_visual(both_cell), PaletteDB.ROLES.match_rim) == here,
			"TP-63: the committed grid's mark still lights every element the card agrees with",
			"drew %d of %d" % [
			rimmed_properties(mark_visual(both_cell), PaletteDB.ROLES.match_rim), here])
	var refused := mark_visual(second_cell)
	check(rimmed_properties(refused, PaletteDB.ROLES.match_rim) == 0
			and rimmed_properties(refused, PaletteDB.ROLES.match_rim_active) == 0,
			"TP-63: and the grid the show can no longer place into lights nothing",
			"agrees on %d, drew %d" % [there,
			rimmed_properties(refused, PaletteDB.ROLES.match_rim)])
	check(uniform_of(refused.rank, &"u_outline_width") == 0
			and uniform_of(refused.suit, &"u_outline_width") == 0,
			"TP-63: it draws no rim at all, which is what a mark at rest looks like",
			"rank %d, suit %d" % [uniform_of(refused.rank, &"u_outline_width"),
			uniform_of(refused.suit, &"u_outline_width")])

	await input.click(centre_of(held_card), MOUSE_BUTTON_RIGHT)
	check(pa.selected_cards.is_empty(), "TP-63: precondition: the card went back down again")
	check(rimmed_properties(mark_visual(both_cell), PaletteDB.ROLES.match_rim) == 0
			and rimmed_properties(refused, PaletteDB.ROLES.match_rim) == 0,
			"TP-63: releasing the card clears the highlight in both grids",
			"grid 0 %d, grid 1 %d" % [
			rimmed_properties(mark_visual(both_cell), PaletteDB.ROLES.match_rim),
			rimmed_properties(refused, PaletteDB.ROLES.match_rim)])

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
	var landed := await land_on(both_cell, held_card)
	check(landed, "TP-83: precondition: the card was placed on the marked cell")

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

#THE SHIMMER IS WIRED PER ELEMENT, and this is the check that goes red if it stops being: at phase 0
#a shimmering rim and a flat activated rim are the SAME colour, so no picture can tell them apart.
	var shimmering := properties_pushing(visual, &"u_alert_kind", CardOutline.Alert.SHIMMER)
	check(shimmering == agreed,
			"TP-91: exactly the elements wearing the activated rim run the shimmer",
			"drew %d of %d" % [shimmering, agreed])
	check(uniform_of(visual.stamp, &"u_alert_kind") == CardOutline.Alert.NONE
			and uniform_of(visual.type, &"u_alert_kind") == CardOutline.Alert.NONE,
			"TP-91: and the elements that agreed with nothing run no alert at all",
			"stamp %d, frame %d" % [uniform_of(visual.stamp, &"u_alert_kind"),
			uniform_of(visual.type, &"u_alert_kind")])
#THE ORACLE IS THE BOARD'S CLOCK, not this card's: the shimmer reads one shared phase, running since
#the pass's first shimmering rim and never returning to 0, so it is read from where it stood rather
#than against zero.
	var stood_at := CardVisual._shimmer_clock
	var drifted := await wait_for(func() -> bool: return CardVisual._shimmer_clock > stood_at)
	check(drifted, "TP-91: and its phase advances on its own, so the colour is a function of TIME",
			"clock still %f" % CardVisual._shimmer_clock)

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

# ==============================================================================
# TP-93 -- one shimmer phase for the whole board
# ==============================================================================

# ⚠ TWO CARDS LANDED ON THE SAME FRAME WOULD AGREE EVEN WITH A CLOCK EACH, so the gap between the two
# landings is asserted before any phase is compared. Both go down through the real placement path,
# because what the owner saw was cards that had landed at different moments drifting apart.
func test_every_shimmer_on_the_board_reads_one_phase() -> void:
	await mark_against_a_fresh_card()
	var landed_first := await land_on(both_cell, held_card)
	var first_frame := Engine.get_process_frames()
	var second := entrance_card_besides(held_card)
	game.effect_api.grant_mark(rank_cell, mark_source(second.rank, second.suit))
	pa.flush_rebuild()
	await settle_on(second)
	var landed_second := await land_on(rank_cell, second)
	var apart := Engine.get_process_frames() - first_frame
	check(landed_first and landed_second,
			"TP-93: precondition: two cards landed on marks they agree with",
			"%s and %s" % [str(landed_first), str(landed_second)])
	check(apart > 0,
			"TP-93: precondition: the second landing is frames after the first, not on its frame",
			"%d frames apart" % apart)

	var first_visual : CardVisual = pa.data_card[held_card]
	var second_visual : CardVisual = pa.data_card[second]
	var shimmering_first := properties_pushing(first_visual, &"u_alert_kind",
			CardOutline.Alert.SHIMMER)
	var shimmering_second := properties_pushing(second_visual, &"u_alert_kind",
			CardOutline.Alert.SHIMMER)
	check(shimmering_first != 0 and shimmering_second != 0,
			"TP-93: precondition: both landed cards have elements running the shimmer",
			"%d and %d" % [shimmering_first, shimmering_second])
	await get_tree().process_frame
	var census := shimmer_phases()
	check(census.size() == 1 and census[0] > 0.0,
			"TP-93: every shimmering element on the board carries ONE phase at the same instant",
			str(census))

	var first_was := phase_of(first_visual.rank)
	var second_was := phase_of(second_visual.rank)
	for _frame : int in 5:
		await get_tree().process_frame
	var first_moved := phase_of(first_visual.rank) - first_was
	var second_moved := phase_of(second_visual.rank) - second_was
	check(first_moved > 0.0 and is_equal_approx(first_moved, second_moved),
			"TP-93: and over the same frames both advance by the same amount",
			"%f and %f" % [first_moved, second_moved])

#A FRESH MATERIAL OPENS AT 0, which is the flat activated ink: zeroed here and rebuilt, the card has
#to come back on the phase the board is already running rather than starting the drift again.
	for poly : Polygon2D in [second_visual.rank, second_visual.suit]:
		CardOutline.set_clock(poly, 0.0)
	game.state.revision += 1
	pa.queue_rebuild()
	pa.flush_rebuild()
	await get_tree().process_frame
	var rebuilt : CardVisual = pa.data_card[second]
	check(phase_of(rebuilt.rank) == CardVisual._shimmer_clock and CardVisual._shimmer_clock > 0.0,
			"TP-93: a card rebuilt mid-drift joins at the shared phase rather than at 0",
			"%f of %f" % [phase_of(rebuilt.rank), CardVisual._shimmer_clock])

#THE BOARD IS PUT BACK: the rows after this one place a card of their own on these cells.
	for _step : int in 4:
		if cards_on_grid_0() == 0: break
		await game.undo()
		pa.flush_rebuild()
		await get_tree().process_frame
	check(cards_on_grid_0() == 0,
			"TP-93: precondition: both landings are undone, leaving the board as it was found",
			"%d card(s) still standing" % cards_on_grid_0())

# ==============================================================================
# TP-66..TP-69 -- the layer view
# ==============================================================================

# The key the InputMap actually carries for the layer action, so a rebinding moves these rows with
# it instead of leaving them pressing a key nothing is listening for.
func plan_layer_key() -> Key:
	for event : InputEvent in InputMap.action_get_events(&"ui_plan_layer"):
		var key := event as InputEventKey
		if key: return key.keycode
	return KEY_NONE

# WHERE A POINTER HAS TO LAND on a HUD control: the furniture is SCALED, so the middle of its
# unscaled rect is not the middle of what is on screen.
func centre_of_control(control: Control) -> Vector2:
	return control.get_global_rect().position + control.size * control.scale / 2.0

# Every cell of grid 0 whose drawing disagrees with the layer the board says it is in: in the marks
# layer every marked cell draws its mark and every card played on one is out of the way; in play
# every one of those cards is drawn again.
func cells_not_in_layer(marks_layer: bool) -> Array[String]:
	var out : Array[String] = []
	var grid : GridData = game.state.grids[0]
	for ci : int in grid.cell_types.size():
		var mark : CardData = grid.cell_types[ci]
		var mark_drawn : CardVisual = pa.data_card.get(mark)
		if BoardPlan.is_marked(mark) and not (mark_drawn and mark_drawn.mark_drawn):
			out.append("cell %d draws no mark" % ci)
		for card : CardData in grid.cells[ci].datas:
			var visual : CardVisual = pa.data_card.get(card)
			if visual and visual.visible == marks_layer:
				out.append("cell %d card %s visible %s" % [ci, str(card), str(visual.visible)])
	return out

# How many cards stand on grid 0 -- what the marks layer has to move out of the way, and a claim
# about hiding them proves nothing until there is at least one.
func cards_on_grid_0() -> int:
	var total := 0
	for cell : ArrayCardData in (game.state.grids[0] as GridData).cells:
		total += cell.datas.size()
	return total

# ==============================================================================
# TP-66 -- the view refuses the board, and the same click places once it is closed
# ==============================================================================

# The discriminating case is THE SAME CLICK TWICE: refused while the layer view is open, and landing
# the card the moment it is closed. Without the second half a click that missed the cell entirely
# would pass this row.
func test_the_layer_view_refuses_a_placement() -> void:
	await mark_against_a_fresh_card()
	await input.click(centre_of(held_card))
	check(pa.selected_cards.has(held_card),
			"TP-66: precondition: a card is held, ready to place",
			str(pa.selected_cards.size()))
	await input.key_press(plan_layer_key())
	check(pa.plan_layer_open, "TP-66: precondition: the held key opened the layer view")

	var digest := TestGridFixtures.board_digest(game.state)
	var revision := game.state.revision
	await input.click(centre_of(game.state.cell_type_at(both_cell)))
	await get_tree().process_frame
	check(TestGridFixtures.board_digest(game.state) == digest,
			"TP-66: a placement attempted while the layer view is open changes nothing")
	check(game.state.revision == revision,
			"TP-66: and nothing bumped the revision",
			"%d then %d" % [revision, game.state.revision])
	check(pa.plan_layer_open, "TP-66: a refused input does not close the view either")
	check(pa.selected_cards.has(held_card),
			"TP-66: the card that could not be placed is still held")

	await input.key_release(plan_layer_key())
	check(not pa.plan_layer_open, "TP-66: precondition: letting the key go returned to play")
	await input.click(centre_of(game.state.cell_type_at(both_cell)))
	var landed := await wait_for(func() -> bool:
			return not game.processing and game.state.card_at(both_cell) == held_card)
	check(landed,
			"TP-66: the identical click places the card the moment the view is closed",
			"digest moved: %s" % str(TestGridFixtures.board_digest(game.state) != digest))
	pa.flush_rebuild()
	await get_tree().process_frame

# ==============================================================================
# TP-67 -- the layer view works focused AND in the overview
# ==============================================================================

# Read off what the cells DRAW -- the mark on the cell's own zone card, and the cards played on it
# out of the way -- rather than off the flag that put them there, which would pass with the whole
# swap deleted.
func test_the_layer_view_opens_focused_and_in_the_overview() -> void:
	check(pa.view_mode == PlayArea.ViewMode.FOCUSED,
			"TP-67: precondition: a grid is focused", str(pa.view_mode))
	check(cards_on_grid_0() > 0,
			"TP-67: precondition: a card stands on the board for the marks layer to cover",
			str(cards_on_grid_0()))
	var realized := await MarkMatch.matches_at(game.state, held_card, both_cell)
	check(realized != 0,
			"TP-67: precondition: one of those cells is realized -- its card agrees with its mark",
			str(realized))

	await input.key_press(plan_layer_key())
	var focused_wrong := cells_not_in_layer(true)
	check(focused_wrong.is_empty(),
			"TP-67: focused, every marked cell draws its mark and every played card steps aside",
			str(focused_wrong))
	check(rimmed_properties(mark_visual(both_cell), PaletteDB.ROLES.match_rim_active) == realized,
			"TP-67: and the realized cell's mark wears the activated rim its card would have worn",
			str(rimmed_properties(mark_visual(both_cell), PaletteDB.ROLES.match_rim_active)))
	await input.key_release(plan_layer_key())
	var back := cells_not_in_layer(false)
	check(back.is_empty(), "TP-67: letting the key go puts the played board back", str(back))

	pa.open_zoomed_out()
	await get_tree().process_frame
	await input.key_press(plan_layer_key())
	check(pa.plan_layer_open and pa.view_mode == PlayArea.ViewMode.OVERVIEW,
			"TP-67: precondition: the overview opened the same layer view", str(pa.view_mode))
	var overview_wrong := cells_not_in_layer(true)
	check(overview_wrong.is_empty(),
			"TP-67: and it draws the same marks at overview zoom", str(overview_wrong))
	await input.key_release(plan_layer_key())
	pa.focus_grid(0)
	await settle_on(held_card)

# WHAT THE BOARD IS FOCUSED ON RIGHT NOW, asked of the viewport's own focus owner: the PlayArea's
# last-known control goes stale, so reading that back would let a focus that never moved pass.
func focused_data() -> CardData:
	var owner : Control = picture_vp.gui_get_focus_owner()
	if owner not in pa.ui_data: return null
	return pa.ui_data[owner]

# ==============================================================================
# TP-67 -- what is looked at is what is drawn
# ==============================================================================

# On a covered cell the marks layer shows the MARK, so the cursor and the info card are about the
# mark, not the card hidden under it. Both routes a player has are driven through the viewport, and
# closing the layer puts the focus back on the played card -- the half that discriminates.
func test_the_layer_view_focuses_and_inspects_the_mark() -> void:
	var covered : CardData = game.state.card_at(both_cell)
	var mark : CardData = game.state.cell_type_at(both_cell)
	check(covered != null and BoardPlan.is_marked(mark),
			"TP-67: precondition: a card covers a marked cell", str(covered))
	var neighbour : Control = pa.data_ui[game.state.cell_type_at(rank_cell)]
	check(game.state.card_at(rank_cell) == null,
			"TP-67: precondition: the cell an arrow starts from is bare, so it draws its own mark")

	await input.key_press(plan_layer_key())
	await settle_on(mark)
	neighbour.grab_focus()
	await get_tree().process_frame
	await input.key_tap(KEY_RIGHT)
	check(focused_data() == mark,
			"TP-67: an arrow onto a covered cell focuses the mark it draws, not the hidden card",
			str(focused_data()))

	await input.move_to(centre_of(mark))
	check(focused_data() == mark,
			"TP-67: and the pointer over that cell focuses the mark too", str(focused_data()))
	check(pa.focused_visual == pa.data_card[mark] and pa.focused_visual.visible,
			"TP-67: the focus brighten lands on the visual that is actually on show",
			str(pa.focused_visual))
	check(not (pa.data_card[covered] as CardVisual).visible,
			"TP-67: precondition: the card under it is the hidden one")

	var entries : Array[InfoEntry] = []
	var collect := func(entry: InfoEntry) -> void: entries.append(entry)
	pa.info_requested.connect(collect)
	var was_info : bool = SettingsManager.settings.wall_info_mode
	SettingsManager.settings.wall_info_mode = true
	await input.click(centre_of(mark))
	check(entries.size() == 1,
			"TP-67: a click in Info mode over a covered cell publishes one info entry",
			str(entries.size()))
	if entries.size() == 1:
		var named := "%s\n%s" % [entries[0].title, entries[0].body]
		check(named.contains(mark.suit.get_str()) and named.contains(mark.rank.get_str()),
				"TP-67: and it names the MARK's own rank and suit", named)
		check(named != ControlCard.describe_card(covered),
				"TP-67: which is the cell's description, not the played card's", named)
		if entries[0].visual: entries[0].visual.free()
	SettingsManager.settings.wall_info_mode = was_info
	pa.info_requested.disconnect(collect)

	await input.key_release(plan_layer_key())
	await get_tree().process_frame
	check(focused_data() == covered,
			"TP-67: closing the view hands the cell's focus back to the played card",
			str(focused_data()))
	check(pa.focused_visual == pa.data_card[covered] and pa.focused_visual.visible,
			"TP-67: and the brighten follows it onto the card that is on show again",
			str(pa.focused_visual))

# ==============================================================================
# TP-68 -- keyboard, mouse and controller all reach it
# ==============================================================================

# Every route is driven through the viewport the way the platform delivers it. The HUD control is
# ONE control, so the three input modes reach the same toggle rather than three wirings of it.
func test_the_layer_toggle_is_reachable_by_every_input_mode() -> void:
	check(InputMap.has_action(&"ui_plan_layer") and plan_layer_key() != KEY_NONE,
			"TP-68: precondition: the layer action exists and carries a keyboard binding",
			OS.get_keycode_string(plan_layer_key()))
	await input.key_press(plan_layer_key())
	check(pa.plan_layer_open, "TP-68: the held key opens the layer view")
	await input.key_release(plan_layer_key())
	check(not pa.plan_layer_open, "TP-68: and letting it go closes it again")

	var button := view.plan_layer_button
	check(button.text != "PLAN_LAYER_TOGGLE" and not button.text.is_empty()
			and button.tooltip_text != "PLAN_LAYER_TOGGLE_HINT"
			and not button.tooltip_text.is_empty(),
			"TP-68: its label and its hint come through the localisation table, not a literal",
			"%s / %s" % [button.text, button.tooltip_text])
	await input.click(centre_of_control(button))
	check(pa.plan_layer_open, "TP-68: a mouse click on the HUD control opens it")
	await input.click(centre_of_control(button))
	check(not pa.plan_layer_open, "TP-68: and a second click closes it")

	button.grab_focus()
	await get_tree().process_frame
	await input.key_tap(KEY_ENTER)
	check(pa.plan_layer_open, "TP-68: the focused HUD control answers a keyboard accept")
	await input.key_tap(KEY_ENTER)
	check(not pa.plan_layer_open, "TP-68: and a second one closes it")

	button.grab_focus()
	await get_tree().process_frame
	await input.joy_tap(JOY_BUTTON_A)
	check(pa.plan_layer_open, "TP-68: the same control answers a controller accept")
	await input.joy_tap(JOY_BUTTON_A)
	check(not pa.plan_layer_open, "TP-68: and a second one closes it")

	await input.click(centre_of_control(button))
	check(pa.plan_layer_open, "TP-68: precondition: the HUD control left the view open")
	(pa.data_ui[held_card] as Control).grab_focus()
	await get_tree().process_frame
	await input.key_tap(KEY_Z)
	check(pa.plan_layer_open,
			"TP-68: a toggled view survives an unrelated key's release -- only its own closes it")
	await input.click(centre_of_control(button))
	check(not pa.plan_layer_open, "TP-68: precondition: the view is closed again")

# ==============================================================================
# TP-89 -- the pad's held peek
# ==============================================================================

#The pad reaches this view two ways that are NOT the same gesture: the HUD control TOGGLES on
#Accept, while the X face button peeks only while it is down. A second face button is pressed to
#prove the peek belongs to that one button and not to any pad press at all.
func test_the_layer_view_peeks_while_the_face_button_is_held() -> void:
	await input.joy_press(JOY_BUTTON_X)
	check(pa.plan_layer_open, "TP-89: holding the X face button opens the layer view")
	var peeked := cells_not_in_layer(true)
	check(peeked.is_empty(),
			"TP-89: and while it is down every marked cell draws its mark", str(peeked))
	await input.joy_release(JOY_BUTTON_X)
	check(not pa.plan_layer_open, "TP-89: letting the face button go closes the view again")
	var back := cells_not_in_layer(false)
	check(back.is_empty(), "TP-89: and the played board is back", str(back))

	picture_vp.gui_release_focus()
	await get_tree().process_frame
	await input.joy_press(JOY_BUTTON_A)
	check(not pa.plan_layer_open, "TP-89: a different face button opens nothing")
	await input.joy_release(JOY_BUTTON_A)

# ==============================================================================
# TP-69 -- any board mutation closes it, and no save carries it
# ==============================================================================

# The layer view is view state and lives nowhere else: a saved state has no property for it, so a
# resumed show cannot come back looking at a layer, and a board rebuilt under an open one is no
# longer the board it was opened over.
func test_the_layer_view_closes_on_a_board_mutation() -> void:
	await input.click(centre_of_control(view.plan_layer_button))
	check(pa.plan_layer_open, "TP-69: precondition: the layer view is open with no key held")

	var carried : Array[String] = []
	for property : Dictionary in game.state.duplicate_state().get_property_list():
		if (property["name"] as String).to_lower().contains("layer"):
			carried.append(str(property["name"]))
	check(carried.is_empty(),
			"TP-69: a saved state carries no layer state at all", str(carried))

	var revision := game.state.revision
	game.effect_api.swap_marks(rank_cell, miss_cell)
	await get_tree().process_frame
	check(game.state.revision != revision,
			"TP-69: precondition: a mark effect mutated the board",
			"%d then %d" % [revision, game.state.revision])
	check(not pa.plan_layer_open, "TP-69: a board mutation closes the layer view")

	await input.click(centre_of_control(view.plan_layer_button))
	check(pa.plan_layer_open, "TP-69: precondition: re-opened over the mutated board")
	view.rebuild()
	await get_tree().process_frame
	check(not pa.plan_layer_open, "TP-69: a rebuilt board comes up in play")
	var drawn := cells_not_in_layer(false)
	check(drawn.is_empty(), "TP-69: with every played card drawn again", str(drawn))
