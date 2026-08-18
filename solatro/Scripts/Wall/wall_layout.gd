@tool
## S34 (Q185=a, §1j): the layout tool loads/saves this resource directly -- a non-`@tool` script
## loads in the editor as a PLACEHOLDER and the editor silently drops any property it could not
## see on save. See `picture_entry.gd`'s own header for the full citation.
class_name WallLayout
extends Resource
## The authored PATTERN — gap, ellipse clamps, the picture list (rings themselves were rejected,
## GAP-009). Consumed whole by WallPacker.pack() (PLAN.md §1.3, as amended by GAP-009/GAP-010);
## nothing else reads it.
## PLAN.md §1.2 — every field, its type and its default are specified there; this transcribes it.

@export var pictures : Array[PictureEntry] = []
@export var home_id : StringName = &"start_menu"     ## Q9=a
@export var gap_px : float = 24.0                    ## between FRAME OUTER EDGES (Q14=a, Q36)
@export var ellipse_aspect_min : float = 1.2         ## Q10=c
@export var ellipse_aspect_max : float = 2.6
@export var view_margin : float = 0.06               ## Q5=b fill, this is the crop bias
