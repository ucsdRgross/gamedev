extends "res://Tests/Visual/tool_shot.gd"

#The REAL outline_atlas.tscn with its GLARE held at both ends of the sweep and the middle: the band
#must travel the whole square card, stopping `glare_buffer` short of each side.

const TOOL_SCENE := preload("res://Tools/outline_atlas.tscn")
## Where the shots pin the alert clock: the band's right end, its middle and its left end.
const PHASES : Array[float] = [0.0, 0.25, 0.5]

func stage() -> void:
	var tool : OutlineAtlas = TOOL_SCENE.instantiate()
	add_child(tool)
	tool.animate = false
	tool.alert_kind = CardOutline.Alert.GLARE
	for phase : float in PHASES:
		tool.phase = phase
		await settle()
		save("outline_atlas_glare_%03d.png" % roundi(phase * 100.0))
