extends Node3D

@export var remote_path : Node3D
@export_subgroup('Position')
@export var x := true
@export var y := true
@export var z := true

func _ready():
	if !remote_path:
		set_physics_process(false)

func _physics_process(delta):
	if x:
		remote_path.global_position.x = global_position.x
	if y:
		remote_path.global_position.y = global_position.y
	if z:
		remote_path.global_position.z = global_position.z
