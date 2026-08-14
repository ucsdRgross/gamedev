@tool
@abstract class_name CardModifierStamp
extends CardModifier
## `@tool` for the reason spelled out in `CardData`: without it a placeholder base strips every
## member of every concrete stamp/skill in the editor.

const STAMP_TEXTURE : Texture2D = preload("res://Assets/stamp_pips.png")
const H_FRAMES: int = 8
const V_FRAMES: int = 8

func set_texture(polygon2d: Polygon2D) -> void:
	CardOutline.frame_polygon(polygon2d, STAMP_TEXTURE, H_FRAMES, V_FRAMES, get_frame())
