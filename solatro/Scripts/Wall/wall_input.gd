class_name WallInput
extends RefCounted
## Converts a wall-space event to the focused picture's SubViewport space and hands it over
## (NAMES.md; PLAN.md §1.9). GAP-001=b: SubViewportContainer is documented as distorting when
## scaled, and the camera scales every picture continuously, so this routing is ours, never the
## engine's.
##
## The wall calls this from its own `_unhandled_input` ONLY (never `_input`), so a focused screen's
## own Controls always get FIRST REFUSAL (Q100=a) -- the same `_unhandled_input` pattern
## `world_map_controller.gd:217` already uses. That wiring lives on `Wall` itself (a later
## integration step, not S19's own scope -- NAMES.md scopes this class to routing alone); S19 pins
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
