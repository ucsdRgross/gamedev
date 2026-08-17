@tool
## S34 (Q185=a, §1j): the layout tool loads/saves `layout_default.tres` directly, and a non-`@tool`
## script loads in the editor as a PLACEHOLDER -- reads still work but the editor SILENTLY DROPS
## any property it could not see on save (the exact `fx_editor.gd` lesson this repo already
## learned once, cited in its own header comment). `PlayerSettings` already carries the identical
## marker for the identical reason.
class_name PictureEntry
extends Resource
## One picture's authored data — id, scene, angle, size multiplier, frame thickness. Read by
## WallPacker (PLAN.md §1.3 as amended by GAP-009) to place it and by WallPicture (S10) to build
## it.
## PLAN.md §1.1 — every field, its type and its default are specified there; this transcribes it,
## EXCEPT `ring` (GAP-009: rings are rejected, the field is deleted, nothing ever read it),
## `slot`'s meaning (GAP-009 authored it as an angle in degrees; GAP-010's amendment -- rebalancing
## is now UNCONDITIONAL -- demoted it further: `slot` is a placement-ORDER key only, its numeric
## value never surviving into the resolved angle for any unlock set, complete or partial -- see
## ASSUMPTIONS.md), and `music` (S33/Q167=c -- added beyond §1.1's original list, same "new field,
## reversible, one defensible shape" reasoning `frame_texture` already establishes; see
## ASSUMPTIONS.md).

@export var id : StringName = &""              ## NAMES.md picture ids; unique within a WallLayout
@export var scene : PackedScene = null         ## null = registered but unbuilt (&"book", Q214=a)
@export var slot : int = 0                     ## GAP-010 (amended): placement-ORDER key, not an angle
@export var size_multiplier : float = 1.0      ## Q16=c, any positive value
@export var design_size : Vector2i = Vector2i(1152, 648)   ## per-screen, Q29=b
@export var frame_px : Vector4 = Vector4(24, 24, 24, 24)   ## L,T,R,B in wall units; Q36, Q37=a
@export var frame_texture : Texture2D = null   ## null = no drawn frame (Q35=c) but geometry stands
@export var unlocked_by_default : bool = false
@export var keep_aspect : bool = false         ## true = never stretched to window aspect (Q32=b)
@export var music : AudioStream = null         ## S33, Q167=c; null = silent, same convention as frame_texture
