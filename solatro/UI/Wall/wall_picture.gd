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

## Provisional shared shadow offset -- "one authored light position shared by the whole wall"
## (Q7=b, B10), authored here as a single constant because S25 ("shadows from one light position")
## is the step that actually tunes/relocates it; every picture uses the SAME offset regardless of
## its own position, which is what "shared" means. See ASSUMPTIONS.md.
const SHADOW_OFFSET := Vector2(18.0, 26.0)

## Builds this picture from its packed rect and authored entry: sizes/positions %Frame to the rect
## grown by frame_px (drawn first -- entirely outside the picture rect, Q38=a), creates this
## picture's SubViewport (size = design_size, filter forced to NEAREST -- the trap this repo has
## hit four times) and parents it under `viewports_parent`, then points %Screen and %Shadow at its
## ViewportTexture. `entry.scene` may be null ("registered but unbuilt", Q214=a) -- the viewport
## then simply renders nothing, which is correct and expected, not an error.
##
## §1.8's "never yet rendered" row: every picture starts at UPDATE_ONCE regardless of eventual
## focus (Q78=b) -- N3 pins that every texture is non-null before any focus() call happens.
func build(rect: PictureRect, entry: PictureEntry, viewports_parent: Node) -> void:
	position = rect.centre
	_design_size = entry.design_size

	viewport = SubViewport.new()
	viewport.size = entry.design_size
	# ⚠ MUST be set explicitly -- a SubViewport defaults to LINEAR and does NOT inherit the
	# project's texture-filter setting (§1c; N1 pins this).
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewports_parent.add_child(viewport)
	if entry.scene:
		screen_root = entry.scene.instantiate()
		# D3 (§1.6): every screen root is PAUSABLE by default — only focus() promotes it to ALWAYS.
		screen_root.process_mode = Node.PROCESS_MODE_PAUSABLE
		viewport.add_child(screen_root)

	var frame_rect := WallPacker.frame_outer_rect(rect)
	_frame.position = frame_rect.position - rect.centre
	_frame.size = frame_rect.size
	_frame.texture = entry.frame_texture

	var view_scale := rect.size / Vector2(entry.design_size)
	_screen.centered = true
	_screen.position = Vector2.ZERO
	_screen.scale = view_scale
	_screen.texture = viewport.get_texture()
	# H5 baseline: every picture starts non-focused, and H5 says non-focused always samples LINEAR
	# -- explicit because CanvasItem.texture_filter otherwise inherits the PROJECT default, which
	# this project sets to NEAREST (pixel art) and would be wrong here without this line.
	_screen.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	_shadow.centered = true
	_shadow.position = SHADOW_OFFSET
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

## Numerical safety margin, not a design knob (same role `wall_packer.gd`'s `_EPS` plays) -- nudges
## focused_scale() strictly past 1:1 coverage even when a picture's aspect exactly matches the
## window's, so the frame is GUARANTEED off-screen at rest (Q27=c: "always slightly overfills"),
## never merely flush with it.
const _OVERFILL_MARGIN := 1.02

## H3 (Q27=c): the scale that makes a picture of `native_size` OVERFILL `window_size` on every
## axis at rest -- "fill and crop" (the LARGER of the two axis ratios), never "fit" (the smaller
## one, which is exactly what would leave a frame sliver visible whenever the aspects don't match,
## the defect H3 exists to rule out). Pure function of the two sizes; no picture/camera state.
static func focused_scale(native_size: Vector2, window_size: Vector2) -> float:
	return maxf(window_size.x / native_size.x, window_size.y / native_size.y) * _OVERFILL_MARGIN

## Frees this picture AND its SubViewport (which build() parented elsewhere, so a plain
## queue_free() on this node would leak it).
func teardown() -> void:
	if viewport and is_instance_valid(viewport):
		viewport.queue_free()
	queue_free()
