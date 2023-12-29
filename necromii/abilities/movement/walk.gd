extends Movement
class_name Walk

@export var SPEED : float = 10
@export var ACCELERATION_FORCE : float = 200
@export var MAX_ACCELERATION_FORCE : float = 150

func move(delta : float, direction : Vector3):
	var cur_vel := Vector3(body.linear_velocity.x, 0, body.linear_velocity.z)
	var goal_vel : Vector3 = direction * SPEED
	goal_vel = cur_vel.move_toward(goal_vel, ACCELERATION_FORCE * delta)
	body.navigation_agent.set_velocity(goal_vel)
	goal_vel = await body.navigation_agent.velocity_computed
	var needed_accel : Vector3 = (goal_vel - cur_vel) / delta
	needed_accel = needed_accel.limit_length(MAX_ACCELERATION_FORCE)
	body.apply_force(needed_accel * body.mass)
