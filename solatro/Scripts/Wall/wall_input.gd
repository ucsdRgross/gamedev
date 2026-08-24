class_name WallInput
extends RefCounted
## Converts a wall-space event to the focused picture's SubViewport space and hands it over.
## `SubViewportContainer` distorts when scaled and the camera scales every picture continuously,
## so this routing is ours, never the engine's.
##
## `Wall` calls this from `_unhandled_input` only, never `_input`, so a focused screen's own
## Controls get first refusal.

## Routes `event` into `picture` if it is focused. A non-focused picture's SubViewport never
## receives `push_input` from here, wherever the event targets in wall space.
static func route(event: InputEvent, picture: WallPicture) -> bool:
	if not picture.is_focused: return false
	var screen : Sprite2D = picture.get_node(^"%Screen")
	if not screen.texture: return false
	# The %Screen sprite's global-transform-with-canvas inverse, and NOTHING ELSE. A centred
	# Sprite2D's local space is already its texture's pixel space, and that texture is the
	# SubViewport's render target, so the inverse lands viewport pixels directly at whatever zoom
	# the camera is currently at.
	#
	# ⚠ Do NOT additionally scale by `viewport.size / (texture.get_size() * sprite.scale)`. The
	# texture IS the render target, so that expression reduces to `1.0 / sprite.scale` — which the
	# inverse has already removed. Dividing by the sprite scale twice is the identity only at
	# scale 1.0, which `WallPacker` produces only at exactly 16:9; at any other window shape every
	# click lands displaced, further off the further it is from the screen centre. Measured at
	# aspect 1.6: viewport pixel (920, 115) arrived at (958.2, 115.0). The centre stays correct,
	# which is why a centre-clicking test cannot see it.
	var local_event := event.xformed_by(
			screen.get_global_transform_with_canvas().affine_inverse())
	# %Screen is CENTERED, so its local origin is the MIDDLE of the viewport's pixel rect while
	# `push_input` and every Control inside read TOP-LEFT-origin pixels. Shift by half the viewport
	# size, applied to the ALREADY-transformed position — NOT via `xformed_by()`'s `local_ofs`,
	# which offsets before the transform and so gets scaled by it (landing at half_vp/zoom).
	# ⚠ EVERY positional event, not just mouse ones: `InputEventScreenTouch` and
	# `InputEventScreenDrag` carry a `position` and do NOT descend from `InputEventMouse`. On
	# desktop `emulate_mouse_from_touch` converts them first, so only a real touch device shows it.
	# Non-positional events (keyboard, actions) need no shift.
	var half_viewport := Vector2(picture.viewport.size) * 0.5
	if local_event is InputEventMouse:
		(local_event as InputEventMouse).position += half_viewport
	elif local_event is InputEventScreenTouch:
		(local_event as InputEventScreenTouch).position += half_viewport
	elif local_event is InputEventScreenDrag:
		(local_event as InputEventScreenDrag).position += half_viewport
	picture.viewport.push_input(local_event, true)
	return true

## The clamped touch-target size in px, used by `WallOverlay._apply_touch_targets()` to grow every
## overlay control. `dpi` is a parameter rather than an internal
## `DisplayServer.screen_get_dpi()` call so a caller can supply a synthetic value.
## ⚠ THE CLAMP IS MANDATORY: DPI is unreliable on multi-monitor Windows, which reports the primary
## screen's DPI for all of them, and on Android.
static func touch_target_px(dpi: float, settings: PlayerSettings) -> float:
	return clampf(mm_to_px(settings.wall_touch_target_mm, dpi), settings.wall_touch_target_min_px,
			settings.wall_touch_target_max_px)

## Millimetres -> pixels at a given DPI (25.4 mm/inch). Split out from touch_target_px() so a test
## can check the unclamped conversion in isolation if it ever needs to.
static func mm_to_px(mm: float, dpi: float) -> float:
	return mm / 25.4 * dpi

## Derives pinch BY HAND from two tracked `InputEventScreenTouch` ids' distance delta.
## `InputEventMagnifyGesture` is never listened for — it does not fire on Windows. One instance
## tracks one in-progress two-finger gesture; `Wall` owns the live one.
class PinchTracker:
	enum Gesture { NONE, PINCH_OUT, PINCH_IN }

	var _ids : Array[int] = []
	var _positions : Dictionary[int, Vector2] = {}
	var _base_distance : float = 0.0
	## Pinch is ONE-SHOT, like a button press, never a continuous stream: latches when the
	## threshold is first crossed and does not re-fire while the same two fingers keep moving.
	var _fired := false

	## Feed one input event through the tracker; returns the gesture it just detected, if any.
	## `threshold_px` is a parameter so the tracker carries no dependency beyond `InputEvent`.
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
		# Deliberately no branch for InputEventMagnifyGesture — it does not fire on Windows. Any
		# unrecognised event type falls through here and changes nothing.
		return Gesture.NONE
