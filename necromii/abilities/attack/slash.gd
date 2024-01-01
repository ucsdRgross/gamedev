extends Attack

var damage : float = 1

var target : RigidBody3D

func attack(t : RigidBody3D):
	target = t
	look_at(target.global_position)
	step_pos = global_position
	animation_player.play(&'slash')
	lock()
	set_physics_process(true)

func can_cast() -> bool:
	return !animation_player.is_playing() and cooldown.is_stopped()

func stop():
	super.stop()
	cooldown.start()
	
var SPEED : float = 5
var ACCELERATION_FORCE : float = 100
var MAX_ACCELERATION_FORCE : float = 150
var step_pos := Vector3.ZERO
#var can_rotate := true
#var rotate_speed := 2

func _physics_process(delta):
	#if can_rotate:
		#var target_transform := global_transform.looking_at(target.global_position)
		#global_transform = global_transform.interpolate_with(target_transform, rotate_speed * delta)
	var direction: Vector3 = step_pos - global_position
	direction.y = 0
	if direction.length_squared() > 1:
		direction = direction.normalized()	
	var cur_vel := Vector3(get_parent().linear_velocity.x, 0, get_parent().linear_velocity.z)
	var goal_vel : Vector3 = direction * SPEED
	goal_vel = cur_vel.move_toward(goal_vel, ACCELERATION_FORCE * delta)
	var needed_accel : Vector3 = (goal_vel - cur_vel) / delta
	needed_accel = needed_accel.limit_length(MAX_ACCELERATION_FORCE)
	get_parent().apply_force(needed_accel * get_parent().mass)

#assume enemy in direction of (0,0,-1) and player at (0,0,0), pass in points based on this grid
func new_step(on_target:bool, v : Vector3):
	var direction: Vector3 = target.global_position - global_position
	var angle : float = Vector3.FORWARD.angle_to(direction)
	v = v.rotated(Vector3.FORWARD.cross(direction).normalized(), angle)
	if on_target:
		step_pos = target.global_position + v
	else:
		step_pos = global_position + v
	global_transform = global_transform.looking_at(target.global_position)
