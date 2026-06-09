@abstract class_name CardModifierType
extends CardModifier

const TYPE_TEXTURE : Texture2D = preload("res://Assets/card_types.png")
const H_FRAMES: int = 8
const V_FRAMES: int = 8

func set_texture(polygon2d: Polygon2D) -> void:
	update_polygon_uv_frame(polygon2d, TYPE_TEXTURE, H_FRAMES, V_FRAMES, get_frame())
