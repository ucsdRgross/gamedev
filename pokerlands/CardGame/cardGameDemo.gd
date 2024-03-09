extends Control

@export var PlayerScene : PackedScene

# Called when the node enters the scene tree for the first time.
func _ready():
	var index = 1
	for i in GameManager.Players:
		var currentPlayer = PlayerScene.instantiate()
		currentPlayer.name = str(GameManager.Players[i].id)
		add_child(currentPlayer)
		for spawn in get_tree().get_nodes_in_group("PlayerSpawnPoint"):
			if spawn.name == str(GameManager.Players[i].index):
				currentPlayer.global_position = spawn.global_position
				currentPlayer.global_rotation = spawn.global_rotation
				
		if multiplayer.get_unique_id() == GameManager.Players[i].id:
			for camera : Camera2D in get_tree().get_nodes_in_group("PlayerCamera"):
				if camera.name == str(index):
						camera.visible = true
						camera.enabled = true
		index += 1
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
