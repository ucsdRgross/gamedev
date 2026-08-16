class_name PictureEntry
extends Resource
## One picture's authored data — id, scene, angle, size multiplier, frame thickness. Read by
## WallPacker (PLAN.md §1.3 as amended by GAP-009) to place it and by WallPicture (S10) to build
## it.
## PLAN.md §1.1 — every field, its type and its default are specified there; this transcribes it,
## EXCEPT `ring` (GAP-009: rings are rejected, the field is deleted, nothing ever read it) and
## `slot`'s meaning (GAP-009: an authored angle in degrees around the wall's centre, not a
## within-ring order -- see ASSUMPTIONS.md).

@export var id : StringName = &""              ## NAMES.md picture ids; unique within a WallLayout
@export var scene : PackedScene = null         ## null = registered but unbuilt (&"book", Q214=a)
@export var slot : int = 0                     ## GAP-009: authored angle in DEGREES, and placement order
@export var size_multiplier : float = 1.0      ## Q16=c, any positive value
@export var design_size : Vector2i = Vector2i(1152, 648)   ## per-screen, Q29=b
@export var frame_px : Vector4 = Vector4(24, 24, 24, 24)   ## L,T,R,B in wall units; Q36, Q37=a
@export var frame_texture : Texture2D = null   ## null = no drawn frame (Q35=c) but geometry stands
@export var unlocked_by_default : bool = false
@export var keep_aspect : bool = false         ## true = never stretched to window aspect (Q32=b)
