extends Node2D
# res://Tests/Visual/focused_pose_probe.gd
# ==============================================================================
# THE FOCUSED-POSE INSTRUMENT (not part of the suite). Boots the REAL res://Levels/main.tscn and
# enters a show through `Main.enter_game()` -- the one path the product uses -- so the camera pose,
# the picture rect, the grid count and the board's zoom are all whatever production produces, never
# a hand-assembled approximation.
#
# `wall_game_squash_probe` builds its own wall, its own WallPicture and its own camera pose, and
# forces THREE grids; the product's default deck yields ONE. Same nominal "focused" state, a
# different framing -- which is why a by-eye gate taken through it certified a pose the player
# never sees.
#
# It REPORTS both stacked scales in one coordinate system: `focused_board_zoom()` fits the board's
# content into the play area, then the wall camera fits the PICTURE into the WINDOW, and a zoom
# that fits an 841 px picture still clips once the camera crops it. Every rect below is printed in
# the picture's own DESIGN units so the two layers can be compared without arithmetic.
#
# Run windowed, WITH AN EXTERNAL KILLING TIMEOUT:
#     OUT_PATH=<path> <console exe> --path solatro res://Tests/Visual/focused_pose_probe.tscn
# Knobs, both optional: WINDOW=<w>x<h> (default 1152x648), GRIDS=<n> (default: whatever the deck
# gives, which is the product's own answer).
# ==============================================================================

const MAIN_SCENE := preload("res://Levels/main.tscn")
const FALLBACK_OUT_PATH := "user://focused_pose_probe/focused.png"
const SAVE_TAG := "focused_pose_probe"

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("focused_pose_probe needs a REAL renderer. Re-run WITHOUT --headless.")
		get_tree().quit(1)
		return
	TestSuite.backup_real_save(SAVE_TAG)
	DisplayServer.window_set_size(_window_knob())
	await get_tree().process_frame
	await get_tree().process_frame

	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	run.pending_goal = 1_000_000_000
	run.pending_node_id = 2
	seed(20260903)

	var main : Main = MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	await main.enter_game()
	for _i : int in 8:
		await get_tree().process_frame

	var wp := _game_picture(main)
	var view : GameView = wp.screen_root as GameView
	var pa := view.play_area
	var grids_knob := _grids_knob()
	if grids_knob > 0:
		while view.game.state.grids.size() < grids_knob:
			Board.add_grid(view.game.state, GridData.new())
		while view.game.state.grids.size() > grids_knob:
			Board.remove_grid(view.game.state, view.game.state.grids.size() - 1)
		pa.flush_rebuild()
		for _i : int in 4:
			await get_tree().process_frame

	await _settle(pa)
	_report(main, wp, view, pa, "focused as the product opens it")
	await _shoot("focused")

	pa.open_zoomed_out()
	await _settle(pa)
	_report(main, wp, view, pa, "overview")
	await _shoot("overview")

	pa.focus_grid(pa.resting_grid())
	await _settle(pa)
	_report(main, wp, view, pa, "focused after an explicit focus_grid")
	await _shoot("refocused")

	TestSuite.restore_real_save(SAVE_TAG)
	get_tree().quit()

## The wall's own `game` picture, found by the id the wall packs it under rather than by tree
## position -- `Main` keeps `_pictures` private and this probe must not fork its bookkeeping.
func _game_picture(main: Main) -> WallPicture:
	var wall : Node = main.get_node(^"Wall")
	for child : Node in wall.get_node(^"%Pictures").get_children():
		var wp := child as WallPicture
		if wp and wp.rect and wp.rect.id == Wall.GAME_PICTURE_ID: return wp
	return null

## Waits until the board's scale and the resting grid's cell block both stop moving, the
## `_settle_layout` pattern -- never a frame count, which certifies a mid-move pose.
func _settle(pa: PlayArea) -> void:
	var last := Vector2.INF
	var waited := 0.0
	while waited < 3.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		var cells := _cells_of(pa, pa.resting_grid())
		var now := (cells.global_position if cells else Vector2.ZERO) + Vector2(pa.board_zoom, 0.0)
		if now.is_equal_approx(last): return
		last = now

func _cells_of(pa: PlayArea, gi: int) -> Control:
	if gi < 0 or gi >= pa.grid_container.get_child_count(): return null
	return pa._cells_root(pa.grid_container.get_child(gi) as Control)

## The inverse of the screen mapping, for the camera's visible rect: a world point back into the
## screen's own layout units.
##
## ⚠ **THE ONE PIECE OF ARITHMETIC THIS PROBE OWNS, AND IT IS EXACT.** `%Screen` is a centred
## sprite of the SubViewport's texture scaled by `rect.size / viewport.size`, and the viewport's
## CANVAS is `design_size` whether or not the render clamp bit. Composing those two collapses the
## render target out entirely: a point `p` in the screen's own layout units draws at
## `rect.centre + (p / design - 0.5) * rect.size`. So the render clamp cannot move a rect this
## probe reports, and the report stays comparable across clamped and unclamped runs.
## A control's rect AS DRAWN, in the screen's layout units.
##
## ⚠ **`size` IS NOT THE RENDERED SIZE HERE.** The focused zoom is a scale on the SCROLL
## CONTAINER, so a cell block inside it keeps its authored 216x286 while drawing 2.29x that.
## `global_position` already carries the scale, so a rect built from position and size is right
## in one corner and wrong in the other -- which reads as a block that fits when it does not.
func _rendered_rect(c: Control) -> Rect2:
	return c.get_global_transform() * Rect2(Vector2.ZERO, c.size)

func _world_to_design(p: Vector2, rect: PictureRect, design: Vector2) -> Vector2:
	return ((p - rect.centre) / rect.size + Vector2(0.5, 0.5)) * design

func _report(main: Main, wp: WallPicture, view: GameView, pa: PlayArea, tag: String) -> void:
	var camera : Camera2D = main.get_node(^"Wall").get_node(^"%Camera2D") as Camera2D
	var window := Vector2(get_viewport().get_visible_rect().size)
	var design := Vector2(PlayArea.game_picture_design_size(SettingsManager.settings))
	var rect := wp.rect
	var visible_world := Rect2(camera.position - window * 0.5 / camera.zoom, window / camera.zoom)
	var top_left := _world_to_design(visible_world.position, rect, design)
	var visible_design := Rect2(top_left, _world_to_design(visible_world.end, rect, design) - top_left)
	print("[POSE][%s] window=%s design_size=%s rect.size=%s rect.centre=%s"
			% [tag, window, design, rect.size, rect.centre])
	print("[POSE][%s] camera.position=%s camera.zoom=%s overfill_margin=%.4f"
			% [tag, camera.position, camera.zoom, SettingsManager.settings.wall_overfill_margin])
	print("[POSE][%s] viewport.size=%s size_2d_override=%s"
			% [tag, wp.viewport.size, wp.viewport.size_2d_override])
	print("[POSE][%s] CAMERA SHOWS, in design units: %s" % [tag, visible_design])
	print("[POSE][%s] play_container=%s play_area.pos=%s play_area.size=%s"
			% [tag, view.play_container.size, pa.global_position, pa.size])
	print("[POSE][%s] view_mode=%d focused_grid=%d pan_grid=%d board_zoom=%.6f grids=%d"
			% [tag, pa.view_mode, pa.focused_grid, pa.pan_grid, pa.board_zoom,
			pa.grid_container.get_child_count()])
	var gi := pa.resting_grid()
	var cells := _cells_of(pa, gi)
	if cells:
		var block := _rendered_rect(cells)
		print("[POSE][%s] grid %d CELL BLOCK, design units: %s" % [tag, gi, block])
		_verdict(tag, "the 5x5 cell block", block, visible_design)
	var strip := _rendered_rect(pa.entrance_strip)
	print("[POSE][%s] ENTRANCE STRIP, design units: %s" % [tag, strip])
	_verdict(tag, "the Entrance strip", strip, visible_design)
	for control : Control in view._furniture:
		if is_instance_valid(control):
			print("[POSE][%s] HUD %s design units: %s" % [tag, control.name, _rendered_rect(control)])

## Names the clipped EDGE and by how much, never a bare in/out -- "the top row is cut" and "the
## Entrance is barely in frame" are different defects and a boolean cannot tell them apart.
func _verdict(tag: String, what: String, r: Rect2, visible: Rect2) -> void:
	var cut_left := visible.position.x - r.position.x
	var cut_top := visible.position.y - r.position.y
	var cut_right := r.end.x - visible.end.x
	var cut_bottom := r.end.y - visible.end.y
	var worst := maxf(maxf(cut_left, cut_top), maxf(cut_right, cut_bottom))
	print("[VERDICT][%s] %s: %s -- cut left=%.2f top=%.2f right=%.2f bottom=%.2f (positive == outside the camera)"
			% [tag, what, "CLIPPED" if worst > 0.01 else "fully framed",
			cut_left, cut_top, cut_right, cut_bottom])

func _shoot(suffix: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var base := _resolve_out_path()
	var dir := base.get_base_dir()
	if dir.begins_with("user://"): DirAccess.make_dir_recursive_absolute(dir)
	var path := "%s_%s.%s" % [base.get_basename(), suffix, base.get_extension()]
	get_viewport().get_texture().get_image().save_png(path)
	print("[focused_pose_probe] wrote=%s" % ProjectSettings.globalize_path(path))

func _window_knob() -> Vector2i:
	var parts := OS.get_environment("WINDOW").split("x")
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		return Vector2i(int(parts[0]), int(parts[1]))
	return Vector2i(1152, 648)

func _grids_knob() -> int:
	var env := OS.get_environment("GRIDS")
	return int(env) if env.is_valid_int() else 0

func _resolve_out_path() -> String:
	var env := OS.get_environment("OUT_PATH")
	if not env.is_empty(): return env
	return FALLBACK_OUT_PATH
