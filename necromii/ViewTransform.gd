@tool
extends MeshInstance3D


@export var t : Transform3D

func _process(delta):
	t = transform
