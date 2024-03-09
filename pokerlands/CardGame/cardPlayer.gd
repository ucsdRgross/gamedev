extends Node
class_name Player

func _ready():
	$MultiplayerSynchronizer.set_multiplayer_authority(str(name).to_int())


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

#@rpc("any_peer","call_local")
func _on_color_rect_mouse_entered() -> void:
	if $MultiplayerSynchronizer.get_multiplayer_authority() == multiplayer.get_unique_id():
		$ColorRect.color = Color.AQUA

#@rpc("any_peer","call_local")
func _on_color_rect_mouse_exited() -> void:
	if $MultiplayerSynchronizer.get_multiplayer_authority() == multiplayer.get_unique_id():
		$ColorRect.color = Color.ALICE_BLUE
