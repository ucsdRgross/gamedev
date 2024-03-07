extends Camera3D


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward",)
	position += Vector3(input_dir.x, 0, input_dir.y) * 0.1
