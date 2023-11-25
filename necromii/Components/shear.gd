@tool
extends Node3D

@export var shear_factor : float = 0

#function imitates this vertex shader
#render_mode world_vertex_coords;
#// Skew for when camera is top down so mesh has slight billboard affect
#// Only works if camera is always facing -Z
#uniform float skew_factor = 0.0;
#void vertex() {
#	VERTEX.z -= VERTEX.y * skew_factor;
#	VERTEX.z += NODE_POSITION_WORLD.y * skew_factor;
#}
func _process(delta):
	for child in get_children():
		child.global_position = global_position
		var shear := Basis()
		var s : Vector3 = global_transform.basis.get_scale()
		#this line of code specifically prevents values jumping when rotating by X, no idea why
		var sY : float = s.y * cos(global_rotation.y)
		shear.y.z = -shear_factor * 1.0/s.z * sY * abs(cos(global_rotation.y))
		shear.x.z = -shear_factor * 1.0/s.z * sY * sin(global_rotation.z)
		#removed shear affect if rotated by multiplying by zero
		#shears and rotations dont mix very well
		#X rotation very odd, acts like two different waves added together likely due to mixing with shear
		var rot_factor_x = (1 - abs(sin(global_rotation.x*2))) * (1 - abs(cos(PI/2 + global_rotation.x)))
		var rot_factor_z = cos(global_rotation.z)
		shear.y.z *= rot_factor_x * rot_factor_z
		shear.x.z *= rot_factor_x
		child.basis = global_transform.basis * shear
		
func _on_child_entered_tree(node : Node3D):
	node.top_level = true
