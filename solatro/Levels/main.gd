class_name Main
extends Node

## Scene orchestrator: Menu -> Map -> Game and back, now the PICTURE WALL (PLAN.md Phase 7,
## S30/S31). Owns the pre-instantiated menu/map scenes, exposes the current run as the static
## save_info alias (kept for the many existing Main.save_info call sites; it always mirrors
## RunManager.run), and owns the ONE real `Wall` the whole app now lives inside.
##
## M1-M4/B7/K6/Q211=a (S30) + L1-L11/Q186=d (S31), all landing here: cold launch focuses
## start_menu directly (no wall-view flash); choosing a save reveals wall view (M2/M3, using the
## ORDINARY transition clock -- the distinct longer/slower reveal is GAP-014, still unbuilt, see
## ASSUMPTIONS.md); entering map/deck/game is focusing that picture via a real WallTransition;
## leaving mid-act calls unfocus() and FREEZES the show instead of freeing it (L4 -- S31's own
## soak already proved the mechanism, this makes it live); wall state never survives a quit (K6)
## because nothing here persists `_focus_stack` or `_current_focus` anywhere.

const MENU = preload("res://Levels/menu.tscn")
const MAP = preload("res://Levels/map.tscn")
const GAME_VIEW = preload("res://Levels/game_view.tscn")
const WALL_SCENE = preload("res://UI/Wall/wall.tscn")
const WALL_PICTURE_SCENE = preload("res://UI/Wall/wall_picture.tscn")

var menu_scene : Menu = MENU.instantiate()
var map_scene : Map = MAP.instantiate()
## Alias of RunManager.run (never null so call sites skip guards; empty between runs).
static var save_info : RunState = RunState.new()

var wall : Wall = null
var _pictures : Dictionary[StringName, WallPicture] = {}
var _rects : Dictionary[StringName, PictureRect] = {}
var _focus_stack : FocusStack = null
## `&""` while in wall view; otherwise the id of whichever picture is currently focused. Tracked
## here (not read back off `wall`) because `Main` is the one that knows what "focused" means for
## each id (a live GameView vs. a persistent menu/map screen).
var _current_focus : StringName = &""
var _window_size : Vector2

func _ready() -> void:
	map_scene.enter_game.connect(enter_game)
	menu_scene.new_run_requested.connect(_on_new_run)
	menu_scene.continue_requested.connect(_on_continue)

	wall = WALL_SCENE.instantiate()
	add_child(wall)
	_window_size = get_viewport().get_visible_rect().size
	_build_pictures()

	var overlay : WallOverlay = wall.get_node(^"%Overlay")
	overlay.back_pressed.connect(_on_back_pressed)
	overlay.forward_pressed.connect(_on_forward_pressed)
	overlay.wall_pressed.connect(_on_wall_pressed)
	wall.wall_view_entered.connect(_on_wall_view_entered)
	wall.picture_enter_requested.connect(_on_picture_enter_requested)

	# K6/M1: a FRESH stack every launch, pre-visited with start_menu -- never read back from any
	# save file (Wall.cold_launch_focus_stack()'s own doc comment).
	_focus_stack = Wall.cold_launch_focus_stack()
	# M1: "the camera starts already zoomed into the start-menu picture" -- no wall-view flash, no
	# transition, straight to focused.
	var start_wp : WallPicture = _pictures[&"start_menu"]
	var start_rect : PictureRect = _rects[&"start_menu"]
	var camera : Camera2D = wall.get_node(^"%Camera2D")
	start_wp.focus()
	camera.position = start_rect.centre
	camera.zoom = Vector2.ONE * WallPicture.focused_scale(start_rect.size, _window_size,
			SettingsManager.settings.wall_overfill_margin)
	_current_focus = &"start_menu"
	overlay.refresh(_focus_stack, _pictures.size())

## S30 (B7, Q211=a, Q141=a): packs `Wall.initial_layout()` and builds every picture, reparenting
## the ALREADY-INSTANTIATED, persistent `menu_scene`/`map_scene` as their `screen_root` (never
## instantiated fresh). `deck` and `game` start with no live screen at all -- `deck` has no
## dedicated persistent screen built yet (ASSUMPTIONS.md), `game` gets one per show (S31,
## `enter_game()` below).
func _build_pictures() -> void:
	var layout := Wall.initial_layout()
	var ids : Array[StringName] = []
	for e : PictureEntry in layout.pictures: ids.append(e.id)
	var rects := WallPacker.pack(layout, ids, _window_size.x / _window_size.y)
	var by_id : Dictionary[StringName, PictureEntry] = {}
	for e : PictureEntry in layout.pictures: by_id[e.id] = e
	var viewports : Node = wall.get_node(^"%Viewports")
	var pictures_root : Node = wall.get_node(^"%Pictures")
	for rect : PictureRect in rects:
		_rects[rect.id] = rect
		var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
		pictures_root.add_child(wp)
		var live_screen : Node = null
		if rect.id == &"start_menu": live_screen = menu_scene
		elif rect.id == &"map": live_screen = map_scene
		wp.build(rect, by_id[rect.id], viewports, live_screen)
		_pictures[rect.id] = wp

# ==============================================================================
# CAMERA / FOCUS ORCHESTRATION
# ==============================================================================

## The on-screen pixel footprint a picture gets while NOT focused, at the current wall-view zoom
## -- `WallPicture.unfocus()`'s own `footprint_px` parameter (GAP-002).
func _footprint(rect: PictureRect) -> Vector2:
	return rect.size * wall.wall_view_zoom(_window_size)

## A plain camera tween to an arbitrary target, over the SAME duration `WallTransition` itself
## uses (`total_duration()`) -- for the two moves `WallTransition` cannot express because it only
## ever runs picture-to-picture: wall-view <-> a picture. `WallTransition` is used instead for
## every picture-to-picture move (`_focus_picture()` below), since it ALREADY latches the
## pause/unpause boundaries correctly (S14-S18/S28) -- this helper does not, and must never be
## used between two pictures.
func _animate_camera(target_pos: Vector2, target_zoom: float) -> void:
	var camera : Camera2D = wall.get_node(^"%Camera2D")
	var settings := SettingsManager.settings
	var duration := WallTransition.total_duration(settings)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(camera, "position", target_pos, duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(camera, "zoom", Vector2.ONE * target_zoom, duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished

## Focuses `id`, `record_visit` controlling whether this is a NEW navigation (visit()) or a
## replay of history already mutated by back()/forward() themselves (which must not visit() again
## -- that would clear the very forward list back() just populated).
func _focus_picture(id: StringName, record_visit: bool = true) -> void:
	var dest_wp : WallPicture = _pictures[id]
	var dest_rect : PictureRect = _rects[id]
	var camera : Camera2D = wall.get_node(^"%Camera2D")
	var settings := SettingsManager.settings
	if _current_focus != &"":
		var source_wp : WallPicture = _pictures[_current_focus]
		var source_rect : PictureRect = _rects[_current_focus]
		var transition := WallTransition.new()
		var landed : Array[bool] = [false]   # boxed -- lambdas capture locals BY VALUE
		transition.landed.connect(func(_lid: StringName) -> void: landed[0] = true)
		transition.request(camera, source_wp, source_rect, dest_wp, dest_rect, _window_size,
				settings)
		while not landed[0]:
			await get_tree().process_frame
		source_wp.unfocus(_footprint(source_rect))
	else:
		await _animate_camera(dest_rect.centre, WallPicture.focused_scale(dest_rect.size,
				_window_size, settings.wall_overfill_margin))
	dest_wp.focus()
	_current_focus = id
	if record_visit:
		_focus_stack.visit(id)
	var overlay : WallOverlay = wall.get_node(^"%Overlay")
	overlay.refresh(_focus_stack, _pictures.size())

## Unfocuses whatever is currently focused (FREEZING it in place, L4 -- never freed here) and
## animates the camera out to wall view. A no-op if already in wall view.
func _go_to_wall_view() -> void:
	if _current_focus != &"":
		var source_wp : WallPicture = _pictures[_current_focus]
		var source_rect : PictureRect = _rects[_current_focus]
		await _animate_camera(wall.wall_view_centre(), wall.wall_view_zoom(_window_size))
		source_wp.unfocus(_footprint(source_rect))
		wall.enter_wall_view(_current_focus)
	_current_focus = &""
	var overlay : WallOverlay = wall.get_node(^"%Overlay")
	overlay.refresh(_focus_stack, _pictures.size())

func _on_wall_view_entered() -> void:
	await _go_to_wall_view()

func _on_wall_pressed() -> void:
	await _go_to_wall_view()

## Q65=a: Back retraces the FocusStack one step at a time; only falls through to wall view once
## the stack itself reports nothing behind the current picture.
func _on_back_pressed() -> void:
	var target := _focus_stack.back()
	if target == &"":
		await _go_to_wall_view()
	else:
		await _focus_picture(target, false)

func _on_forward_pressed() -> void:
	var target := _focus_stack.forward()
	if target != &"":
		await _focus_picture(target, false)

## Q88=a/Q99=a (S31): a click or ui_accept in wall view committing to `id`.
func _on_picture_enter_requested(id: StringName) -> void:
	await _focus_picture(id)

# ==============================================================================
# RUN LIFECYCLE (menu -> map -> game), same signals as before, now wall-native
# ==============================================================================

func _on_new_run(cards: Array[CardData], rules: Array[CardData]) -> void:
	save_info = RunManager.new_run(cards, rules)
	map_scene.start_run(save_info)
	# M2/M3: choosing a save reveals WALL VIEW, on every launch. Using the ORDINARY transition
	# clock (`_go_to_wall_view()`'s own `_animate_camera()` call) -- the distinct, longer/slower
	# one-off reveal is GAP-014, still unbuilt; see ASSUMPTIONS.md.
	await _go_to_wall_view()

func _on_continue() -> void:
	save_info = RunManager.load_run()
	map_scene.start_run(save_info)
	# A pending_node_id means the player quit mid-show (§1.6's pause model does not survive a real
	# process exit -- L8, "a frozen act does NOT survive a quit"): the show restarts fresh, same
	# as before this run existed. M2/M3 still apply uniformly -- every launch reveals wall view.
	if save_info.pending_node_id >= 0:
		enter_game()
	await _go_to_wall_view()

## S31 (L2): entering a show. If the `game` picture already holds a LIVE screen (a previous
## mid-act freeze -- the player left via Back/Wall instead of winning/losing), this RESUMES it --
## focus alone, no rebuild, exactly L4's guarantee. Otherwise builds a fresh GameView (L2, "still
## built fresh per show and freed after, exactly as main.gd does now").
func enter_game() -> void:
	var game_wp : WallPicture = _pictures[&"game"]
	if not game_wp.screen_root:
		var new_view : GameView = GAME_VIEW.instantiate()
		new_view.game_ended.connect(game_ended)
		new_view.run_lost.connect(_on_run_lost)
		game_wp.attach_screen(new_view)
	await _focus_picture(&"game")

## Won game handing back: the show is genuinely OVER (not frozen) -- detach and free the
## GameView (L2), return to the map and let it resolve the node (fame HUD, lap completion, save).
func game_ended() -> void:
	var game_wp : WallPicture = _pictures[&"game"]
	game_wp.detach_screen()
	await _focus_picture(&"map")
	map_scene.returned_from_game()
	LeakSentinel.request_check()  # quiescent moment: the finished show just dropped

## Lost game = run over: discard the save, rebuild the map scene so the next run starts clean,
## detach the (over) game picture, and fall back to start_menu.
func _on_run_lost() -> void:
	RunManager.clear_save()
	save_info = RunState.new()
	var game_wp : WallPicture = _pictures[&"game"]
	game_wp.detach_screen()
	map_scene.queue_free()
	map_scene = MAP.instantiate()
	map_scene.enter_game.connect(enter_game)
	_pictures[&"map"].attach_screen(map_scene)
	await _focus_picture(&"start_menu")
	menu_scene.refresh_continue()
	LeakSentinel.request_check()  # quiescent moment: the lost run's whole graph just dropped
