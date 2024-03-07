extends Node3D

@onready var sprite_3d = $Sprite3D
@onready var sorute = $sorute

# Called when the node enters the scene tree for the first time.
func _ready():
	pass
	#print($MeshInstance3D2.basis)
#	for i in range(100):
#		var b = sorute.duplicate()
#		add_child(b)
#		b.position.z -= i * 1.0
#		for j in range(100):
#			var a = sprite_3d.duplicate()
#			add_child(a)
#			a.position.z -= i * 0.01
#			a.position.x += j * 1.0
			
			


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
