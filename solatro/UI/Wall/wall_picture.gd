class_name WallPicture
extends Node2D
## One picture: frame + screen sprite + its own SubViewport (PLAN.md §1.7; NAMES.md). A Sprite2D
## showing a ViewportTexture, never a SubViewportContainer (GAP-001=b -- N5 pins the absence).
##
## ⚠ THE SUBVIEWPORT IS NOT A CHILD OF THIS NODE. NAMES.md's `%Viewports` is a container that lives
## once on `wall.tscn` itself, sibling to `%Pictures` (which is where WallPicture instances live) --
## build() is handed that container and parents the SubViewport there, so this node's own children
## are only %Shadow / %Frame / %Screen, exactly as NAMES.md fixes.

@onready var _shadow : Sprite2D = %Shadow
@onready var _frame : NinePatchRect = %Frame
@onready var _screen : Sprite2D = %Screen

## The SubViewport build() creates for this picture -- exposed so a caller can free it explicitly
## (it lives under `viewports_parent`, not under this node, so queue_free()ing this node alone
## would leak it).
var viewport : SubViewport = null

## §1.8's "focused / live" state, tracked so a caller can ask without re-deriving it. build()
## leaves this false -- construction is the "never yet rendered" row, not the "focused" one.
var is_focused : bool = false

## Remembered from build() so focus() can restore full design resolution without needing the
## caller to hand PictureEntry back in every time.
var _design_size : Vector2i

## §1.6's "screen root" — entry.scene instantiated under `viewport`, or null if the entry had no
## scene (Q214=a, e.g. &"book"). PROCESS_MODE_PAUSABLE by default (D3); focus()/unfocus() flip
## exactly this node between ALWAYS and PAUSABLE (D4). Nothing else in the chain needs an explicit
## override: WallPicture's own root is also explicit-PAUSABLE (wall_picture.tscn), so the ALWAYS
## inherited from Wall/%Pictures/%Viewports is cut off at these two points, never reaching further.
var screen_root : Node = null

## The packed rect build() was given -- kept so a caller (S36's `Wall`: spatial selection, wall-view
## framing/pan) can read id/centre/size/frame_px back without re-deriving them from this node's own
## children. Not fixed by NAMES.md; same category as `screen_root` above (ASSUMPTIONS.md).
var rect : PictureRect = null

## S24 (QR4=b, GAP-013): the ONE shared frame texture every framed picture references -- a simple
## beveled profile (light near the outer edge, dark near the inner edge closest to the picture),
## generated once and cached, never per-picture. Placeholder art: QR4=b's own text defers "the
## shader and art pass", so the actual pixels here are scaffolding, same category as
## `Tests/Visual`'s `_swatch_texture()` helpers -- not an author-tunable number under §1.8, since
## nothing downstream can vary it per picture (GAP-013 parks "colour" as unresolved; this is the
## fallback all framed pictures share until that lands). `_FRAME_CORNER_PX` is the fixed corner
## size (in TEXTURE pixels, not wall units) `%Frame`'s 9-slice patch margins are set to below --
## it travels WITH the texture as one bundle, not a second knob that could drift out of sync with
## the pixels it describes.
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

## Builds this picture from its packed rect and authored entry: sizes/positions %Frame to the rect
## grown by frame_px (drawn first -- entirely outside the picture rect, Q38=a), creates this
## picture's SubViewport (size = design_size, filter forced to NEAREST -- the trap this repo has
## hit four times) and parents it under `viewports_parent`, then points %Screen and %Shadow at its
## ViewportTexture. `entry.scene` may be null ("registered but unbuilt", Q214=a) -- the viewport
## then simply renders nothing, which is correct and expected, not an error.
##
## S30 (B7, Q211=a, Q141=a): `live_screen`, when given, is an ALREADY-INSTANTIATED, PERSISTENT
## node (`start_menu`/`map`/`deck` -- built once, kept alive for the whole session, never freed
## and rebuilt) REPARENTED here rather than instantiated fresh from `entry.scene`. "Screens are
## reparented unchanged" (PLAN §4 anti-scope item 1) -- this is the literal reparenting, not a
## copy. Takes priority over `entry.scene` if both are somehow given (should never happen in
## practice: an entry either owns a fresh-per-use scene, `game`/S31's own case, or a live screen
## the caller already built -- never both).
##
## §1.8's "never yet rendered" row: every picture starts at UPDATE_ONCE regardless of eventual
## focus (Q78=b) -- N3 pins that every texture is non-null before any focus() call happens.
func build(p_rect: PictureRect, entry: PictureEntry, viewports_parent: Node,
		live_screen: Node = null) -> void:
	rect = p_rect
	position = rect.centre
	_design_size = entry.design_size

	viewport = SubViewport.new()
	viewport.size = entry.design_size
	# ⚠ MUST be set explicitly -- a SubViewport defaults to LINEAR and does NOT inherit the
	# project's texture-filter setting (§1c; N1 pins this).
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewports_parent.add_child(viewport)
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

	var frame_rect := WallPacker.frame_outer_rect(rect)
	_frame.position = frame_rect.position - rect.centre
	_frame.size = frame_rect.size
	_frame.texture = entry.frame_texture
	# S24 (QR4=b): genuine nine-slice -- corners hold at a FIXED pixel size regardless of how far
	# this picture's own frame stretches the rect, only the edge bands between them stretch.
	# Identity check against the ONE shared texture specifically, not "any texture is assigned":
	# `_FRAME_CORNER_PX` is that texture's OWN corner size, and applying it to some OTHER,
	# differently-proportioned texture (e.g. a small diagnostic swatch elsewhere in this repo)
	# would push the patch margins past that texture's own bounds -- the exact degenerate-corner
	# failure mode `Tests/Visual`'s swatch-texture fixtures must stay immune to.
	if entry.frame_texture == shared_frame_texture():
		_frame.patch_margin_left = _FRAME_CORNER_PX
		_frame.patch_margin_top = _FRAME_CORNER_PX
		_frame.patch_margin_right = _FRAME_CORNER_PX
		_frame.patch_margin_bottom = _FRAME_CORNER_PX

	var view_scale := rect.size / Vector2(entry.design_size)
	_screen.centered = true
	_screen.position = Vector2.ZERO
	_screen.scale = view_scale
	_screen.texture = viewport.get_texture()
	# H5 baseline: every picture starts non-focused, and H5 says non-focused always samples LINEAR
	# -- explicit because CanvasItem.texture_filter otherwise inherits the PROJECT default, which
	# this project sets to NEAREST (pixel art) and would be wrong here without this line.
	_screen.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	# S25 (B10, Q7=b): the shadow's own offset is ONE authored light position, shared by every
	# picture on the wall regardless of its own location -- `wall_light_offset` (GAP-011's own
	# precedent: was a typed literal here, `SHADOW_OFFSET`, promoted to a knob; default (18, 26) is
	# that exact prior value, so this changes no observable behaviour at the default).
	_shadow.centered = true
	_shadow.position = SettingsManager.settings.wall_light_offset
	_shadow.scale = view_scale
	_shadow.texture = viewport.get_texture()
	_shadow.self_modulate = Color(0.0, 0.0, 0.0, 0.35)

## §1.8 "focused / live": UPDATE_ALWAYS, full design_size. The caller (S12+) is responsible for
## ensuring exactly one picture is focused at a time -- this method only enacts the state, it does
## not arbitrate focus.
func focus() -> void:
	is_focused = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.size = _design_size
	# D4 (§1.6): the live screen's root is flipped to ALWAYS. screen_root may be null (Q214=a) if
	# this picture has no scene, in which case there is nothing to flip.
	if screen_root:
		screen_root.process_mode = Node.PROCESS_MODE_ALWAYS
	# H5: becoming focused starts "at rest" -- no zoom has changed yet this frame.
	update_filter(false)

## §1.8 "any other" (non-focused): UPDATE_DISABLED -- render_target_update_mode stops, but the
## already-rendered texture persists on the GPU (Q82=a); sized down to the wall-view footprint via
## update_wall_view_size(), never left at full design_size while off-focus.
func unfocus(footprint_px: Vector2) -> void:
	is_focused = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	update_wall_view_size(footprint_px)
	# D3/D8 (§1.6): back to PAUSABLE the instant this picture stops being the live one — wall view
	# (D8) is simply every picture in this state at once, nothing extra required to enforce it.
	if screen_root:
		screen_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	# H5: everything non-focused samples LINEAR, unconditionally -- never NEAREST, regardless of
	# zoom state (update_filter()'s zoom branching only applies to the FOCUSED picture).
	_screen.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

## GAP-002 / Q86=a, Q87=b: "no resolution manager -- it is one property, written when the
## footprint changes." `SubViewport.size` is set directly from the picture's on-screen pixel
## footprint at wall-view zoom, each axis independently clamped below by
## `SettingsManager.settings.wall_view_min_texture_px` so a tiny footprint never asks the GPU for
## an unreasonably small (or zero) render target.
func update_wall_view_size(footprint_px: Vector2) -> void:
	var min_px := SettingsManager.settings.wall_view_min_texture_px
	viewport.size = Vector2i(maxi(int(footprint_px.x), min_px), maxi(int(footprint_px.y), min_px))

## §1.8 "window restored from minimise": UPDATE_ONCE for every picture, size UNCHANGED (Q208=b).
## Focus state is untouched -- if the caller's focus tracking needs the live picture back at
## UPDATE_ALWAYS afterward, that is a focus() call, not this one's job.
func mark_for_rerender() -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

## §1.7's filter swap (QR7=c, Q34, chart H5): crisp NEAREST at rest, LINEAR only while the camera's
## zoom is actively changing THIS FRAME -- pure pan/translation must never flip it. The caller (the
## wall's camera tracking, S12/S13) reports whether zoom changed; meaningful only while this
## picture is focused, but harmless to call regardless.
func update_filter(zoom_changed_this_frame: bool) -> void:
	_screen.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if zoom_changed_this_frame \
			else CanvasItem.TEXTURE_FILTER_NEAREST

## S36 (F11, Q70=c): the wall-view selection highlight -- "shape and motion, not colour," a lift off
## the wall. Only the lift half is built here: the frame GLOW half needs actual frame art/shader
## inputs S24 ("frame art parameters") deferred (QR4=b, GAP-013) rather than built, so this stays
## provisional -- same category `wall_overfill_margin`/`wall_light_offset` were in before GAP-011/
## S25 promoted them, not yet promoted itself because no coordinator ruling has named it. Left as
## a constant on purpose rather than silently promoted on my own authority (ASSUMPTIONS.md).
const _SELECTED_LIFT := Vector2(0.0, -14.0)

func set_selected(selected: bool) -> void:
	position = rect.centre + (_SELECTED_LIFT if selected else Vector2.ZERO)

## H3 (Q27=c): the scale that makes a picture of `native_size` OVERFILL `window_size` on every
## axis at rest -- "fill and crop" (the LARGER of the two axis ratios), never "fit" (the smaller
## one, which is exactly what would leave a frame sliver visible whenever the aspects don't match,
## the defect H3 exists to rule out). Pure function of its three inputs; no picture/camera state.
##
## GAP-011 (owner-answered a): `overfill_margin` is `PlayerSettings.wall_overfill_margin`
## (default 1.02) -- a REQUIRED parameter, never a literal or default value here, because §1.8
## forbids a typed-in-a-.gd number for anything an author could reasonably argue with (the margin
## is a visible design choice, not a float epsilon like `wall_packer.gd`'s `_EPS`; that was the
## exact miscategorisation GAP-011 corrects). Callers read the live knob (`SettingsManager.
## settings.wall_overfill_margin`, or a `settings: PlayerSettings` already in scope) and pass it
## in -- this function stays pure and untestable-only-by-eye either way.
static func focused_scale(native_size: Vector2, window_size: Vector2,
		overfill_margin: float) -> float:
	return maxf(window_size.x / native_size.x, window_size.y / native_size.y) * overfill_margin

## S28 (J2/Q128 override -- "zooms out just enough to reveal the BOTTOM frame only. Top, left and
## right stay covered"): camera position/zoom for a picture in Info mode, as a `{"position":
## Vector2, "zoom": float}` dictionary (`WallTransition.phase_bounds()`'s own return-shape
## precedent, not a new nested class for two values).
##
## Zoom is UNCHANGED from `focused_scale()`'s own at-rest fill value -- only the camera POSITION
## shifts downward. This is provably correct for EVERY frame_px, not just a symmetric one: at
## rest, H3 already guarantees the whole frame (all four edges) sits outside the visible rect, so
## `frame.top < visible_top_rest` always holds; shifting the camera straight down by `delta > 0`
## only INCREASES `visible_top` (`visible_top_rest + delta`), which can never cross back below
## `frame.top` (a fixed value the shift never touches) -- so the top edge cannot be revealed by
## ANY positive downward shift, regardless of how large. `delta` is chosen as the SMALLEST shift
## that brings the bottom frame edge into view plus `wall_frame_reveal_margin`'s own clearance
## (reused rather than a second near-identical knob -- ASSUMPTIONS.md): the same "extra share of
## the picture's size revealed" role it already plays for the transition's own zoom-out stop.
static func info_zoom_state(rect: PictureRect, window_size: Vector2,
		settings: PlayerSettings) -> Dictionary:
	var zoom := focused_scale(rect.size, window_size, settings.wall_overfill_margin)
	var frame_rect := WallPacker.frame_outer_rect(rect)
	var visible_bottom_rest := rect.centre.y + window_size.y / (2.0 * zoom)
	var target_bottom := frame_rect.end.y + settings.wall_frame_reveal_margin * rect.size.y
	var delta := maxf(target_bottom - visible_bottom_rest, 0.0)
	return {"position": rect.centre + Vector2(0.0, delta), "zoom": zoom}

## Frees this picture AND its SubViewport (which build() parented elsewhere, so a plain
## queue_free() on this node would leak it).
func teardown() -> void:
	if viewport and is_instance_valid(viewport):
		viewport.queue_free()
	queue_free()
