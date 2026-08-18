class_name Main
extends Node

## Scene orchestrator: Menu -> Map -> Game and back, now the PICTURE WALL (PLAN.md Phase 7,
## S30/S31). Owns the pre-instantiated menu/map scenes, exposes the current run as the static
## save_info alias (kept for the many existing Main.save_info call sites; it always mirrors
## RunManager.run), and owns the ONE real `Wall` the whole app now lives inside.
##
## M1-M4/B7/K6/Q211=a (S30) + L1-L11/Q186=d (S31), all landing here: cold launch focuses
## start_menu directly (no wall-view flash); choosing a save reveals wall view (M2/M3), scaled by
## `wall_reveal_delay_scale` (GAP-014, owner-answered a) so it reads as distinct from an ordinary
## Wall press; entering map/deck/game is focusing that picture via a real WallTransition;
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
## S33 (Q167=c): every picture's own authored data, kept so `_focus_picture()`/`_go_to_wall_view()`
## can read `.music` for whichever id they are moving to/from -- `WallPicture.build()` takes an
## entry as a parameter but does not keep one, so nothing else on this class already holds it.
var _entries : Dictionary[StringName, PictureEntry] = {}
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
	# CODE_REVIEW.md A2: info_toggled had no consumer anywhere -- the Info button did nothing.
	overlay.info_toggled.connect(_on_info_toggled)
	wall.wall_view_entered.connect(_on_wall_view_entered)
	wall.picture_enter_requested.connect(_on_picture_enter_requested)
	# S38 (K2-K4): ProfileManager already exists (S7) and already emits this on a genuine new
	# unlock -- wiring the wall to it here, not building a second unlock path.
	ProfileManager.picture_unlocked.connect(_repack_wall)

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
	# S33 (Q167=c, M1): no ceremony, matching the camera's own "starts already focused" cold-launch
	# rule -- start_menu's music (if any) begins immediately, at full volume, nothing to fade FROM.
	wall.start_music(_entries[&"start_menu"])
	overlay.refresh(_focus_stack, _pictures.size())

## S30 (B7, Q211=a, Q141=a): packs `Wall.initial_layout()` and builds every UNLOCKED picture,
## reparenting the ALREADY-INSTANTIATED, persistent `menu_scene`/`map_scene` as their
## `screen_root` (never instantiated fresh). `deck` and `game` start with no live screen at all --
## `deck` has no dedicated persistent screen built yet (ASSUMPTIONS.md), `game` gets one per show
## (S31, `enter_game()` below).
##
## ⚠ Bug found and fixed (register-settings-book correction): this used to add EVERY id in
## `layout.pictures` unconditionally, never checking `unlocked_by_default`/`ProfileManager.
## is_unlocked()` at all. Invisible while every registered picture was `unlocked_by_default = true`
## (the four-picture layout), but with `book` now `unlocked_by_default = false`, the bug meant a
## LOCKED picture was already built and visible on the very first cold launch -- exactly the "no
## reveal ceremony" guarantee (K2) inverted, since it applied before ANY unlock, not after one. The
## SAME filter `_repack_wall()` already uses.
func _build_pictures() -> void:
	var layout := Wall.initial_layout()
	var ids : Array[StringName] = []
	for e : PictureEntry in layout.pictures:
		if ProfileManager.is_unlocked(e.id) or e.unlocked_by_default: ids.append(e.id)
	var rects := WallPacker.pack(layout, ids, _window_size.x / _window_size.y)
	var by_id : Dictionary[StringName, PictureEntry] = {}
	for e : PictureEntry in layout.pictures: by_id[e.id] = e
	var viewports : Node = wall.get_node(^"%Viewports")
	var pictures_root : Node = wall.get_node(^"%Pictures")
	for rect : PictureRect in rects:
		_rects[rect.id] = rect
		_entries[rect.id] = by_id[rect.id]
		var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
		pictures_root.add_child(wp)
		var live_screen : Node = null
		if rect.id == &"start_menu": live_screen = menu_scene
		elif rect.id == &"map": live_screen = map_scene
		wp.build(rect, by_id[rect.id], viewports, live_screen)
		_pictures[rect.id] = wp

## S38 (K2, K3, K4, K11): reacts to `ProfileManager.picture_unlocked` -- recomputes the layout's
## unlocked id set (`ProfileManager.is_unlocked()` already honours `wall_unlock_all`, K11's debug
## flag, with no separate check needed here), packs fresh rects for all of them, builds any picture
## never built before at its final rect directly (K2: "no reveal ceremony -- the picture is simply
## there next time the wall is seen" -- build() itself, not a tween, is the correct way to make
## that true), and repositions every already-built picture via `Wall.apply_layout()`: LIVE-ANIMATED
## if the player is currently in wall view (K3), silent otherwise (K4). The `FocusStack` is never
## touched here -- it holds ids, not positions (K4's own guarantee), so Back/Forward keep resolving
## correctly regardless of how a picture's geometry just changed.
func _repack_wall(_unlocked_id: StringName) -> void:
	var layout := Wall.initial_layout()
	var by_id : Dictionary[StringName, PictureEntry] = {}
	var ids : Array[StringName] = []
	for e : PictureEntry in layout.pictures:
		by_id[e.id] = e
		if ProfileManager.is_unlocked(e.id) or e.unlocked_by_default:
			ids.append(e.id)
	var rects := WallPacker.pack(layout, ids, _window_size.x / _window_size.y)
	var viewports : Node = wall.get_node(^"%Viewports")
	var pictures_root : Node = wall.get_node(^"%Pictures")
	var rects_by_id : Dictionary[StringName, PictureRect] = {}
	for rect : PictureRect in rects:
		rects_by_id[rect.id] = rect
		_rects[rect.id] = rect
		_entries[rect.id] = by_id[rect.id]
		if not _pictures.has(rect.id):
			var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
			pictures_root.add_child(wp)
			wp.build(rect, by_id[rect.id], viewports)
			_pictures[rect.id] = wp
	wall.apply_layout(rects_by_id, _current_focus == &"")
	var overlay : WallOverlay = wall.get_node(^"%Overlay")
	overlay.refresh(_focus_stack, _pictures.size())
	_print_wall_debug_readout()

## S39 (E9, Q210=a): the debug-flag GATE itself, as a pure function returning
## `wall.debug_memory_readout()` when the readout should be visible (a debug build AND the
## `wall_debug_readout` flag -- the SAME gate the leak sentinel uses, `OS.is_debug_build()`) or
## `""` otherwise. Split out from `_print_wall_debug_readout()` so the gate is directly testable
## without capturing stdout -- a `print()` call has no return value a test can assert on.
func _wall_debug_readout_text() -> String:
	if not OS.is_debug_build() or not SettingsManager.settings.wall_debug_readout: return ""
	return wall.debug_memory_readout()

## Called from the same QUIESCENT moments `LeakSentinel.request_check()` already marks (a show
## ending, a run being lost, a re-pack), never on a per-frame timer -- no new interval knob for a
## cadence nothing has asked for.
func _print_wall_debug_readout() -> void:
	var text := _wall_debug_readout_text()
	if text != "": print(text)

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
## S33 (Q167=c, Q168=c, Q170=b): also drives the wall's own music cross-fade for this move, using
## the SAME `Wall.update_travel_music()` distance-driven blend `_focus_picture()`'s WallTransition
## branch uses below -- `audio_dest_entry == null` (wall view has no picture of its own, Q167=c)
## fades the current track out with nothing to fade IN, exactly what entering wall view needs.
## GAP-014 (owner-answered a): `duration_scale` multiplies the ordinary transition clock -- 1.0 for
## every ordinary move (an explicit Wall press, entering/leaving a picture), and
## `wall_reveal_delay_scale` ONLY for M2's one-off opening reveal (`_on_new_run()`/`_on_continue()`
## below), which is the one call site that needs the reveal to read as "distinct... longer, slower".
func _animate_camera(target_pos: Vector2, target_zoom: float, audio_source_centre: Vector2,
		audio_dest_centre: Vector2, audio_dest_entry: PictureEntry,
		duration_scale: float = 1.0) -> void:
	var camera : Camera2D = wall.get_node(^"%Camera2D")
	var settings := SettingsManager.settings
	var duration := WallTransition.total_duration(settings) * duration_scale
	wall.begin_music_crossfade(audio_dest_entry)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(camera, "position", target_pos, duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(camera, "zoom", Vector2.ONE * target_zoom, duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(func(_progress: float) -> void:
			wall.update_travel_music(audio_source_centre, audio_dest_centre, camera.position),
			0.0, 1.0, duration)
	await tween.finished
	wall.finish_music_crossfade()

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
		# A4 (CODE_REVIEW.md, NAMES.md): a REAL picture-to-picture move -- the only case
		# transition_started/transition_landed name (both take real picture ids, and wall view is
		# never one, Q66=b), unlike the wall-view<->picture moves _animate_camera() drives below.
		wall.transition_started.emit(_current_focus, id)
		var transition := WallTransition.new()
		var landed : Array[bool] = [false]   # boxed -- lambdas capture locals BY VALUE
		transition.landed.connect(func(_lid: StringName) -> void: landed[0] = true)
		transition.request(camera, source_wp, source_rect, dest_wp, dest_rect, _window_size,
				settings)
		# S33 (Q167=c, Q168=c, Q170=b): cross-fades from the source's music toward the dest's over
		# the SAME real camera motion WallTransition is already driving -- see
		# Wall.update_travel_music()'s own doc comment for the distance-driven blend and
		# ASSUMPTIONS.md for the reading taken on Q168's "fades out over the zoom-out."
		wall.begin_music_crossfade(_entries[id])
		while not landed[0]:
			wall.update_travel_music(source_rect.centre, dest_rect.centre, camera.position)
			await get_tree().process_frame
		wall.finish_music_crossfade()
		source_wp.unfocus(_footprint(source_rect))
		wall.transition_landed.emit(id)
	else:
		await _animate_camera(dest_rect.centre, WallPicture.focused_scale(dest_rect.size,
				_window_size, settings.wall_overfill_margin),
				wall.wall_view_centre(), dest_rect.centre, _entries[id])
	dest_wp.focus()
	_current_focus = id
	# A4 (CODE_REVIEW.md, NAMES.md): fires for EVERY focus change, both branches above -- the one
	# signal NAMES.md's table names with no "real transition only" qualifier.
	wall.focus_changed.emit(id)
	if record_visit:
		_focus_stack.visit(id)
	var overlay : WallOverlay = wall.get_node(^"%Overlay")
	overlay.refresh(_focus_stack, _pictures.size())

## Unfocuses whatever is currently focused (FREEZING it in place, L4 -- never freed here) and
## animates the camera out to wall view. A no-op if already in wall view. `duration_scale` (GAP-014)
## defaults to an ORDINARY move; only the M2 opening reveal passes anything else.
func _go_to_wall_view(duration_scale: float = 1.0) -> void:
	if _current_focus != &"":
		var source_wp : WallPicture = _pictures[_current_focus]
		var source_rect : PictureRect = _rects[_current_focus]
		# S33 (Q167=c): wall view has no picture of its own, so there is nothing to fade music IN
		# to -- a null dest entry fades the current track out over the same move.
		await _animate_camera(wall.wall_view_centre(), wall.wall_view_zoom(_window_size),
				source_rect.centre, wall.wall_view_centre(), null, duration_scale)
		source_wp.unfocus(_footprint(source_rect))
		wall.enter_wall_view(_current_focus)
	_current_focus = &""
	var overlay : WallOverlay = wall.get_node(^"%Overlay")
	overlay.refresh(_focus_stack, _pictures.size())

func _on_wall_view_entered() -> void:
	await _go_to_wall_view()

func _on_wall_pressed() -> void:
	await _go_to_wall_view()

## CODE_REVIEW.md A2 (J1-J2/Q127=a, J2/Q128): the Info toggle previously did nothing. `active`
## sets the shared `wall_info_mode` flag (so any code reading it, present or future, agrees with
## what the button shows), resets `%InfoCard` to hidden on the way OUT (J6: "leaving info mode
## resets it to nothing" -- nothing here re-shows it on the way in, since J1/J5 say the card stays
## empty until something is actually hovered, which this batch does not add a hover source for),
## and animates the camera to/from the info zoom (J2/Q128: "reveals the BOTTOM frame only") when a
## picture is currently focused -- a no-op in wall view, where no single frame exists to reveal.
func _on_info_toggled(active: bool) -> void:
	SettingsManager.settings.wall_info_mode = active
	var info_card : InfoCard = wall.get_node(^"%Overlay/InfoCard")
	if not active:
		info_card.reset()
	if _current_focus == &"": return
	var dest_rect : PictureRect = _rects[_current_focus]
	var settings := SettingsManager.settings
	if active:
		var state := WallPicture.info_zoom_state(dest_rect, _window_size, settings)
		var info_pos : Vector2 = state["position"]
		var info_zoom : float = state["zoom"]
		await _animate_camera(info_pos, info_zoom, dest_rect.centre, dest_rect.centre,
				_entries[_current_focus])
	else:
		await _animate_camera(dest_rect.centre, WallPicture.focused_scale(dest_rect.size,
				_window_size, settings.wall_overfill_margin), dest_rect.centre, dest_rect.centre,
				_entries[_current_focus])

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
	# L12/Q157=a: a GameView left over from a LOST run is kept alive (see _on_run_lost() below) so
	# re-entering `game` showed the game-over screen -- "the map is replaced only when a new run
	# starts" applies equally to the game picture, so THIS is where it finally gets replaced, not
	# at loss time. Without this, enter_game()'s own "resume if already attached" check would
	# wrongly resume last run's lose screen instead of building a fresh board for this run. A no-op
	# (detach_screen() is itself a no-op on a null/already-freed screen_root) after a WON run, which
	# already detaches its own GameView immediately (game_ended()).
	var game_wp : WallPicture = _pictures[&"game"]
	game_wp.detach_screen()
	map_scene.start_run(save_info)
	# M2/M3 (GAP-014, owner-answered a): choosing a save reveals WALL VIEW, on every launch, with
	# the one-off "distinct... longer, slower" reveal -- `wall_reveal_delay_scale` multiplies the
	# ordinary transition clock for THIS call only; every other _go_to_wall_view() caller (an
	# ordinary Wall press, Back falling through to wall view) stays at the plain clock.
	await _go_to_wall_view(SettingsManager.settings.wall_reveal_delay_scale)

func _on_continue() -> void:
	save_info = RunManager.load_run()
	map_scene.start_run(save_info)
	# A pending_node_id means the player quit mid-show (§1.6's pause model does not survive a real
	# process exit -- L8, "a frozen act does NOT survive a quit"): the show restarts fresh, same
	# as before this run existed. M2/M3 still apply uniformly -- every launch reveals wall view,
	# with the same GAP-014 reveal scale as _on_new_run().
	if save_info.pending_node_id >= 0:
		enter_game()
	await _go_to_wall_view(SettingsManager.settings.wall_reveal_delay_scale)

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
	_print_wall_debug_readout()

## S32 (L12, Q157=a -- "stays on the wall, shows its own empty state"): the run save is cleared,
## but NEITHER picture is torn down here. The map picture STAYS on the wall exactly as it last
## rendered (L12's own words) -- `map_scene` is not rebuilt, its `run` field is not reset, nothing
## about it changes; Q157's rejected option (b), "removed from the wall until a run exists again,"
## would additionally re-pack the wall for a reason unrelated to unlocks, which is exactly the
## "preset pattern" the owner's own note says that fights. The game picture's GameView is likewise
## left attached, frozen showing its own game-over screen (LoseScreen) -- re-entering `game` shows
## exactly that. The camera is not moved: the player is already looking at the game-over screen
## they just triggered, and nothing in L12 asks to navigate them away from it. Both pictures are
## only actually REPLACED once the next run starts (`_on_new_run()`'s own `game_wp.detach_screen()`
## + `map_scene.start_run()` calls) -- "the map is replaced only when a new run starts."
func _on_run_lost() -> void:
	RunManager.clear_save()
	save_info = RunState.new()
	menu_scene.refresh_continue()
	LeakSentinel.request_check()  # quiescent moment: the lost run's board state just settled
	_print_wall_debug_readout()
