extends Node2D

@onready var goal = $"../goal"
@onready var area_2d = $Area2D
@onready var pointer = $"."

@onready var neg = (randi() & 2) - 1

# Called when the node enters the scene tree for the first time.
func _ready():
	print(neg)
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	var goal_vec = (goal.position - pointer.position).normalized()
	var total_dir : Vector2 = goal_vec
	
	for p in area_2d.get_overlapping_areas():
		var vec2 : Vector2 = p.position - pointer.position
		var weight = p.to * (1-(vec2.length_squared() / ($Area2D/CollisionShape2D.shape.radius ** 2)))
		#vec2 *= p.to / dist
		vec2 = vec2.normalized()
		var shaping = 0.4 * vec2.dot(goal_vec) * neg
		vec2 = vec2.rotated(shaping)
		total_dir +=  vec2 * weight * 1
	
	#total_dir = total_dir.normalized()
	
	pointer.look_at(total_dir + pointer.position)
	
	
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward",)
	position += input_dir * 2
	
	if Input.is_action_pressed("move_jump"):
		position += transform.x * 2
