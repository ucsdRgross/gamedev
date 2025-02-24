extends RigidBody3D

@onready var ground_ray = $GroundRay
@onready var miss_study = $MissStudy
@onready var wheel = $wheel

const max_speed : float = 8
const acceleration : float = 200
const max_acceleration_force :float = 150

const ride_height := 1.5
const ride_spring_strength := 200.0
const ride_spring_damper := 10.0

const upright_spring_strength := 100.0
const upright_spring_damper := 0.3

const jump_velocity := 7.5
const jump_duration := 1.0/3
var jump_timer := Timer.new()
# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

var look_direction := Vector3.FORWARD
var movement_velocity := Vector3.ZERO
var floor_velocity := Vector3.ZERO

#floating capsule theory
#https://www.youtube.com/watch?v=qdskE8PJy6Q

enum STATES {
	IDLE,
	WALK,
	RUN,
	JUMP
}

var state = STATES.IDLE

func _ready():
	add_child(jump_timer)
	jump_timer.one_shot = true
	jump_timer.autostart = true
	
	#var anim : AnimationPlayer = miss_study.AnimationPlayer

func _integrate_forces(state):
	ground_ray.global_rotation = Vector3.ZERO
	
	match state:
		STATES.IDLE:
			pass
	
	update_movement()
	update_ride_spring()
	update_upright_force()
	update_animation()
	rotate_wheel()
	
	if jump_timer.is_stopped():
		ground_ray.enabled = true
	
	if Input.is_action_just_pressed("ui_accept") and ground_ray.is_colliding() and jump_timer.is_stopped():
		linear_velocity.y = 0
		apply_central_impulse(Vector3.UP * jump_velocity * gravity)
		ground_ray.enabled = false
		jump_timer.start(jump_duration)
		
		
	
	transform = transform.orthonormalized()

func update_animation():
	var cur_vel := Vector3(linear_velocity.x, 0, linear_velocity.z) - floor_velocity
	var v : float = cur_vel.length()/max_speed
	$MissStudy/AnimationTree["parameters/Blend3/blend_amount"] = clamp(v * 2 - 1, -1, 1)
	
	
func rotate_wheel():
	var turn = Vector3(linear_velocity.x, 0, linear_velocity.z).length() / (2 * PI * wheel.scale.x / 2) * 0.1 * 1.5
	var anim : AnimationPlayer = $MissStudy/AnimationPlayer
	anim.speed_scale = turn * 2 #* 10
	#print(turn)
	wheel.rotate(Vector3.LEFT, turn)

func update_movement():
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := Vector3(input_dir.x, 0, input_dir.y).normalized()
	if direction:
		look_direction = direction
	var cur_vel := Vector3(linear_velocity.x, 0, linear_velocity.z)
	var cur_dir := cur_vel.normalized()
	var vel_dot := direction.dot(cur_dir)
	
	#turn around increase, double acceleration when turning around
	if vel_dot < 0:
		vel_dot = -sin(vel_dot*PI + PI/2)/2 + 1.5
	else:
		vel_dot = 1
	
	var accel := acceleration * vel_dot
	var goal_vel := direction * max_speed#* speed_modifier
	goal_vel = cur_vel.move_toward(goal_vel + floor_velocity, accel * (1.0/60))# * delta)
	#calculate necessary force to reach goal_vel
	var needed_accel : Vector3 = (goal_vel - cur_vel) / (1.0/60)
	var max_accel = max_acceleration_force * vel_dot #* acceleration_modifier
	needed_accel = needed_accel.limit_length(max_accel)
	needed_accel.y = 0
	#applying force offset from center causes tilt
	var tilt_factor := Vector3(0,0.2,0)
	apply_force(needed_accel, tilt_factor)
	movement_velocity = goal_vel
	
	
	

func update_upright_force():
	var currentRot := basis.get_rotation_quaternion()
	var _uprightTargetRot := Transform3D.IDENTITY.looking_at(look_direction, Vector3.UP).basis.get_rotation_quaternion()
	var toGoal := shortest_rotation(_uprightTargetRot, currentRot)
	var rot_axis : Vector3 = toGoal.get_axis().normalized()
	var rot_radians : float = deg_to_rad(toGoal.get_angle())
	apply_torque_impulse((rot_axis * (rot_radians * upright_spring_strength)) - (angular_velocity * upright_spring_damper))

func update_ride_spring():
	if ground_ray.is_colliding():
		var ray_dir := Vector3.DOWN
		#if ray hits another rigidbody
		var collider_vel := Vector3.ZERO
		var hit_body = ground_ray.get_collider()
		if "velocity" in hit_body:
			collider_vel = ground_ray.get_collider().velocity
			
		var ray_dir_vel := ray_dir.dot(linear_velocity)
		var collider_dir_vel := ray_dir.dot(collider_vel)
		
		var rel_vel := ray_dir_vel - collider_dir_vel
		
		var ray_dist : float = ground_ray.global_position.distance_to(ground_ray.get_collision_point())
		var x := ray_dist - ride_height 

		var spring_force := (x * ride_spring_strength) - (rel_vel * ride_spring_damper)
		apply_force(ray_dir * spring_force * mass)
		
#		if hit_body is CharacterBody3D:
#			#account for platform movement
#			print(hit_body.velocity)
#			apply_force(Vector3(hit_body.velocity.x, 0, hit_body.velocity.z))
		
		if hit_body is RigidBody3D: #.has_method("apply_force"):
			var relative_pos : Vector3 = ground_ray.get_collision_point() - hit_body.global_position
			relative_pos.y = 0
			hit_body.apply_force(ray_dir * -spring_force, relative_pos)
			#print(hit_body.linear_velocity)
			floor_velocity = hit_body.linear_velocity
			var ang := Vector3(-hit_body.angular_velocity.z, hit_body.angular_velocity.y, hit_body.angular_velocity.x) * relative_pos.length()
			#do apply force here instead using same logic as movement, calculate force necessary to reach floor velocity
			#calculate necessary force to reach goal_vel
			var needed_accel : Vector3 = (floor_velocity) / (1.0/60)
			#applying force offset from center causes tilt
			var tilt_factor := Vector3(0,0.2,0)
			#apply_force(needed_accel * 0.75, tilt_factor)
			
			
			#linear_velocity = movement_velocity + floor_velocity
			
#			apply_force(Vector3(hit_body.linear_velocity.x, 0, hit_body.linear_velocity.z))
#
#			#account for platform rotation
#			var ang := Vector3(-hit_body.angular_velocity.z, hit_body.angular_velocity.y, hit_body.angular_velocity.x)
#			apply_force(ang * relative_pos.length() * 10)
		else:
			floor_velocity = Vector3.ZERO
			
func shortest_rotation(a : Quaternion, b : Quaternion) -> Quaternion:
	if a.dot(b) < 0:
		return a * (b * -1).inverse()
	else:
		return a * b.inverse()
