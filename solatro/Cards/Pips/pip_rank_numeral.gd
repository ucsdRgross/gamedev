@tool
class_name PipRankNumeral
extends PipRank

const RANK_TEXTURE : Texture2D = preload("res://Assets/rank_pips.png")
const H_FRAMES: int = 13
const V_FRAMES: int = 5
@export_storage var original_value : float
func get_str() -> String: return "NumeralRank" + str(value)
func set_texture(polygon2d:Polygon2D) -> void:
	CardModifier.update_polygon_uv_frame(polygon2d, RANK_TEXTURE, H_FRAMES, V_FRAMES, value - 1)

func with_random() -> PipRank:
	return with_value(randi_range(1,13))
