@tool
## ⚠ `@tool` because the layout tool loads and saves `layout_default.tres` directly. A non-`@tool`
## script loads in the editor as a PLACEHOLDER: reads work, but the editor SILENTLY DROPS any
## property it could not see when saving. `PlayerSettings` carries the same marker for the same
## reason.
class_name PictureEntry
extends Resource
## One picture's authored data. Read by `WallPacker` to place it and `WallPicture` to build it.

## Unique within a `WallLayout`.
@export var id : StringName = &""
## The screen this picture hosts. null = registered but unbuilt.
@export var scene : PackedScene = null
## Placement-ORDER key, not an angle: the packer derives every angle itself, so this value only
## decides where the picture falls in the sequence.
@export var slot : int = 0
## Scales this picture relative to the others. Any positive value.
@export var size_multiplier : float = 1.0
## The authored resolution of `scene`, per picture.
@export var design_size : Vector2i = Vector2i(1152, 648)
## Frame thickness, L/T/R/B, in wall units.
@export var frame_px : Vector4 = Vector4(24, 24, 24, 24)
## null = no frame is drawn, but the frame GEOMETRY still occupies its space.
@export var frame_texture : Texture2D = null
@export var unlocked_by_default : bool = false
## true = the picture is never stretched to the window aspect.
@export var keep_aspect : bool = false
## Plays while this picture is focused. null = silent.
@export var music : AudioStream = null
## Per-picture tint over the one shared frame texture, applied as `%Frame.modulate`. White leaves
## the texture's own tone unchanged.
@export var frame_colour : Color = Color(1.0, 1.0, 1.0, 1.0)
## The resting image shown inside this picture whenever it has no live screen. null = nothing
## drawn, the same look an absent `scene` produces.
@export var background_texture : Texture2D = null
