extends "res://Tests/Visual/tool_shot.gd"

#The REAL fx_editor.tscn: every host at a zoom that fits the window, then the burning card close up,
#where the flames must wrap the square card's staircase corners.

const TOOL_SCENE := preload("res://Tools/fx_editor.tscn")
## The zooms the two views use: the whole row fits the window at the first, the card fills it at the second.
const OVERVIEW_ZOOM := 2.0
const CLOSE_ZOOM := 8.0
## Seconds of fire before each shot, so the flames have risen off the card.
const WARM_SECS := 1.5

func stage() -> void:
	var tool : FxEditor = TOOL_SCENE.instantiate()
	add_child(tool)
	var centre := get_viewport_rect().size * 0.5
	tool.zoom = OVERVIEW_ZOOM
	tool.position = centre
	await get_tree().create_timer(WARM_SECS).timeout
	await settle()
	save("fx_editor_overview.png")
	tool.zoom = CLOSE_ZOOM
	tool.position = centre - Vector2(tool._x(0), 0.0) * CLOSE_ZOOM
	await get_tree().create_timer(WARM_SECS).timeout
	await settle()
	save("fx_editor_card_fire.png")
