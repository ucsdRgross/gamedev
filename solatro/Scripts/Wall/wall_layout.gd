@tool
## ⚠ `@tool` because the layout tool loads and saves this resource directly, and a non-`@tool`
## script loads in the editor as a placeholder whose unseen properties are dropped on save. See
## `picture_entry.gd`.
class_name WallLayout
extends Resource
## The authored wall pattern: spacing, the aspect clamps, and the picture list. Consumed whole by
## `WallPacker.pack()`; nothing else reads it.

@export var pictures : Array[PictureEntry] = []
## The picture the wall opens on.
@export var home_id : StringName = &"start_menu"
## Spacing between adjacent FRAME OUTER EDGES, in wall units.
@export var gap_px : float = 24.0
## The packing ellipse's aspect is clamped to this range, so a very wide or very tall window still
## produces a wall-shaped arrangement.
@export var ellipse_aspect_min : float = 1.2
@export var ellipse_aspect_max : float = 2.6
## Fraction of the packed extent left as breathing room around the wall in wall view.
@export var view_margin : float = 0.06
