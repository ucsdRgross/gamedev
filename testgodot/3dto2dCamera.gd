extends MeshInstance3D

@onready var camera_2d = $"../SubViewport/Camera2D"
@onready var sub_viewport = $"../SubViewport"

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	camera_2d.position = global_to_viewport_relative(global_position)

#convert global position to 2d viewport pos
func global_to_viewport(pos : Vector3) -> Vector2:
	var new_pos := Vector2(pos.x, pos.z) - Vector2(position.x, position.z)
	# We need to convert it into the following range: 0 -> quad_size
	new_pos.x += scale.x
	new_pos.y += scale.y
	# Then we need to convert it into the following range: 0 -> 1
	new_pos.x = new_pos.x / (scale.x * 2) 
	new_pos.y = new_pos.y / (scale.y * 2)

	# Finally, we convert the position to the following range: 0 -> viewport.size
	new_pos.x = new_pos.x * sub_viewport.size.x
	new_pos.y = new_pos.y * sub_viewport.size.y
	return new_pos

func global_to_viewport_relative(pos : Vector3) -> Vector2:
	pos.x /= scale.x * 2
	pos.z /= scale.y * 2
	pos.x *= sub_viewport.size.x
	pos.z *= sub_viewport.size.y
	return Vector2(pos.x, pos.z)
