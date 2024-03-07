@tool
extends Node3D

@onready var mesh = $MeshInstance3D2

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	mesh.position = position
	var shear := Basis()
	var s : Vector3 = basis.get_scale()
	shear.y.z = -1 * 1/s.z * s.y 
	mesh.basis = basis * shear

