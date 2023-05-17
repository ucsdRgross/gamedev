@tool
extends Camera3D

@export var target: Node3D

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	if not target is Node3D:
		if Engine.is_editor_hint():
			look_at(Vector3(0,1.4,0))
		return
		
	var look := target.global_position
	look_at(look)
