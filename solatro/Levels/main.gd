class_name Main
extends Node

## Scene orchestrator, and the owner of the ONE `Wall` the whole app lives inside. Holds the
## pre-instantiated menu/map scenes and exposes the current run as the static `save_info` alias,
## which always mirrors `RunManager.run`.
##
## Navigation shape: cold launch focuses `start_menu` directly with no wall-view flash; choosing a
## save reveals wall view, slowed by `wall_reveal_delay_scale` so it reads as distinct from an
## ordinary Wall press; entering map/deck/game focuses that picture through a real
## `WallTransition`; leaving mid-act unfocuses and FREEZES the show rather than freeing it. Wall
## state never survives a quit — nothing here persists `_focus_stack` or `_current_focus`.

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
## Every picture's authored entry, kept so the movers can read `.music` for whichever id they are
## moving to or from. `WallPicture.build()` takes an entry but does not keep one.
var _entries : Dictionary[StringName, PictureEntry] = {}
var _focus_stack : FocusStack = null
## `&""` while in wall view; otherwise the id of whichever picture is currently focused. Tracked
## here (not read back off `wall`) because `Main` is the one that knows what "focused" means for
## each id (a live GameView vs. a persistent menu/map screen).
var _current_focus : StringName = &""
var _window_size : Vector2

func _ready() -> void:
	# ⚠ Info mode must not survive a quit. `wall_info_mode` is not `@export`ed, but a
	# `settings.tres` written by an older build still carries the key and `ResourceLoader` will set
	# it on load — which would silently put every transition into the info branch while the card is
	# hidden and the button reads un-pressed.
	if SettingsManager.settings.wall_info_mode:
		SettingsManager.settings.wall_info_mode = false

	map_scene.enter_game.connect(enter_game)
	# ⚠ There is exactly ONE InfoCard, on the wall overlay. A screen must never mount its own: a
	# second instance is not what `_on_info_toggled()` resets, so it could never be dismissed.
	map_scene.info_hovered.connect(_on_screen_info_hovered)
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
	overlay.info_toggled.connect(_on_info_toggled)
	wall.wall_view_entered.connect(_on_wall_view_entered)
	# ⚠ Every keyboard/joypad wall action reuses the SAME handler its overlay control drives, so
	# the key and the button cannot diverge. `wall_overview`/`wall_back` need no line of their own:
	# they emit `wall_view_entered`/`back_requested`, connected above.
	wall.back_requested.connect(_on_back_pressed)
	wall.forward_requested.connect(_on_forward_pressed)
	wall.info_toggle_requested.connect(_on_info_toggle_requested)
	wall.picture_enter_requested.connect(_on_picture_enter_requested)
	wall.picture_hovered.connect(_on_picture_hovered)
	ProfileManager.picture_unlocked.connect(_repack_wall)

	_focus_stack = Wall.cold_launch_focus_stack()
	# The camera starts already zoomed into the start-menu picture: no wall-view flash, no
	# transition, straight to focused.
	var start_wp : WallPicture = _pictures[&"start_menu"]
	var start_rect : PictureRect = _rects[&"start_menu"]
	var camera : Camera2D = wall.get_node(^"%Camera2D")
	start_wp.focus()
	camera.position = start_rect.centre
	camera.zoom = Vector2.ONE * WallPicture.focused_scale(start_rect.size, _window_size,
			SettingsManager.settings.wall_overfill_margin)
	_current_focus = &"start_menu"
	# No ceremony, matching the camera above: start_menu's music begins immediately at full
	# volume, with nothing to fade FROM.
	wall.start_music(_entries[&"start_menu"])
	overlay.refresh(_focus_stack, _pictures.size(), _current_focus == &"")

	get_viewport().size_changed.connect(_on_window_resized)

## Packs `Wall.load_layout()` and builds every UNLOCKED picture, reparenting the already-
## instantiated `menu_scene`/`map_scene` as their `screen_root` rather than instantiating fresh
## copies. `deck` and `game` start with no live screen: `deck` has no persistent screen yet, and
## `game` gets one per show in `enter_game()`.
##
## ⚠ Filter by `ProfileManager.is_unlocked()`/`unlocked_by_default`, the same filter
## `_repack_wall()` uses. Building every id in `layout.pictures` puts a LOCKED picture on the wall
## from cold launch.
func _build_pictures() -> void:
	var layout := Wall.load_layout()
	var ids : Array[StringName] = []
	for e : PictureEntry in layout.pictures:
		if ProfileManager.is_unlocked(e.id) or e.unlocked_by_default: ids.append(e.id)
	var rects := WallPacker.pack(layout, ids, _window_size.x / _window_size.y)
	var by_id : Dictionary[StringName, PictureEntry] = {}
	for e : PictureEntry in layout.pictures: by_id[e.id] = e
	var viewports : Node = wall.get_node(^"%Viewports")
	var pictures_root : Node = wall.get_node(^"%Pictures")
	var rects_by_id : Dictionary[StringName, PictureRect] = {}
	for rect : PictureRect in rects:
		_rects[rect.id] = rect
		rects_by_id[rect.id] = rect
		_entries[rect.id] = by_id[rect.id]
		var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
		pictures_root.add_child(wp)
		var live_screen : Node = null
		if rect.id == &"start_menu": live_screen = menu_scene
		elif rect.id == &"map": live_screen = map_scene
		wp.build(rect, by_id[rect.id], viewports, live_screen)
		_pictures[rect.id] = wp
	# ⚠ Needed for `_placement_order`, which `apply_layout()` alone records and which `wall_jump_N`
	# reads. The geometry half is a no-op here — every picture was just built at exactly this rect
	# — but without this call the number keys are inert until some other path re-packs.
	wall.apply_layout(rects_by_id, false)
	# A picture's render target is its wall-view footprint — the same rule `_repack_wall()` and
	# `_on_window_resized()` follow. `build()` leaves every picture at full `_design_size`, which
	# is ~7x the pixels each. Nothing is focused yet; `_ready()` focuses start_menu straight after
	# and `focus()` restores its full size.
	for id : StringName in _pictures:
		_pictures[id].update_wall_view_size(_footprint(_rects[id]))

## Reacts to `ProfileManager.picture_unlocked`: recomputes the unlocked id set (`is_unlocked()`
## already honours `wall_unlock_all`), packs fresh rects, BUILDS any picture never built before
## straight at its final rect — no reveal ceremony, it is simply there the next time the wall is
## seen — and repositions the rest through `Wall.apply_layout()`, animated while the player is in
## wall view and silent otherwise.
##
## The `FocusStack` is never touched: it holds ids, not positions, so Back/Forward keep resolving
## however a picture's geometry just changed.
func _repack_wall(_unlocked_id: StringName) -> void:
	var layout := Wall.load_layout()
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
	# A re-pack changes every unfocused picture's wall-view footprint just as a resize does, so
	# each render target follows. The focused picture is skipped: it renders at full `_design_size`
	# and `focus()` owns that.
	for id : StringName in _pictures:
		var wp : WallPicture = _pictures[id]
		if not wp.is_focused: wp.update_wall_view_size(_footprint(_rects[id]))
	# Same as a resize: a transition in flight is RETARGETED to the new geometry and CONTINUES.
	# Without this an unlock landing mid-move animates toward rects that no longer exist.
	if _active_transition and _active_transition.is_active:
		_active_transition.retarget(_rects[_current_focus], _rects[_transition_dest_id],
				_window_size)
	var overlay : WallOverlay = wall.get_node(^"%Overlay")
	overlay.refresh(_focus_stack, _pictures.size(), _current_focus == &"")
	_print_wall_debug_readout()

## The window changed shape. The wall is RE-PACKED at the new aspect, so the ellipse and every
## picture's aspect follow the window, and it SNAPS. A fullscreen toggle is an ordinary resize,
## with no separate branch.
##
## A transition in flight is RETARGETED and CONTINUES, and the camera is deliberately left alone in
## that case — the transition's tween owns it until it lands, and re-fitting here would be a snap
## mid-move. At rest nothing else drives the camera, so this re-fits it through `_settle_camera()`.
func _on_window_resized() -> void:
	var new_size := get_viewport().get_visible_rect().size
	if new_size.x <= 0.0 or new_size.y <= 0.0: return
	if new_size.is_equal_approx(_window_size): return
	_window_size = new_size
	# Exactly the pictures that currently EXIST: a resize never unlocks anything, so re-deriving the
	# unlocked set here could only ever disagree with what is actually on the wall.
	var layout := Wall.load_layout()
	var ids : Array[StringName] = []
	for e : PictureEntry in layout.pictures:
		if _pictures.has(e.id): ids.append(e.id)
	var rects_by_id : Dictionary[StringName, PictureRect] = {}
	for rect : PictureRect in WallPacker.pack(layout, ids, _window_size.x / _window_size.y):
		rects_by_id[rect.id] = rect
		_rects[rect.id] = rect
	wall.apply_layout(rects_by_id, false)
	# The re-pack just changed every unfocused picture's footprint, so each render target follows.
	# The focused picture is skipped: `focus()` owns its full-`_design_size` render.
	for id : StringName in _pictures:
		var wp : WallPicture = _pictures[id]
		if not wp.is_focused: wp.update_wall_view_size(_footprint(_rects[id]))
	if _active_transition and _active_transition.is_active:
		_active_transition.retarget(_rects[_current_focus], _rects[_transition_dest_id],
				_window_size)
		return
	# A wall-view <-> picture move is a plain `_animate_camera()` tween toward a target computed
	# before the resize, so there is nothing on it to retarget and settling now would simply be
	# overwritten by its next frame. Deferred to the moment that move finishes instead.
	if _move_in_flight:
		_resize_pending = true
		return
	_settle_camera()

## The camera's RESTING pose for whatever the wall currently shows: the info-mode pose while Info
## is on, otherwise the ordinary focused or wall-view pose. Snaps — every caller wants a snap.
## The ONE home for this arithmetic; a second copy would drift.
func _settle_camera() -> void:
	var camera : Camera2D = wall.get_node(^"%Camera2D")
	var settings := SettingsManager.settings
	if _current_focus == &"":
		camera.position = wall.wall_view_centre()
		camera.zoom = Vector2.ONE * wall.wall_view_zoom(_window_size)
		return
	var focused_rect : PictureRect = _rects[_current_focus]
	if settings.wall_info_mode:
		var state := WallPicture.info_zoom_state(focused_rect, _window_size, settings)
		var info_pos : Vector2 = state["position"]
		var info_zoom : float = state["zoom"]
		camera.position = info_pos
		camera.zoom = Vector2.ONE * info_zoom
	else:
		camera.position = focused_rect.centre
		camera.zoom = Vector2.ONE * WallPicture.focused_scale(focused_rect.size, _window_size,
				settings.wall_overfill_margin)

## Set by `_on_window_resized()` when a move was already in flight with no retargetable transition;
## cleared by whichever move was in flight, which settles the camera itself once it lands.
var _resize_pending : bool = false

## Called by every move as it releases `_move_in_flight`: if a resize arrived while that move owned
## the camera, its tween has just landed on a target computed for the OLD window, so the resting
## pose is re-applied now that `_current_focus` is finally correct.
func _settle_after_deferred_resize() -> void:
	if not _resize_pending: return
	_resize_pending = false
	_settle_camera()

## `wall.debug_memory_readout()` when the readout should be visible — a debug build AND the
## `wall_debug_readout` flag, the same gate the leak sentinel uses — or `""`. Split from
## `_print_wall_debug_readout()` so the gate is testable without capturing stdout.
func _wall_debug_readout_text() -> String:
	if not OS.is_debug_build() or not SettingsManager.settings.wall_debug_readout: return ""
	return wall.debug_memory_readout()

## Called from the same QUIESCENT moments `LeakSentinel.request_check()` marks — a show ending, a
## run lost, a re-pack — never on a per-frame timer.
func _print_wall_debug_readout() -> void:
	var text := _wall_debug_readout_text()
	if text != "": print(text)

# ==============================================================================
# CAMERA / FOCUS ORCHESTRATION
# ==============================================================================

## The on-screen pixel footprint a picture gets while NOT focused, at the current wall-view zoom —
## `WallPicture.unfocus()`'s `footprint_px` parameter.
func _footprint(rect: PictureRect) -> Vector2:
	return rect.size * wall.wall_view_zoom(_window_size)

## A plain camera tween to an arbitrary target, over the same duration `WallTransition` uses. For
## the two moves `WallTransition` cannot express, since it only runs picture-to-picture:
## wall view <-> a picture.
## ⚠ NEVER use this between two pictures. `WallTransition` latches the pause/unpause boundaries;
## this helper does not.
##
## Also drives the music cross-fade, through the same distance-driven blend the transition branch
## uses. A null `audio_dest_entry` fades the current track out with nothing to fade in, which is
## what entering wall view needs.
##
## `duration_scale` multiplies the transition clock: 1.0 for every ordinary move, and
## `wall_reveal_delay_scale` only for the one-off opening reveal.
func _animate_camera(target_pos: Vector2, target_zoom: float, audio_source_centre: Vector2,
		audio_dest_centre: Vector2, audio_dest_entry: PictureEntry,
		duration_scale: float = 1.0) -> void:
	var camera : Camera2D = wall.get_node(^"%Camera2D")
	var settings := SettingsManager.settings
	var duration := WallTransition.total_duration(settings) * duration_scale
	wall.begin_music_crossfade(audio_dest_entry)
	# The AUTHORED travel curve, never a typed-in literal: this move is travel with no zoom leg.
	#
	# ⚠ BOUND TO THE CAMERA, NOT TO `Main`. A bare `create_tween()` binds to this node, and `Main`
	# is PAUSABLE while the wall holds `get_tree().paused = true` for the whole session — a tween
	# bound to a PAUSABLE node under a paused tree NEVER ADVANCES, so `await tween.finished` never
	# returns and the app soft-locks with `_move_in_flight` and `input_locked` stuck true.
	# `%Camera2D` is `PROCESS_MODE_ALWAYS`.
	var tween := camera.create_tween()
	tween.set_parallel(true)
	tween.tween_property(camera, "position", target_pos, duration) \
			.set_trans(settings.wall_travel_trans).set_ease(settings.wall_travel_ease)
	tween.tween_property(camera, "zoom", Vector2.ONE * target_zoom, duration) \
			.set_trans(settings.wall_travel_trans).set_ease(settings.wall_travel_ease)
	tween.tween_method(func(_progress: float) -> void:
			wall.update_travel_music(audio_source_centre, audio_dest_centre, camera.position),
			0.0, 1.0, duration)
	await tween.finished
	wall.finish_music_crossfade()

## Focuses `id`, `record_visit` controlling whether this is a NEW navigation (visit()) or a
## replay of history already mutated by back()/forward() themselves (which must not visit() again
## -- that would clear the very forward list back() just populated).
## ⚠ The re-entrancy guard: a new destination is IGNORED until the in-flight move finishes.
## `WallTransition.request()` has its own `is_active` check, but `_focus_picture()` constructs a
## FRESH transition per call, so that guard never sees the other one — two clicks in wall view run
## two tweens on one Camera2D, both land, and both call `focus()`, leaving two
## `PROCESS_MODE_ALWAYS` screen roots. The flag lives here because `Main`, not the transition, owns
## "a move is happening".
var _move_in_flight : bool = false

## The in-flight `WallTransition`, or null at rest — needed only so a resize or unlock can
## `retarget()` it. The destination id is kept alongside because `_current_focus` still names the
## SOURCE until the transition lands.
var _active_transition : WallTransition = null
var _transition_dest_id : StringName = &""

func _focus_picture(id: StringName, record_visit: bool = true) -> void:
	if _move_in_flight: return
	if id == _current_focus: return   # requesting the current picture does nothing
	_move_in_flight = true
	# Input goes inert for the length of the move. The transition's `input_unlocked` lifts it
	# EARLY below; this is the only thing that ever sets it.
	wall.lock_input()
	var dest_wp : WallPicture = _pictures[id]
	var dest_rect : PictureRect = _rects[id]
	var camera : Camera2D = wall.get_node(^"%Camera2D")
	var settings := SettingsManager.settings
	if _current_focus != &"":
		var source_wp : WallPicture = _pictures[_current_focus]
		var source_rect : PictureRect = _rects[_current_focus]
		# A REAL picture-to-picture move -- the only case `transition_started`/`transition_landed`
		# cover, since both take real picture ids and wall view is never one.
		wall.transition_started.emit(_current_focus, id)
		var transition := WallTransition.new()
		var landed : Array[bool] = [false]   # boxed -- lambdas capture locals BY VALUE
		transition.landed.connect(func(_lid: StringName) -> void: landed[0] = true)
		transition.request(camera, source_wp, source_rect, dest_wp, dest_rect, _window_size,
				settings)
		_active_transition = transition
		_transition_dest_id = id
		# The wall answers input again the instant the destination and its frame are fully in
		# view, which is strictly BEFORE landing.
		transition.input_unlocked.connect(wall.unlock_input)
		# Cross-fades from the source's music toward the destination's over the SAME real camera
		# motion the transition is driving -- see `Wall.update_travel_music()`.
		wall.begin_music_crossfade(_entries[id])
		while not landed[0]:
			wall.update_travel_music(source_rect.centre, dest_rect.centre, camera.position)
			await get_tree().process_frame
		wall.finish_music_crossfade()
		_active_transition = null
		_transition_dest_id = &""
		# The LANDED source rect, not the one captured before the loop: a mid-flight resize re-packs
		# the wall (and skips the focused picture's own footprint, which `focus()` owns), so `_rects`
		# is the only current truth about the footprint this picture is about to shrink to.
		source_rect = _rects[_current_focus]
		source_wp.unfocus(_footprint(source_rect))
		wall.transition_landed.emit(id)
	else:
		await _animate_camera(dest_rect.centre, WallPicture.focused_scale(dest_rect.size,
				_window_size, settings.wall_overfill_margin),
				wall.wall_view_centre(), dest_rect.centre, _entries[id])
	dest_wp.focus()
	_current_focus = id
	# Fires for EVERY focus change, both branches above -- unlike `transition_landed`.
	wall.focus_changed.emit(id)
	if record_visit:
		_focus_stack.visit(id)
	var overlay : WallOverlay = wall.get_node(^"%Overlay")
	overlay.refresh(_focus_stack, _pictures.size(), _current_focus == &"")
	# ⚠ A move ENDS at its destination's resting pose, whatever route it took. A no-op for the
	# ordinary branch, which already lands there — but `sample_at()`'s reduced-motion branch holds
	# a constant zoom for every elapsed including the last, and its info-mode branch holds the
	# SOURCE's info zoom, so both would otherwise rest wherever the tween stopped, showing frame.
	# Deliberately `_settle_camera()`, the same function a resize settles to, never a second copy
	# of the resting-pose arithmetic.
	_settle_camera()
	_move_in_flight = false
	wall.unlock_input()   # backstop: the early unlock above may never have had a frame to fire in
	_settle_after_deferred_resize()

## Unfocuses whatever is focused — FREEZING it in place, never freeing it — and animates the
## camera out to wall view. A no-op if already in wall view. `duration_scale` defaults to an
## ordinary move; only the opening reveal passes anything else.
func _go_to_wall_view(duration_scale: float = 1.0) -> void:
	# Same re-entrancy guard as `_focus_picture()`: this is the OTHER path animating the shared
	# Camera2D, so a Wall press racing an in-flight enter would fight it for position and zoom.
	if _move_in_flight: return
	_move_in_flight = true
	# Just as much a transition to the player. No `WallTransition`, so no early unlock -- input
	# clears on landing.
	wall.lock_input()
	if _current_focus != &"":
		var source_wp : WallPicture = _pictures[_current_focus]
		var source_rect : PictureRect = _rects[_current_focus]
		# Wall view has no picture of its own, so there is nothing to fade music IN to -- a null
		# dest entry fades the current track out over the same move.
		await _animate_camera(wall.wall_view_centre(), wall.wall_view_zoom(_window_size),
				source_rect.centre, wall.wall_view_centre(), null, duration_scale)
		# The LANDED rect: a resize mid-move re-packs the wall, so the rect captured before the
		# await no longer says where this picture is or how big its footprint should be.
		source_wp.unfocus(_footprint(_rects[_current_focus]))
		wall.enter_wall_view(_current_focus)
	_current_focus = &""
	var overlay : WallOverlay = wall.get_node(^"%Overlay")
	overlay.refresh(_focus_stack, _pictures.size(), _current_focus == &"")
	_move_in_flight = false
	wall.unlock_input()
	_settle_after_deferred_resize()

func _on_wall_view_entered() -> void:
	await _go_to_wall_view()

func _on_wall_pressed() -> void:
	await _go_to_wall_view()

## The `wall_info` key. Presses the overlay's toggle rather than writing `wall_info_mode` here, so
## the key, the button and the mode stay one thing: the button's `toggled` then runs
## `_on_info_toggled()` exactly as a mouse press does.
func _on_info_toggle_requested() -> void:
	var overlay : WallOverlay = wall.get_node(^"%Overlay")
	overlay.toggle_info()

## Sets the shared `wall_info_mode` flag so anything reading it agrees with what the button shows,
## resets `%InfoCard` to hidden on the way OUT — nothing re-shows it on the way in, since the card
## stays empty until something is hovered — and animates the camera to or from the info zoom while
## a picture is focused. A no-op in wall view, where no single frame exists to reveal.
func _on_info_toggled(active: bool) -> void:
	SettingsManager.settings.wall_info_mode = active
	var info_card : InfoCard = wall.get_node(^"%Overlay/InfoCard")
	if not active:
		info_card.reset()
	if _current_focus == &"": return
	# ⚠ ONE move at a time: this drives the same shared `%Camera2D` as every other move, so
	# toggling Info during a transition would run a second tween against the live one and settle on
	# the SOURCE picture's info pose, leaving the destination ~99% off-screen with no way out.
	#
	# The MODE still changes — the button has already moved — but the CAMERA is left to whichever
	# move owns it. `_settle_camera()` honours `wall_info_mode`, so the destination arrives posed
	# for the mode just chosen.
	if _move_in_flight: return
	_move_in_flight = true
	var dest_rect : PictureRect = _rects[_current_focus]
	var settings := SettingsManager.settings
	if active:
		var state := WallPicture.info_zoom_state(dest_rect, _window_size, settings)
		var info_pos : Vector2 = state["position"]
		var info_zoom : float = state["zoom"]
		await _animate_camera(info_pos, info_zoom, dest_rect.centre, dest_rect.centre,
				_entries[_current_focus], settings.wall_info_zoom_scale)
	else:
		await _animate_camera(dest_rect.centre, WallPicture.focused_scale(dest_rect.size,
				_window_size, settings.wall_overfill_margin), dest_rect.centre, dest_rect.centre,
				_entries[_current_focus], settings.wall_info_zoom_scale)
	# Same reason `_focus_picture()` ends this way: a move ENDS at the resting pose for whatever
	# the wall shows NOW. A second Info press during this animation flips `wall_info_mode` and is
	# then refused by the guard above, so the tween finishes travelling to a pose for a mode the
	# player has already changed their mind about — leaving a band of frame and bare wall showing
	# with Info reading OFF. `_settle_camera()` reads the flag itself.
	_settle_camera()
	_move_in_flight = false
	# A resize that arrived while this move owned the camera deferred its settle to whoever was
	# moving -- which is this, exactly as for the other two movers.
	_settle_after_deferred_resize()

## A focused screen published something hoverable. Shown on the wall's ONE card, and ONLY while
## Info mode is on. Ignored silently otherwise — a screen has no business checking the flag before
## it speaks.
func _on_screen_info_hovered(entry: InfoEntry) -> void:
	if not SettingsManager.settings.wall_info_mode:
		# ⚠ FREE THE DROPPED ENTRY'S VISUAL. Screens build entries eagerly, and for a booster node
		# that is a container holding one live preview card per card in the pack. `InfoEntry` is
		# RefCounted, but `entry.visual` is a NODE never added to any tree, so dropping the
		# reference orphans it in ObjectDB for the rest of the session. Info mode is off by
		# default, so this is the NORMAL path, once per hover-enter.
		if entry and entry.visual and is_instance_valid(entry.visual):
			entry.visual.queue_free()
		return
	var info_card : InfoCard = wall.get_node(^"%Overlay/InfoCard")
	info_card.show_entry(entry)

## A different picture is under the pointer in wall view. `get_info()` is called HERE rather than
## in `Wall` so it runs only when Info mode will show the result: it builds a live preview node per
## call, and one per motion event would leak one per frame. `&""` — the pointer left every picture
## — deliberately does nothing, so the card KEEPS its last entry rather than blinking out.
func _on_picture_hovered(picture_id: StringName) -> void:
	if not SettingsManager.settings.wall_info_mode: return
	if picture_id == &"" or not _pictures.has(picture_id): return
	_on_screen_info_hovered(_pictures[picture_id].get_info())

## Back retraces the `FocusStack` one step at a time, falling through to wall view only once the
## stack reports nothing behind the current picture.
func _on_back_pressed() -> void:
	# ⚠ The guard has to be on the HANDLER, because the handler is what MUTATES. The movers carry
	# their own, but they only see it after `back()` has already popped an entry — so a second
	# press mid-move pops and then refuses to navigate, losing a picture from the stack for good.
	if _move_in_flight: return
	# In WALL VIEW the stack's top is still the picture the player just left, since wall view is
	# never an entry — so one step back from here is THAT picture. `back()` would step PAST it and
	# push it onto the forward list, leaving it "ahead of you" having never been revisited.
	if _current_focus == &"":
		var top := _focus_stack.current()
		if top != &"":
			await _focus_picture(top, false)
		return
	var target := _focus_stack.back()
	if target == &"":
		await _go_to_wall_view()
	else:
		await _focus_picture(target, false)

func _on_forward_pressed() -> void:
	if _move_in_flight: return   # same reason as Back above -- forward() mutates too
	var target := _focus_stack.forward()
	if target != &"":
		await _focus_picture(target, false)

## A click, `ui_accept` or pinch-out in wall view committing to `id`.
func _on_picture_enter_requested(id: StringName) -> void:
	await _focus_picture(id)

# ==============================================================================
# RUN LIFECYCLE (menu -> map -> game), same signals as before, now wall-native
# ==============================================================================

func _on_new_run(cards: Array[CardData], rules: Array[CardData]) -> void:
	save_info = RunManager.new_run(cards, rules)
	# ⚠ A GameView left over from a LOST run is kept alive so re-entering `game` shows the
	# game-over screen; a new run is where it is finally replaced. Without this, `enter_game()`'s
	# "resume if already attached" check resumes the last run's lose screen instead of building a
	# fresh board. A no-op after a WON run, which detaches its own GameView in `game_ended()`.
	var game_wp : WallPicture = _pictures[&"game"]
	game_wp.detach_screen()
	map_scene.start_run(save_info)
	# Choosing a save reveals WALL VIEW, longer and slower than an ordinary move. Only this call
	# and `_on_continue()` pass a scale; every other `_go_to_wall_view()` uses the plain clock.
	await _go_to_wall_view(SettingsManager.settings.wall_reveal_delay_scale)

func _on_continue() -> void:
	save_info = RunManager.load_run()
	map_scene.start_run(save_info)
	# A `pending_node_id` means the player quit mid-show: the pause model does not survive a
	# process exit, so the show restarts fresh. The reveal happens on EVERY launch, resume
	# included, so it runs FIRST and the show is re-entered after it lands.
	# ⚠ ORDER AND `await` BOTH MATTER. `enter_game()` is a coroutine: calling it un-awaited runs it
	# as far as its first await — inside `_focus_picture()`, AFTER `_move_in_flight = true` — and
	# returns, so the reveal below hits its own `if _move_in_flight: return` and does nothing.
	await _go_to_wall_view(SettingsManager.settings.wall_reveal_delay_scale)
	if save_info.pending_node_id >= 0:
		await enter_game()

## Entering a show. If the `game` picture already holds a LIVE screen — a previous mid-act freeze,
## where the player left via Back or Wall rather than winning or losing — this RESUMES it: focus
## alone, no rebuild. Otherwise it builds a fresh GameView.
func enter_game() -> void:
	var game_wp : WallPicture = _pictures[&"game"]
	if not game_wp.screen_root:
		var new_view : GameView = GAME_VIEW.instantiate()
		new_view.game_ended.connect(game_ended)
		new_view.run_lost.connect(_on_run_lost)
		game_wp.attach_screen(new_view)
	await _focus_picture(&"game")

## Won game handing back: the show is genuinely OVER, not frozen — detach and free the GameView,
## return to the map and let it resolve the node (fame HUD, lap completion, save).
func game_ended() -> void:
	var game_wp : WallPicture = _pictures[&"game"]
	game_wp.detach_screen()
	await _focus_picture(&"map")
	map_scene.returned_from_game()
	LeakSentinel.request_check()  # quiescent moment: the finished show just dropped
	_print_wall_debug_readout()

## The run save is cleared, but NEITHER picture is torn down. The map picture stays on the wall
## exactly as it last rendered — `map_scene` is not rebuilt and its `run` is not reset — because
## removing it would re-pack the wall for a reason unrelated to unlocks. The game picture's
## GameView is likewise left attached, frozen on its game-over screen, so re-entering `game` shows
## exactly that. The camera is not moved: the player is already looking at what they triggered.
## Both are replaced only when the next run starts, in `_on_new_run()`.
func _on_run_lost() -> void:
	RunManager.clear_save()
	save_info = RunState.new()
	menu_scene.refresh_continue()
	LeakSentinel.request_check()  # quiescent moment: the lost run's board state just settled
	_print_wall_debug_readout()
