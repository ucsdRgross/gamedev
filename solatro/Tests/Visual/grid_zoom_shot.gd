extends Control

#Photographs and MEASURES the board inside the REAL game picture, in both view modes. The board
#lives in a SubViewport sized PlayArea.game_picture_design_size and occupies only the PlayContainer
#rect inside it, and every "is the grid cut off" question is about THAT rectangle.

#⚠ grid_layer_shot renders the board straight into a 1152x648 window, so for a multi-grid board its
#framing is a harness artefact. Only this scene puts the real rectangle on screen.

#Run windowed, WITH AN EXTERNAL KILLING TIMEOUT:
#    OUT_DIR=<absolute dir> <console exe> --path solatro res://Tests/Visual/grid_zoom_shot.tscn

#Needs a real renderer and is by-eye material, so it stays out of all_tests.tscn.

const OUT_DIR_FALLBACK := "user://reveal_shots"
const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")
const SAVE_TAG := "grid_zoom_shot"
#How many grids the board is stood up with. GRID_COUNT in the environment overrides it, so the same
#instrument answers the centring rule at one, two and three grids.
const GRID_COUNT_DEFAULT := 3
## How long past the pan clock nothing may move before the board counts as at rest.
const STILL_MARGIN := 0.2
## How long a view is given to come to rest before the run is called a failure.
const SETTLE_TIMEOUT := 20.0

var _out_dir : String
var _grid_count := GRID_COUNT_DEFAULT

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("grid_zoom_shot needs a REAL renderer: --headless never fires frame_post_draw.")
		get_tree().quit(1)
		return
	_out_dir = OS.get_environment("OUT_DIR")
	if _out_dir.is_empty(): _out_dir = OUT_DIR_FALLBACK
	if _out_dir.begins_with("user://"): DirAccess.make_dir_recursive_absolute(_out_dir)
	TestSuite.backup_real_save(SAVE_TAG)

	var env_count := OS.get_environment("GRID_COUNT")
	if env_count.is_valid_int(): _grid_count = maxi(env_count.to_int(), 1)
	var design := PlayArea.game_picture_design_size(SettingsManager.settings)
	print("[grid_zoom_shot] picture design_size %d x %d" % [design.x, design.y])
	DisplayServer.window_set_size(design)
	await get_tree().process_frame

#The picture IS a SubViewport at the design size; the wall camera only displays it. Standing the
#real GameView up in one of exactly that size reproduces the product's board geometry without the
#wall's own transform in the way.
	var holder := SubViewportContainer.new()
	holder.stretch = false
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(holder)
	var vp := SubViewport.new()
	vp.size = design
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	holder.add_child(vp)

	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	run.pending_goal = 1_000_000_000
	run.pending_node_id = 2
	seed(20260830)
	var view : GameView = GAME_VIEW_SCENE.instantiate()
	vp.add_child(view)
	await get_tree().process_frame
	await get_tree().process_frame
	CardEnvironment.CURRENT = view.game
	var g := view.game
	var pa := view.play_area
	while g.state.grids.size() < _grid_count:
		Board.add_grid(g.state, GridData.new())
	while g.state.grids.size() > _grid_count:
		Board.remove_grid(g.state, g.state.grids.size() - 1)
#⚠ THE ONE-GRID DEAL ALREADY COMMITTED ITS GRID; a dealt board of two or more commits nothing
#until a placement, which is the board these shots are about.
	if _grid_count > 1: g.state.committed_grid = -1
	pa.flush_rebuild()
#THE BOARD GREW AFTER THE SHOW OPENED, which the one-deal product never does, so the opening view
#is re-run by its own entry point for the count the shots are about.
	pa.open_show_view()
	await get_tree().process_frame

#THE UNCOMMITTED ENTRANCE, BEFORE ANY PLACEMENT COMMITS A GRID: centred in the board's window,
#under no grid, and still there after the view has panned to another grid.
	if not await _await_still(view, "uncommitted"): return
	if not await _shoot(pa, vp, "uncommitted"): return
	pa.pan_by_grids(1)
	if not await _await_still(view, "uncommitted_panned"): return
	if not await _shoot(pa, vp, "uncommitted_panned"): return

#THE PICKUP, through the product's one pickup route. It aims the BOARD and leaves the Entrance
#where it is: the frames are taken over the pan clock, and the printed x must not move across them,
#because a single still cannot tell a row that stayed from a row that had already arrived.
	var lift := _leftmost_entrance_control(pa)
	if lift:
		view._pick_up(pa.ui_data[lift])
		for i : int in 3:
			for _f : int in 5:
				await get_tree().physics_frame
			await RenderingServer.frame_post_draw
			_shoot_frame(pa, vp, "pickup_%d" % i)
	if not await _await_still(view, "pickup"): return
	if not await _shoot(pa, vp, "pickup"): return
	pa.ungrab_cards()

#Cards on the board, so the shot shows what a player sees rather than an empty lattice.
	for gi : int in _grid_count:
		var grid : GridData = g.state.grids[gi]
		for x : int in mini(5, grid.grid_width):
			var card := TestGridFixtures.draw_any(g)
			if not card: break
			await g.place_card_in_grid(card, BoardCoord.new(gi, x, 0, 0))
	pa.flush_rebuild()
	if not await _await_still(view, "deal"): return

	pa.open_zoomed_out()
	if not await _await_still(view, "overview"): return
	if not await _shoot(pa, vp, "overview"): return
	pa.focus_grid(_grid_count / 2)
	if not await _await_still(view, "focused"): return
	if not await _shoot(pa, vp, "focused"): return

#THE COMMITTED ENTRANCE SEEN FROM ANOTHER GRID: it belongs to the grid the first placement
#committed to, so looking elsewhere leaves it off the board's window entirely.
	pa.focus_grid(0 if g.state.committed_grid != 0 else _grid_count - 1)
	if not await _await_still(view, "committed_elsewhere"): return
	if not await _shoot(pa, vp, "committed_elsewhere"): return

#THE ENTRANCE USED UP. Once the hand has nowhere left to go on the committed grid the commitment
#lifts, so the row comes back to the middle of the window and the next hand may choose any grid.
	if _grid_count > 1:
		var home := g.state.committed_grid
		var spent := await _leave_one_entrance_card(g, home)
		if spent:
			var target := await _legal_cell_in_grid(g, spent, home)
			if target.grid != -1:
				await g.place_card_in_grid(spent, target)
				pa.flush_rebuild()
				pa.focus_grid(home)
				if not await _await_still(view, "entrance_freed"): return
				if not await _shoot(pa, vp, "entrance_freed"): return
				var other := 0 if home != 0 else _grid_count - 1
				var next : CardData = null
				for column : ArrayCardData in g.state.upper_zone:
					if column.datas.is_empty(): continue
					next = column.datas.back()
					break
				var cell := await _legal_cell_in_grid(g, next, other) if next else BoardCoord.new(-1, 0, 0, 0)
				if next and cell.grid != -1:
					await g.place_card_in_grid(next, cell)
					pa.flush_rebuild()
					pa.focus_grid(other)
					if not await _await_still(view, "committed_other"): return
					if not await _shoot(pa, vp, "committed_other"): return

#THE FIRST GRID, the end of the board the shots above never reach: the scroller clamps at both
#ends, so an edge grid's framing has to be seen from either side before it is believed.
	pa.focus_grid(0)
	if not await _await_still(view, "focused_first"): return
	if not await _shoot(pa, vp, "focused_first"): return

#A DRAG PAN LET GO PART OF THE WAY ACROSS. The board must not stop where the pointer left it: the
#release lands the grid nearest the middle of the window, as Left and Right do.
	if _grid_count > 1:
		var from := _bare_board_point(pa)
		assert(from != Vector2.INF, "the board window has a pixel on no card to press")
		var travel := -pa.grid_pitch_px() * 0.75 * pa.drawn_zoom
		await _drag_the_board(vp, from, travel)
		await RenderingServer.frame_post_draw
		_shoot_frame(pa, vp, "drag_midway")
		vp.push_input(_button_event(from + Vector2(travel, 0.0), false))
		if not await _await_still(view, "drag_landed"): return
		if not await _shoot(pa, vp, "drag_landed"): return

#A CANCEL WITH NOTHING HELD AND NOTHING STUCK steps out of the focused grid to the every-grid view,
#which is where another grid can be chosen (owner ruling). One press, and the board is looked at
#whole again.
		pa.focus_grid(_grid_count / 2)
		if not await _await_still(view, "before_cancel"): return
		var cancel := InputEventMouseButton.new()
		cancel.button_index = MOUSE_BUTTON_RIGHT
		cancel.pressed = true
		cancel.position = from
		cancel.global_position = from
		vp.push_input(cancel)
		if not await _await_still(view, "cancel_overview"): return
		if not await _shoot(pa, vp, "cancel_overview"): return

#THREE FRAMES OF THE EASE. ⚠ A STILL CANNOT TELL AN EASE FROM A SNAP, so the frames are taken
#across the pan clock with the drawn scale printed beside each: the board must be at a scale
#BETWEEN the two modes in the middle ones, and exactly on the focused one when it lands.
		pa.open_zoomed_out()
		if not await _await_still(view, "before_ease"): return
		if not await _shoot(pa, vp, "before_ease"): return
		pa.focus_grid(_grid_count - 1)
		for i : int in 3:
			for _f : int in 4:
				await get_tree().physics_frame
			await RenderingServer.frame_post_draw
			_shoot_frame(pa, vp, "ease_%d" % i)
		if not await _await_still(view, "ease_landed"): return
		if not await _shoot(pa, vp, "ease_landed"): return

	view.queue_free()
	await get_tree().process_frame
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	TestSuite.restore_real_save(SAVE_TAG)
	get_tree().quit()

#⚠ THE SHOT IS THE PICTURE'S OWN VIEWPORT, NOT THE WINDOW. The window hosts the picture through a
#Control the root viewport scales, so a picture wider than the project's authored window is CROPPED
#there -- 1152 of 1576 design px, and the grid at the right-hand end never appeared.

#One shot plus the numbers behind it: the board window inside the picture, and every grid's CELL
#BLOCK against it. Off-screen is reported per grid because the "no cut-off" rule speaks only about
#the focused one.
func _shoot(pa: PlayArea, picture: SubViewport, tag: String) -> bool:
	await RenderingServer.frame_post_draw
	var drawn := _probe(pa)
	var sc := pa.scroll_container
	var z := sc.scale.x
	var left := sc.global_position.x
	var right := left + sc.size.x * z
	var top := sc.global_position.y
	var bottom := top + sc.size.y * z
	print("[grid_zoom_shot] %s board window x [%.1f .. %.1f] w %.1f, y [%.1f .. %.1f] h %.1f"
			% [tag, left, right, right - left, top, bottom, bottom - top])
	var block := PlayArea.grid_block_size_px(SettingsManager.settings, GridData.new())
	print("[grid_zoom_shot] %s unscaled grid block %.1f x %.1f, board_zoom %.4f, live scale %.4f"
			% [tag, block.x, block.y, pa.board_zoom, pa.scroll_container.scale.x])
	var row := pa.upper_zone_right.get_global_transform()
	print("[grid_zoom_shot] %s entrance x %.1f, travelled %.3f, home grid %d, pan_grid %d, "
			% [tag, pa.entrance_h_track.position.x, pa._entrance_slide, pa.entrance_home_grid(),
			pa.pan_grid] + "row x [%.1f .. %.1f]"
			% [row.origin.x, row.origin.x + row.get_scale().x * pa.upper_zone_right.size.x])
	var gutters := pa._grid_gutters()
	print("[grid_zoom_shot] %s drawn gap: separation %d + gutters %.1f/%.1f, pitch %.1f"
			% [tag, pa.grid_container.get_theme_constant(&"separation"), gutters.x, gutters.y,
			pa.grid_pitch_px()])
	for gi : int in pa.grid_container.get_child_count():
		var panel := pa.grid_container.get_child(gi) as Control
		var cells := pa._cells_root(panel)
		var r := Rect2(cells.global_position, cells.size * z)
		var off := maxf(maxf(left - r.position.x, 0.0), maxf(r.end.x - right, 0.0))
		print("[grid_zoom_shot] %s grid %d cells x [%.1f .. %.1f] w %.1f, y [%.1f .. %.1f] h %.1f, off-screen %.1f%s"
				% [tag, gi, r.position.x, r.end.x, r.size.x, r.position.y, r.end.y, r.size.y, off,
				"" if off <= 0.5 else "   <-- CUT OFF"])
	var img := picture.get_texture().get_image()
	img.save_png("%s/grid_zoom_%d_%s.png" % [_out_dir, _grid_count, tag])
	print("[grid_zoom_shot] wrote grid_zoom_%d_%s.png" % [_grid_count, tag])
	await RenderingServer.frame_post_draw
	var after := _probe(pa)
	if _probe_same(drawn, after): return true
	push_error("[grid_zoom_shot] %s MOVED ACROSS THE GRAB (%s): the numbers printed above are not "
			% [tag, _what_moved(pa, drawn, after)] + "the frame that was saved.")
	get_tree().quit(1)
	return false

#A FRAME TAKEN WHILE THE BOARD IS STILL MOVING, so it carries no stillness guard: what the
#Entrance is doing while the view travels is the thing being photographed, and one still cannot
#tell a row that stayed put from a row that had already finished moving.
func _shoot_frame(pa: PlayArea, picture: SubViewport, tag: String) -> void:
	print("[grid_zoom_shot] %s drawn zoom %.4f of %.4f, gap %.1f, ease %.3f, entrance x %.1f, travelled %.3f, row centre %.1f"
			% [tag, pa.drawn_zoom, pa.board_zoom, pa._drawn_grid_gap, pa._view_ease,
			pa.entrance_h_track.position.x, pa._entrance_slide,
			pa.upper_zone_right.get_global_transform().origin.x
			+ pa.upper_zone_right.get_global_transform().get_scale().x
			* pa.upper_zone_right.size.x * 0.5])
	picture.get_texture().get_image().save_png("%s/grid_zoom_%d_%s.png"
			% [_out_dir, _grid_count, tag])

#Empties every Entrance slot but the one whose top card grid `home` still accepts, and hands that
#card back: a show that runs its own Entrance dry takes the whole deck to reach.
func _leave_one_entrance_card(g: Game, home: int) -> CardData:
	assert(home >= 0 and home < g.state.grids.size(), "the deal's first placement committed a grid")
	var keep : CardData = null
	var keep_column : ArrayCardData = null
	for column : ArrayCardData in g.state.upper_zone:
		if column.datas.is_empty(): continue
		var top : CardData = column.datas.back()
		if (await g.legal_cells_for([top] as Array[CardData], [g.state.grids[home]])).is_empty():
			continue
		keep = top
		keep_column = column
		break
	if not keep: return null
	for column : ArrayCardData in g.state.upper_zone:
		if column != keep_column: column.datas.clear()
	keep_column.datas.assign([keep] as Array[CardData])
	return keep

## A coordinate in grid `gi` that accepts `held`, or a coord whose grid is -1 when none does.
func _legal_cell_in_grid(g: Game, held: CardData, gi: int) -> BoardCoord:
	var grid : GridData = g.state.grids[gi]
	var legal := await g.legal_cells_for([held] as Array[CardData], [grid])
	for i : int in grid.cells.size():
		if grid.cell_types[i] in legal:
			return BoardCoord.new(gi, i % grid.grid_width, i / grid.grid_width, 0)
	return BoardCoord.new(-1, 0, 0, 0)

## A point inside the board's window that no card control answers to: a press there is a PAN.
func _bare_board_point(pa: PlayArea) -> Vector2:
	var window := pa.scroll_container.get_global_rect()
	for step : int in 12:
		var at := Vector2(window.position.x + 4.0 + step * 6.0, window.get_center().y)
		if pa._card_control_at(at) == null: return at
	return Vector2.INF

func _button_event(at: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.global_position = at
	return event

#Press and carry the pointer `travel` px, leaving the button DOWN. ⚠ The motions CARRY THEIR TRAVEL:
#the scroll container pans by `relative` alone and ignores where the pointer actually is.
func _drag_the_board(vp: SubViewport, from: Vector2, travel: float) -> void:
	vp.push_input(_button_event(from, true))
	await get_tree().process_frame
	for step : int in 4:
		var motion := InputEventMouseMotion.new()
		motion.position = from + Vector2(travel * (step + 1) / 4.0, 0.0)
		motion.global_position = motion.position
		motion.relative = Vector2(travel / 4.0, 0.0)
		vp.push_input(motion)
		await get_tree().process_frame

## The Entrance's leftmost card control: what a click has to land on to lift a card.
func _leftmost_entrance_control(pa: PlayArea) -> Control:
	var found : Control = null
	for control : Control in pa.ui_data:
		if control.focus_mode == Control.FOCUS_NONE: continue
		if pa.is_stock_control(control): continue
		if not pa.upper_zone_right.is_ancestor_of(control): continue
		if not found or control.get_global_rect().position.x < found.get_global_rect().position.x:
			found = control
	return found

#Float-tolerant, because the question is whether the BOARD moved, not whether a transform's last
#bit did. One comparison for both the settle and the grab guard, so they cannot disagree.
func _probe_same(a: PackedFloat32Array, b: PackedFloat32Array) -> bool:
	if a.size() != b.size(): return false
	for i : int in a.size():
		if not is_equal_approx(a[i], b[i]): return false
	return true

## Which quantity of the probe moved, and by how much -- a bare "it moved" cannot be acted on.
func _what_moved(pa: PlayArea, before: PackedFloat32Array, after: PackedFloat32Array) -> String:
	var grids := pa.grid_container.get_child_count()
	for i : int in mini(before.size(), after.size()):
		if is_equal_approx(before[i], after[i]): continue
		var what := "separation" if i == 0 else ("board scale" if i == 1 else \
				("grid %d rect" % ((i - 2) / 4) if i < 2 + grids * 4 \
				else "card %d pose" % ((i - 2 - grids * 4) / 3)))
		return "%s: %.4f -> %.4f" % [what, before[i], after[i]]
	return "the probe changed length: %d -> %d" % [before.size(), after.size()]

#Everything the shot REPORTS, plus everything that would betray a frame taken mid-deal: the applied
#separation, each grid's cell rect, and every card's pose. A still that disagrees with its own
#printed numbers is this instrument's characteristic failure, so it watches both.
func _probe(pa: PlayArea) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.append(float(pa.grid_container.get_theme_constant(&"separation")))
	out.append(pa.scroll_container.scale.x)
	for gi : int in pa.grid_container.get_child_count():
		var cells := pa._cells_root(pa.grid_container.get_child(gi) as Control)
		out.append(cells.global_position.x)
		out.append(cells.global_position.y)
		out.append(cells.size.x)
		out.append(cells.size.y)
	for card : CardVisual in _cards_under(pa):
		out.append(card.global_position.x)
		out.append(card.global_position.y)
		out.append(card.rotation)
	return out

## Every card visual on the board, so a card still in flight counts as the board still moving.
func _cards_under(root: Node) -> Array[CardVisual]:
	var found : Array[CardVisual] = []
	var card := root as CardVisual
	if card: found.append(card)
	for child : Node in root.get_children():
		found.append_array(_cards_under(child))
	return found

#The gap the shot is ABOUT, straight off the first two cell blocks, so "what moved while we waited"
#is reported in the quantity the picture is read for.
func _gap_now(pa: PlayArea) -> float:
	if pa.grid_container.get_child_count() < 2: return 0.0
	var z := maxf(pa.scroll_container.scale.x, 0.0001)
	var a := pa._cells_root(pa.grid_container.get_child(0) as Control)
	var b := pa._cells_root(pa.grid_container.get_child(1) as Control)
	return (b.global_position.x - (a.global_position.x + a.size.x * z)) / z

#⚠ STILLNESS IS MEASURED IN TIME, NEVER IN FRAMES: these boxes differ by an order of magnitude in
#frame rate. It must also outlast the pan clock, because a re-centre WAITS that long for the panels
#to stop before it aims -- a board sitting still inside its own settle is not a board at rest.
func _await_still(view: GameView, tag: String) -> bool:
	var pa := view.play_area
	var needed : float = PlayArea.settings().grid_pan_duration + STILL_MARGIN
	var entry_gap := _gap_now(pa)
	var gap := entry_gap
	var gap_moved := 0.0
	var last := _probe(pa)
	var still := 0.0
	var waited := 0.0
	while waited < SETTLE_TIMEOUT:
		await get_tree().process_frame
		CardEnvironment.CURRENT = view.game
		var dt := get_process_delta_time()
		waited += dt
		var seen := _gap_now(pa)
		if not is_equal_approx(seen, gap):
			gap = seen
			gap_moved = waited
		var now := _probe(pa)
		if not _probe_same(now, last):
			last = now
			still = 0.0
			continue
		still += dt
		if still < needed or view.game.processing: continue
		print("[grid_zoom_shot] %s came to rest %.2f s in; gap %.1f -> %.1f, last moved %.2f s in"
				% [tag, waited - still, entry_gap, gap, gap_moved])
		return true
	push_error("[grid_zoom_shot] %s NEVER CAME TO REST in %.0f s -- the still could not match its "
			% [tag, SETTLE_TIMEOUT] + "own numbers.")
	get_tree().quit(1)
	return false
