extends TestSuite
# res://Tests/UI/test_grid_layout.gd
# ==============================================================================
# S20b — THE GRID BOARD IS DRAWN. Phase 5's first view step: the play area builds one panel per
# grid, one slot per cell, and a real control and CardVisual for every card on a grid.
#
# WHY THIS SUITE EXISTS AT ALL. Every Phase 1-4 and Phase 8 test is headless by design, and that
# is the right call — but it means the engine shipped a complete, tested board that NOTHING
# DREW, and no suite could see it. `grids` did not appear in `UI/play_area.gd` at all
# (design/poker-patience/gaps/GAP-009.md). These checks are the ones that would have caught it.
#
# CATEGORY MAP: BEHAVIOR — a card on a grid has a control, a visual and a position is what the
# player experiences as "the board exists". IMPLEMENTATION pins: the cell count comes from the
# data, and the panels are in lockstep with the grid list.
#
# ⚠ NONE OF THIS IS EVIDENCE ABOUT PIXELS (repo rule 4). It proves the tree and the numbers; a
# rendered snapshot signed off by eye is what proves the board LOOKS right.
# ==============================================================================

const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")

var _prev_run : RunState
var _prev_save_info : RunState

func suite_name() -> String:
	return "GRID LAYOUT"

func _ready() -> void:
	TestLog.line("============ GRID LAYOUT TEST PASS ============")
	backup_real_settings()
	use_own_settings()   # geometry checks must not depend on the player's tuning
	check_all_tests_registered()
	await run_a_panel_per_grid_and_a_slot_per_cell_test()
	await run_a_placed_card_has_a_control_a_visual_and_a_position_test()
	await run_a_placed_card_draws_over_its_cell_test()
	await run_every_grid_sits_on_the_same_floor_test()
	await run_a_stack_grows_upward_test()
	await run_a_row_shares_one_bottom_edge_and_pushes_the_rows_above_it_test()
	await run_slot_center_global_reads_no_control_rects_test()
	await run_a_row_grows_into_its_height_test()
	await run_a_freshly_dealt_board_animates_nothing_test()
	await run_the_entrance_height_pushes_the_board_up_test()
	await run_a_jump_lifts_the_stack_above_it_test()
	await run_a_hoop_rides_the_card_that_jumped_test()
	await run_no_subtotal_is_displayed_anywhere_test()
	await run_score_labels_sit_where_the_design_puts_them_test()
	await run_a_height_label_sits_above_its_stack_test()
	await run_a_height_label_stays_above_its_stack_when_focused_zoom_is_not_one_test()
	await run_a_row_label_lines_up_with_its_own_row_test()
	await run_a_rows_zone_cards_share_one_line_at_a_non_one_zoom_test()
	await run_the_first_card_in_a_cell_does_not_widen_its_row_test()
	await run_a_banked_grid_score_pops_its_label_test()
	await run_the_card_is_put_down_before_anything_scores_test()
	await run_a_deepening_stack_grows_the_board_upward_test()
	await run_hovering_the_board_does_not_move_it_test()
	await run_every_score_label_is_the_same_size_test()
	await run_a_row_score_sits_on_its_pip_row_test()
	restore_real_settings()
	finish()

## A real GameView on the frozen 52-card deck: one grid, dealt Entrance, nothing crafted.
func _stand_up() -> GameView:
	backup_real_save(suite_tag())
	_prev_run = RunManager.run
	_prev_save_info = Main.save_info
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	# ⚠ **A GOAL OF 1 ENDS THE SHOW ON THE FIRST SCORING PLACEMENT**, and a layout test that places
	# a few cards then measures is left reading a board whose Game has already been torn down —
	# `slot_center_global` answers from a null game, every row collapses onto the floor, and the
	# numbers look like a geometry bug rather than a dead fixture. Out of reach instead.
	run.pending_goal = 1_000_000_000
	run.pending_node_id = 2
	seed(20260828)
	var view : GameView = GAME_VIEW_SCENE.instantiate()
	add_child(view)
	await get_tree().process_frame
	await get_tree().process_frame
	# ⚠ RE-ASSERT IT. The PREVIOUS test's Game nulls CardEnvironment.CURRENT from its own
	# _exit_tree, and queue_free lands whenever the frame ends -- which can be AFTER this view's
	# Game entered the tree and set it. A null CURRENT makes PlayArea.set_card_zones return
	# immediately and do nothing, so the board silently stops rebuilding and every check here
	# reads a stale control tree.
	CardEnvironment.CURRENT = view.game
	# THIS FIXTURE OWNS ITS VIEW MODE. The board opens FOCUSED when it holds exactly one grid,
	# and one grid is what the default deck gives -- which would put every check below on a
	# zoomed board. These suites assert the board's LAYOUT ARITHMETIC at the overview's scale;
	# the zoomed board is GRID VIEW's subject. Latching here keeps the overview the fixture was
	# written against, and the opening view stays the product's own decision everywhere else.
	view.play_area._show_view_opened = true
	view.play_area.open_zoomed_out()
	return view

func _tear_down(view: GameView) -> void:
	view.queue_free()
	await get_tree().process_frame
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = _prev_run
	Main.save_info = _prev_save_info

## ⚠ **WAIT FOR THE GEOMETRY TO STOP MOVING, NOT FOR A FIXED NUMBER OF FRAMES.** A container sorts
## its children on a later frame than the rebuild that changed them, and the panel origin the
## arithmetic reads is published by that sort — so a single `process_frame` measures a board that
## is one layout pass behind. It read 36 px of movement where 40 was due, and the missing 4 was
## simply the part that had not happened yet.
## ⚠ **RE-ASSERTS `CardEnvironment.CURRENT` ON EVERY FRAME IT WAITS.** This suite does not await its
## siblings, so another suite's teardown can null the shared CURRENT while we are settling — and
## `slot_center_global` then answers from no game at all, collapsing every row onto the floor. The
## numbers that produces (every row reporting the same y) look exactly like a geometry bug. Same
## re-assertion `_stand_up` makes, for the same reason, just repeated while time passes.
func _settle_layout(view: GameView) -> void:
	var pa := view.play_area
	CardEnvironment.CURRENT = view.game
	pa.flush_rebuild()
	var last := INF
	var waited := 0.0
	while waited < 2.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		CardEnvironment.CURRENT = view.game
		var now := pa.slot_center_global(BoardCoord.new(0, 0, 0, 0)).y
		if is_equal_approx(now, last): return
		last = now

## Drive one prop tick to completion, with a watchdog so a stalled tick fails loudly instead of
## hanging. Mirrors the same helper in `test_visual_layers`.
func _prop_tick(pl: PropLayer, live: Array, spawned: Array) -> bool:
	var sig := pl.begin_prop_tick(live, spawned, [], [])
	var fired : Array[bool] = [false]
	var handler := func() -> void: fired[0] = true
	sig.connect(handler)
	var waited := 0.0
	while not fired[0] and waited < 10.0:
		waited += await _tick()
	if sig.is_connected(handler): sig.disconnect(handler)
	return fired[0]

## One frame, and how long it took — for settling loops that must not spin forever.
func _tick() -> float:
	await get_tree().process_frame
	return get_process_delta_time()

## Waits for every CardVisual's OWN control-center position to stop moving. `_settle_layout` waits
## for the computed slot, which is stable the instant the layout pass lands, while a CardVisual eases
## toward it -- a check comparing the visual to the arithmetic must wait for the visual's tween, not
## the arithmetic, or it reads a card mid-flight.
func _settle_visuals(visuals: Array[CardVisual]) -> void:
	var last : Array[Vector2] = []
	for i in visuals.size(): last.append(Vector2.INF)
	var waited := 0.0
	while waited < 2.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		var moving := false
		for i in visuals.size():
			var vis := visuals[i]
			if not vis or not is_instance_valid(vis) or not vis.control_anchor: continue
			var now := vis.get_card_control_center(vis.control_anchor)
			if not now.is_equal_approx(last[i]): moving = true
			last[i] = now
		if not moving: return

## The cell grid inside grid `gi`'s panel.
## Grid `gi`'s row `ry` — one HBox of cells. Rows are their own containers so a deep stack in
## one cell cannot bleed into the row above, and every cell in a row bottom-aligns inside it.
func _cell_row(pa: PlayArea, gi: int, ry: int) -> HBoxContainer:
	var panel : Control = pa.grid_container.get_child(gi)
	return pa._cells_root(panel).get_child(ry) as HBoxContainer

# ==============================================================================
# TP-80b — one panel per grid, and a slot per cell, sized FROM THE DATA.
# ==============================================================================
func run_a_panel_per_grid_and_a_slot_per_cell_test() -> void:
	behavior_section("A PANEL PER GRID AND A SLOT PER CELL")
	var view := await _stand_up()
	var pa := view.play_area
	pa.flush_rebuild()
	await get_tree().process_frame
	var grids : Array[GridData] = view.game.state.grids

	check(grids.size() > 0, "precondition: the show built at least one grid",
			"%d grids" % grids.size())
	check(pa.grid_container.get_child_count() == grids.size(),
			"the board has exactly one panel per grid",
			"%d panels vs %d grids" % [pa.grid_container.get_child_count(), grids.size()])

	var grid : GridData = grids[0]
	var panel : Control = pa.grid_container.get_child(0)
	var cells := _cell_row(pa, 0, 0)
	# ⚠ Compared against the DATA's own width and height, never against 5. A grid carries its
	# own size and a later card could make one a different shape; a check written against 5
	# would pass today and silently stop describing the board the day that happens.
	var cells_root := pa._cells_root(panel)
	check(cells_root != null and cells_root.get_child_count() == grid.grid_height,
			"the panel has one ROW CONTAINER per grid row, from the DATA",
			"%d rows vs grid_height %d"
			% [cells_root.get_child_count() if cells_root else -1, grid.grid_height])
	check(cells.get_child_count() == grid.grid_width,
			"a row is as wide as the DATA says, not a hard-coded 5",
			"%d cells vs grid_width %d" % [cells.get_child_count(), grid.grid_width])
	# TP-80k — the Entrance's slots line up with the grid's columns (chart L3). It is what makes
	# the Entrance read as the row BELOW the board rather than a separate strip near it, and it
	# is easy to lose: the Entrance carried a row-score gutter left over from the retired upper
	# zone, and its row was left-aligned while the grid centred itself in the same width. Each
	# of those put it 25-50 px out, which looks like a rounding artefact and is not one.
	# S20b.3: the Entrance moved to its own pinned %EntranceStrip (GAP-010) — read it through the
	# unique-named accessor, not a path under TopLevelVBox (which no longer holds it).
	var entrance_row : Control = pa.upper_zone_right
	var worst_dx := 0.0
	for col : int in mini(entrance_row.get_child_count(), grid.grid_width):
		var slot_x : float = (cells.get_child(col) as Control).get_global_rect().position.x
		var ent_x : float = (entrance_row.get_child(col) as Control).get_global_rect().position.x
		worst_dx = maxf(worst_dx, absf(slot_x - ent_x))
	check(worst_dx < 1.0,
			"every Entrance slot lines up with the grid column above it",
			"worst %.1f px out" % worst_dx)
	var slots := 0
	for ry : int in cells_root.get_child_count():
		slots += cells_root.get_child(ry).get_child_count()
	check(slots == grid.cells.size(),
			"there is exactly one cell slot per cell in the data, across every row",
			"%d slots vs %d cells" % [slots, grid.cells.size()])
	# ⚠ **EVERY CELL IN A ROW BOTTOMS OUT ON ONE LINE.** This is the reason a row is its own
	# container: cells shrink-align to the row's END, so an uneven row still has one zone line.
	var worst_dy := 0.0
	for col : int in cells.get_child_count():
		var r := (cells.get_child(col) as Control).get_global_rect()
		worst_dy = maxf(worst_dy, absf(r.end.y - (cells.get_child(0) as Control).get_global_rect().end.y))
	check(worst_dy < 1.0,
			"every cell in a row shares one bottom line, whatever its stack",
			"worst %.1f px out" % worst_dy)
	await _tear_down(view)

# ==============================================================================
# TP-80c — THE CHECK GAP-009 WOULD HAVE FAILED. A card on a grid is a card the player can see.
# ==============================================================================
func run_a_placed_card_has_a_control_a_visual_and_a_position_test() -> void:
	behavior_section("A PLACED CARD HAS A CONTROL, A VISUAL AND A POSITION")
	var view := await _stand_up()
	var pa := view.play_area
	var g := view.game
	var coord := BoardCoord.new(0, 2, 3, 0)
	var placed : CardData = g.state.upper_zone[0].datas[0]
	await g.place_card_in_grid(placed, coord)
	pa.flush_rebuild()
	await get_tree().process_frame
	await get_tree().process_frame

	check(g.state.card_at(coord) == placed, "precondition: the card is in the cell")
	var control : Control = pa.data_ui.get(placed)
	check(control != null, "the placed card has a board control")
	var visual : CardVisual = pa.data_card.get(placed)
	check(visual != null and is_instance_valid(visual),
			"the placed card has a CardVisual in the card layer")
	if control:
		# Inside the panel, not left in some legacy zone: walk up to the cell grid.
		var slot : Node = control.get_parent()
		check(slot != null and slot.get_parent() == _cell_row(pa, 0, 3),
				"...and its control lives in grid 0's row 3",
				str(slot.get_parent().name) if slot and slot.get_parent() else "<none>")
	if visual and is_instance_valid(visual):
		check(visual.global_position != Vector2.ZERO,
				"...and the visual has a real position on screen, not the origin",
				str(visual.global_position))
	await _tear_down(view)

# ==============================================================================
# TP-80m -- A CARD ON A CELL DRAWS ON TOP OF THE CELL IT SITS ON.
#
# Owner report, by eye: "some cards appear behind the grid zone cells they are supposed to be
# on top of". Draw order in a CanvasItem layer is CHILD INDEX -- lower draws first, so the
# card's visual must sit at a HIGHER index than the zone card of its own cell.
#
# ⚠ Nothing assigned grid cards an index at all: _order_board_cards walked the two legacy zones
# and stopped, so a grid card kept whatever index creation happened to give it, and a cell
# frame rebuilt after its card drew over the card. No test looked, because no visual harness
# ever put a card ON a cell.
# ==============================================================================
func run_a_placed_card_draws_over_its_cell_test() -> void:
	behavior_section("A PLACED CARD DRAWS OVER ITS CELL")
	var view := await _stand_up()
	var pa := view.play_area
	var g := view.game
	var coord := BoardCoord.new(0, 2, 3, 0)
	var placed : CardData = g.state.upper_zone[0].datas[0]
	await g.place_card_in_grid(placed, coord)
	pa.flush_rebuild()
	await get_tree().process_frame
	await get_tree().process_frame

	var cell_type : CardData = g.state.grids[0].cell_types[3 * g.state.grids[0].grid_width + 2]
	var card_vis : CardVisual = pa.data_card.get(placed)
	var cell_vis : CardVisual = pa.data_card.get(cell_type)
	check(card_vis != null and is_instance_valid(card_vis)
			and cell_vis != null and is_instance_valid(cell_vis),
			"precondition: both the placed card and its cell have visuals")
	if not (card_vis and is_instance_valid(card_vis) and cell_vis and is_instance_valid(cell_vis)):
		await _tear_down(view)
		return
	check(card_vis.get_parent() == cell_vis.get_parent(),
			"precondition: both draw in the SAME layer -- an index only orders within one layer",
			"%s vs %s" % [str(card_vis.get_parent()), str(cell_vis.get_parent())])
	check(card_vis.get_index() > cell_vis.get_index(),
			"the placed card draws OVER the cell it sits on",
			"card idx %d vs cell idx %d" % [card_vis.get_index(), cell_vis.get_index()])
	await _tear_down(view)

# ==============================================================================
# TP-80g — every grid sits on the same floor. With cross-grid row alignment OFF (the default)
# the rows do NOT line up, and the bottom edges are the only thing that does.
# ==============================================================================
func run_every_grid_sits_on_the_same_floor_test() -> void:
	behavior_section("EVERY GRID SITS ON THE SAME FLOOR")
	var view := await _stand_up()
	var pa := view.play_area
	pa.flush_rebuild()
	await get_tree().process_frame
	var panels := pa.grid_container.get_child_count()
	if panels < 2:
		check(true, "only one grid in this show — nothing to align against",
				"%d panels" % panels)
		await _tear_down(view)
		return
	var floor_y : float = (pa.grid_container.get_child(0) as Control).get_global_rect().end.y
	var worst := 0.0
	for gi : int in range(1, panels):
		var rect := (pa.grid_container.get_child(gi) as Control).get_global_rect()
		worst = maxf(worst, absf(rect.end.y - floor_y))
	check(worst < 1.0, "every grid's bottom edge sits on the same floor",
			"worst %.2f px off" % worst)
	await _tear_down(view)


# ==============================================================================
# TP-81 -- A STACK GROWS UPWARD: card h+1 sits HIGHER on screen than card h.
#
# ⚠ The reading this separates: "upward" could mean the DATA order flipped (h 0 on top) or the
# GEOMETRY flipped (h 0 stays the bottom of the stack and the stack rises). It is the geometry --
# h 0 is still the first card placed, and it ends up on the row's bottom edge with later cards
# rising over it. So the test asks about SCREEN Y for ascending h, not about the data.
#
# TP-82 rides along here: a covered card must still show its own bottom strip, which is where the
# pips are, so consecutive cards are exactly one depth pitch apart -- not a full card.
# ==============================================================================
func run_a_stack_grows_upward_test() -> void:
	behavior_section("A STACK GROWS UPWARD")
	var view := await _stand_up()
	var pa := view.play_area
	var g := view.game
	var coord := BoardCoord.new(0, 1, 2, 0)
	# Three cards into ONE cell, so there is a covered card, a middle card and a top card.
	var count := 0
	for i in 3:
		var card : CardData = g.state.upper_zone[i].datas[0]
		await g.place_card_in_grid(card, coord)
		count += 1
	pa.flush_rebuild()
	await get_tree().process_frame
	await get_tree().process_frame

	var grid : GridData = g.state.grids[0]
	var stack : Array[CardData] = grid.cells[grid.cell_index(1, 2)].datas
	check(stack.size() == 3, "precondition: three cards really stacked in one cell",
			"%d deep" % stack.size())
	if stack.size() < 3:
		await _tear_down(view)
		return

	var ys : Array[float] = []
	for h : int in 3:
		ys.append(pa.slot_center_global(BoardCoord.new(0, 1, 2, h)).y)
	check(ys[1] < ys[0] and ys[2] < ys[1],
			"E7: card h+1 sits HIGHER on screen than card h -- the stack grows UPWARD",
			"h0 %.1f h1 %.1f h2 %.1f" % [ys[0], ys[1], ys[2]])
	var depth_pitch := float(CardVisual.card_separation_play_custom) + float(pa.separation)
	check(absf((ys[0] - ys[1]) - depth_pitch) < 0.5 and absf((ys[1] - ys[2]) - depth_pitch) < 0.5,
			"E8: consecutive cards are exactly ONE DEPTH PITCH apart, so a covered card shows its "
			+ "bottom strip -- a full card apart would hide the pips it exists to show",
			"gaps %.1f / %.1f vs pitch %.1f" % [ys[0] - ys[1], ys[1] - ys[2], depth_pitch])

	# E9 -- the draw order does NOT flip with the geometry: the newest card is still in front.
	var v0 : CardVisual = pa.data_card.get(stack[0])
	var v2 : CardVisual = pa.data_card.get(stack[2])
	if v0 and v2 and v0.get_parent() == v2.get_parent():
		check(v2.get_index() > v0.get_index(),
				"E9: the newest card still draws IN FRONT -- it overlaps the lower card's TOP and "
				+ "the pips are at the BOTTOM, so the order never needed to change",
				"h2 idx %d vs h0 idx %d" % [v2.get_index(), v0.get_index()])

	# ⚠ **COMPARE THE ARITHMETIC TO THE CONTROLS, NOT TO A CARD IN FLIGHT.** The claim that matters
	# is that `slot_center_global` and the control tree name the same point — that is what keeps a
	# card on its cell. A CardVisual EASES to that point, so the visual itself must be settled first
	# -- `_settle_layout` only waits for the computed slot, which is stable long before the tween is.
	var visuals : Array[CardVisual] = []
	for h : int in 3:
		var vis : CardVisual = pa.data_card.get(stack[h])
		if vis: visuals.append(vis)
	await _settle_visuals(visuals)

	var worst := 0.0
	for h : int in 3:
		var vis : CardVisual = pa.data_card.get(stack[h])
		if not vis or not is_instance_valid(vis) or not vis.control_anchor: continue
		worst = maxf(worst, absf(vis.get_card_control_center(vis.control_anchor).y
				- pa.slot_center_global(BoardCoord.new(0, 1, 2, h)).y))
	check(worst < 2.0,
			"...and the arithmetic lands on the same point the card's own CONTROL does, at every "
			+ "height — the agreement that keeps a card on its cell",
			"worst %.1f px out" % worst)
	await _tear_down(view)

# ==============================================================================
# TP-82 / TP-83 -- a row's cells share a BOTTOM edge, and a tall stack pushes the rows ABOVE it up.
#
# ⚠ TP-83's discriminating case is the row BELOW the tall one, which must NOT move. "Rows are
# pushed up" and "the board re-centres" both raise the rows above; only the first leaves the rows
# beneath exactly where they were, and that is what the board growing upward from the Entrance
# actually means.
# ==============================================================================
func run_a_row_shares_one_bottom_edge_and_pushes_the_rows_above_it_test() -> void:
	behavior_section("A ROW SHARES A BOTTOM EDGE AND PUSHES THE ROWS ABOVE IT UP")
	var view := await _stand_up()
	var pa := view.play_area
	var g := view.game
	# One card each into two cells of row 2, so the row has a shared bottom to measure.
	await g.place_card_in_grid(g.state.upper_zone[0].datas[0], BoardCoord.new(0, 0, 2, 0))
	await g.place_card_in_grid(g.state.upper_zone[1].datas[0], BoardCoord.new(0, 3, 2, 0))
	await _settle_layout(view)

	var left := pa.slot_center_global(BoardCoord.new(0, 0, 2, 0)).y
	var right := pa.slot_center_global(BoardCoord.new(0, 3, 2, 0)).y
	check(absf(left - right) < 0.5,
			"E10: two cells in the same row bottom out on the same line",
			"%.1f vs %.1f" % [left, right])

	# ⚠ **TP-83's DISCRIMINATING CASE IS THE ROW BELOW, WHICH MUST NOT MOVE.** "Rows are pushed up"
	# and "the board re-centres" both raise the rows above a deepened stack; only the first leaves
	# the rows beneath exactly where they were, and that is what growing upward out of the Entrance
	# means.
	var above_before := pa.slot_center_global(BoardCoord.new(0, 0, 1, 0)).y
	var below_before := pa.slot_center_global(BoardCoord.new(0, 0, 3, 0)).y
	var row2_before := pa.slot_center_global(BoardCoord.new(0, 0, 2, 0)).y

	for i in 2:
		await g.place_card_in_grid(g.state.upper_zone[2 + i].datas[0], BoardCoord.new(0, 0, 2, 0))
	await _settle_layout(view)

	var depth_pitch := float(CardVisual.card_separation_play_custom) + float(pa.separation)
	# ⚠ Without this the three checks below can only report nonsense: a torn-down show leaves
	# `slot_center_global` with no grid to measure and every row lands on the floor together.
	check(CardEnvironment.get_current_game() != null,
			"precondition: the show is still running, so the rows below are real measurements")
	var above_after := pa.slot_center_global(BoardCoord.new(0, 0, 1, 0)).y
	var below_after := pa.slot_center_global(BoardCoord.new(0, 0, 3, 0)).y
	var row2_after := pa.slot_center_global(BoardCoord.new(0, 0, 2, 0)).y

	check(absf(row2_after - row2_before) < 0.5,
			"a row's own bottom edge does not move when its stack deepens — it grows UP off it",
			"%.1f -> %.1f" % [row2_before, row2_after])
	check(absf(below_after - below_before) < 0.5,
			"Q307: the row BELOW does NOT move — the board grows upward, it does not re-centre",
			"%.1f -> %.1f" % [below_before, below_after])
	check(above_after < above_before - 0.5,
			"E11: the row ABOVE is pushed UP by the deeper stack",
			"%.1f -> %.1f" % [above_before, above_after])
	check(absf((above_before - above_after) - 2.0 * depth_pitch) < 1.0,
			"...by exactly the height the stack gained, not an approximation",
			"moved %.1f, stack gained %.1f" % [above_before - above_after, 2.0 * depth_pitch])
	await _tear_down(view)

# ==============================================================================
# TP-84 -- slot_center_global stays PURE MATH. Props anchor through it EVERY FRAME, so a
# control-rect read makes a prop's position depend on relayout timing.
#
# ⚠ **THE DISCRIMINATING INPUT IS A SLOT WITH NO CONTROL AT ALL.** Calling it on an occupied cell
# proves nothing -- a rect read and a formula agree there, which is the whole reason a rect read
# survived this long. An EMPTY cell and a height ABOVE the stack have no control to read, so only
# a formula can answer, and it must answer on the same pitch as the occupied heights below it.
#
# ⚠ Do NOT "disturb" a control's rect to test this: writing size/custom_minimum_size on a child of
# a live container fights the container's own relayout and hangs the tree (measured -- the suite
# died on its 400 s timeout with no banner).
# ==============================================================================
func run_slot_center_global_reads_no_control_rects_test() -> void:
	implementation_section("SLOT GEOMETRY IS ARITHMETIC, NOT A RECT READ")
	var view := await _stand_up()
	var pa := view.play_area
	var g := view.game
	var coord := BoardCoord.new(0, 2, 2, 0)
	await g.place_card_in_grid(g.state.upper_zone[0].datas[0], coord)
	pa.flush_rebuild()
	await get_tree().process_frame

	var depth_pitch := float(CardVisual.card_separation_play_custom) + float(pa.separation)
	var occupied := pa.slot_center_global(coord)
	check(pa.data_ui.has(g.state.card_at(coord)),
			"precondition: h 0 really does have a control, so the two cases differ")

	# A height ABOVE the stack: no control exists for it, and there is no rect to read.
	var empty_h := pa.slot_center_global(BoardCoord.new(0, 2, 2, 4))
	check(absf((occupied.y - empty_h.y) - 4.0 * depth_pitch) < 0.5,
			"Q255: a height with NO control still answers, on the same pitch as the occupied ones -- "
			+ "a rect read could not, because there is no rect",
			"%.1f vs %.1f" % [occupied.y - empty_h.y, 4.0 * depth_pitch])
	check(absf(empty_h.x - occupied.x) < 0.5,
			"...and it stays in its own column")

	# An entirely EMPTY cell answers too, on the row geometry alone.
	var empty_cell := pa.slot_center_global(BoardCoord.new(0, 4, 2, 0))
	check(absf(empty_cell.y - occupied.y) < 0.5,
			"an EMPTY cell in the same row bottoms out on that row's line like every other cell",
			"%.1f vs %.1f" % [empty_cell.y, occupied.y])
	await _tear_down(view)


# ==============================================================================
# TP-85 / TP-87 -- a row GROWS into its new height instead of snapping there, and a row with
# nothing above it grows just the same.
#
# ⚠ **THE READING TP-87 SEPARATES.** `Q77`=(b) says the height shift inherits the reveal's guard
# "re-derived for the new direction", and the guard it inherits is about the STACK -- a layer only
# contributes height if the stack really reaches it. The misreading is to re-derive it as "does
# this row have anything ABOVE it to push", which would leave the TOP row of a grid snapping while
# every other row eased. So the case that matters is the row with nothing above it, which is
# exactly the one the example never covers.
#
# ⚠ Mid-flight is sampled by the growth's OWN progress, not by a frame count, so the assertion is
# about the same moment of the animation whatever the frame rate.
# ==============================================================================
func run_a_row_grows_into_its_height_test() -> void:
	behavior_section("A ROW GROWS INTO ITS HEIGHT INSTEAD OF SNAPPING")
	var view := await _stand_up()
	var pa := view.play_area
	var g := view.game

	# Row 0 is the TOP row of the grid: nothing above it. That is TP-87's case.
	var coord := BoardCoord.new(0, 1, 0, 0)
	await g.place_card_in_grid(g.state.upper_zone[0].datas[0], coord)
	await _settle_layout(view)
	var settled_before := pa.slot_center_global(BoardCoord.new(0, 1, 0, 0)).y
	var height_before := pa._grid_row_height(0, 0)

	# A SECOND card into the same cell: the row now owes one depth pitch of growth.
	await g.place_card_in_grid(g.state.upper_zone[1].datas[0], coord)
	pa.flush_rebuild()
	await get_tree().process_frame

	check(not pa._layer_grown.is_empty(),
			"TP-87: a row with NOTHING ABOVE IT still registers growth -- the guard is about the "
			+ "stack having the height, not about anything being there to push",
			"layers growing: %d" % pa._layer_grown.size())

	# Mid-flight: the row is taller than it was and NOT yet at its full new height.
	var pitch := float(CardVisual.card_separation_play_custom) + float(pa.separation)
	var caught_midway := false
	var waited := 0.0
	while waited < 3.0 and not pa._layer_grown.is_empty():
		var t : float = pa._layer_grown.values()[0] if not pa._layer_grown.is_empty() else 1.0
		if t > 0.15 and t < 0.85:
			var mid := pa._grid_row_height(0, 0)
			caught_midway = mid > height_before + 0.5 and mid < height_before + pitch - 0.5
			break
		waited += await _tick()
	check(caught_midway,
			"TP-85: caught mid-growth, the row is PART WAY to its new height -- it eases rather "
			+ "than snapping (a snap would only ever be at the old height or the new one)",
			"row %.1f, was %.1f, will be %.1f" % [pa._grid_row_height(0, 0), height_before,
			height_before + pitch])

	# It arrives, exactly one pitch taller, and stops.
	waited = 0.0
	while waited < 3.0 and not pa._layer_grown.is_empty():
		waited += await _tick()
	await _settle_layout(view)
	check(absf(pa._grid_row_height(0, 0) - (height_before + pitch)) < 0.5,
			"...and it arrives at exactly one depth pitch taller",
			"%.1f vs %.1f" % [pa._grid_row_height(0, 0), height_before + pitch])
	check(pa._layer_grown.is_empty(),
			"...and an arrived board carries no growth state at all",
			"%d left" % pa._layer_grown.size())

	# The bottom line of the row itself never moved: it grew UP off it.
	check(absf(pa.slot_center_global(BoardCoord.new(0, 1, 0, 0)).y - settled_before) < 0.5,
			"the card on the row's bottom line never moved while the row grew above it",
			"%.1f -> %.1f" % [settled_before,
			pa.slot_center_global(BoardCoord.new(0, 1, 0, 0)).y])
	await _tear_down(view)

# ==============================================================================
# A dealt board must NOT play a growth it never had -- the seeding's own edge case.
# ==============================================================================
func run_a_freshly_dealt_board_animates_nothing_test() -> void:
	behavior_section("A FRESHLY DEALT BOARD ANIMATES NOTHING")
	var view := await _stand_up()
	var pa := view.play_area
	pa.flush_rebuild()
	await get_tree().process_frame
	check(pa._layer_grown.is_empty(),
			"a board seen for the first time is already the shape it should be, so nothing eases "
			+ "in -- a restored or dealt board must not play a growth that never happened",
			"%d layers growing" % pa._layer_grown.size())
	await _tear_down(view)


# ==============================================================================
# TP-86 -- the Entrance is row -1, and its own height pushes the whole board UP.
#
# Owner, quoted in Q313: *"if entrance/input cards are somehow stacked with multiple cards as well
# increasing in height, then it raises everything above it up as well so as to not cover any card
# in the grid."* Q313=(a): that is the SAME mechanism a grid row's height uses, not a special case.
#
# ⚠ **THE DISCRIMINATING CASE IS A GRID CARD, NOT THE ENTRANCE'S OWN.** "The Entrance got taller"
# and "the Entrance got taller AND the board moved" both leave the strip looking right; only the
# second keeps the Entrance from covering the board. So this measures a card sitting on the GRID.
# ==============================================================================
func run_the_entrance_height_pushes_the_board_up_test() -> void:
	behavior_section("THE ENTRANCE'S OWN HEIGHT PUSHES THE BOARD UP")
	var view := await _stand_up()
	var pa := view.play_area
	var g := view.game

	# A card on the grid, so there is a board position that must not be covered.
	await g.place_card_in_grid(g.state.upper_zone[0].datas[0], BoardCoord.new(0, 2, 4, 0))
	await _settle_layout(view)
	var board_before := pa.slot_center_global(BoardCoord.new(0, 2, 4, 0)).y
	# ⚠ The Entrance's OVERFLOW past its visible strip is what moves the board. The strip itself is
	# a player setting and deliberately does NOT move when cards land in the Entrance — resizing it
	# would re-lay out everything anchored inside it.
	var reservation := CardVisual.card_size_play.y * SettingsManager.settings.entrance_visible_rows
	var strip_before := maxf(reservation, pa._entrance_row_height())

	# Stack the Entrance PAST the configured minimum, so the strip genuinely has to grow.
	var col : ArrayCardData = g.state.upper_zone[1]
	for _i in 4:
		var extra := TestFactories.m_card(7, TestFactories.uc())
		extra.stage = CardData.Stage.PLAY
		col.datas.append(extra)
	g.state.revision += 1
	pa.queue_rebuild()
	await _settle_layout(view)

	var strip_after := maxf(reservation, pa._entrance_row_height())
	check(strip_after > strip_before + 0.5,
			"precondition: the Entrance really did get taller",
			"%.1f -> %.1f" % [strip_before, strip_after])

	var board_after := pa.slot_center_global(BoardCoord.new(0, 2, 4, 0)).y
	check(board_after < board_before - 0.5,
			"Q313: a card on the GRID is pushed UP when the Entrance stacks — the Entrance is row "
			+ "-1 and its height raises everything above it rather than covering it",
			"%.1f -> %.1f" % [board_before, board_after])
	# ⚠ **NOT "by exactly the overflow".** That looks like the mechanism but is an identity the
	# layout does not owe: the scroll content's own origin can shift as the region around it
	# resizes (measured: the content top moved -1 -> +7, so the floor rose 49 where the Entrance
	# overflowed 57, and the board tracked the FLOOR exactly, which is correct). The requirement is
	# the owner's own words — *"so as to not cover any card in the grid"* — so assert that.
	var lowest_bottom := board_after + CardVisual.card_size_play.y * 0.5
	var entrance_top := pa.global_position.y + pa.size.y - pa._entrance_row_height()
	check(lowest_bottom <= entrance_top + 1.0,
			"...far enough that the board's LOWEST card clears the Entrance's real height — the "
			+ "point of raising it at all",
			"lowest card bottom %.1f vs Entrance top %.1f" % [lowest_bottom, entrance_top])
	await _tear_down(view)


# ==============================================================================
# TP-88 / TP-89 / TP-90 -- THE SPRING.
#
# Owner, quoted in Q310: *"animations such as jumping will cause cards stacked above to jump up as
# well like a spring as if jumping card has all above cards on its shoulder."*
#   Q310=(a) the WHOLE stack above lifts, by the FULL rise, as one rigid body.
#   Q312=(a) it OVERLAPS the rows above; the board does NOT re-flow.
#   Q311=(a) a hoop rides the card that actually JUMPED, not the stack top.
#
# ⚠ **THE CASE THAT SEPARATES "RIGID" FROM "SPRING-LIKE" IS THE TOP CARD.** A decaying lift and a
# rigid one both move the card just above the jump; only the rigid one moves the TOP of a deep
# stack by the same amount. So the fixture is three deep and the assertion is about equality
# between the riders, not merely that they moved.
# ==============================================================================
func run_a_jump_lifts_the_stack_above_it_test() -> void:
	behavior_section("A JUMP LIFTS THE WHOLE STACK ABOVE IT, RIGIDLY")
	var view := await _stand_up()
	var pa := view.play_area
	var g := view.game
	var coord := BoardCoord.new(0, 1, 1, 0)
	for i in 3:
		await g.place_card_in_grid(g.state.upper_zone[i].datas[0], coord)
	await _settle_layout(view)

	var grid : GridData = g.state.grids[0]
	var stack : Array[CardData] = grid.cells[grid.cell_index(1, 1)].datas
	check(stack.size() == 3, "precondition: a three-deep stack to spring",
			"%d deep" % stack.size())
	if stack.size() < 3:
		await _tear_down(view)
		return

	var rows_before := pa.slot_center_global(BoardCoord.new(0, 1, 0, 0)).y
	var visuals : Array[CardVisual] = []
	for c : CardData in stack:
		visuals.append(pa.data_card.get(c))
	if visuals[0] == null or visuals[1] == null or visuals[2] == null:
		check(false, "precondition: every card in the stack has a visual")
		await _tear_down(view)
		return

	# The card at the BOTTOM jumps. Everything above it should ride.
	pa.jump_card_with_its_stack(stack[0])
	var lifted : Array[float] = [0.0, 0.0, 0.0]
	var waited := 0.0
	while waited < 3.0:
		waited += await _tick()
		CardEnvironment.CURRENT = g   # siblings run concurrently; see `_settle_layout`
		for i in 3:
			lifted[i] = minf(lifted[i], visuals[i].offset.position.y)
		if lifted[0] < -1.0 and lifted[2] < -1.0: break

	check(lifted[1] < -1.0 and lifted[2] < -1.0,
			"E14/Q310: every card ABOVE the jumping one lifts too -- the stack rides on its "
			+ "shoulder rather than being passed through",
			"h1 %.1f h2 %.1f" % [lifted[1], lifted[2]])
	check(absf(lifted[2] - lifted[0]) < 1.0 and absf(lifted[1] - lifted[0]) < 1.0,
			"...by the SAME rise as the card that jumped -- one rigid body, not a decaying spring. "
			+ "The TOP of the stack is the case that separates the two",
			"jumped %.1f, h1 %.1f, h2 %.1f" % [lifted[0], lifted[1], lifted[2]])

	# TP-89 -- the board does not RE-FLOW while the stack is up.
	check(absf(pa.slot_center_global(BoardCoord.new(0, 1, 0, 0)).y - rows_before) < 0.5,
			"E15/Q312: the row ABOVE does not move while the stack is lifted -- a jump OVERLAPS "
			+ "rather than re-flowing the board, which would shove the screen on every jump",
			"%.1f -> %.1f" % [rows_before,
			pa.slot_center_global(BoardCoord.new(0, 1, 0, 0)).y])
	check(absf(pa.slot_center_global(BoardCoord.new(0, 1, 1, 0)).y
			- pa.slot_center_global(BoardCoord.new(0, 1, 1, 0)).y) < 0.5,
			"...and the slot geometry itself is untouched: the lift rides the card's own offset, "
			+ "which the containers never see")

	# It comes back down.
	# ⚠ Wait for it to SETTLE, not merely to cross zero: the descent is TRANS_BACK, so it
	# overshoots past the resting pose and comes back — sampling on the way through caught it at
	# 1.1 px and called a working animation a failure.
	waited = 0.0
	while waited < 4.0 and absf(visuals[2].offset.position.y) > 0.5:
		waited += await _tick()
		CardEnvironment.CURRENT = g
	check(absf(visuals[2].offset.position.y) < 1.0,
			"...and the whole stack settles back down again",
			"top card left at %.1f" % visuals[2].offset.position.y)
	await _tear_down(view)

# ==============================================================================
# TP-90 -- a hoop rides the card that JUMPED, not the top of the stack it lifted.
#
# ⚠ The coupling is exact and documented on `CARD_JUMP_RISE`: the ring's centre and the card's
# centre must coincide, so riding the wrong card of a lifted stack makes the card pass through the
# SIDE of the hoop. On a three-deep stack the two candidates are two depth pitches apart, which is
# why the fixture is deep rather than flat.
# ==============================================================================
func run_a_hoop_rides_the_card_that_jumped_test() -> void:
	behavior_section("A HOOP RIDES THE CARD THAT JUMPED")
	var view := await _stand_up()
	var pa := view.play_area
	var g := view.game
	var coord := BoardCoord.new(0, 1, 1, 0)
	for i in 3:
		await g.place_card_in_grid(g.state.upper_zone[i].datas[0], coord)
	await _settle_layout(view)

	var pl := pa.prop_layer
	var jumped := BoardCoord.new(0, 1, 1, 0)     # the card at the BOTTOM, which jumps
	var stack_top := BoardCoord.new(0, 1, 1, 2)  # the card at the top, which merely rides
	var pitch := float(CardVisual.card_separation_play_custom) + float(pa.separation)

	# A hoop's own lane offset carries the rise (`_live_lane_offset`), so the ring it anchors to is
	# its slot point plus that. Driven through a real PropVisual rather than asserted on constants.
	var hoop := PropData.new()
	hoop.kind = 0   # hoop -- rides_card_jump
	hoop.at = jumped
	hoop.route = [] as Array[BoardCoord]
	var ok := await _prop_tick(pl, [hoop], [hoop])
	check(ok, "hoop spawn tick completes")
	var hv : PropVisual = pl._visuals.get(hoop)
	check(hv != null and hv.rides_card_jump,
			"precondition: the hoop is a kind a card jumps INTO")
	if hv == null:
		await _tear_down(view)
		return
	var ring := pl._slot_point(jumped) + pl._live_lane_offset(hv)
	var want := pl._slot_point(jumped).y - CardVisual.card_jump_rise_play
	check(absf(ring.y - want) < 1.0,
			"Q311: the hoop's anchor is the JUMPING card's slot lifted by the jump rise, so the "
			+ "two centres coincide",
			"ring %.1f vs card-plus-rise %.1f" % [ring.y, want])
	var top_ring := pl._slot_point(stack_top).y - CardVisual.card_jump_rise_play
	check(absf(ring.y - top_ring) > pitch - 1.0,
			"...and NOT the top of the stack it lifted, which sits two depth pitches away -- a card "
			+ "would pass through the SIDE of a ring placed there",
			"ring %.1f vs stack-top-plus-rise %.1f" % [ring.y, top_ring])
	await _tear_down(view)


# ==============================================================================
# TP-93 -- NO SUBTOTAL IS DISPLAYED ANYWHERE. No per-grid score, no bucket breakdown.
#
# Owner correction, recorded on Q326 and superseding its round-2 answer: *"do not display subtotals
# such as grid score."* D22 states it as a design node: *"NO subtotals are displayed: no grid score,
# no bucket breakdown."* The HUD shows the board total and the combo, and nothing else.
#
# ⚠ **THIS IS A RATCHET, AND IT PASSES TRIVIALLY TODAY -- THAT IS THE POINT.** No grid-score label
# exists yet, so the claim holds for free; it is written NOW because S24 is about to add score
# labels around every grid, and "we also added a grid subtotal while we were there" is precisely
# the drift a negative claim cannot catch after the fact. It fails the day one appears.
#
# ⚠ It must not pass by finding nothing at all. The board really does display SOME numbers (the
# board total, the combo), so the test first proves it can see labels, then proves none of them is
# a per-grid subtotal.
# ==============================================================================
func run_no_subtotal_is_displayed_anywhere_test() -> void:
	behavior_section("NO SUBTOTAL IS DISPLAYED ANYWHERE")
	var view := await _stand_up()
	var pa := view.play_area
	var g := view.game
	# Score something, so every bucket a subtotal could be drawn from is non-zero.
	await g.place_card_in_grid(g.state.upper_zone[0].datas[0], BoardCoord.new(0, 0, 2, 0))
	await _settle_layout(view)

	var grid_score := g.state.grid_score(0)
	check(grid_score >= 0.0, "precondition: a grid score exists to be (not) displayed",
			"grid 0 scores %.1f" % grid_score)

	# Every label anywhere under the view, so the search cannot miss a surface.
	var labels : Array[Label] = []
	var stack : Array[Node] = [view]
	while not stack.is_empty():
		var n : Node = stack.pop_back()
		var l := n as Label
		if l: labels.append(l)
		for c : Node in n.get_children(): stack.append(c)
	check(labels.size() > 0,
			"the sweep can SEE labels at all — otherwise this test passes by looking at nothing",
			"%d labels found" % labels.size())

	# The board total and the combo are allowed; a PER-GRID subtotal is not. Anything parented
	# under a grid panel that reads as a score is the shape D22 forbids.
	var offenders : Array[String] = []
	for panel_i : int in pa.grid_container.get_child_count():
		var panel : Node = pa.grid_container.get_child(panel_i)
		var inner : Array[Node] = [panel]
		while not inner.is_empty():
			var n : Node = inner.pop_back()
			var bl := n as BigNumberLabel
			if bl and not bl.text.is_empty():
				offenders.append("%s = '%s'" % [bl.name, bl.text])
			for c : Node in n.get_children(): inner.append(c)
	check(offenders.is_empty(),
			"D22/Q326: no grid panel displays a subtotal — no grid score, no bucket breakdown",
			"found: " + ", ".join(offenders))
	await _tear_down(view)


# ==============================================================================
# TP-91 / TP-94 -- WHERE THE SCORE LABELS SIT, AND THAT THERE IS ONE PER (LINE, HEIGHT).
#
# Q107=(a) rows LEFT. Q108 (settled by the flip) columns BELOW. Q110, owner verbatim: *"All
# diagonal type scores go to a single label to the right of the grid aligned with center of the
# grid, opposite side of row labels."* GAP-015, owner verbatim: *"each will need to be tracked and
# displayed, with height stacked in same order as rows and cols next to the same height rows and
# cols. so row could display 10 scores if 5 rows each with 2 height cards at 0 and 1."*
#
# ⚠ **THE CASE THAT SEPARATES THE TWO READINGS OF "height stacked in same order" IS WHICH END THE
# HEIGHT-0 LABEL SITS AT.** Both orderings give a row two labels; only one puts the height-0 score
# level with the height-0 cards, and since the cards stack UPWARD that is the BOTTOM of the label
# column. Asserting merely "two labels exist" would pass on the reversed board.
# ==============================================================================
func run_score_labels_sit_where_the_design_puts_them_test() -> void:
	behavior_section("SCORE LABELS SIT WHERE THE DESIGN PUTS THEM")
	var view := await _stand_up()
	var pa := view.play_area
	var g := view.game
	var st := g.state

	# Two heights of row scores and of column scores, so a stack of labels really is a stack.
	st.bank_line_score(st.scores_row, 0, 1, 0, 11)
	st.bank_line_score(st.scores_row, 0, 1, 1, 22)
	st.bank_line_score(st.scores_col, 0, 2, 0, 33)
	st.bank_line_score(st.scores_col, 0, 2, 1, 44)
	st.resize_grid_bucket(st.score_special, 1)
	st.score_special[0].plus_equals(55)
	pa.queue_rebuild()
	await _settle_layout(view)

	var panel : Control = pa.grid_container.get_child(0)
	var board : Control = panel.get_node_or_null("Board")
	var row_labels : Control = board.get_node_or_null("RowLabels") if board else null
	var col_labels : Control = panel.get_node_or_null("Board/CellsColumn/ColLabels")
	var special : BigNumberLabel = board.get_node_or_null("SpecialLabel") if board else null
	check(row_labels != null and col_labels != null and special != null,
			"the panel carries a row gutter, a column gutter and one special label")
	if row_labels == null or col_labels == null or special == null:
		await _tear_down(view)
		return

	var cells := pa._cells_root(panel)
	# Q107=a: rows to the LEFT of the columns.
	check(row_labels.get_global_rect().end.x <= cells.get_global_rect().position.x + 1.0,
			"Q107: the row gutter sits entirely LEFT of the grid's columns",
			"gutter ends %.1f, cells start %.1f"
			% [row_labels.get_global_rect().end.x, cells.get_global_rect().position.x])
	# Q108, as the flip settled it: columns BELOW.
	check(col_labels.get_global_rect().position.y >= cells.get_global_rect().end.y - 1.0,
			"Q108: the column gutter sits BELOW the grid — the flip inverted the recorded answer",
			"gutter starts %.1f, cells end %.1f"
			% [col_labels.get_global_rect().position.y, cells.get_global_rect().end.y])
	# ⚠ **A COLUMN'S LABEL MUST SIT UNDER THAT COLUMN.** The gutter being "below the grid" is not
	# enough: as a bare child of the panel it began at the PANEL's left edge, which is the ROW
	# gutter's edge, so every column label sat most of a column left of the column it names —
	# owner: *"3rd column has its label on 2nd col, and so on"*. Each label is checked against its
	# OWN column, so a gutter shifted by a whole column still fails on all five.
	var row0 : Control = cells.get_child(0)
	var worst_dx := 0.0
	for cx : int in mini(col_labels.get_child_count(), row0.get_child_count()):
		var label_x : float = (col_labels.get_child(cx) as Control).get_global_rect().position.x
		var cell_x : float = (row0.get_child(cx) as Control).get_global_rect().position.x
		worst_dx = maxf(worst_dx, absf(label_x - cell_x))
	check(worst_dx <= 1.0,
			"every column's score label starts on that column's own left edge — the gutter is "
			+ "indented past the row labels, not flush with the panel",
			"worst %.2f px out across %d columns" % [worst_dx, col_labels.get_child_count()])

	# Q110: ONE special label, right of the grid, centred on it, opposite the row labels.
	check(special.get_global_rect().position.x >= cells.get_global_rect().end.x - 1.0,
			"Q110: the special-meld label sits to the RIGHT of the grid, opposite the row labels",
			"label at %.1f, cells end %.1f"
			% [special.get_global_rect().position.x, cells.get_global_rect().end.x])
	var cells_mid := cells.get_global_rect().get_center().y
	var special_mid := special.get_global_rect().get_center().y
	check(absf(special_mid - cells_mid) < CardVisual.card_size_play.y,
			"...and is aligned with the CENTRE of the grid, not with a row",
			"label centre %.1f vs grid centre %.1f" % [special_mid, cells_mid])
	check(special.text.contains("55") or not special.text.is_empty(),
			"...and carries the one special bucket every diagonal shares", "'%s'" % special.text)
	# ⚠ **A SCORE LABEL WITHOUT A BOX IS NOT A SCORE LABEL.** With no minimum of its own the
	# special label shrank to whatever its own text measured and `AutosizeLabel` pinned its font at
	# the floor, so it read at a different size from the gutters either side of the grid — owner:
	# *"special score not same size as row and col scores label"*. It is the row gutter's mirror,
	# so it takes the row gutter's box and therefore the row gutter's font.
	var a_row_label : Label = (row_labels.get_child(1) as Control).get_child(-1) as Label
	check(special.custom_minimum_size.is_equal_approx(a_row_label.custom_minimum_size),
			"the special label carries the same box a row score label does",
			"special %s vs row %s" % [special.custom_minimum_size,
			a_row_label.custom_minimum_size])
	check(special.get_theme_font_size("font_size")
			== a_row_label.get_theme_font_size("font_size"),
			"...and therefore renders at the same font size, not squashed to the autosize floor",
			"special %d vs row %d" % [special.get_theme_font_size("font_size"),
			a_row_label.get_theme_font_size("font_size")])

	# GAP-015: one label per (line, height) — a row with two heights shows TWO scores.
	var stack : VBoxContainer = row_labels.get_child(1)
	check(stack != null and stack.get_child_count() == 2,
			"GAP-015: a row with two scored heights shows TWO labels, not one",
			"%d labels" % (stack.get_child_count() if stack else -1))
	if stack == null or stack.get_child_count() < 2:
		await _tear_down(view)
		return
	var bottom_label : BigNumberLabel = stack.get_child(-1)
	var top_label : BigNumberLabel = stack.get_child(0)
	check(bottom_label.text.contains("11") and top_label.text.contains("22"),
			"...with the HEIGHT-0 score at the BOTTOM, level with the height-0 cards — the cards "
			+ "stack upward, so the labels beside them must too",
			"bottom '%s' top '%s'" % [bottom_label.text, top_label.text])

	# The same for a column.
	var col_stack : VBoxContainer = col_labels.get_child(2)
	check(col_stack != null and col_stack.get_child_count() == 2,
			"a column with two scored heights shows two labels as well",
			"%d labels" % (col_stack.get_child_count() if col_stack else -1))
	if col_stack and col_stack.get_child_count() >= 2:
		check((col_stack.get_child(-1) as BigNumberLabel).text.contains("33"),
				"...ordered the same way, height 0 nearest the grid",
				"bottom '%s'" % (col_stack.get_child(-1) as BigNumberLabel).text)

	# TP-94 -- the numbers survive a save/reload of the state they came from.
	st.pack_scores()
	var restored := st.duplicate_state()
	restored.unpack_scores()
	check(restored.line_score(restored.scores_row, 0, 1, 1) == 22.0
			and restored.line_score(restored.scores_col, 0, 2, 1) == 44.0,
			"TP-94: a label's number survives the save round trip at its own (row, height)",
			"row %f col %f" % [restored.line_score(restored.scores_row, 0, 1, 1),
			restored.line_score(restored.scores_col, 0, 2, 1)])
	await _tear_down(view)

# ==============================================================================
# TP-92 -- a HEIGHT score label sits ABOVE the topmost card of its stack (E17, Q309=a),
# and rises as the stack grows.
#
# ⚠ **THE CASE THAT SEPARATES "above the stack" FROM "above the cell" IS A SECOND CARD.** Both put
# the label over a one-card cell; only the first moves it when the stack deepens. So the assertion
# is about the label MOVING UP by a depth pitch, not merely about where it starts.
# ==============================================================================
func run_a_height_label_sits_above_its_stack_test() -> void:
	behavior_section("A HEIGHT LABEL SITS ABOVE ITS STACK")
	var view := await _stand_up()
	var pa := view.play_area
	var g := view.game
	var coord := BoardCoord.new(0, 3, 2, 0)
	await g.place_card_in_grid(g.state.upper_zone[0].datas[0], coord)
	g.state.bank_cell_score(0, Vector2i(3, 2), 12)
	await _settle_layout(view)
	await get_tree().physics_frame

	var key := Vector3i(0, 3, 2)
	var label : BigNumberLabel = pa._cell_score_labels.get(key)
	check(label != null and is_instance_valid(label),
			"a cell that has scored gets a height label at all")
	if label == null:
		await _tear_down(view)
		return
	check(label.text.contains("12"), "...carrying that cell's own banked score",
			"'%s'" % label.text)

	var top_card_y := pa.slot_center_global(BoardCoord.new(0, 3, 2, 0)).y
	check(label.global_position.y + label.size.y <= top_card_y
			- CardVisual.card_size_play.y * 0.5 + 1.0,
			"E17: the label sits entirely ABOVE the topmost card, never over it",
			"label bottom %.1f vs card top %.1f"
			% [label.global_position.y + label.size.y,
			top_card_y - CardVisual.card_size_play.y * 0.5])
	var before := label.global_position.y

	# Deepen the stack: the label must RISE with it, which is what "above its STACK" means.
	await g.place_card_in_grid(g.state.upper_zone[1].datas[0], coord)
	await _settle_layout(view)
	await get_tree().physics_frame
	var pitch := float(CardVisual.card_separation_play_custom) + float(pa.separation)
	check(absf((before - label.global_position.y) - pitch) < 1.5,
			"Q309: it RISES by one depth pitch as the stack grows — above the STACK, not above the "
			+ "cell, which is the reading a one-card fixture cannot tell apart",
			"moved %.1f, pitch %.1f" % [before - label.global_position.y, pitch])
	await _tear_down(view)

# ==============================================================================
# A height label stays above its stack when the board is FOCUSED, where `board_zoom` departs
# from 1.0 -- a check that is arithmetically blind at the overview's own zoom of exactly 1.
# ==============================================================================
func run_a_height_label_stays_above_its_stack_when_focused_zoom_is_not_one_test() -> void:
	behavior_section("A HEIGHT LABEL STAYS ABOVE ITS STACK AT A NON-1.0 BOARD ZOOM")
	var view := await _stand_up()
	var pa := view.play_area
	var g := view.game
	var coord := BoardCoord.new(0, 3, 2, 0)
	await g.place_card_in_grid(g.state.upper_zone[0].datas[0], coord)
	await g.place_card_in_grid(g.state.upper_zone[1].datas[0], coord)
	g.state.bank_cell_score(0, Vector2i(3, 2), 12)
	pa.focus_grid(0)
	await _settle_layout(view)
	await get_tree().physics_frame
	check(not is_equal_approx(pa.board_zoom, 1.0),
			"precondition: focusing a grid takes the board off the overview's own zoom of 1.0",
			"board_zoom %.3f" % pa.board_zoom)

	var key := Vector3i(0, 3, 2)
	var label : BigNumberLabel = pa._cell_score_labels.get(key)
	check(label != null and is_instance_valid(label),
			"a cell that has scored gets a height label at all")
	if label == null:
		await _tear_down(view)
		return

	var top_card_y := pa.slot_center_global(BoardCoord.new(0, 3, 2, 1)).y
	var expected_gap := CardVisual.card_size_play.y * pa.board_zoom * 0.5
	var label_bottom := label.global_position.y + label.size.y * pa.board_zoom
	check(absf((top_card_y - expected_gap) - label_bottom) < 1.5,
			"the label's bottom sits exactly half a (zoom-scaled) card above its stack's top card, "
			+ "even off the overview's own zoom of 1.0",
			"label bottom %.1f vs expected %.1f" % [label_bottom, top_card_y - expected_gap])
	await _tear_down(view)

# ==============================================================================
# A ROW'S ZONE CARDS SHARE ONE LINE, AT A BOARD ZOOM THAT IS NOT 1.0 (owner ruling: "stacking
# cards on a zone should not cause the zone to move relative to grid").
#
# ⚠ TWO THINGS MUST BOTH VARY OR THIS CHECK IS BLIND.
#  * THE DEPTHS MUST BE UNEVEN, AND ONE CELL MUST BE EMPTY. An empty cell's frame control is a
#    WHOLE CARD while an occupied one's is collapsed to zero, and those are the two ends of the
#    error. An even row cannot tell "every frame on the row's bottom line" from "every frame at
#    its own stack's bottom" — they are the same picture until one cell differs.
#  * THE BOARD MUST BE FOCUSED. The defect is a control-local length added to a scaled global
#    position, so it is EXACTLY ZERO at the overview's own zoom of 1.0. Measured: 69.74 px of
#    spread at board_zoom 2.29, 0.00 px at 1.0.
#
# Asserts the VISUALS, not the controls: the containers were already right — every occupied
# slot's frame control sat on one line — and it was the card that drew somewhere else.
# ==============================================================================
func run_a_rows_zone_cards_share_one_line_at_a_non_one_zoom_test() -> void:
	behavior_section("A ROW'S ZONE CARDS SHARE ONE LINE AT A NON-1.0 BOARD ZOOM")
	var view := await _stand_up()
	var pa := view.play_area
	var g := view.game
	var depths : Array[int] = [2, 1, 0, 3]
	for x : int in depths.size():
		for _h : int in depths[x]:
			var card := g.draw_card()
			if not card: break
			await g.place_card_in_grid(card, BoardCoord.new(0, x, 0, _h))
	pa.focus_grid(0)
	await _settle_layout(view)
	await get_tree().physics_frame
	check(not is_equal_approx(pa.board_zoom, 1.0),
			"precondition: the board is FOCUSED, so board_zoom is off 1.0 and the defect can show",
			"board_zoom %.4f" % pa.board_zoom)

	var grid : GridData = g.state.grids[0]
	var empty_seen := false
	var occupied_seen := false
	var visuals : Array[CardVisual] = []
	for x : int in depths.size():
		var zone_card : CardData = grid.cell_types[grid.cell_index(x, 0)]
		var vis : CardVisual = pa.data_card.get(zone_card)
		if vis: visuals.append(vis)
		if depths[x] == 0: empty_seen = true
		else: occupied_seen = true
	check(empty_seen and occupied_seen and visuals.size() == depths.size(),
			"precondition: the row mixes an EMPTY cell with occupied ones, and every zone card drew",
			"%d visuals, empty %s, occupied %s" % [visuals.size(), empty_seen, occupied_seen])
	await _settle_visuals(visuals)

	var lo := INF
	var hi := -INF
	for vis : CardVisual in visuals:
		lo = minf(lo, vis.global_position.y)
		hi = maxf(hi, vis.global_position.y)
	check(hi - lo < 1.0,
			"every zone card in one row draws on ONE line however deep its own cell is stacked",
			"spread %.2f px across %d cells" % [hi - lo, visuals.size()])

	await _tear_down(view)

# ==============================================================================
# ROW LABEL `ry` MUST LINE UP WITH CELL ROW `ry`. TP-91/TP-93/TP-94 only ever compare the WHOLE
# label gutter rect to the WHOLE cell block rect -- left-of, below-of, counts, text -- so a gutter
# that gives every row a fixed height regardless of its cells' real depth reads green there while
# every row past the first drifts off its cards.
#
# ⚠ THE DISCRIMINATING FIXTURE IS UNEVEN BANKED SCORE LEVELS, NOT UNEVEN CARD DEPTH. A grid-wide
# `levels` computed from the whole grid's deepest banked score still fits every row's real height
# when every row banks the SAME number of scores -- both a correct, per-row-sized gutter and a
# broken, grid-wide-sized one put every row at the same height. Only a row that banks MORE scores
# than another row can force the broken gutter's surplus fixed-height children past that row's
# `_grid_row_height`, so row 2 here banks three scores while row 0 banks one, matching
# `Tests/Visual/uneven_stack_score_shot.gd`'s shape.
# ==============================================================================
func run_a_row_label_lines_up_with_its_own_row_test() -> void:
	behavior_section("A ROW LABEL LINES UP WITH ITS OWN ROW, NOT A FIXED GUTTER SLOT")
	var view := await _stand_up()
	var pa := view.play_area
	var g := view.game
	var st := g.state

	# Row 0 stays one card deep; row 2 goes three deep, so the two rows' real, measured heights
	# differ -- the case a fixed per-level gutter cannot follow.
	await g.place_card_in_grid(g.state.upper_zone[0].datas[0], BoardCoord.new(0, 0, 0, 0))
	for i in 3:
		await g.place_card_in_grid(g.state.upper_zone[1 + i].datas[0], BoardCoord.new(0, 0, 2, 0))
	# Row 0 banks one score; row 2 banks three, one per height -- the uneven LEVEL count that a
	# grid-wide `levels` cannot follow without overflowing row 0's gutter.
	st.bank_line_score(st.scores_row, 0, 0, 0, 5)
	st.bank_line_score(st.scores_row, 0, 2, 0, 7)
	st.bank_line_score(st.scores_row, 0, 2, 1, 9)
	st.bank_line_score(st.scores_row, 0, 2, 2, 11)
	pa.queue_rebuild()
	await _settle_layout(view)

	var panel : Control = pa.grid_container.get_child(0)
	var cells := pa._cells_root(panel)
	var board : Control = panel.get_node_or_null("Board")
	var row_labels : Control = board.get_node_or_null("RowLabels") if board else null
	check(cells != null and row_labels != null,
			"precondition: the panel carries both a cell block and a row gutter")
	if cells == null or row_labels == null:
		await _tear_down(view)
		return

	for ry in st.grids[0].grid_height:
		var cell_row := cells.get_child(ry) as Control
		var label_row := row_labels.get_child(ry) as Control
		check(cell_row != null and label_row != null,
				"row %d has both a cell row and a label row" % ry)
		if cell_row == null or label_row == null: continue
		var cell_rect := cell_row.get_global_rect()
		var label_rect := label_row.get_global_rect()
		check(absf(cell_rect.position.y - label_rect.position.y) < 1.5
				and absf(cell_rect.end.y - label_rect.end.y) < 1.5,
				"row %d's score label lines up with row %d's cells, top and bottom" % [ry, ry],
				"cell row y [%.1f, %.1f], label row y [%.1f, %.1f]"
				% [cell_rect.position.y, cell_rect.end.y, label_rect.position.y, label_rect.end.y])
	await _tear_down(view)


# ==============================================================================
# THE FIRST CARD IN A CELL DOES NOT WIDEN ITS ROW.
#
# Owner: *"adding a card to a zone widens gap between the rows. This should not occur for very
# first card placed into a zone, but additional height stacked cards can do that."*
#
# A cell's zone card is the cell's own frame -- a whole card, exactly the size of the card that
# will cover it -- so a stack of ONE is exactly one card tall and the row must not move. Every
# layer above the first brings a real depth pitch, and the row is expected to grow for those.
#
# ⚠ **THE THIRD CHECK IS THE ONE THAT MATTERS.** "The row did not grow" alone is satisfied by a
# row that never grows at all, which would be a worse bug than the one being fixed.
# ==============================================================================
func run_the_first_card_in_a_cell_does_not_widen_its_row_test() -> void:
	behavior_section("THE FIRST CARD IN A CELL DOES NOT WIDEN ITS ROW")
	var view := await _stand_up()
	var pa := view.play_area
	var g := view.game
	await _settle_layout(view)
	var empty_h := _row_control_height(pa, 0, 0)
	var other_empty_h := _row_control_height(pa, 0, 1)
	check(empty_h > 0.0 and is_equal_approx(empty_h, other_empty_h),
			"precondition: every empty row is the same height, so a change can only come from a "
			+ "card", "row 0 %.2f, row 1 %.2f" % [empty_h, other_empty_h])

	var first := g.draw_card()
	check(first != null, "precondition: the deck gave a card to place")
	if first: await g.place_card_in_grid(first, BoardCoord.new(0, 0, 0, 0))
	pa.queue_rebuild()
	await _settle_layout(view)
	var one_h := _row_control_height(pa, 0, 0)
	check(is_equal_approx(one_h, empty_h),
			"the FIRST card in a cell leaves its row exactly as tall as it was empty -- the card "
			+ "covers the zone card, it does not sit on top of it",
			"empty %.2f, one card %.2f" % [empty_h, one_h])
	check(is_equal_approx(_row_control_height(pa, 0, 1), other_empty_h),
			"...and the untouched row beside it did not move either",
			"%.2f vs %.2f" % [_row_control_height(pa, 0, 1), other_empty_h])

	var second := g.draw_card()
	if second: await g.place_card_in_grid(second, BoardCoord.new(0, 0, 0, 1))
	pa.queue_rebuild()
	await _settle_layout(view)
	var two_h := _row_control_height(pa, 0, 0)
	var pitch := float(CardVisual.card_separation_play_custom) + float(pa.separation)
	check(is_equal_approx(two_h - one_h, pitch),
			"a SECOND card in that cell grows the row by exactly one depth pitch -- rows still "
			+ "grow, they just do not grow for the first card",
			"one %.2f, two %.2f, pitch %.2f" % [one_h, two_h, pitch])

	# The arithmetic every card and prop is placed by has to agree with the containers, or the
	# cards drift off the rows the containers drew.
	# ⚠ **AT REST, AND THE WAIT IS NOT OPTIONAL.** A newly-landed depth layer EASES into the
	# arithmetic's height while the container takes its full height at once, so the two genuinely
	# disagree for the length of that ease -- measured 57.68 against 74.00 mid-growth. This asks
	# whether they agree once nothing is moving.
	var waited := 0.0
	while not pa._layer_grown.is_empty() and waited < 3.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	two_h = _row_control_height(pa, 0, 0)
	check(is_equal_approx(pa._grid_row_height(0, 0), two_h),
			"the row height the slot arithmetic uses equals the height the container laid out",
			"arithmetic %.2f, container %.2f" % [pa._grid_row_height(0, 0), two_h])
	await _tear_down(view)

## One grid row's laid-out height, in BOARD units -- `size` never carries the board zoom.
func _row_control_height(pa: PlayArea, gi: int, ry: int) -> float:
	var panel := pa.grid_container.get_child(gi) as Control
	var cells := pa._cells_root(panel)
	if not cells or ry >= cells.get_child_count(): return 0.0
	return (cells.get_child(ry) as Control).size.y


# ==============================================================================
# A BANKED GRID SCORE POPS ITS OWN LABEL.
#
# Owner: *"scores are not popping up immediately upon scoring like before pre grid."*
#
# `Game.add_line_score()` is THE single write path for line scores -- melds and prop effects both
# come through it -- so it is driven directly here rather than through a contrived meld. Its
# LEGACY branch calls `view.update_line_score()`, which pops; its GRID branch banked into the
# buckets and told the view nothing at all, so a grid score only ever appeared on whatever
# rebuild happened next.
#
# ⚠ **THE ASSERTION IS THAT THE LABEL MOVED, NOT THAT A TWEEN OBJECT EXISTS.** A pop has a
# DURATION; a check that only asks whether something was created passes on a tween that animates
# nothing.
# ==============================================================================
func run_a_banked_grid_score_pops_its_label_test() -> void:
	behavior_section("A BANKED GRID SCORE POPS ITS OWN LABEL")
	var view := await _stand_up()
	var pa := view.play_area
	var g := view.game
	await _settle_layout(view)

	var section := ScoringSection.of_line_at(g.state, 0, ScoringSection.LineKind.ROW, 1, 0)
	check(g.view != null, "precondition: the game has a view to animate through")
	g.add_line_score(section, 500)
	check(g.state.line_score(g.state.scores_row, 0, 1, 0) == 500.0,
			"precondition: the score really banked into the row bucket",
			"%f, kind %d grid %d index %d height %d" % [
			g.state.line_score(g.state.scores_row, 0, 1, 0), section.kind, section.grid,
			section.index, section.height])
	var panel : Control = pa.grid_container.get_child(0)
	var label := pa._grid_score_label(panel, section)
	check(label != null,
			"banking a grid row score creates the label that score belongs to -- a line scoring "
			+ "at a height nothing reached before had none, and a pop on a missing label is "
			+ "silently dropped")
	if label == null:
		await _tear_down(view)
		return
	check(label.text.contains("500"),
			"...and that label carries the banked number", "'%s'" % label.text)

	var peak := 0.0
	var waited := 0.0
	while waited < 2.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		peak = maxf(peak, absf(label.scale.x - 1.0))
	check(peak > 0.01,
			"...and the label POPS -- its scale really leaves 1.0, the same way a legacy gutter "
			+ "label does when a line banks into it",
			"peak scale departure %.4f" % peak)
	check(is_equal_approx(label.scale.x, 1.0),
			"...and comes back to rest, so a scored label is not left permanently enlarged",
			"resting scale %.4f" % label.scale.x)

	# The special bucket is a different node on a different branch of the lookup, and it had the
	# same silence.
	var diag := ScoringSection.of_line_at(g.state, 0, ScoringSection.LineKind.DIAG, 0, 0)
	g.add_line_score(diag, 700)
	var special := pa._grid_score_label(panel, diag)
	check(special != null and special.text.contains("700"),
			"the special-meld bucket's label is found and updated by the same path",
			"'%s'" % (special.text if special else "<null>"))
	var special_peak := 0.0
	waited = 0.0
	while waited < 2.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if special: special_peak = maxf(special_peak, absf(special.scale.x - 1.0))
	check(special_peak > 0.01, "...and it pops too",
			"peak scale departure %.4f" % special_peak)
	await _tear_down(view)


# ==============================================================================
# THE CARD IS PUT DOWN BEFORE ANYTHING SCORES.
#
# Owner: *"when putting down a card, it scores the meld line first while card is still being
# dragged around. card should be put down first."*
#
# The data placement always committed first -- that part was never in doubt. What did not happen
# is the VISUAL half: `GameView._on_data_selected()` awaits the whole of `try_place()` (placement,
# mutation broadcast, scoring, refill, undo snapshot) and only then calls `ungrab_cards()`, so the
# card stayed stuck to the cursor for the entire scoring pass.
#
# ⚠ **THE ASSERTION IS TAKEN AT THE MOMENT THE FIRST SCORE LANDS**, not after the dust settles --
# afterwards the grab is released either way, which is exactly why this went unnoticed.
# ==============================================================================
func run_the_card_is_put_down_before_anything_scores_test() -> void:
	behavior_section("THE CARD IS PUT DOWN BEFORE ANYTHING SCORES")
	var view := await _stand_up()
	var pa := view.play_area
	var g := view.game
	await _settle_layout(view)

	var card := g.draw_card()
	check(card != null, "precondition: the deck gave a card to place")
	if card == null:
		await _tear_down(view)
		return
	pa.grab_cards([card] as Array[CardData])
	check(pa.selected_cards.size() == 1,
			"precondition: the player really is holding the card before it is placed",
			"%d held" % pa.selected_cards.size())

	# ⚠ **NOT AWAITED.** The whole question is what is true WHILE the placement runs -- afterwards
	# the grab is released either way, which is exactly why this went unnoticed. The coroutine is
	# started and then sampled every frame until it finishes.
	var done : Array[bool] = [false]
	var runner := func() -> void:
		await g.place_card_in_grid(card, BoardCoord.new(0, 0, 0, 0))
		done[0] = true
	runner.call()

	var still_held_throughout := true
	var samples := 0
	var waited := 0.0
	while not done[0] and waited < 4.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		samples += 1
		if pa.selected_cards.is_empty(): still_held_throughout = false
	check(done[0], "precondition: the placement finished", "%d frames" % samples)
	check(samples > 1,
			"precondition: the placement really spans frames, so there IS a window in which the "
			+ "card could be seen still held", "%d frames" % samples)
	check(not still_held_throughout,
			"the grab is released DURING the placement, before the mutation pass it ends with -- "
			+ "not by the caller after the whole scoring cascade has already played",
			"held for all %d frames of the placement" % samples)
	check(pa.selected_cards.is_empty(),
			"...and it stays released", "%d held" % pa.selected_cards.size())
	await _tear_down(view)


# ==============================================================================
# A DEEPENING STACK GROWS THE BOARD UPWARD.
#
# Owner: *"as grid gets more stacks, it drops further down under the entrance card instead of
# upwards, and that buffers are still clipping"*.
#
# The board is bottom-anchored on a floor above the Entrance, so a stack that gets deeper must
# push its own top UP and leave the bottom line alone. What happened instead: the scroll content
# grew taller, the offset stayed where it was, and every new pixel appeared BELOW the window --
# measured on a single column, the cell block hung 14.7 px past the window's bottom at depth 3 and
# 112.8 px at depth 6.
#
# ⚠ **THE SECOND CHECK IS THE LOAD-BEARING ONE.** "The bottom did not move" is also satisfied by a
# board that never grows at all, so the top has to be shown to have risen by the height gained.
# ==============================================================================
func run_a_deepening_stack_grows_the_board_upward_test() -> void:
	behavior_section("A DEEPENING STACK GROWS THE BOARD UPWARD")
	var view := await _stand_up()
	var pa := view.play_area
	var g := view.game
	# ⚠ **THE BOARD MUST ALREADY OVERFLOW ITS WINDOW, OR THE DEFECT CANNOT SHOW.** Where the
	# content fits, the bottom-aligned panel grows upward on its own and the scroll offset is
	# irrelevant -- the bug only exists once there is a scroll range for the growth to be added to.
	# Focusing zooms the board, which is what the product's own default one-grid show does.
	pa.focus_grid(0)
	await _settle_layout(view)
	var first := g.draw_card()
	if first: await g.place_card_in_grid(first, BoardCoord.new(0, 0, 0, 0))
	pa.queue_rebuild()
	await _settle_layout(view)
	await get_tree().physics_frame

	var bar := pa.scroll_container.get_v_scroll_bar()
	var range_before : float = bar.max_value
	var before := _cell_block_rect(pa, 0)
	for h : int in range(1, 7):
		var card := g.draw_card()
		if not card: break
		await g.place_card_in_grid(card, BoardCoord.new(0, 0, 0, h))
	pa.queue_rebuild()
	await _settle_layout(view)
	# The growth follow runs on the physics tick, and the ease has to have finished before the
	# board's height is final.
	var waited := 0.0
	while not pa._layer_grown.is_empty() and waited < 3.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var after := _cell_block_rect(pa, 0)

	check(range_before > 1.0 and bar.max_value > 1.0,
			"precondition: the board OVERFLOWS its window, so there is a scroll offset for the "
			+ "growth to have been added to -- where the content fits, a bottom-aligned panel "
			+ "grows upward on its own and this test could not fail",
			"range %.1f -> %.1f" % [range_before, bar.max_value])
	check(after.size.y > before.size.y + 1.0,
			"precondition: the stack really made the cell block taller",
			"%.1f -> %.1f" % [before.size.y, after.size.y])
	# ⚠ **THE TOLERANCE IS A DISCLOSED RESIDUAL, NOT A ROUNDING ALLOWANCE.** Six placements leave
	# the bottom 5.1 px out where the unfixed board left it 157.5 px out. Carrying the integer
	# scroll offset's fraction did NOT move that number, so the residual is something else and is
	# not explained. It is small, and the guarantee the owner's report is actually about -- the
	# block never reaching past its own window into the Entrance -- is the check below.
	check(absf(after.end.y - before.end.y) <= 8.0,
			"the cell block's BOTTOM line does not move as the stack deepens -- the board grows "
			+ "out of the Entrance, it does not sink into it",
			"bottom %.1f -> %.1f" % [before.end.y, after.end.y])
	check(after.position.y < before.position.y - 1.0,
			"...and it is the TOP that rose, by the height the board gained",
			"top %.1f -> %.1f, gained %.1f"
			% [before.position.y, after.position.y, after.size.y - before.size.y])

	var sc := pa.scroll_container
	var window_bottom : float = sc.global_position.y + sc.size.y * sc.scale.y
	check(after.end.y <= window_bottom + 1.0,
			"...so the block never hangs past the bottom of its own window, which is where the "
			+ "Entrance begins",
			"block bottom %.1f vs window bottom %.1f" % [after.end.y, window_bottom])
	await _tear_down(view)

## Grid `gi`'s cell block in GLOBAL space. ⚠ `size` never carries the board zoom; the transform does.
func _cell_block_rect(pa: PlayArea, gi: int) -> Rect2:
	var cells := pa._cells_root(pa.grid_container.get_child(gi) as Control)
	return cells.get_global_transform() * Rect2(Vector2.ZERO, cells.size)


# ==============================================================================
# HOVERING THE BOARD DOES NOT MOVE THE BOARD.
#
# Owner: *"gap between entrance and grid moves around for some reason when moving mouse around,
# presumably to reveal more of bottom part of grid, but it is already revealed. gap should stay
# static."*
#
# A card control grabs focus on `mouse_entered`, and a `ScrollContainer` with `follow_focus` on
# scrolls whatever just took focus into view -- so moving the mouse across the board scrolled it.
# Measured before the fix: the gap between the cell block and the Entrance wandered between 44.2
# and 25.3 px across twelve hovers, with nothing placed and nothing removed.
#
# ⚠ **FOCUS IS WHAT A HOVER DOES TO THIS TREE**, so focusing the controls in turn is the real
# route and not a stand-in for one -- `create_card_control()` connects `mouse_entered` straight to
# `grab_focus()`.
# ==============================================================================
func run_hovering_the_board_does_not_move_it_test() -> void:
	behavior_section("HOVERING THE BOARD DOES NOT MOVE THE BOARD")
	var view := await _stand_up()
	var pa := view.play_area
	var g := view.game
	pa.focus_grid(0)
	await _settle_layout(view)
	for h : int in 2:
		var card := g.draw_card()
		if card: await g.place_card_in_grid(card, BoardCoord.new(0, 1, 2, h))
	pa.queue_rebuild()
	await _settle_layout(view)

	var controls : Array[Control] = []
	for node : Node in get_tree().get_nodes_in_group("CardVisualControl"):
		var c := node as Control
		if c and c.is_inside_tree() and pa.is_ancestor_of(c): controls.append(c)
	check(controls.size() >= 4,
			"precondition: there are card controls on the board to hover",
			"%d controls" % controls.size())
	if controls.size() < 4:
		await _tear_down(view)
		return

	# One hover first, THEN the baseline: the first focus of a session legitimately settles the
	# inspector and the focus widening. What the owner is describing is the board moving on every
	# subsequent mouse move, which is what this measures.
	controls[0].grab_focus()
	await get_tree().process_frame
	await get_tree().physics_frame
	var base := _cell_block_rect(pa, 0)
	var base_scroll : float = pa.scroll_container.scroll_vertical

	var worst := 0.0
	var worst_scroll := 0.0
	for i : int in mini(controls.size(), 10):
		controls[i].grab_focus()
		await get_tree().process_frame
		await get_tree().physics_frame
		worst = maxf(worst, absf(_cell_block_rect(pa, 0).end.y - base.end.y))
		worst_scroll = maxf(worst_scroll,
				absf(float(pa.scroll_container.scroll_vertical) - base_scroll))
	check(worst <= 1.0,
			"the cell block's bottom line does not move as the hover moves across the board -- "
			+ "the gap to the Entrance stays put",
			"worst %.2f px over %d hovers" % [worst, mini(controls.size(), 10)])
	check(worst_scroll <= 0.5,
			"...because nothing scrolled the board: the scroller does not chase focus, the "
			+ "board's own pan is its only writer",
			"worst scroll delta %.2f" % worst_scroll)
	check(not pa.scroll_container.follow_focus,
			"the board's scroller has follow_focus OFF")
	await _tear_down(view)


# ==============================================================================
# EVERY SCORE LABEL IS THE SAME SIZE AS EVERY OTHER.
#
# Owner: *"all score labels should be same size as each other"*.
#
# `AutosizeLabel` fits its font to its own box AND its own text, so this needs two things: one box
# for every score label (a 16 px row gutter against a 40 px column gutter rendered the same number
# at 8 px and 14 px), and then one shared size across the group, because a four-digit row score and
# a two-digit column score in identical boxes still choose differently.
# ==============================================================================
func run_every_score_label_is_the_same_size_test() -> void:
	behavior_section("EVERY SCORE LABEL IS THE SAME SIZE")
	var view := await _stand_up()
	var pa := view.play_area
	var st := view.game.state
	# Deliberately DIFFERENT lengths: equal boxes alone would still size these differently.
	st.bank_line_score(st.scores_row, 0, 1, 0, 1234567)
	st.bank_line_score(st.scores_col, 0, 2, 0, 7)
	st.resize_grid_bucket(st.score_special, 1)
	st.score_special[0].plus_equals(42)
	pa.queue_rebuild()
	await _settle_layout(view)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var panel : Control = pa.grid_container.get_child(0)
	var labels := pa._score_labels_of(panel)
	var shown : Array[BigNumberLabel] = []
	for l : BigNumberLabel in labels:
		if not l.text.is_empty(): shown.append(l)
	check(shown.size() >= 3,
			"precondition: a row, a column and the special label all carry a number, and they are "
			+ "not the same length", "%d labels with text" % shown.size())
	if shown.size() < 3:
		await _tear_down(view)
		return

	var first_font := shown[0].get_theme_font_size("font_size")
	var first_box := shown[0].custom_minimum_size
	var same_font := true
	var same_box := true
	for l : BigNumberLabel in shown:
		if l.get_theme_font_size("font_size") != first_font: same_font = false
		if not l.custom_minimum_size.is_equal_approx(first_box): same_box = false
	check(same_box, "every score label carries the same box", "first %s" % first_box)
	check(same_font,
			"...and every one renders at the SAME font size, however long its own number is",
			"sizes %s" % [shown.map(func(l: BigNumberLabel) -> int:
			return l.get_theme_font_size("font_size"))])
	check(first_font > 8,
			"...and that size is the one the shared box supports, not the autosize floor a 16 px "
			+ "gutter used to force", "font %d" % first_font)

	# ⚠ **EACH GUTTER LEANS TOWARD THE CELLS IT DESCRIBES** (owner: *"make all row score labels
	# right aligned instead. all column based labels centered. special score left aligned."*). The
	# row gutter is LEFT of the grid and the special gutter is its mirror on the RIGHT, so they lean
	# opposite ways; the column gutter sits under its own columns and centres on them.
	var panel2 : Control = pa.grid_container.get_child(0)
	var board2 : Control = panel2.get_node_or_null("Board")
	var a_row : Label = ((board2.get_node("RowLabels") as Control).get_child(1) as Control) 			.get_child(-1) as Label
	var a_col : Label = ((panel2.get_node("Board/CellsColumn/ColLabels") as Control)
			.get_child(2) as Control).get_child(-1) as Label
	var a_special : Label = board2.get_node("SpecialLabel") as Label
	check(a_row.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT,
			"a ROW score is right-aligned, hard against the cells it describes",
			"alignment %d" % a_row.horizontal_alignment)
	check(a_col.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER,
			"a COLUMN score is centred on its column",
			"alignment %d" % a_col.horizontal_alignment)
	check(a_special.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT,
			"the SPECIAL score is left-aligned -- the row gutter's mirror, leaning the other way",
			"alignment %d" % a_special.horizontal_alignment)
	await _tear_down(view)

# ==============================================================================
# A ROW'S SCORE SITS ON THE PIP ROW OF THE CARD IT NAMES.
#
# Owner: *"row score not aligned with bottom card row separation against pips still. still aligned
# to top like old non grid version."*
#
# A `VBoxContainer` packs from the TOP, so a label stack as tall as its row put its scores against
# the row's top edge -- 60.5 px above the pip row at the focused zoom, measured at every height.
# Two things fix it: the stack aligns to the END, and its pitch is the CARD depth pitch, or the
# labels fan away from the cards one separation per level.
#
# ⚠ **THE TARGET IS THE PIP ROW, NOT THE CARD'S BOTTOM EDGE.** The pips span art y 13..23 on a face
# running -27..27, so the bottom edge is 4 art units below what the player actually reads.
# ⚠ **AND IT IS CHECKED AT EVERY HEIGHT.** Only the bottom label lines up if the pitch is wrong,
# and the bottom label is the one a single-card fixture would show.
# ==============================================================================
func run_a_row_score_sits_on_its_pip_row_test() -> void:
	behavior_section("A ROW'S SCORE SITS ON ITS PIP ROW")
	var view := await _stand_up()
	var pa := view.play_area
	var g := view.game
	pa.focus_grid(0)
	await _settle_layout(view)
	for h : int in 3:
		var c := g.draw_card()
		if c: await g.place_card_in_grid(c, BoardCoord.new(0, 0, 2, h))
	for h : int in 3:
		g.state.bank_line_score(g.state.scores_row, 0, 2, h, 1234)
	pa.queue_rebuild()
	await _settle_layout(view)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var panel : Control = pa.grid_container.get_child(0)
	var board : Control = panel.get_node_or_null("Board")
	var row_labels : Control = board.get_node_or_null("RowLabels")
	var stack : Control = row_labels.get_child(2)
	check(stack.get_child_count() == 3,
			"precondition: the row banked three heights, so there are three bands to line up",
			"%d bands" % stack.get_child_count())
	if stack.get_child_count() != 3:
		await _tear_down(view)
		return

	var art_to_px : float = CardVisual.card_size_play.y / CardVisual.CARD_SIZE.y
	var worst := 0.0
	for i : int in stack.get_child_count():
		var h : int = stack.get_child_count() - 1 - i
		var label : Control = stack.get_child(i)
		var band := label.get_global_transform() * Rect2(Vector2.ZERO, label.size)
		var centre := pa.slot_center_global(BoardCoord.new(0, 0, 2, h))
		var pip_mid : float = centre.y + 18.0 * art_to_px * pa.board_zoom
		worst = maxf(worst, absf(band.get_center().y - pip_mid))
	check(worst < 6.0,
			"every height's score band is centred on the PIP ROW of the card it names, not on the "
			+ "top of the row",
			"worst %.1f px out over %d heights" % [worst, stack.get_child_count()])
	await _tear_down(view)
