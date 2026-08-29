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

## One frame, and how long it took — for settling loops that must not spin forever.
func _tick() -> float:
	await get_tree().process_frame
	return get_process_delta_time()

## The cell grid inside grid `gi`'s panel.
## Grid `gi`'s row `ry` — one HBox of cells. Rows are their own containers so a deep stack in
## one cell cannot bleed into the row above, and every cell in a row bottom-aligns inside it.
func _cell_row(pa: PlayArea, gi: int, ry: int) -> HBoxContainer:
	var panel : Control = pa.grid_container.get_child(gi)
	return panel.get_child(ry) as HBoxContainer

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
	check(panel.get_child_count() == grid.grid_height,
			"the panel has one ROW CONTAINER per grid row, from the DATA",
			"%d rows vs grid_height %d" % [panel.get_child_count(), grid.grid_height])
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
	for ry : int in panel.get_child_count():
		slots += panel.get_child(ry).get_child_count()
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
	# card on its cell. A CardVisual EASES to that point, so measuring the visual measures the
	# flight: it read 116 px out while every settled card was exactly 0.0 out, and no settle loop
	# makes that anything but flaky. The visual's own target is `get_card_control_center`.
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
