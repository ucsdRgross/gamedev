@abstract class_name CardModifierSkill
extends CardModifier

const SKILL_TEXTURE : Texture2D = preload("res://Assets/skill_art.png")
const H_FRAMES: int = 16
const V_FRAMES: int = 16
@export_storage var active := false

func set_texture(polygon2d: Polygon2D) -> void:
	update_polygon_uv_frame(polygon2d, SKILL_TEXTURE, H_FRAMES, V_FRAMES, get_frame())
