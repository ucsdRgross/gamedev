class_name PictureRect
extends RefCounted
## One packed result — id, centre, size, frame insets. What WallPacker.pack() returns one of per
## visible picture (PLAN.md §1.3; NAMES.md). `centre`/`size` describe the PICTURE's own screen
## rect (never the frame's outer rect -- callers grow it by `frame_px` themselves, same as the
## packer does internally for collision).

var id : StringName
var centre : Vector2
var size : Vector2
var frame_px : Vector4

## Convenience constructor -- every field is set at construction, never mutated after (the packer
## builds one immutable-by-convention result per picture, never edits one in place).
func _init(p_id: StringName, p_centre: Vector2, p_size: Vector2, p_frame_px: Vector4) -> void:
	id = p_id
	centre = p_centre
	size = p_size
	frame_px = p_frame_px
