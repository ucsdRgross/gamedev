@tool
extends Node3D

@export var shear_factor : float = 0

func _process(delta):
	for child in get_children():
		child.global_position = global_position
		var shear := Basis()
		var s : Vector3 = global_transform.basis.get_scale()
		shear.y.z = -shear_factor * 1.0/s.z * s.y 
		#shear = shear.rotated(Vector3(0,1,0), -global_rotation.y)
		child.basis = global_transform.basis * shear
		#child.basis.x *= 2
		child.position.y += s.y/2
		
func _on_child_entered_tree(node : Node3D):
	node.top_level = true
