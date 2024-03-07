extends Node2D

@onready var pointer = $pointer
@onready var points = $points
@onready var goal = $goal

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	var goal_vec = (goal.position - pointer.position)
	var total_dir : Vector2 = goal_vec.normalized()
	
	for p in points.get_children():
		var vec2 : Vector2 = p.position - pointer.position
		var dist = vec2.length_squared()
		vec2 *= p.to / dist
		total_dir += vec2
	
	total_dir = total_dir.normalized()
	
	pointer.look_at(total_dir + pointer.position)
