extends Attack

var target : RigidBody3D
var last_target_pos : Vector3
@onready var attack_range = $AttackRange
@export var damage_ratio : float = 1.0
@export var speed_ratio : float = 0.5

func attack():
	if can_cast():
		target = closest_enemy()
		if target:
			last_target_pos = target.global_position
			look_at(last_target_pos)
			step_pos = global_position
			animation_player.play(&'slash')
			set_physics_process(true)

func can_cast() -> bool:
	return !animation_player.is_playing() and cooldown.is_stopped()

func closest_enemy() -> Unit:
	var closest : Unit = null
	var shortest := INF
	for unit:Unit in attack_range.get_overlapping_bodies():
		if unit != body and unit.alive and unit.team != body.team:
			var dist := global_position.distance_squared_to(unit.global_position)
			if dist < shortest:
				shortest = dist
				closest = unit
	return closest

func stop():
	super.stop()
	cooldown.start()
	
var step_pos := Vector3.ZERO

func _physics_process(delta):
	#if can_rotate:
		#var target_transform := global_transform.looking_at(target.global_position)
		#global_transform = global_transform.interpolate_with(target_transform, rotate_speed * delta)
	var direction: Vector3 = step_pos - global_position
	direction.y = 0
	if direction.length_squared() > 1:
		direction = direction.normalized()	
	var cur_vel := Vector3(body.linear_velocity.x, 0, body.linear_velocity.z)
	var goal_vel : Vector3 = direction * body.stats.speed * speed_ratio
	goal_vel = cur_vel.move_toward(goal_vel, body.stats.accel_force * speed_ratio * delta)
	var needed_accel : Vector3 = (goal_vel - cur_vel) / delta
	needed_accel = needed_accel.limit_length(body.stats.accel_force_cap * speed_ratio)
	body.apply_force(needed_accel * body.mass)

#assume enemy in direction of (0,0,-1) and player at (0,0,0), pass in points based on this grid
func new_step(on_target:bool, v : Vector3):
	if is_instance_valid(target):
		last_target_pos = target.global_position
	var direction: Vector3 = last_target_pos - global_position
	var angle : float = Vector3.FORWARD.angle_to(direction)
	v = v.rotated(Vector3.FORWARD.cross(direction).normalized(), angle)
	if on_target:
		step_pos = last_target_pos + v
	else:
		step_pos = global_position + v
	global_transform = global_transform.looking_at(last_target_pos)

func _on_area_3d_area_entered(area:Area3D):
	if area.get_parent() is Unit:
		var target : Unit = area.get_parent()
		if body.team != target.team:
			target.damage(body.stats.damage * damage_ratio)
