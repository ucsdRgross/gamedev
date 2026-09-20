extends Control

## Photographs and MEASURES the board inside the REAL game picture, in both view modes.
##
## ⚠ **THE INSTRUMENT `grid_layer_shot` IS NOT.** That one renders the board straight into a
## 1152x648 window, so for a multi-grid board its framing is a harness artefact: the real board
## lives in a SubViewport sized `PlayArea.game_picture_design_size` and occupies only the
## `PlayContainer` rect inside it. Every "is the grid cut off" question is about THAT rectangle,
## and only this scene puts it on screen.
##
## Run windowed, WITH AN EXTERNAL KILLING TIMEOUT:
##     OUT_DIR=<absolute dir> <console exe> --path solatro res://Tests/Visual/grid_zoom_shot.tscn
##
## Deliberately NOT in all_tests.tscn: needs a real renderer and is by-eye material.

const OUT_DIR_FALLBACK := "user://reveal_shots"
const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")
const SAVE_TAG := "grid_zoom_shot"
## How many grids the board is stood up with. `GRID_COUNT` in the environment overrides it, so the
## same instrument answers the centring rule at one, two and three grids.
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

	# The picture IS a SubViewport at the design size; the wall camera only displays it. Standing
	# the real GameView up in one of exactly that size reproduces the product's board geometry
	# without the wall's own transform in the way.
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
	pa.flush_rebuild()
	await get_tree().process_frame

	# Cards on the board, so the shot shows what a player sees rather than an empty lattice.
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

## One shot plus the numbers behind it: the board window inside the picture, and every grid's
## CELL BLOCK against it. Off-screen is reported per grid because the "no cut-off" rule speaks
## only about the focused one.
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
