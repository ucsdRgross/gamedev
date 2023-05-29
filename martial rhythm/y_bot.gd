extends CharacterBody3D

@export var camera : Node

@onready var animation_tree = $AnimationTree

const SPEED = 5.0
const JUMP_VELOCITY = 4.5

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")


func _physics_process(delta):
	var root_motion : Vector3 = animation_tree.get_root_motion_position()
	var v = root_motion / delta
	
	# Add the gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle Jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		animation_tree["parameters/conditions/jump"] = true
	else:
		animation_tree["parameters/conditions/jump"] = false

	
	var input_dir = Input.get_vector("right", "left", "backward", "forward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		direction = direction.rotated(Vector3.UP, camera.setup.rotation.y)
		
		var current_rotation := Vector2(rotation.x, rotation.z)
		var desired_rotation := Vector2(direction.x, direction.z)
		
		var phi : float = desired_rotation.angle_to(current_rotation)
		#phi = phi * delta * 3.0
		rotation.y += phi
		
		if Input.is_action_pressed("sprint"):
			animation_tree["parameters/playback"].travel("Drunk Run Forward")
		else:
			animation_tree["parameters/playback"].travel("Strut Walking")	
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		animation_tree["parameters/playback"].travel("Happy Idle")
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
