@tool
## ⚠ `@tool` because the layout tool builds REAL `WallPicture` instances for its live preview. A
## non-`@tool` script loads as a PLACEHOLDER while that tool's scene is open in the editor, and
## calling `build()` on a placeholder throws "Attempt to call a method on a placeholder instance".
class_name WallPicture
extends Node2D
## One picture: frame + screen sprite + its own SubViewport. A `Sprite2D` showing a
## `ViewportTexture`, never a `SubViewportContainer`, which distorts when scaled.
##
## ⚠ THE SUBVIEWPORT IS NOT A CHILD OF THIS NODE. `%Viewports` lives once on `wall.tscn`, sibling
## to `%Pictures`; `build()` is handed that container and parents the SubViewport there. This
## node's own children are only %Shadow / %Frame / %Screen.

## ⚠ PUBLIC so an editor-side tool can assign its own tunable instance and have every knob it
## drags reach the real wall. Null in the shipped game, which then reads `SettingsManager`.
##
## ⚠ **THE OVERRIDE WINS IN BOTH CONTEXTS.** Making it editor-only is the bug `LightLayer` already
## paid for: the moment a tool scene is PLAYED rather than previewed, the wall would silently read
## the player's saved `settings.tres` while the tool's own panel kept showing its own resource —
## two instances, two sets of numbers, and the preview stops being evidence about anything.
static var editor_settings : PlayerSettings = null

## Which `PlayerSettings` the wall reads. The ONE place that answers it: `Wall`, `InfoCard` and
## `WallInput`'s callers all come through here rather than re-deriving the rule.
static func settings() -> PlayerSettings:
	if editor_settings: return editor_settings
	return FxAttachment.settings()

@onready var _shadow : Sprite2D = %Shadow
@onready var _frame : NinePatchRect = %Frame
@onready var _screen : Sprite2D = %Screen

## The SubViewport `build()` creates. Public so a caller can free it explicitly: it lives under
## `viewports_parent`, so `queue_free()`ing this node alone would leak it.
var viewport : SubViewport = null

## Whether this is the live picture. Tracked so a caller can ask without re-deriving it.
## `build()` leaves it false — construction is "never yet rendered", not "focused".
var is_focused : bool = false

## Remembered from build() so focus() can restore full design resolution without needing the
## caller to hand PictureEntry back in every time.
var _design_size : Vector2i

## `entry.scene` instantiated under `viewport`, or null when the entry has no scene.
## `PROCESS_MODE_PAUSABLE` by default; `focus()`/`unfocus()` flip exactly this node between ALWAYS
## and PAUSABLE. Nothing else in the chain needs an override: `WallPicture`'s own root is
## explicitly PAUSABLE in the scene, so the ALWAYS inherited from Wall/%Pictures/%Viewports is cut
## off at these two points and reaches no further.
var screen_root : Node = null

## The packed rect `build()` was given, kept so a caller can read id/centre/size/frame_px back
## without re-deriving them from this node's children.
var rect : PictureRect = null

## The entry's `background_texture`, remembered so `attach_screen()`/`detach_screen()` can show and
## hide it as `screen_root` comes and goes. A live screen always wins; this is the fallback. Null
## when the entry authored none.
var _background_texture : Texture2D = null
## The Sprite2D actually showing `_background_texture` inside `viewport`, or null when there is
## none to show (no texture authored, or a live screen currently covers it).
var _background : Sprite2D = null

## The ONE shared frame texture every framed picture references: a bevel profile, light at the
## outer edge and dark at the inner, generated once and cached. Placeholder art pending a shader
## and art pass, and not per-picture — `PictureEntry.frame_colour` is what varies per picture.
## `_FRAME_CORNER_PX` is the 9-slice corner size in TEXTURE pixels, kept beside the texture it
## describes rather than as a separate knob that could drift out of sync with these pixels.
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

## The nine-slice corner for `tex`, in texture pixels: the shared frame style's own
## `_FRAME_CORNER_PX`, clamped so opposing margins can never meet or cross. Any texture at least
## `2 * _FRAME_CORNER_PX` on both axes gets the authored corner; anything smaller gets the largest
## corner it can actually carry, which is a valid nine-slice rather than a degenerate one.
static func _frame_corner_px(tex: Texture2D) -> int:
	var smallest := mini(int(tex.get_width()), int(tex.get_height()))
	return mini(_FRAME_CORNER_PX, smallest / 2)

## Builds this picture from its packed rect and authored entry: sizes %Frame to the rect grown by
## `frame_px` (drawn entirely OUTSIDE the picture rect), creates the SubViewport under
## `viewports_parent`, and points %Screen and %Shadow at its `ViewportTexture`.
##
## `entry.scene` may be null — "registered but unbuilt". The viewport then renders nothing, which
## is expected, not an error.
##
## `live_screen`, when given, is an ALREADY-INSTANTIATED, session-long node (start_menu / map /
## deck) REPARENTED here rather than instantiated fresh from `entry.scene`, and takes priority over
## it. An entry has one or the other, never both.
##
## Every picture starts at UPDATE_ONCE regardless of eventual focus, so every texture is non-null
## before any `focus()` call.
func build(p_rect: PictureRect, entry: PictureEntry, viewports_parent: Node,
		live_screen: Node = null) -> void:
	rect = p_rect
	position = rect.centre
	_design_size = entry.design_size

	viewport = SubViewport.new()
	viewport.size = entry.design_size
	# ⚠ MUST be set explicitly: a SubViewport defaults to LINEAR and does NOT inherit the
	# project's texture-filter setting.
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewports_parent.add_child(viewport)
	_background_texture = entry.background_texture
	if live_screen:
		screen_root = live_screen
		# D3 (§1.6): every screen root is PAUSABLE by default — only focus() promotes it to ALWAYS.
		screen_root.process_mode = Node.PROCESS_MODE_PAUSABLE
		viewport.add_child(screen_root)
	elif entry.scene:
		screen_root = entry.scene.instantiate()
		# D3 (§1.6): every screen root is PAUSABLE by default — only focus() promotes it to ALWAYS.
		screen_root.process_mode = Node.PROCESS_MODE_PAUSABLE
		viewport.add_child(screen_root)
	else:
		# No live screen at construction -- show the authored background, if any.
		_show_background()

	var frame_rect := WallPacker.frame_outer_rect(rect)
	_frame.position = frame_rect.position - rect.centre
	_frame.size = frame_rect.size
	_frame.texture = entry.frame_texture
	# Per-picture tint over the shared bevel texture; white leaves its baked tone untouched.
	_frame.modulate = entry.frame_colour
	# Nine-slice: corners hold at a FIXED pixel size however far the frame stretches the rect;
	# only the edge bands between them stretch.
	#
	# ⚠ Gate this on the texture EXISTING, never on `entry.frame_texture == shared_frame_texture()`
	# reference identity. A texture loaded from `layout_default.tres` deserialises as a different
	# `ImageTexture` instance from the one this class generates, so an identity check never fires in
	# the real game and the 40x40 bevel smears across the whole NinePatchRect. `_frame_corner_px()`
	# carries the property that check was reaching for: a margin never exceeds half its texture.
	if entry.frame_texture:
		var corner := _frame_corner_px(entry.frame_texture)
		_frame.patch_margin_left = corner
		_frame.patch_margin_top = corner
		_frame.patch_margin_right = corner
		_frame.patch_margin_bottom = corner

	_screen.centered = true
	_screen.position = Vector2.ZERO
	_screen.texture = viewport.get_texture()
	# Every picture starts non-focused, and non-focused always samples LINEAR. Explicit because
	# `CanvasItem.texture_filter` otherwise inherits the project default of NEAREST.
	_screen.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	# ONE authored light position, shared by every picture on the wall whatever its location.
	_shadow.centered = true
	_shadow.position = settings().wall_light_offset
	_shadow.texture = viewport.get_texture()
	# Both sprites read the SAME render target, so both need the same scale -- and it can only be
	# computed once the texture is assigned. See `_rescale_screen()`.
	_rescale_screen()
	# ONE authored shadow opacity for the whole wall, like `wall_light_offset` above.
	_shadow.self_modulate = Color(0.0, 0.0, 0.0, settings().wall_shadow_opacity)

## Swaps this already-built picture's `screen_root` for a new live node, freeing whatever was
## there. Unlike `build()`'s `live_screen` — set once, for a session-long screen — this is for a
## picture whose CONTENT is rebuilt per use while the picture itself stays put on the wall, as
## `game` gets a fresh `GameView` per show. Frame, viewport and shadow are untouched.
func attach_screen(live_screen: Node) -> void:
	if screen_root and is_instance_valid(screen_root):
		screen_root.queue_free()
	# A live screen always wins over the authored background.
	_hide_background()
	screen_root = live_screen
	# D3 (§1.6): every screen root is PAUSABLE by default — only focus() promotes it to ALWAYS.
	screen_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	viewport.add_child(screen_root)

## Frees the current `screen_root`, leaving this picture showing its authored background — or,
## with none authored, the same "registered but unbuilt" rendering an absent `scene` produces.
func detach_screen() -> void:
	if screen_root and is_instance_valid(screen_root):
		screen_root.queue_free()
	screen_root = null
	# With the live screen gone, the authored background (if any) reappears.
	_show_background()

## Shows `_background_texture` inside `viewport`, stretched to fill `_design_size` exactly, the
## same way `%Screen` reads the WHOLE viewport whatever the texture's native size. A no-op with no
## texture, or with one already showing.
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

## Removes the authored background the instant a real screen takes over — it is never drawn behind
## a live `screen_root`.
func _hide_background() -> void:
	if not _background: return
	if is_instance_valid(_background): _background.queue_free()
	_background = null

## Makes this the live picture: UPDATE_ALWAYS at full `design_size`. The CALLER guarantees exactly
## one picture is focused at a time; this only enacts the state, it does not arbitrate focus.
func focus() -> void:
	is_focused = true
	# ⚠ Re-apply position: the selection LIFT is a wall-view affordance and a focused picture is
	# not in wall view. Without this a picture entered by keyboard or controller stays lifted while
	# the camera sits at `rect.centre`, showing a strip of frame and bare wall along the bottom
	# edge. A mouse-only player never sees it, because a click never selects.
	_apply_position()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.size = _design_size
	_rescale_screen()
	# The live screen's root is flipped to ALWAYS. `screen_root` may be null when this picture has
	# no scene, in which case there is nothing to flip.
	if screen_root:
		screen_root.process_mode = Node.PROCESS_MODE_ALWAYS
	# Becoming focused starts at rest -- no zoom has changed yet this frame.
	update_filter(false)
	# A focused picture is always fully opaque: a reduced-motion cross-fade may have left this
	# alpha mid-fade, and no resting state is ever partially faded.
	set_screen_alpha(1.0)

## Drops this out of focus: UPDATE_DISABLED, so rendering stops but the already-rendered texture
## persists on the GPU. Sized down to the wall-view footprint, never left at full `design_size`.
func unfocus(footprint_px: Vector2) -> void:
	is_focused = false
	# Leaving focus is exactly when a still-selected picture's lift becomes visible again.
	_apply_position()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	update_wall_view_size(footprint_px)
	# Back to PAUSABLE the instant this stops being the live picture. Wall view is simply every
	# picture in this state at once — nothing extra enforces it.
	if screen_root:
		screen_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	# Everything non-focused samples LINEAR unconditionally; `update_filter()`'s zoom branching
	# applies only to the FOCUSED picture.
	_screen.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# Same reasoning as focus() above -- never left mid-fade from a reduced-motion cross-fade.
	set_screen_alpha(1.0)

## `%Screen`'s opacity — the one thing `WallTransition._apply()` needs to drive a reduced-motion
## cross-fade. Exposed narrowly rather than the whole private node.
func set_screen_alpha(alpha: float) -> void:
	_screen.modulate.a = alpha

## Sets `SubViewport.size` straight from this picture's on-screen pixel footprint at wall-view
## zoom — no resolution manager, one property written when the footprint changes. Each axis is
## clamped below by `wall_view_min_texture_px` so a tiny footprint never asks the GPU for a
## degenerate render target.
func update_wall_view_size(footprint_px: Vector2) -> void:
	var min_px := settings().wall_view_min_texture_px
	viewport.size = Vector2i(maxi(int(footprint_px.x), min_px), maxi(int(footprint_px.y), min_px))
	_rescale_screen()

## Rescales %Screen and %Shadow so this picture draws at exactly `rect.size`.
## ⚠ Both sprites' texture IS the SubViewport render target, so what they draw is
## `viewport.size * scale` — the render-target resolution, NEVER `_design_size`. Since
## `update_wall_view_size()` rewrites `viewport.size` to the wall-view footprint, a scale computed
## against `_design_size` collapses the picture to `rect.size * footprint / design_size` the moment
## it unfocuses. The correct scale is `rect.size / viewport.size`, recomputed wherever either
## moves.
func _rescale_screen() -> void:
	var render_size := Vector2(viewport.size)
	if render_size.x <= 0.0 or render_size.y <= 0.0: return
	var view_scale := rect.size / render_size
	_screen.scale = view_scale
	_shadow.scale = view_scale

## Re-renders a FROZEN texture at unchanged size, for a window restored from minimise — the GPU
## may have discarded it.
##
## ⚠ A FOCUSED picture is NOT frozen: it is UPDATE_ALWAYS and has nothing to restore. Forcing
## UPDATE_ONCE on it renders one more frame and then stops forever, since nothing calls `focus()`
## again until the player leaves and re-enters — turning a live game into a still image for the
## rest of the session. Guarded here, not at the call site, so a second caller cannot lose it.
func mark_for_rerender() -> void:
	if is_focused: return
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

## Crisp NEAREST at rest, LINEAR only while the camera's zoom is actively changing THIS FRAME —
## a pure pan must never flip it. The caller reports whether zoom changed. Meaningful only while
## focused, but harmless to call regardless.
func update_filter(zoom_changed_this_frame: bool) -> void:
	_screen.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if zoom_changed_this_frame \
			else CanvasItem.TEXTURE_FILTER_NEAREST

## The wall-view selection highlight: shape and motion, not colour — a lift off the wall by
## `wall_selected_lift`. Only the lift half exists; the frame glow half awaits the frame art pass.
func set_selected(selected: bool) -> void:
	is_selected = selected
	_apply_position()

## Whether the wall-view selection cursor is on this picture. Stored, not derived, so the lift
## survives a re-pack — see `_apply_position()`.
var is_selected : bool = false

## The single home for where this picture sits: its rect's centre, plus the selection lift when it
## is BOTH selected and not focused — focus wins, because the lift is a wall-view affordance.
## Everything that moves the picture goes through here, so the two rules cannot disagree.
func _apply_position() -> void:
	var lift := settings().wall_selected_lift if (is_selected and not is_focused) 			else Vector2.ZERO
	position = rect.centre + lift

## Applies a NEW packed rect to an already-built picture: the geometry-only subset of `build()`.
## The viewport, `screen_root` and every render-gating flag are untouched — only WHERE this
## picture sits changes, which is all a silent re-pack after an unlock needs.
func reposition(new_rect: PictureRect) -> void:
	rect = new_rect
	_apply_position()
	_apply_rect_geometry(rect)

func _apply_rect_geometry(r: PictureRect) -> void:
	var frame_rect := WallPacker.frame_outer_rect(r)
	_frame.position = frame_rect.position - r.centre
	_frame.size = frame_rect.size
	_rescale_screen()

## Tweens this picture from its current rect to `new_rect` over `duration`, on the given tween:
## position, frame geometry and both scales move together, so a live re-pack reads as one resize
## and slide rather than a size pop.
## `rect` is updated IMMEDIATELY, not at completion, so hit-testing and selection read the real
## destination mid-tween — state updates now, the tween is only visual catch-up.
## ⚠ The caller must `tween.set_parallel(true)`, or these properties animate in sequence.
func animate_reposition(tween: Tween, new_rect: PictureRect, duration: float) -> void:
	var frame_rect := WallPacker.frame_outer_rect(new_rect)
	# Same `rect.size / viewport.size` as `_rescale_screen()`; `viewport.size` does not move during
	# a reposition, so the tween target is stable for the whole duration.
	var view_scale := new_rect.size / Vector2(viewport.size)
	rect = new_rect
	tween.tween_property(self, "position", new_rect.centre, duration)
	tween.tween_property(_frame, "position", frame_rect.position - new_rect.centre, duration)
	tween.tween_property(_frame, "size", frame_rect.size, duration)
	tween.tween_property(_screen, "scale", view_scale, duration)
	tween.tween_property(_shadow, "scale", view_scale, duration)

## The state blob a torn-down screen would hand over before being unloaded.
## ⚠ UNREACHABLE today: every screen stays instantiated for the whole session, so nothing tears one
## down and nothing calls this. Implemented anyway so screen eviction, if it is ever built, is a
## measurement away rather than a rewrite. Delegates to `screen_root.get_wall_state()` when the
## live screen opts into that method; nothing implements it yet. `{}` is a valid blob — it means
## freezing already preserves everything that screen needs.
func write_state_blob() -> Dictionary:
	if screen_root and screen_root.has_method(&"get_wall_state"):
		return screen_root.call(&"get_wall_state")
	return {}

## The scale at which a picture of `native_size` OVERFILLS `window_size` on every axis at rest —
## fill and crop, the LARGER of the two axis ratios. Never "fit", which leaves a frame sliver
## visible whenever the aspects differ. A pure function of its three inputs.
##
## ⚠ The margin is CONDITIONAL. When the two axis ratios are already equal there is no frame to
## hide, so the exact fill ratio is returned with the margin untouched. Applied unconditionally it
## crops REAL UI in the ordinary 16:9-in-16:9 case — the start-menu's bottom button row loses a
## slice at both edges.
##
## `overfill_margin` is a REQUIRED parameter, never defaulted here: it is a visible design choice
## and lives in `PlayerSettings.wall_overfill_margin`. Callers pass the live knob in, which keeps
## this function pure.
static func focused_scale(native_size: Vector2, window_size: Vector2,
		overfill_margin: float) -> float:
	var x_ratio := window_size.x / native_size.x
	var y_ratio := window_size.y / native_size.y
	var fill := maxf(x_ratio, y_ratio)
	if is_equal_approx(x_ratio, y_ratio):
		return fill
	return fill * overfill_margin

## Camera position/zoom for a picture in Info mode, as `{"position": Vector2, "zoom": float}`:
## just enough reveal to show the BOTTOM frame, with top, left and right still covered.
##
## Zoom is UNCHANGED from `focused_scale()`'s at-rest value — only POSITION shifts downward. That
## is correct for every `frame_px`, symmetric or not: at rest the whole frame sits outside the
## visible rect, so `frame.top < visible_top`; shifting down by `delta > 0` only increases
## `visible_top`, which can never cross back below the fixed `frame.top`. `delta` is the SMALLEST
## shift bringing the bottom frame edge into view plus `wall_frame_reveal_margin`'s clearance,
## reused rather than duplicated as a second near-identical knob.
static func info_zoom_state(rect: PictureRect, window_size: Vector2,
		settings: PlayerSettings) -> Dictionary:
	var zoom := focused_scale(rect.size, window_size, settings.wall_overfill_margin)
	var frame_rect := WallPacker.frame_outer_rect(rect)
	var visible_bottom_rest := rect.centre.y + window_size.y / (2.0 * zoom)
	var target_bottom := frame_rect.end.y + settings.wall_frame_reveal_margin * rect.size.y
	var delta := maxf(target_bottom - visible_bottom_rest, 0.0)
	return {"position": rect.centre + Vector2(0.0, delta), "zoom": zoom}

## This picture's info-mode entry. Strings are resolved HERE, not stored on the entry —
## `InfoEntry` is "already localised by the caller" — under the same `<THING>` /
## `<THING>_DESCRIPTION` key pair `localization.csv` uses for every card.
##
## The visual is a `TextureRect` on this picture's own live `ViewportTexture`: a real copy of the
## thing hovered, not a stand-in. `InfoCard.show_entry()` takes ownership and frees it on the next
## entry, which is why a fresh one is built per call rather than cached.
func get_info() -> InfoEntry:
	var entry := InfoEntry.new()
	var key := String(rect.id).to_upper()
	entry.title = TRANSLATION.find(StringName("WALL_PICTURE_" + key))
	entry.body = TRANSLATION.find(StringName("WALL_PICTURE_" + key + "_DESCRIPTION"))
	if viewport:
		var preview := TextureRect.new()
		preview.texture = viewport.get_texture()
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.custom_minimum_size = _INFO_PREVIEW_SIZE
		entry.visual = preview
	return entry

## The on-card size of `get_info()`'s preview — internal card layout, not a player-tunable knob.
const _INFO_PREVIEW_SIZE := Vector2(160.0, 90.0)

## Frees this picture AND its SubViewport (which build() parented elsewhere, so a plain
## queue_free() on this node would leak it).
func teardown() -> void:
	if viewport and is_instance_valid(viewport):
		viewport.queue_free()
	queue_free()
