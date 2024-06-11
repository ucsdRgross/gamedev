@tool
extends Node2D

@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var node_3d: Node3D = $Node3D

func _process(delta: float) -> void:
	var b := node_3d.transform.basis
	sprite_2d.transform.x = Vector2(b.x[0],b.x[1])
	sprite_2d.transform.y = Vector2(b.y[0],b.y[1])
	if b.z[2] < 0:
		modulate = Color.RED
	else:
		modulate = Color.WHITE
