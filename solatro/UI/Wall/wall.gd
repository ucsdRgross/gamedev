class_name Wall
extends Node2D
## The picture-wall shell root — owns the camera, the pictures and the overlay. Handles wall-view
## framing, clamped pan, selection, input routing and the wall's own music players. It does NOT
## orchestrate focus or transitions: it announces player INTENT through signals, and `Main` (which
## holds the `FocusStack`) decides what each one means.

## ⚠ Pauses the whole tree once, at construction, and NEVER clears it. The wall's own root and
## `%Camera2D` are `PROCESS_MODE_ALWAYS` so they keep running regardless, and each screen opts back
## in individually through its own process mode.
func _ready() -> void:
	get_tree().paused = true

const LAYOUT_PATH := "res://Assets/Wall/layout_default.tres"

## The layout the game runs on — the same resource `Tools/wall_editor.tscn` edits and saves, so
## every value an author tunes there is what boots.
##
## Falls back to `initial_layout()` when the file is absent, so a fresh checkout still runs. `path`
## is a parameter so a test can point at a temp file and prove the layout really came from disk.
static func load_layout(path: String = LAYOUT_PATH) -> WallLayout:
	if ResourceLoader.exists(path):
		var loaded : Resource = ResourceLoader.load(path)
		if loaded is WallLayout: return loaded as WallLayout
		push_error("Wall.load_layout: %s exists but did not load as a WallLayout -- " % path
				+ "falling back to the built-in layout")
	return initial_layout()

## The wall's starting content, used to seed `layout_default.tres` the first time and as the
## fallback when it is missing. Six registered ids; `entry.scene` is null on every one:
## `start_menu`/`map` are session-long nodes the caller reparents in through
## `WallPicture.build()`'s `live_screen`, `game` is attached per show via `attach_screen()`, and
## `deck`/`settings`/`book` are registered ids whose contents are not built yet.
##
## `slot` values are placement ORDER only — the packer rebalances the resolved angles regardless of
## the degrees authored here.
static func initial_layout() -> WallLayout:
	var layout := WallLayout.new()
	layout.home_id = &"start_menu"
	var start_menu := PictureEntry.new()
	start_menu.id = &"start_menu"
	start_menu.slot = 0
	start_menu.unlocked_by_default = true
	start_menu.frame_texture = WallPicture.shared_frame_texture()
	var book := PictureEntry.new()
	book.id = &"book"
	book.slot = 45
	book.unlocked_by_default = false
	book.frame_texture = WallPicture.shared_frame_texture()
	var map := PictureEntry.new()
	map.id = &"map"
	map.slot = 90
	map.unlocked_by_default = true
	map.frame_texture = WallPicture.shared_frame_texture()
	var deck := PictureEntry.new()
	deck.id = &"deck"
	deck.slot = 180
	deck.unlocked_by_default = true
	deck.frame_texture = WallPicture.shared_frame_texture()
	var game := PictureEntry.new()
	game.id = &"game"
	game.slot = 270
	game.unlocked_by_default = true
	game.frame_texture = WallPicture.shared_frame_texture()
	var settings := PictureEntry.new()
	settings.id = &"settings"
	settings.slot = 315
	settings.unlocked_by_default = true
	settings.frame_texture = WallPicture.shared_frame_texture()
	layout.pictures = [start_menu, book, map, deck, game, settings]
	return layout

## The wall-view camera's target POSITION: the centre of every packed picture's frame-outer-rect
## union. The counterpart to `wall_view_zoom()`, for whatever animates the camera to wall view.
func wall_view_centre() -> Vector2:
	return _wall_extent().get_center()

## Wall state does not survive a quit: every launch opens on the start-menu picture. A FRESH
## `FocusStack` pre-visited with `&"start_menu"`, never read back from a save file — nothing
## persists a "current picture" anywhere. Two calls must produce two INDEPENDENT stacks.
static func cold_launch_focus_stack() -> FocusStack:
	var stack := FocusStack.new()
	stack.visit(&"start_menu")
	return stack

## An explicit request for WALL VIEW itself, never for Back: the Wall button and pinch-in. Back
## falling through to wall view at the bottom of the stack is NOT this signal — that is the
## `FocusStack`'s verdict, reached through `back_requested`, and only `Main` holds the stack.
signal wall_view_entered

## Back was pressed, with the focused screen taking first refusal. `Wall` does not own the stack,
## so it announces the INTENT and `Main._on_back_pressed()` — the SAME handler the overlay's Back
## button uses, so the two paths cannot diverge — decides what Back means, including falling
## through to wall view once the stack reports nothing behind.
signal back_requested

## Forward was pressed. Same shape and reason as `back_requested`: only `Main` holds the
## `FocusStack`, so only it can say whether there is anything ahead.
signal forward_requested

## Info was toggled from the KEYBOARD. Carries no state: `WallOverlay`'s toggle button is the one
## source of truth for whether Info is on, so `Main` flips THAT and lets the existing `info_toggled`
## chain run rather than writing `wall_info_mode` from a second place and leaving the button
## reading un-pressed.
signal info_toggle_requested

## The pointer moved onto a DIFFERENT picture in wall view, or off every picture (`&""`). Fired on
## CHANGE only, never per motion event. `Wall` deliberately does not call `get_info()` itself: only
## `Main` knows whether Info mode wants an entry, and building one per motion event when it does not
## would allocate a preview node per frame and leak it.
signal picture_hovered(picture_id: StringName)

## The picture the pointer was last over in wall view, so `picture_hovered` fires on change only.
var _hovered_id : StringName = &""

## ⚠ Emitted BY `Main`, not by this class: `Wall` does not orchestrate focus or transitions, so
## only `Main` knows the exact moment each of these occurs.
signal focus_changed(picture_id: StringName)
signal transition_started(from_id: StringName, to_id: StringName)
signal transition_landed(picture_id: StringName)

## Fired from WALL VIEW when the player commits to a destination: a click inside an unfocused
## picture's frame-outer rect, `ui_accept` on `selected_id`, or pinch-out. `Wall` has no notion of
## GameView/menu/map, so acting on this — building a screen, attaching one, or focusing what is
## already there — is the caller's job.
signal picture_enter_requested(id: StringName)

## While true the wall answers no input at all. Set by `Main` for the length of a move and cleared
## by `WallTransition.input_unlocked` or, as a backstop, when the move lands — a lock only a signal
## could clear would strand the wall if that signal ever stopped firing.
var input_locked : bool = false

func lock_input() -> void:
	input_locked = true

func unlock_input() -> void:
	input_locked = false

## One tracker for the whole wall's touch session.
var _pinch := WallInput.PinchTracker.new()

## ⚠ The wall reads input in `_unhandled_input` ONLY, so a focused screen's own Controls get FIRST
## REFUSAL. Routes to the focused picture through `WallInput.route()` first; if that viewport marks
## the event handled, the wall does nothing more.
##
## Arrow-key SELECTION only runs with NO picture focused — the wall never listens while a screen is
## focused. Back, Forward, Info and `wall_jump_N` stay meaningful either way.
func _unhandled_input(event: InputEvent) -> void:
	# Input is inert during a transition. `Main` locks it when a move starts; the transition's
	# `input_unlocked` clears it the moment the destination and its frame are fully in view, which
	# is BEFORE the tween ends.
	if input_locked: return
	var focused := _focused_picture()
	if focused:
		WallInput.route(event, focused)
		if focused.viewport and focused.viewport.is_input_handled():
			return
	else:
		if event.is_action_pressed(&"ui_up"):
			move_selection(Vector2.UP)
			_hold(Vector2.UP)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_released(&"ui_up"):
			_release(Vector2.UP)
			return
		if event.is_action_pressed(&"ui_down"):
			move_selection(Vector2.DOWN)
			_hold(Vector2.DOWN)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_released(&"ui_down"):
			_release(Vector2.DOWN)
			return
		if event.is_action_pressed(&"ui_left"):
			move_selection(Vector2.LEFT)
			_hold(Vector2.LEFT)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_released(&"ui_left"):
			_release(Vector2.LEFT)
			return
		if event.is_action_pressed(&"ui_right"):
			move_selection(Vector2.RIGHT)
			_hold(Vector2.RIGHT)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_released(&"ui_right"):
			_release(Vector2.RIGHT)
			return
		# ui_accept enters the currently selected picture.
		if event.is_action_pressed(&"ui_accept") and selected_id != &"":
			get_viewport().set_input_as_handled()
			picture_enter_requested.emit(selected_id)
			return
		# A click inside an unfocused picture's frame enters it immediately, hit-tested in WALL
		# SPACE. Reads the EVENT's own `position` through `canvas_transform` (which already
		# reflects the camera) rather than `get_global_mouse_position()`: the two agree for a real
		# click, but only the event-driven read can be driven by a synthetic event.
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if not mb.pressed:
					_panning = false
				else:
					var wall_pos : Vector2 = get_viewport().canvas_transform.affine_inverse() * mb.position
					var clicked_id := _picture_at(wall_pos)
					if clicked_id != &"":
						get_viewport().set_input_as_handled()
						picture_enter_requested.emit(clicked_id)
						return
					# A press on BARE WALL does nothing by itself: it only ARMS a pan drag, which
					# moves nothing until the pointer moves, and nothing at all on a window
					# already showing the whole wall.
					_panning = true
		elif event is InputEventMouseMotion:
			if _panning:
				get_viewport().set_input_as_handled()
				pan_by((event as InputEventMouseMotion).relative)
				return
			# Hover tracking. NOT marked handled: hovering is an observation, and consuming every
			# motion event would starve anything else reading them.
			var motion := event as InputEventMouseMotion
			var over : StringName = _picture_at(
					get_viewport().canvas_transform.affine_inverse() * motion.position)
			if over != _hovered_id:
				_hovered_id = over
				picture_hovered.emit(over)
	# Pinch reaches here only if the focused screen did not consume the touch first, like every
	# other wall-level action. Pinch-OUT mirrors ui_accept (wall view only, commits the current
	# selection); pinch-IN goes to wall view, which is why it emits `wall_view_entered` while
	# `ui_cancel` below is Back.
	var gesture := _pinch.feed(event, WallPicture.settings().wall_pinch_threshold_px)
	if gesture == WallInput.PinchTracker.Gesture.PINCH_OUT:
		if not focused and selected_id != &"":
			get_viewport().set_input_as_handled()
			picture_enter_requested.emit(selected_id)
			return
	elif gesture == WallInput.PinchTracker.Gesture.PINCH_IN:
		get_viewport().set_input_as_handled()
		wall_view_entered.emit()
		return
	# Keyboard Back, after the focused screen's first refusal above. Announces Back, never wall
	# view -- see `back_requested`.
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		back_requested.emit()
		return
	# The four `wall_*` actions are ordinary rebindable actions, bound for BOTH keyboard and
	# joypad (Tab/Select-View, `[`/L1, `]`/R1, `I`/Y). Read here alongside `ui_cancel` and
	# `wall_jump_N` because only the SELECTION keys are scoped to wall view — these four are
	# meaningful focused or not, each after the same first refusal as everything above.
	if event.is_action_pressed(&"wall_overview"):
		get_viewport().set_input_as_handled()
		wall_view_entered.emit()
		return
	if event.is_action_pressed(&"wall_back"):
		get_viewport().set_input_as_handled()
		back_requested.emit()
		return
	if event.is_action_pressed(&"wall_forward"):
		get_viewport().set_input_as_handled()
		forward_requested.emit()
		return
	if event.is_action_pressed(&"wall_info"):
		get_viewport().set_input_as_handled()
		info_toggle_requested.emit()
		return
	for n : int in range(1, 10):
		if event.is_action_pressed(StringName("wall_jump_%d" % n)):
			_jump_to_index(n - 1)
			get_viewport().set_input_as_handled()
			return

## Arms the repeat for `direction`, restarting the hold clock. A fresh press always restarts it,
## so tapping never inherits the previous key's part-elapsed delay.
func _hold(direction: Vector2) -> void:
	_held_direction = direction
	_hold_elapsed = 0.0

## Disarms, but ONLY if the released key is the one currently held -- releasing a different arrow
## (rolling from one to another) must not cancel the arrow still down.
func _release(direction: Vector2) -> void:
	if _held_direction == direction:
		_held_direction = Vector2.ZERO
		_hold_elapsed = 0.0

## The one picture currently `is_focused`, or null in wall view. At most one: keeping
## `focus()`/`unfocus()` exclusive is the caller's responsibility.
func _focused_picture() -> WallPicture:
	for child : Node in %Pictures.get_children():
		var wp := child as WallPicture
		if wp and wp.is_focused: return wp
	return null

## The id of whichever picture's FRAME OUTER rect contains `wall_pos`, or `&""`. Frame outer, not
## the bare picture rect, so clicking the frame counts too.
func _picture_at(wall_pos: Vector2) -> StringName:
	for child : Node in %Pictures.get_children():
		var wp := child as WallPicture
		if not wp or not wp.rect: continue
		# ⚠ Offset by where the picture is actually DRAWN, not by its rect alone: the selection
		# lift moves a picture off its rect, so hit-testing the bare rect puts the selected
		# picture's click box `wall_selected_lift` away from what the player sees.
		var frame := WallPacker.frame_outer_rect(wp.rect)
		frame.position += wp.position - wp.rect.centre
		if frame.has_point(wall_pos):
			return wp.rect.id
	return &""

## `wall_jump_N` enters the Nth picture in PLACEMENT order. Silently does nothing past the last.
##
## ⚠ Emits `picture_enter_requested` — the SAME signal a click and `ui_accept` use — rather than
## calling `focus()`: a direct focus skips the unfocus, the camera move, the `FocusStack` update
## and the overlay refresh, leaving TWO screen roots at `PROCESS_MODE_ALWAYS`.
## ⚠ Ordered by the PACKER's result, never `%Pictures` child order, which stops matching placement
## order the moment a re-pack appends a newly-unlocked picture.
func _jump_to_index(index: int) -> void:
	var ordered := _packed_ids_in_placement_order()
	if index < 0 or index >= ordered.size(): return
	picture_enter_requested.emit(ordered[index])

## Placement order as the packer resolved it, recorded by apply_layout(). Empty until the first
## layout is applied, which is why _jump_to_index() range-checks rather than assuming.
var _placement_order : Array[StringName] = []

func _packed_ids_in_placement_order() -> Array[StringName]:
	return _placement_order

## Exactly one picture is selected in wall view, always — empty only before the wall has any
## pictures to select. Set by `enter_wall_view()`/`move_selection()`, never directly.
var selected_id : StringName = &""

## The selection cursor renders only after the first directional input, so a mouse-only session
## never sees a keyboard cursor. `move_selection()` latches this true; nothing ever clears it.
var selection_visible : bool = false

## Every currently packed picture, id -> node, from `%Pictures`' children. Pictures never
## `build()`-ed have no `rect` and are skipped. Typed so callers get `WallPicture` back rather than
## Variant, which warnings-as-errors would reject.
func _pictures_by_id() -> Dictionary[StringName, WallPicture]:
	var out : Dictionary[StringName, WallPicture] = {}
	for child : Node in %Pictures.get_children():
		var wp := child as WallPicture
		if wp and wp.rect:
			out[wp.rect.id] = wp
	return out

## Entering wall view re-seeds the selection to whichever picture the player came FROM, and
## applies it immediately so the cursor exists on arrival rather than on the first arrow press.
## A screen's own internal Control focus needs no code here: `screen_root` nodes are never
## destroyed across a wall-view visit, so Godot's focus state persists on the same instance.
func enter_wall_view(from_id: StringName) -> void:
	selected_id = from_id
	_render_selection()

## The one place that turns (`selected_id`, `selection_visible`) into what is drawn: exactly one
## picture lifted, and only once a directional input has earned the cursor.
func _render_selection() -> void:
	var pictures := _pictures_by_id()
	for id : StringName in pictures:
		pictures[id].set_selected(selection_visible and id == selected_id)

## Moves the selection to the geometrically NEAREST other picture whose centre lies in
## `direction`'s half-plane. WRAPS: with nothing in that direction at all, picks whichever picture
## is MOST OPPOSITE `direction`, i.e. the first from the far end of that axis. Latches
## `selection_visible`.
func move_selection(direction: Vector2) -> void:
	selection_visible = true
	var pictures := _pictures_by_id()
	if pictures.is_empty(): return
	if selected_id == &"" or not pictures.has(selected_id):
		selected_id = pictures.keys()[0]
		_render_selection()
		return
	var dir := direction.normalized()
	var current : PictureRect = pictures[selected_id].rect
	var best_id := &""
	var best_dist := INF
	var wrap_id := &""
	var wrap_dot := INF
	for id : StringName in pictures:
		if id == selected_id: continue
		var candidate : PictureRect = pictures[id].rect
		var offset : Vector2 = candidate.centre - current.centre
		if offset.is_zero_approx(): continue
		var d := offset.normalized().dot(dir)
		if d > 0.0:
			var dist := offset.length()
			if dist < best_dist:
				best_dist = dist
				best_id = id
		if d < wrap_dot:
			wrap_dot = d
			wrap_id = id
	var new_id := best_id if best_id != &"" else wrap_id
	if new_id == &"": return
	selected_id = new_id
	_render_selection()

## Wall view's camera framing: FILL AND CROP the wall's whole extent into the window, through the
## same `WallPicture.focused_scale()` formula a single picture uses at rest. 1.0 when nothing is
## packed yet.
func wall_view_zoom(window_size: Vector2) -> float:
	var extent := _wall_extent()
	if extent.size.x <= 0.0 or extent.size.y <= 0.0: return 1.0
	# ⚠ The crop bias is `WallLayout.view_margin`, NOT `wall_overfill_margin` — that one is a
	# PICTURE knob, meaning a focused picture's own overfill, not the wall's framing. Stored as a
	# fraction and passed as the multiplier `focused_scale()` takes.
	#
	# Passed THROUGH `focused_scale()` rather than multiplied afterwards, so the margin stays
	# CONDITIONAL on the aspects differing: at a matching aspect fill and fit coincide exactly,
	# which is what makes "everything visible means panning is off" an exact zero rather than a
	# few per cent of slack.
	return WallPicture.focused_scale(extent.size, window_size, 1.0 + view_margin())

## `WallLayout.view_margin`, read from disk ONCE per wall and cached.
##
## ⚠ On the POINTER HOT PATH: `wall_view_zoom()` runs from `clamp_pan()`, which `pan_by()` calls
## for every mouse-motion event of a drag. `Wall.load_layout()` does a `ResourceLoader.exists()` —
## a file-system stat — so an uncached read costs one stat per motion event. The layout does not
## change within a session, so once is the right number of times.
func view_margin() -> float:
	if _view_margin_cache < 0.0:
		_view_margin_cache = Wall.load_layout().view_margin
	return _view_margin_cache

## Negative until `view_margin()` has read the layout. Not a tunable -- a "not yet loaded" marker,
## and `view_margin` is a non-negative fraction so no real value can collide with it.
var _view_margin_cache : float = -1.0

## The camera zoom this tracker last saw, or -1 before the first frame. Compared per frame rather
## than hooked to a signal because `Camera2D.zoom` has none, and the trigger is a FRAME in which
## zoom changed, not an event.
var _last_camera_zoom : float = -1.0

## Drives the focused picture's texture filter from the camera, suppressing shimmer while zooming.
##
## Compares ZOOM, not position — a pure pan must never flip the filter. Only the FOCUSED picture is
## told; everything else is unconditionally LINEAR, which `unfocus()` sets once. Runs while the
## tree is paused because the wall root is `PROCESS_MODE_ALWAYS`, and a transition's whole zoom
## happens under that pause.
func _process(delta: float) -> void:
	var camera : Camera2D = %Camera2D
	var zoom := camera.zoom.x
	var zoom_changed := _last_camera_zoom >= 0.0 and not is_equal_approx(zoom, _last_camera_zoom)
	_last_camera_zoom = zoom
	var focused := _focused_picture()
	if focused: focused.update_filter(zoom_changed)
	_tick_selection_repeat(delta, focused != null)

## Repeats the selection step while a direction is held. The FIRST step is the press itself, in
## `_unhandled_input()`; this adds the repeats after `wall_selection_repeat_delay`, reusing that
## same knob as the interval between them.
##
## ⚠ The held direction is latched from the wall's OWN press/release events, never read back off
## the `Input` singleton: `Input` is global, suites run concurrently, and one of them holding an
## arrow would otherwise drive this wall's selection.
## Dropped the moment a picture is focused, so releasing a key inside a screen cannot leave a stale
## repeat armed.
func _tick_selection_repeat(delta: float, has_focused_picture: bool) -> void:
	if has_focused_picture or _held_direction == Vector2.ZERO:
		_held_direction = Vector2.ZERO
		_hold_elapsed = 0.0
		return
	_hold_elapsed += delta
	if _hold_elapsed < WallPicture.settings().wall_selection_repeat_delay: return
	_hold_elapsed = 0.0
	move_selection(_held_direction)

## The direction currently held down in wall view, or ZERO. Latched by `_unhandled_input()`.
var _held_direction : Vector2 = Vector2.ZERO
var _hold_elapsed : float = 0.0

## A pan drag is in progress: the left button went down on BARE WALL in wall view and has not come
## up. Latched here rather than read off `Input` so a synthetic event sequence drives the same path
## a real pointer does.
var _panning : bool = false

## Drags the wall-view camera by a SCREEN-space pointer delta. The camera moves OPPOSITE the
## pointer and divides by the live zoom (direct magnification), so the wall tracks the pointer 1:1
## on screen at any zoom.
##
## "Everything visible means panning is off" needs no check here: `clamp_pan()` collapses each axis
## whose extent fits inside the visible rect to that extent's centre.
##
## Touch needs no separate path — `emulate_mouse_from_touch` delivers a one-finger drag as these
## same mouse events, and a two-finger drag is consumed by the pinch tracker first.
func pan_by(delta: Vector2) -> void:
	var camera : Camera2D = %Camera2D
	var zoom := camera.zoom.x
	if zoom <= 0.0: return
	camera.position = clamp_pan(camera.position - delta / zoom,
			get_viewport().get_visible_rect().size)

## Clamps a requested camera position so the window never shows past the wall's extent, and
## collapses to that extent's centre on whichever axis the extent already fits inside the window —
## panning is a no-op there. `target` is what a drag requests; the return is what to actually set.
func clamp_pan(target: Vector2, window_size: Vector2) -> Vector2:
	var extent := _wall_extent()
	if extent.size.x <= 0.0 or extent.size.y <= 0.0: return Vector2.ZERO
	var zoom := wall_view_zoom(window_size)
	var visible := window_size / zoom
	var half_visible := visible * 0.5
	var min_pos := extent.position + half_visible
	var max_pos := extent.position + extent.size - half_visible
	var x := clampf(target.x, min_pos.x, max_pos.x) if min_pos.x <= max_pos.x \
			else extent.get_center().x
	var y := clampf(target.y, min_pos.y, max_pos.y) if min_pos.y <= max_pos.y \
			else extent.get_center().y
	return Vector2(x, y)

## The union of every packed picture's frame outer rect -- the wall's own bounding box in wall
## space. Empty (zero size) when nothing is packed yet.
func _wall_extent() -> Rect2:
	var extent := Rect2()
	var first := true
	for child : Node in %Pictures.get_children():
		var wp := child as WallPicture
		if wp and wp.rect:
			var frame := WallPacker.frame_outer_rect(wp.rect)
			extent = frame if first else extent.merge(frame)
			first = false
	return extent

## The re-pack tween currently animating pictures into new rects, or null. Kept so a SECOND
## re-pack can kill it -- see `apply_layout()`.
var _layout_tween : Tween = null

## Re-applies a fresh packed layout to every ALREADY-BUILT picture under `%Pictures` — geometry
## only, never touching a viewport, `screen_root` or focus state. `animate` tweens every moved
## picture together on one shared parallel tween over the transition clock; false snaps instantly,
## which is what a re-pack behind a focused screen wants.
##
## Ids with no existing `WallPicture` are SKIPPED: building a new picture node needs its
## `PictureEntry` and screen, which only `Main` has. The `FocusStack` is never touched here — it
## holds ids, not positions, so nothing in this method can invalidate it.
func apply_layout(rects: Dictionary[StringName, PictureRect], animate: bool) -> void:
	# `rects` is built by iterating WallPacker's returned Array, so its key order IS placement
	# order. Kept because %Pictures child order diverges from it the moment a re-pack appends a
	# newly-unlocked picture, and `wall_jump_N` means the Nth picture as PLACED.
	_placement_order.assign(rects.keys())
	# ⚠ KILL ANY LIVE RE-PACK FIRST. A previous animated call's tween is still writing `position`,
	# `%Frame` and `%Screen.scale` toward targets computed against the OLD rects and the OLD
	# `viewport.size`. `WallPicture.rect` is updated immediately (animate_reposition()'s own
	# contract), so leaving that tween running means the picture's rect -- which hit-testing,
	# `_wall_extent()` and the camera framing all read -- permanently disagrees with what is drawn.
	# A resize landing during an animated unlock re-pack is the reachable case.
	if _layout_tween and _layout_tween.is_valid():
		_layout_tween.kill()
	_layout_tween = null
	var pictures := _pictures_by_id()
	var tween : Tween = null
	for id : StringName in rects:
		if not pictures.has(id): continue
		var wp := pictures[id]
		var new_rect : PictureRect = rects[id]
		if not animate:
			wp.reposition(new_rect)
			continue
		if wp.rect and wp.rect.centre.is_equal_approx(new_rect.centre) \
				and wp.rect.size.is_equal_approx(new_rect.size):
			continue
		if tween == null:
			tween = create_tween()
			tween.set_parallel(true)
			_layout_tween = tween
		wp.animate_reposition(tween, new_rect, WallPicture.settings().wall_transition_delay)

## A live count of instantiated screens and an ESTIMATE of their combined texture memory. Godot
## has no cheap per-texture VRAM query, so this assumes RGBA8 — the format every wall SubViewport
## renders in — times each viewport's `.size`. An approximation, not byte-exact GPU accounting.
## Pure: reads only `%Pictures`' children, no engine singletons.
func debug_memory_readout() -> String:
	var screens := 0
	var viewports := 0
	var texture_bytes := 0
	for child : Node in %Pictures.get_children():
		var wp := child as WallPicture
		if not wp: continue
		if wp.screen_root: screens += 1
		if wp.viewport:
			viewports += 1
			texture_bytes += wp.viewport.size.x * wp.viewport.size.y * 4
	return "WALL DEBUG: %d screens instantiated, %d viewports, ~%.2f MB texture memory" \
			% [screens, viewports, texture_bytes / 1048576.0]

## The wall's two ping-pong music players, both on the existing "Music" bus. Exactly one is the
## FOREGROUND player between crossfades; `_music_active` says which index.
@onready var _music_a : AudioStreamPlayer = %MusicA
@onready var _music_b : AudioStreamPlayer = %MusicB
var _music_active : int = 0

func _music_player(index: int) -> AudioStreamPlayer:
	return _music_a if index == 0 else _music_b

## Starts `entry.music` on the foreground player at full volume with no fade — the cold-launch
## case, where there is nothing to cross-fade FROM. A null `entry.music` leaves the wall silent.
func start_music(entry: PictureEntry) -> void:
	_music_player(1 - _music_active).stop()
	var fg := _music_player(_music_active)
	if entry == null or entry.music == null:
		fg.stop()
		return
	fg.stream = entry.music
	fg.volume_db = 0.0
	fg.play()

## True between a `begin_music_crossfade()` that actually ARMED the background player and the
## `finish_music_crossfade()` that resolves it.
## ⚠ `finish` must check this: without it, stepping between two pictures that SHARE a track (where
## `begin` takes its no-op early return) promotes the silent, never-armed player to foreground and
## the music stops dead.
var _crossfade_armed : bool = false

## Arms the BACKGROUND player with `dest_entry`'s track, or silence, ready for
## `update_travel_music()` to blend per frame. A no-op when that is the SAME stream already playing
## in the foreground — no restart, no audible glitch.
func begin_music_crossfade(dest_entry: PictureEntry) -> void:
	var fg := _music_player(_music_active)
	if dest_entry != null and dest_entry.music != null and fg.stream == dest_entry.music \
			and fg.playing:
		_crossfade_armed = false
		return
	_crossfade_armed = true
	var bg := _music_player(1 - _music_active)
	bg.stream = dest_entry.music if dest_entry != null else null
	bg.volume_db = -80.0
	if bg.stream != null:
		bg.play()
	else:
		bg.stop()

## The per-frame music blend during a camera move: `t` is the camera's fractional progress from
## `source_centre` to `dest_centre`, so the crossfade is driven by the REAL camera position the
## transition is already animating rather than a separate timing curve. The outgoing picture fades
## as the camera's distance to it grows. Guards `source_centre == dest_centre`.
func update_travel_music(source_centre: Vector2, dest_centre: Vector2, camera_pos: Vector2) -> void:
	var total := source_centre.distance_to(dest_centre)
	var t := 1.0 if total <= 0.0 else \
			clampf(1.0 - camera_pos.distance_to(dest_centre) / total, 0.0, 1.0)
	_music_player(_music_active).volume_db = linear_to_db(clampf(1.0 - t, 0.001, 1.0))
	_music_player(1 - _music_active).volume_db = linear_to_db(clampf(t, 0.001, 1.0))

## Resolves a crossfade begun by `begin_music_crossfade()`: STOPS and silences the old foreground
## player — never leaves it merely quiet — and flips which player is foreground, so the next
## crossfade's background player is the one that just faded out.
func finish_music_crossfade() -> void:
	# Nothing was armed, so there is nothing to resolve and nothing to swap.
	if not _crossfade_armed: return
	_crossfade_armed = false
	var old_fg := _music_player(_music_active)
	old_fg.stop()
	old_fg.volume_db = -80.0
	_music_active = 1 - _music_active
	_music_player(_music_active).volume_db = 0.0

## Force-renders every frozen picture once: the GPU may have discarded their textures while the
## window was minimised. Godot has no dedicated un-minimise signal on desktop, so this uses
## `NOTIFICATION_APPLICATION_FOCUS_IN`, which also fires on a plain alt-tab back — harmless, since
## a forced re-render costs one frame.
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_IN:
		return
	for child : Node in %Pictures.get_children():
		var wp := child as WallPicture
		if wp:
			wp.mark_for_rerender()
