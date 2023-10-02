@tool
extends Camera3D

@onready var target: Node3D = $"../.."

func _process(_delta):
	if not target is Node3D:
		if Engine.is_editor_hint():
			look_at(Vector3(0,1.4,0))
		return
		
	var look := target.global_position
	look.y -= 1
	look_at(look)
