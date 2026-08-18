class_name WallInput
extends RefCounted
## Converts a wall-space event to the focused picture's SubViewport space and hands it over
## (NAMES.md; PLAN.md §1.9). GAP-001=b: SubViewportContainer is documented as distorting when
## scaled, and the camera scales every picture continuously, so this routing is ours, never the
## engine's.
##
## The wall calls this from its own `_unhandled_input` ONLY (never `_input`), so a focused screen's
## own Controls always get FIRST REFUSAL (Q100=a) -- the same `_unhandled_input` pattern
## `world_map_controller.gd:217` already uses. That wiring lives on `Wall` itself
## (`UI/Wall/wall.gd:_unhandled_input`) -- NAMES.md scopes THIS class to routing alone; S19 pins
## `route()`'s own contract directly.

## Q95=a (I2): only the FOCUSED picture is ever routed to. A non-focused `picture`'s SubViewport
## never receives `push_input` from here, regardless of where `event` targets in wall space --
## returns false outright, before touching the viewport at all.
static func route(event: InputEvent, picture: WallPicture) -> bool:
	if not picture.is_focused: return false
	var screen : Sprite2D = picture.get_node(^"%Screen")
	if not screen.texture: return false
	# §1.9's literal formula: the %Screen sprite's own global-transform-with-canvas inverse (wall
	# space -> the sprite's local/native-texture space, already correct for whatever zoom the
	# camera is currently at -- the GAP-001 risk this class exists to defend against), SCALED by
	# SubViewport.size / (sprite.texture.get_size() * sprite.scale) -- corrects for the sprite's
	# texture tracking the viewport's own LIVE render resolution (which GAP-002's wall-view
	# footprint clamp can shrink below the sprite's own display size) rather than a fixed design
	# size.
	var inverse := screen.get_global_transform_with_canvas().affine_inverse()
	var scale_factor := Vector2(picture.viewport.size) \
			/ (Vector2(screen.texture.get_size()) * screen.scale)
	var local_event := event.xformed_by(inverse.scaled(scale_factor))
	# %Screen is CENTERED (S10, §1.7's own construction) -- its own local origin (0,0) is the
	# MIDDLE of the viewport's native pixel rect, not its top-left corner, so the transform above
	# lands "sprite-centred" local coordinates for a POSITIONAL event. SubViewport.push_input(event,
	# true) and every Control inside it read TOP-LEFT-origin viewport pixels, so it needs shifting
	# by half the viewport's own size -- applied to the ALREADY-transformed position, not via
	# xformed_by()'s own `local_ofs` parameter, which offsets BEFORE the transform (so it gets
	# scaled by it too -- measured directly: Tests/Visual/wall_input_route_spike.gd showed the
	# offset landing at half_vp/zoom, not a constant half_vp, when passed that way). Non-positional
	# events (keyboard, actions) pass through xformed_by() unchanged and need no shift.
	if local_event is InputEventMouse:
		(local_event as InputEventMouse).position += Vector2(picture.viewport.size) * 0.5
	picture.viewport.push_input(local_event, true)
	return true

## GAP-004=b (I8c, §1.9's literal formula): the clamped touch-target size in px. `dpi` is passed in
## rather than read from `DisplayServer.screen_get_dpi()` internally so a caller (or a test) can
## supply a synthetic value -- the live call site is `WallInput.touch_target_px(DisplayServer.
## screen_get_dpi(), settings)`. THE CLAMP IS MANDATORY: DPI is unreliable on multi-monitor Windows
## (primary screen's DPI reported for all) and on Android.
static func touch_target_px(dpi: float, settings: PlayerSettings) -> float:
	return clampf(mm_to_px(settings.wall_touch_target_mm, dpi), settings.wall_touch_target_min_px,
			settings.wall_touch_target_max_px)

## Millimetres -> pixels at a given DPI (25.4 mm/inch). Split out from touch_target_px() so a test
## can check the unclamped conversion in isolation if it ever needs to.
static func mm_to_px(mm: float, dpi: float) -> float:
	return mm / 25.4 * dpi

## GAP-003=a (I8b): pinch is derived BY HAND from two tracked `InputEventScreenTouch` ids' distance
## delta -- `InputEventMagnifyGesture` is NEVER listened for (`feed()` below simply does not match
## on that event type, so it is structurally a no-op, not a skipped check). One instance tracks one
## in-progress two-finger gesture; `Wall` owns the live one (`UI/Wall/wall.gd`'s `_pinch` field,
## fed from `_unhandled_input`) -- NAMES.md only fixes `WallInput.route()`'s own contract, not this
## nested class's identifiers.
class PinchTracker:
	enum Gesture { NONE, PINCH_OUT, PINCH_IN }

	var _ids : Array[int] = []
	var _positions : Dictionary[int, Vector2] = {}
	var _base_distance : float = 0.0
	## Q119=a: pinch is a ONE-SHOT request (enter on pinch-out, wall view on pinch-in), like a
	## button press, never a continuous stream -- latches once the threshold is first crossed and
	## does not re-fire while the same two fingers keep moving further apart/together.
	var _fired := false

	## Feed one input event through the tracker; returns the gesture it just detected, if any.
	## `threshold_px` is `settings.wall_pinch_threshold_px`, passed in rather than read off a stored
	## settings reference so the tracker itself carries no dependency beyond `InputEvent` shapes.
	func feed(event: InputEvent, threshold_px: float) -> Gesture:
		if event is InputEventScreenTouch:
			var t := event as InputEventScreenTouch
			if t.pressed:
				if t.index not in _ids and _ids.size() < 2:
					_ids.append(t.index)
					_positions[t.index] = t.position
					if _ids.size() == 2:
						_base_distance = _positions[_ids[0]].distance_to(_positions[_ids[1]])
						_fired = false
			elif t.index in _ids:
				_ids.erase(t.index)
				_positions.erase(t.index)
				_fired = false
				_base_distance = 0.0
			return Gesture.NONE
		if event is InputEventScreenDrag:
			var d := event as InputEventScreenDrag
			if d.index in _ids:
				_positions[d.index] = d.position
				if _ids.size() == 2 and not _fired:
					var now := _positions[_ids[0]].distance_to(_positions[_ids[1]])
					var delta := now - _base_distance
					if delta >= threshold_px:
						_fired = true
						return Gesture.PINCH_OUT
					if delta <= -threshold_px:
						_fired = true
						return Gesture.PINCH_IN
		# Deliberately no branch for InputEventMagnifyGesture (GAP-003=a) -- it does not fire on
		# Windows and must not be relied on; any event type this tracker does not recognise, that
		# one included, falls through to here and changes nothing.
		return Gesture.NONE
