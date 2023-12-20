extends Node3D

@onready var mesh_instance_3d = $"../Camera3D/MeshInstance3D"

func _process(delta):
	mesh_instance_3d.mesh.material.set_shader_parameter(&"focal_point", global_position)
