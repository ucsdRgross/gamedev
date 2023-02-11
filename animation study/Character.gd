extends RigidBody3D

@onready var ground_ray = $GroundRay

const max_speed := 8
const acceleration := 200
const max_acceleration_force := 150

const ride_height := 1.5
const ride_spring_strength := 2000.0
const ride_spring_damper := 100.0

const upright_spring_strength := 2000.0
const upright_spring_damper := 100.0

const jump_velocity := 7.5
const jump_duration := 2/3

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

#floating capsule theory
#https://www.youtube.com/watch?v=qdskE8PJy6Q

enum STATES {
	IDLE,
	WALK,
	RUN,
	JUMP
}

var state = STATES.IDLE

func _physics_process(delta):
	ground_ray.global_rotation = Vector3.ZERO
	
	match state:
		STATES.IDLE:
			pass
			
	update_ride_spring()
	update_upright_force()
	
	transform = transform.orthonormalized()
	
	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
#	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
#	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
#	if direction:
#		velocity.x = direction.x * SPEED
#		velocity.z = direction.z * SPEED
#	else:
#		velocity.x = move_toward(velocity.x, 0, SPEED)
#		velocity.z = move_toward(velocity.z, 0, SPEED)

	
		
#	if Input.is_action_just_pressed("ui_accept") and on_floor:
#		velocity.y += JUMP_VELOCITY

func update_upright_force():
	var rot_correction := Quaternion(Vector3.UP, rotation.normalized())
	var rot_axis : Vector3 = rot_correction.get_axis()
	var rot_radian : float = deg_to_rad(rot_correction.get_angle())
	var rot_force : Vector3 = (rot_axis * (rot_radian * upright_spring_strength) - (angular_velocity * upright_spring_damper))
	apply_torque_impulse(rot_force.normalized())
	

func update_ride_spring():
	if ground_ray.is_colliding():
		var ray_dir := Vector3.DOWN
		#if ray hits another rigidbody
		var collider_vel := Vector3.ZERO
		var hit_body = ground_ray.get_collider()
		if "linear_velocity" in hit_body:
			collider_vel = ground_ray.get_collider().linear_velocity
			
		var ray_dir_vel := ray_dir.dot(linear_velocity)
		var collider_dir_vel := ray_dir.dot(collider_vel)
		
		var rel_vel := ray_dir_vel - collider_dir_vel
		
		var ray_dist : float = ground_ray.global_position.distance_to(ground_ray.get_collision_point())
		var x := ray_dist - ride_height 

		var spring_force := (x * ride_spring_strength) - (rel_vel * ride_spring_damper)
		apply_force(ray_dir * spring_force)
		
		if "apply_force(" in hit_body:
			hit_body.apply_central_force(ray_dir * -spring_force)
