@tool
extends Node2D

@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var node_3d: Node3D = $Node3D
@onready var label = $Label

func _process(delta: float) -> void:
	var b := node_3d.transform.basis
	sprite_2d.transform.x = Vector2(b.x[0],b.x[1])
	sprite_2d.transform.y = Vector2(b.y[0],b.y[1])
	#print(node_3d.transform.basis.z.dot(Vector3(0,0,1)))
	sprite_2d.material.set('shader_parameter/squeeze', node_3d.transform.basis.z.dot(Vector3(0,1,0)) / 5)
	label.text = "%.2f" % b.x[0] + " %.2f\n" % b.x[1] + "%.2f" % b.y[0] + " %.2f" % b.y[1]
	if b.z[2] < 0:
		modulate = Color.RED
	else:
		modulate = Color.WHITE


func _on_area_2d_mouse_entered():
	print('entered')


func _on_area_2d_mouse_exited():
	print('exited')
