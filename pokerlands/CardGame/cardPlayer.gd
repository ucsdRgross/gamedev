extends Node2D
class_name Player

func _ready() -> void:
	print(str(name))
	$MultiplayerSynchronizer.set_multiplayer_authority(str(name).to_int())

var dragging = false

# Called every frame. 'delta' is the elapsed time since the previous frame.

func _process(delta: float) -> void:
	if dragging:
		global_position = lerp(global_position, get_global_mouse_position(), 15*delta)

func _input(event: InputEvent) -> void:
	if $MultiplayerSynchronizer.get_multiplayer_authority() == multiplayer.get_unique_id():
		if event is InputEventMouseMotion:
			dragging = (event.button_mask == 1)

#@rpc("any_peer","call_local")
func _on_color_rect_mouse_entered() -> void:
	if $MultiplayerSynchronizer.get_multiplayer_authority() == multiplayer.get_unique_id():
		$ColorRect.color = Color.AQUA

#@rpc("any_peer","call_local")
func _on_color_rect_mouse_exited() -> void:
	if $MultiplayerSynchronizer.get_multiplayer_authority() == multiplayer.get_unique_id():
		$ColorRect.color = Color.ALICE_BLUE
