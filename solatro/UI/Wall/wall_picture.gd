@tool
## ⚠ `@tool` so the layout tool can build REAL instances: a non-`@tool` script loads as a PLACEHOLDER, and `build()` on one throws.
class_name WallPicture
extends Node2D
# One picture: frame + screen sprite + its own SubViewport, drawn by a `Sprite2D` showing a
# `ViewportTexture` -- never a `SubViewportContainer`, which distorts when scaled.
# ⚠ NOT A CHILD OF THIS NODE: `build()` parents it under `%Viewports` on `wall.tscn`.

# Public so an editor-side tool can assign its own tunable instance and have every knob it drags
# reach the real wall; null in the shipped game, which then reads `SettingsManager`.
# ⚠ The override wins PREVIEWED OR PLAYED -- PICTURE_WALL.md "Tuning it — `Tools/wall_editor.tscn`".
static var editor_settings : PlayerSettings = null

## The ONE place that answers which `PlayerSettings` the wall reads; nothing re-derives the rule.
static func settings() -> PlayerSettings:
	if editor_settings: return editor_settings
	return FxAttachment.settings()

@onready var _shadow : Sprite2D = %Shadow
@onready var _frame : NinePatchRect = %Frame
@onready var _screen : Sprite2D = %Screen

## The SubViewport `build()` creates, public so a caller can free it: it lives under `viewports_parent`, not under this node.
var viewport : SubViewport = null

## Emitted by `go_live()`: this picture draws and runs live from this frame, landed or still zooming in.
signal went_live

## Whether this picture draws live: from `go_live()` until `unfocus()`.
var is_live : bool = false

## Whether this is the live picture. `build()` leaves it false -- construction is "never yet rendered", not "focused".
var is_focused : bool = false

## Remembered from build() so focus() can restore full design resolution without the caller handing `PictureEntry` back in.
var _design_size : Vector2i

# `entry.scene` instantiated under `viewport`, or null when the entry has no scene.
# `focus()`/`unfocus()` flip exactly THIS node between ALWAYS and PAUSABLE; nothing else in the
# chain needs an override, this node's root being PAUSABLE and cutting `%Viewports`' ALWAYS.
var screen_root : Node = null

## The packed rect `build()` was given, kept so a caller can read id/centre/size/frame_px without re-deriving them.
var rect : PictureRect = null

## The entry's `background_texture`, shown and hidden as `screen_root` comes and goes; a live screen always wins. Null when unauthored.
var _background_texture : Texture2D = null
## The Sprite2D actually showing `_background_texture` inside `viewport`, or null when there is none to show.
var _background : Sprite2D = null

# The ONE shared frame texture every framed picture references: a bevel profile, light at the outer
# edge and dark at the inner, generated once and cached. Placeholder art pending a shader and art
# pass; `PictureEntry.frame_colour` is what varies per picture. `_FRAME_CORNER_PX` is in TEXTURE px.
const _FRAME_TEXTURE_SIZE := 40
const _FRAME_CORNER_PX := 14
static var _shared_frame_texture : ImageTexture = null

static func shared_frame_texture() -> ImageTexture:
	if _shared_frame_texture: return _shared_frame_texture
	var img := Image.create(_FRAME_TEXTURE_SIZE, _FRAME_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var light := Color(0.62, 0.52, 0.38)
	var dark := Color(0.24, 0.18, 0.12)
	for y : int in _FRAME_TEXTURE_SIZE:
		for x : int in _FRAME_TEXTURE_SIZE:
			var depth : int = mini(mini(x, y), mini(_FRAME_TEXTURE_SIZE - 1 - x,
					_FRAME_TEXTURE_SIZE - 1 - y))
			var t := clampf(float(depth) / float(_FRAME_CORNER_PX), 0.0, 1.0)
			img.set_pixel(x, y, light.lerp(dark, t))
	_shared_frame_texture = ImageTexture.create_from_image(img)
	return _shared_frame_texture

# The nine-slice corner for `tex` in texture pixels, clamped so opposing margins can never meet or
# cross: a texture under `2 * _FRAME_CORNER_PX` on either axis gets the largest corner it can carry
# rather than a degenerate nine-slice.
static func _frame_corner_px(tex: Texture2D) -> int:
	var smallest := mini(int(tex.get_width()), int(tex.get_height()))
	return mini(_FRAME_CORNER_PX, smallest / 2)

# Builds this picture from its packed rect and authored entry. %Frame is the rect grown by
# `frame_px`, drawn entirely OUTSIDE it; a null `entry.scene` is "registered but unbuilt" and
# renders nothing; `live_screen` is a session-long node REPARENTED here instead -- never both.

# ⚠ UPDATE_ONCE regardless of eventual focus, so every texture is non-null before any `focus()`.
# Both filter writes, and the nine-slice gated on the texture EXISTING not on identity, are
# PICTURE_WALL.md "Landmines". One light for the whole wall; white `modulate` keeps the bevel's tone.
func build(p_rect: PictureRect, entry: PictureEntry, viewports_parent: Node,
		live_screen: Node = null) -> void:
	rect = p_rect
	position = rect.centre
	_design_size = entry.design_size

	viewport = SubViewport.new()
	_apply_design_render_size()
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewports_parent.add_child(viewport)
	_background_texture = entry.background_texture
	if live_screen:
		screen_root = live_screen
		screen_root.process_mode = Node.PROCESS_MODE_PAUSABLE
		viewport.add_child(screen_root)
	elif entry.scene:
		screen_root = entry.scene.instantiate()
		screen_root.process_mode = Node.PROCESS_MODE_PAUSABLE
		viewport.add_child(screen_root)
	else:
		_show_background()

	var frame_rect := WallPacker.frame_outer_rect(rect)
	_frame.position = frame_rect.position - rect.centre
	_frame.size = frame_rect.size
	_frame.texture = entry.frame_texture
	_frame.modulate = entry.frame_colour
	if entry.frame_texture:
		var corner := _frame_corner_px(entry.frame_texture)
		_frame.patch_margin_left = corner
		_frame.patch_margin_top = corner
		_frame.patch_margin_right = corner
		_frame.patch_margin_bottom = corner

	_screen.centered = true
	_screen.region_enabled = true
	_screen.position = Vector2.ZERO
	_screen.texture = viewport.get_texture()
	_screen.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	_shadow.centered = true
	_shadow.region_enabled = true
	_shadow.position = settings().wall_light_offset
	_shadow.texture = viewport.get_texture()
	_rescale_screen()
	_shadow.self_modulate = Color(0.0, 0.0, 0.0, settings().wall_shadow_opacity)

# Swaps `screen_root` for a new live node, freeing whatever was there. Unlike `build()`'s
# `live_screen`, set once for a session-long screen, this is for a picture whose CONTENT is rebuilt
# per use while the picture stays put, as `game` gets a fresh `GameView` per show.
func attach_screen(live_screen: Node) -> void:
	if screen_root and is_instance_valid(screen_root):
		screen_root.queue_free()
	_hide_background()
	screen_root = live_screen
	screen_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	viewport.add_child(screen_root)
#A screen attached to a picture that is ALREADY live starts at once: no move is coming to take it
#live, and a held show would stay held (a show restarted onto the focused game picture).
	if is_live:
		is_live = false
		go_live()

## Frees `screen_root`, leaving the authored background -- or, with none, the "registered but unbuilt" rendering.
func detach_screen() -> void:
	if screen_root and is_instance_valid(screen_root):
		screen_root.queue_free()
	screen_root = null
	_show_background()

## Shows `_background_texture` inside `viewport`, stretched to fill `_design_size` exactly, of which `%Screen` shows the centred part `_crop_to_rect()` cuts.
func _show_background() -> void:
	if _background or not _background_texture: return
	_background = Sprite2D.new()
	_background.centered = true
	_background.position = Vector2.ZERO
	_background.texture = _background_texture
	var tex_size := _background_texture.get_size()
	if tex_size.x > 0.0 and tex_size.y > 0.0:
		_background.scale = Vector2(_design_size) / tex_size
	viewport.add_child(_background)

## Removes the authored background the instant a real screen takes over; it is never drawn behind a live `screen_root`.
func _hide_background() -> void:
	if not _background: return
	if is_instance_valid(_background): _background.queue_free()
	_background = null

# Makes this the live picture: UPDATE_ALWAYS at full `design_size`. The CALLER guarantees one
# picture is focused at a time; this enacts the state, it does not arbitrate focus. It starts at
# rest (no zoom has changed yet) and fully opaque (no resting state is ever partly faded).

# ⚠ Position is re-applied because the selection LIFT is a wall-view affordance: without it a
# picture entered by keyboard or pad stays lifted while the camera sits at `rect.centre`, showing
# a strip of frame and bare wall along the bottom edge. A click never selects, so a mouse misses.
func focus() -> void:
	is_focused = true
	_apply_position()
	prepare_to_focus()
	go_live()
	update_filter(false)
	set_screen_alpha(1.0)

#A move toward a picture takes it live at the start of its ZOOM-IN, before the landing: the scene is
#responsible for its own display (owner ruling). `focus()` goes live too, so every route does.
func go_live() -> void:
	if is_live: return
	is_live = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if screen_root:
		screen_root.process_mode = Node.PROCESS_MODE_ALWAYS
	went_live.emit()

# The full-`design_size` render target, restored when a move toward this picture STARTS and again by
# `focus()`. ⚠ A SubViewport resized on the frame it is first shown focused is drawn from the OLD
# target's contents read at the new size: magnified by the size ratio, cropped, for one frame.
func prepare_to_focus() -> void:
	_apply_design_render_size()
	_rescale_screen()

# The render-target size for a picture laid out at `design`: each axis capped at `max_px`.
# ⚠ An oversized `SubViewport.size` cannot be read back to detect, so never write one --
# PICTURE_WALL.md "Landmines".
static func clamped_render_size(design: Vector2i, max_px: int) -> Vector2i:
	return Vector2i(mini(design.x, max_px), mini(design.y, max_px))

# Writes `viewport`'s render target at FULL design size -- what `build()` and `focus()` both want.
# Clamped to `game_picture_max_render_px`, with the canvas override engaged ONLY when the clamp
# bites, so an over-wide picture pays sharpness rather than a destroyed framebuffer.

# ⚠ At 1:1 the override must be CLEARED, not left at an identity -- PICTURE_WALL.md "Landmines".
# `update_wall_view_size()` uses the same mechanism; only the size asked for differs.
func _apply_design_render_size() -> void:
	var render := clamped_render_size(_design_size, settings().game_picture_max_render_px)
	viewport.size = render
	var clamped := render != _design_size
	viewport.size_2d_override = _design_size if clamped else Vector2i.ZERO
	viewport.size_2d_override_stretch = clamped

# Drops this out of focus: UPDATE_DISABLED, so rendering stops while the rendered texture persists
# on the GPU, sized down to the wall-view footprint and never left at full `design_size`. Leaving
# focus is exactly when a still-selected picture's lift becomes visible again.

# The screen root goes back to PAUSABLE: wall view is every picture in that state at once, nothing
# extra enforcing it. Non-focused samples LINEAR (PICTURE_WALL.md "Landmines") and the alpha is reset,
# never left mid-fade from a reduced-motion cross-fade.
func unfocus(footprint_px: Vector2) -> void:
	is_focused = false
	is_live = false
	_apply_position()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	update_wall_view_size(footprint_px)
	if screen_root:
		screen_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	_screen.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	set_screen_alpha(1.0)

## `%Screen`'s opacity -- all `WallTransition._apply()` needs for a reduced-motion cross-fade. Exposed narrowly, not the whole node.
func set_screen_alpha(alpha: float) -> void:
	_screen.modulate.a = alpha

# Whether this picture's frame is drawn. Exposed narrowly, like `set_screen_alpha()` above: the
# caller decides WHEN no frame may be on screen, and this node stays the only writer of `%Frame`.
func set_frame_visible(shown: bool) -> void:
	_frame.visible = shown

# ONLY THE SHOWN PART IS ON SCREEN, so it alone is sized to a texel per footprint pixel and floored
# at `wall_view_min_texture_px`: sizing the whole canvas to the footprint drew a cropped picture ~3x
# magnified. One scale on both axes, like the canvas it renders.

# ⚠ `size_2d_override` is what makes the screen SHRINK rather than crop, and
# `size_2d_override_stretch` maps the two onto each other -- PICTURE_WALL.md "Landmines".
func update_wall_view_size(footprint_px: Vector2) -> void:
	var shown := _shown_canvas()
	var texels_per_canvas_px := maxf(cover_scale(shown, footprint_px),
			settings().wall_view_min_texture_px / minf(shown.x, shown.y))
	viewport.size = Vector2i((Vector2(_design_size) * texels_per_canvas_px).ceil())
	viewport.size_2d_override = _design_size
	viewport.size_2d_override_stretch = true
	_rescale_screen()

## How big a window pixel is against one of this picture's own while focused -- what a hosted screen converts through to match window space.
func window_scale(window: Vector2) -> float:
	return focused_scale(rect.size, window, settings().wall_overfill_margin) \
			* cover_scale(Vector2(_design_size), rect.size)

# The space LEFT beside `rect` (the shared `HudContainer`'s rect, against this viewport's own
# `window` size) once both convert into THIS picture's own space -- the unmargined cover scale and
# inset `GameView._publish_board_inset()` uses, extended to a rect a focused screen can centre in.
func local_rect_beside(window: Vector2, rect: Rect2, top: bool) -> Rect2:
	return visible_rect_beside(Vector2(_design_size), window, rect, top)

## The part of `design` a covering `window` SHOWS beside `rect`: what is left once the crop and `rect`'s own axis are taken off.
static func visible_rect_beside(design: Vector2, window: Vector2, rect: Rect2, top: bool) -> Rect2:
	var scale := cover_scale(design, window)
	var visible := Rect2((design - window / scale) / 2.0, window / scale)
	var inset := inset_beside(rect, top, scale)
	return Rect2(visible.position + inset, visible.size - inset)

## The px `rect` takes off the space beside it at `scale`: its height when it sits on top, else its width.
static func inset_beside(rect: Rect2, top: bool, scale: float) -> Vector2:
	if top: return Vector2(0.0, rect.size.y / scale)
	return Vector2(rect.size.x / scale, 0.0)

## The scale at which `native_size` exactly covers `window_size`: the larger axis ratio, no margin.
static func cover_scale(native_size: Vector2, window_size: Vector2) -> float:
	return maxf(window_size.x / native_size.x, window_size.y / native_size.y)

# Rescales %Screen and %Shadow so this picture draws at exactly `rect.size`. Call it wherever
# `rect` or `viewport.size` moves.
func _rescale_screen() -> void:
	var view_scale := _crop_to_rect()
	_screen.scale = view_scale
	_shadow.scale = view_scale

# ⚠ A SCREEN IS NEVER STRETCHED to its rect's shape: %Screen and %Shadow show the canvas's centred
# part at the rect's aspect -- what `visible_rect_beside()` reports as visible -- cut on whole texels,
# as `Sprite2D.get_rect()` reads a region, and the returned scale draws that part at `rect.size`.
func _crop_to_rect() -> Vector2:
	var texture := Vector2(viewport.size)
	var shown := (texture * _shown_canvas() / Vector2(_design_size)).round()
	var region := Rect2((texture - shown) / 2.0, shown)
	_screen.region_rect = region
	_shadow.region_rect = region
	return rect.size / region.size

## The part of the canvas this picture shows, in canvas px: its centre at the rect's aspect.
func _shown_canvas() -> Vector2:
	return rect.size / cover_scale(Vector2(_design_size), rect.size)

# Re-renders a FROZEN texture at unchanged size, for a window restored from minimise -- the GPU
# may have discarded it. ⚠ A LIVE picture is NOT frozen and must never be forced to
# UPDATE_ONCE; guarded here, not at the call site -- PICTURE_WALL.md "Landmines".
func mark_for_rerender() -> void:
	if is_live: return
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

## Crisp NEAREST at rest, LINEAR only while zoom is changing THIS FRAME -- a pure pan must never flip it. Meaningful only while focused.
func update_filter(zoom_changed_this_frame: bool) -> void:
	_screen.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if zoom_changed_this_frame \
			else CanvasItem.TEXTURE_FILTER_NEAREST

## The wall-view selection highlight: a lift by `wall_selected_lift`. Only the lift exists; the frame glow awaits the frame art pass.
func set_selected(selected: bool) -> void:
	is_selected = selected
	_apply_position()

## Whether the selection cursor is on this picture. Stored, not derived, so the lift survives a re-pack -- see `_apply_position()`.
var is_selected : bool = false

## The single home for where this picture sits: `rect.centre`, plus the selection lift when it is selected and NOT focused -- focus wins.
func _apply_position() -> void:
	var lift := settings().wall_selected_lift if (is_selected and not is_focused) 			else Vector2.ZERO
	position = rect.centre + lift

## A NEW packed rect on an already-built picture: the geometry-only subset of `build()`, every render-gating flag untouched.
func reposition(new_rect: PictureRect) -> void:
	rect = new_rect
	_apply_position()
	_apply_rect_geometry(rect)

func _apply_rect_geometry(r: PictureRect) -> void:
	var frame_rect := WallPacker.frame_outer_rect(r)
	_frame.position = frame_rect.position - r.centre
	_frame.size = frame_rect.size
	_rescale_screen()

# Tweens this picture to `new_rect` over `duration`: position, frame geometry and both scales move
# together, so a live re-pack reads as one resize and slide rather than a size pop. `viewport.size`
# does not move during a reposition, so `_rescale_screen()`'s scale is a stable tween target.

# `rect` is updated IMMEDIATELY, not at completion, so hit-testing and selection read the real
# destination mid-tween. ⚠ The caller must `tween.set_parallel(true)`, or these run in sequence.
func animate_reposition(tween: Tween, new_rect: PictureRect, duration: float) -> void:
	var frame_rect := WallPacker.frame_outer_rect(new_rect)
	rect = new_rect
	var view_scale := _crop_to_rect()
	tween.tween_property(self, "position", new_rect.centre, duration)
	tween.tween_property(_frame, "position", frame_rect.position - new_rect.centre, duration)
	tween.tween_property(_frame, "size", frame_rect.size, duration)
	tween.tween_property(_screen, "scale", view_scale, duration)
	tween.tween_property(_shadow, "scale", view_scale, duration)

# The state blob a torn-down screen would hand over before being unloaded. ⚠ UNREACHABLE today:
# every screen stays instantiated for the session, and nothing implements `get_wall_state()`.
# `{}` is a valid blob -- it means freezing already preserves everything that screen needs.
func write_state_blob() -> Dictionary:
	if screen_root and screen_root.has_method(&"get_wall_state"):
		return screen_root.call(&"get_wall_state")
	return {}

# The scale at which `native_size` OVERFILLS `window_size` on every axis at rest: fill and crop,
# the LARGER of the two axis ratios. Never "fit", which leaves a frame sliver whenever the aspects
# differ. ⚠ The margin is CONDITIONAL -- PICTURE_WALL.md "Landmines".

# `overfill_margin` is REQUIRED, never defaulted here: it is a visible design choice living in
# `PlayerSettings.wall_overfill_margin`, and passing the live knob in keeps this function pure.
static func focused_scale(native_size: Vector2, window_size: Vector2,
		overfill_margin: float) -> float:
	var fill := cover_scale(native_size, window_size)
	if is_equal_approx(window_size.x / native_size.x, window_size.y / native_size.y):
		return fill
	return fill * overfill_margin

## ⚠ EVERY MOVE MUST AIM HERE: a move's destination IS its resting pose, or the settle cuts it.
static func resting_state(rect: PictureRect, window_size: Vector2,
		settings: PlayerSettings) -> Dictionary:
	return {"position": rect.centre,
			"zoom": focused_scale(rect.size, window_size, settings.wall_overfill_margin)}

## Frees this picture AND its SubViewport, which `build()` parented elsewhere, so `queue_free()` alone would leak it.
func teardown() -> void:
	if viewport and is_instance_valid(viewport):
		viewport.queue_free()
	queue_free()
