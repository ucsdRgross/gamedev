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
func build(rect: PictureRect, entry: PictureEntry, viewports_parent: Node) -> void:
	position = rect.centre

	viewport = SubViewport.new()
	viewport.size = entry.design_size
	# ⚠ MUST be set explicitly -- a SubViewport defaults to LINEAR and does NOT inherit the
	# project's texture-filter setting (§1c; N1 pins this).
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewports_parent.add_child(viewport)
	if entry.scene:
		viewport.add_child(entry.scene.instantiate())

	var frame_rect := WallPacker.frame_outer_rect(rect)
	_frame.position = frame_rect.position - rect.centre
	_frame.size = frame_rect.size
	_frame.texture = entry.frame_texture

	var view_scale := rect.size / Vector2(entry.design_size)
	_screen.centered = true
	_screen.position = Vector2.ZERO
	_screen.scale = view_scale
	_screen.texture = viewport.get_texture()

	_shadow.centered = true
	_shadow.position = SHADOW_OFFSET
	_shadow.scale = view_scale
	_shadow.texture = viewport.get_texture()
	_shadow.self_modulate = Color(0.0, 0.0, 0.0, 0.35)

## Frees this picture AND its SubViewport (which build() parented elsewhere, so a plain
## queue_free() on this node would leak it).
func teardown() -> void:
	if viewport and is_instance_valid(viewport):
		viewport.queue_free()
	queue_free()
