extends MeshInstance3D

@onready var player_2 = $"../../Player2"

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta):
	mesh.material.set_shader_parameter(&"focal_point", player_2.global_position)
