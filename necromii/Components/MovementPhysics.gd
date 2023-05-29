extends Node

@export var max_speed : float = 8
@export var acceleration : float = 200
@export var max_acceleration_force :float = 150

@export var ride_height := 0.5
@export var ride_spring_strength := 200.0
@export var ride_spring_damper := 10.0

@export var upright_spring_strength := 100.0
@export var upright_spring_damper := 0.3

@export var jump_velocity := 7.5
@export var tilt_factor := Vector3(0,0.25,0)
# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

var look_direction := Vector3.BACK
var movement_velocity := Vector3.ZERO
var floor_velocity := Vector3.ZERO

@onready var body : RigidBody3D = get_parent()
@onready var ground_ray : RayCast3D = $GroundRay
@onready var jump_timer = $JumpTimer

signal jumping

func _physics_process(delta):
	ground_ray.global_rotation = Vector3.DOWN
	
func is_on_floor():
	return ground_ray.is_colliding()

func update(delta : float, velocity : Vector3):
	update_movement(delta, velocity)
	update_ride_spring(delta)
	update_upright_force(delta)

func update_movement(delta : float, velocity : Vector3):
	var direction : Vector3 = Vector3(velocity.x, 0, velocity.z).normalized()
	if direction != Vector3.ZERO:
		look_direction = direction

	var cur_vel := Vector3(body.linear_velocity.x, 0, body.linear_velocity.z)
	var cur_dir := cur_vel.normalized()
	var vel_dot := look_direction.dot(cur_dir)
	
	#turn around increase, double acceleration when turning around
	if vel_dot < 0:
		vel_dot = -sin(vel_dot*PI + PI/2)/2 + 1.5
	else:
		vel_dot = 1
	
	var accel := acceleration * vel_dot
	var goal_vel : Vector3 = velocity
	goal_vel = cur_vel.move_toward(goal_vel + floor_velocity, accel * delta)
	#calculate necessary force to reach goal_vel
	var needed_accel : Vector3 = (goal_vel - cur_vel) / delta
	var max_accel = max_acceleration_force * vel_dot #* acceleration_modifier
	needed_accel = needed_accel.limit_length(max_accel)
	#applying force offset from center causes tilt
	var tilt := tilt_factor
	if goal_vel.dot(needed_accel) <= 0:
		tilt *= -1.5
	body.apply_force(needed_accel, tilt)
	movement_velocity = goal_vel
	
func update_upright_force(delta : float):
	var currentRot := body.basis.get_rotation_quaternion()
	var uprightTargetRot := Transform3D.IDENTITY.looking_at(look_direction, Vector3.UP).basis.get_rotation_quaternion()
	var toGoal := shortest_rotation(uprightTargetRot, currentRot)
	var rot_axis : Vector3 = toGoal.get_axis()
	#rot_axis = rot_axis.normalized()
	var rot_radians : float = deg_to_rad(toGoal.get_angle())
	var force : Vector3 = ((rot_axis * (rot_radians * upright_spring_strength)) - (body.angular_velocity * upright_spring_damper)) / delta
	#avoid bug, best guess is that applying tiny forces causes floating point error on basis causing it to be not normalized
	if force.length_squared() > 0.01:
		body.apply_torque(force)

func update_ride_spring(delta : float):
	if is_on_floor():
		var ray_dir := Vector3.DOWN
		#if ray hits another rigidbody
		var collider_vel := Vector3.ZERO
		var hit_body = ground_ray.get_collider()
		if "velocity" in hit_body:
			collider_vel = ground_ray.get_collider().velocity
			
		var ray_dir_vel := ray_dir.dot(body.linear_velocity)
		var collider_dir_vel := ray_dir.dot(collider_vel)
		
		var rel_vel := ray_dir_vel - collider_dir_vel
		
		var ray_dist : float = ground_ray.global_position.distance_to(ground_ray.get_collision_point())
		var x := ray_dist - ride_height 

		var spring_force := (x * ride_spring_strength) - (rel_vel * ride_spring_damper)
		body.apply_force(ray_dir * spring_force * body.mass * 60 * delta)
		
#		if hit_body is CharacterBody3D:
#			#account for platform movement
#			print(hit_body.velocity)
#			apply_force(Vector3(hit_body.velocity.x, 0, hit_body.velocity.z))
		
#		if hit_body is RigidBody3D: #.has_method("apply_force"):
#			var relative_pos : Vector3 = ground_ray.get_collision_point() - hit_body.global_position
#			relative_pos.y = 0
#			hit_body.apply_force(ray_dir * -spring_force, relative_pos)
#			#print(hit_body.linear_velocity)
#			floor_velocity = hit_body.linear_velocity
#			var ang := Vector3(-hit_body.angular_velocity.z, hit_body.angular_velocity.y, hit_body.angular_velocity.x) * relative_pos.length()
#			#do apply force here instead using same logic as movement, calculate force necessary to reach floor velocity
#			#calculate necessary force to reach goal_vel
#			var needed_accel : Vector3 = (floor_velocity) / (1.0/60)
#			#applying force offset from center causes tilt
#			var tilt_factor := Vector3(0,0.25,0)
#			#apply_force(needed_accel * 0.75, tilt_factor)
#
#
#			#linear_velocity = movement_velocity + floor_velocity
#
##			apply_force(Vector3(hit_body.linear_velocity.x, 0, hit_body.linear_velocity.z))
##
##			#account for platform rotation
##			var ang := Vector3(-hit_body.angular_velocity.z, hit_body.angular_velocity.y, hit_body.angular_velocity.x)
##			apply_force(ang * relative_pos.length() * 10)
#		else:
#			floor_velocity = Vector3.ZERO
			
func jump():
	if is_on_floor() and jump_timer.is_stopped():
		body.linear_velocity.y = 0
		body.apply_central_impulse(Vector3.UP * jump_velocity * body.mass + Vector3.UP * gravity)
		ground_ray.enabled = false
		jump_timer.start()
		jumping.emit()


func _on_jump_timer_timeout():
	ground_ray.enabled = true

#set look direction when character is not moving
func set_look_direction(dir : Vector3):
	look_direction = dir
	
func shortest_rotation(a : Quaternion, b : Quaternion) -> Quaternion:
	if a.dot(b) < 0:
		return a * (b * -1).inverse()
	else:
		return a * b.inverse()


