extends "res://Tests/Visual/tool_shot.gd"

#The REAL spotlight_tool.tscn held on its first section with the show up, so the glow around each lit
#card is still: its inner edge must follow the square card's staircase corners, not a sharp box.

#Loaded, not preloaded: the tool scene names user://settings.tres, which SettingsManager writes on boot.
const TOOL_PATH := "res://Tools/spotlight_tool.tscn"
## The board's card scale for the shot, large enough that the glow's corner texels can be counted.
const CARD_SCALE := 3.0
## Seconds for the dim, the show and the beams to finish easing in.
const EASE_SECS := 2.5

func stage() -> void:
	SettingsManager.settings.card_scale = CARD_SCALE
	var tool : SpotlightTool = (load(TOOL_PATH) as PackedScene).instantiate()
	add_child(tool)
	tool.play = false
	tool.section = 0
	tool.revealed = true
	await get_tree().create_timer(EASE_SECS).timeout
	await settle()
	save("spotlight_tool_glow.png")
	_rest_rigs(tool)
	await settle()
	save("spotlight_tool_glow_rest.png")

## Hold every card's rig at its rest pose; the tool keeps advancing it, at speed zero.
func _rest_rigs(tool : SpotlightTool) -> void:
	for card : CardVisual in tool._slot_card.values():
		var ap := card.get_node("AnimationPlayer") as AnimationPlayer
		ap.speed_scale = 0.0
		ap.seek(0.0, true)
