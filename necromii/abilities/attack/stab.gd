extends Attack

var target : RigidBody3D
@onready var attack_range = $AttackRange

func attack():
	if can_cast():
		target = closest_enemy()
		if target:
			look_at(target.global_position)
			step_pos = global_position
			animation_player.play(&'slash')
			set_physics_process(true)

func can_cast() -> bool:
	return !animation_player.is_playing() and cooldown.is_stopped()

func closest_enemy() -> Unit:
	var closest : Unit = null
	var shortest := INF
	for unit in attack_range.get_overlapping_bodies():
		if unit != body:
			var dist := global_position.distance_squared_to(unit.global_position)
			if dist < shortest:
				shortest = dist
				closest = unit
	return closest

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
	var cur_vel := Vector3(body.linear_velocity.x, 0, body.linear_velocity.z)
	var goal_vel : Vector3 = direction * SPEED
	goal_vel = cur_vel.move_toward(goal_vel, ACCELERATION_FORCE * delta)
	var needed_accel : Vector3 = (goal_vel - cur_vel) / delta
	needed_accel = needed_accel.limit_length(MAX_ACCELERATION_FORCE)
	body.apply_force(needed_accel * body.mass)

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