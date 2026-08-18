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
	# C3 (ADVERSARIAL_REVIEW): `wall_info_mode` lives on PlayerSettings, and every setter there
	# saves to user://settings.tres -- so toggling Info wrote it to disk and it came back on the
	# next launch, silently putting every transition into the info branch while the card was hidden
	# and the button read un-pressed. J1 says info mode is "NOT persisted across sessions" (Q135
	# note) and PLAN.md §4 anti-scope item 9 forbids persisting wall state across a quit. Cleared at
	# startup so the stored value can never survive a relaunch, whatever is on disk.
	if SettingsManager.settings.wall_info_mode:
		SettingsManager.settings.wall_info_mode = false

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

	# M1 (ADVERSARIAL_REVIEW): S17's whole resize path was built and never reached -- nothing
	# anywhere connected `size_changed`, so `_on_window_resized()` below is its ONE call site, and
	# the only caller `WallTransition.retarget()` has.
	get_viewport().size_changed.connect(_on_window_resized)

## S30 (B7, Q211=a, Q141=a): packs `Wall.load_layout()` and builds every UNLOCKED picture,
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
	var layout := Wall.load_layout()
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
	var overlay : WallOverlay = wall.get_node(^"%Overlay")
	overlay.refresh(_focus_stack, _pictures.size())
	_print_wall_debug_readout()

## S17 (C16, G7, G8, Q22=b, Q25=a, Q26=a, Q28=b) + M1 (ADVERSARIAL_REVIEW): the window changed
## shape. Everything S17 built was unreachable before this handler existed -- a resize or a
## fullscreen toggle left every picture packed for the OLD aspect and the camera at the OLD fit, so
## the focused picture stopped overfilling and showed its own frame at rest, which Q27 forbids.
##
## G7/Q22=b: the wall is RE-PACKED at the new aspect, so both the ellipse and every picture's aspect
## follow the window. G8/Q25=a: it SNAPS (`apply_layout(animate = false)`); Q28=b: a fullscreen
## toggle is an ordinary resize, with no separate branch.
##
## Q26=a: a transition in flight is RETARGETED and CONTINUES -- and the camera is deliberately left
## alone in that case, because the transition's own tween owns it until it lands; re-fitting it here
## would be exactly the snap Q26 rejects. At rest nothing else is driving the camera, so this re-fits
## it directly: the info-mode pose while Info is on (J2/Q128), otherwise the ordinary focused
## (Q27/H3) or wall-view (G9) pose.
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
	# GAP-002 ("one property, written when the footprint changes"): the re-pack just changed every
	# unfocused picture's wall-view footprint, so each one's render target follows. The focused
	# picture is skipped -- it renders at full `_design_size` and `focus()` owns that.
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

## M1/S17: the camera's RESTING pose for whatever the wall currently shows -- the info-mode pose
## while Info is on (J2/Q128), otherwise the ordinary focused (Q27/H3) or wall-view (G9) pose.
## Snaps; only a resize (G8/Q25=a) and the deferred settle after a move that a resize interrupted
## call it, and both are snaps by design.
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
## ⚠ Re-entrancy guard (ADVERSARIAL_REVIEW C5). §1.10/Q56=b: "a new destination is ignored until"
## the in-flight move finishes. WallTransition.request() has its own `is_active` check, but this
## method used to construct a FRESH WallTransition per call, so that guard never saw the other one:
## two clicks in wall view ran two tweens on one Camera2D, both landed, and both called focus() —
## leaving two PROCESS_MODE_ALWAYS screen roots. The flag lives here because Main, not the
## transition, is what owns "a move is happening".
var _move_in_flight : bool = false

## M1/S17: the in-flight `WallTransition`, or null at rest -- `_on_window_resized()` is the only
## reader, and `retarget()` (Q26=a) is the only thing it needs one for. Its destination id is kept
## alongside because `_current_focus` still names the SOURCE until the transition lands, so the two
## rects `retarget()` takes cannot both be derived from `_current_focus` alone.
var _active_transition : WallTransition = null
var _transition_dest_id : StringName = &""

func _focus_picture(id: StringName, record_visit: bool = true) -> void:
	if _move_in_flight: return
	if id == _current_focus: return   # Q55=a: requesting the current picture does nothing
	_move_in_flight = true
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
		_active_transition = transition
		_transition_dest_id = id
		# S33 (Q167=c, Q168=c, Q170=b): cross-fades from the source's music toward the dest's over
		# the SAME real camera motion WallTransition is already driving -- see
		# Wall.update_travel_music()'s own doc comment for the distance-driven blend and
		# ASSUMPTIONS.md for the reading taken on Q168's "fades out over the zoom-out."
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
	# A4 (CODE_REVIEW.md, NAMES.md): fires for EVERY focus change, both branches above -- the one
	# signal NAMES.md's table names with no "real transition only" qualifier.
	wall.focus_changed.emit(id)
	if record_visit:
		_focus_stack.visit(id)
	var overlay : WallOverlay = wall.get_node(^"%Overlay")
	overlay.refresh(_focus_stack, _pictures.size())
	_move_in_flight = false
	_settle_after_deferred_resize()

## Unfocuses whatever is currently focused (FREEZING it in place, L4 -- never freed here) and
## animates the camera out to wall view. A no-op if already in wall view. `duration_scale` (GAP-014)
## defaults to an ORDINARY move; only the M2 opening reveal passes anything else.
func _go_to_wall_view(duration_scale: float = 1.0) -> void:
	# Same re-entrancy guard as _focus_picture (ADVERSARIAL_REVIEW C5) -- this is the OTHER path
	# that animates the shared Camera2D, so a Wall press racing an in-flight enter would fight it
	# for position and zoom just as two enters did.
	if _move_in_flight: return
	_move_in_flight = true
	if _current_focus != &"":
		var source_wp : WallPicture = _pictures[_current_focus]
		var source_rect : PictureRect = _rects[_current_focus]
		# S33 (Q167=c): wall view has no picture of its own, so there is nothing to fade music IN
		# to -- a null dest entry fades the current track out over the same move.
		await _animate_camera(wall.wall_view_centre(), wall.wall_view_zoom(_window_size),
				source_rect.centre, wall.wall_view_centre(), null, duration_scale)
		# The LANDED rect (M1/S17): a resize mid-move re-packed the wall, so the rect captured
		# before the await no longer says where this picture is or how big its footprint should be.
		source_wp.unfocus(_footprint(_rects[_current_focus]))
		wall.enter_wall_view(_current_focus)
	_current_focus = &""
	var overlay : WallOverlay = wall.get_node(^"%Overlay")
	overlay.refresh(_focus_stack, _pictures.size())
	_move_in_flight = false
	_settle_after_deferred_resize()

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
