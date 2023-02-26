extends RigidBody3D

@onready var point = $"../AnimationPlayer/point"

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _integrate_forces(state):
	var direction : Vector3 = (point.global_position - global_position).normalized()
	var accel := 5
	var goal_vel := direction * 10 #* speed_modifier
	var cur_vel := Vector3(linear_velocity.x, 0, linear_velocity.z)
	var cur_dir := cur_vel.normalized()
	goal_vel = cur_dir.move_toward(goal_vel, accel )# * delta)
	#calculate necessary force to reach cur_vel
	var needed_accel : Vector3 = (goal_vel - cur_vel) / (1.0/60)
	var max_accel = 20
	needed_accel = needed_accel.limit_length(max_accel)
	needed_accel.y = 0
	apply_force(needed_accel * mass/2)
