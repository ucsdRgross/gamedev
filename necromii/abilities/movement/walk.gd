extends Movement

@export var SPEED : float = 10
@export var ACCELERATION_FORCE : float = 200
@export var MAX_ACCELERATION_FORCE : float = 150

var look_direction := Vector3.BACK
func move(delta : float, direction : Vector3):
	if direction != Vector3.ZERO:
		look_direction = direction
	var cur_vel := Vector3(get_parent().linear_velocity.x, 0, get_parent().linear_velocity.z)
	var vel_dot := look_direction.dot(cur_vel.normalized())
	vel_dot = -sin(vel_dot*PI + PI/2)/2 + 1.5 if vel_dot < 0 else 1
	var goal_vel : Vector3 = direction * SPEED
	goal_vel = cur_vel.move_toward(goal_vel, ACCELERATION_FORCE * vel_dot * delta)
	#get_parent().navigation_agent.set_velocity(goal_vel)
	#goal_vel = await get_parent().navigation_agent.velocity_computed
	var needed_accel : Vector3 = (goal_vel - cur_vel) / delta
	needed_accel = needed_accel.limit_length(MAX_ACCELERATION_FORCE )#* vel_dot)
	get_parent().apply_force(needed_accel * get_parent().mass)
