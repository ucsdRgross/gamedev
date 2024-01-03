@tool
extends Marker3D

func _process(delta):
	var target = $"../circle/radius".global_position
	look_at(target, Vector3.FORWARD)
