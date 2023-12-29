extends CharacterBody3D

@export var SPEED = 5.0
@export var JUMP_VELOCITY = 4.5

var is_selected := false
var is_paused := false
var delta := 0.0

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var collision_shape_3d : CollisionShape3D = $CollisionShape3D
@onready var navigation_agent : NavigationAgent3D = $NavigationAgent3D
@onready var animation_player : AnimationPlayer = $AnimationPlayer
@onready var health_bar : Sprite3D = $HealthBar
@onready var mesh_instance_3d : MeshInstance3D = $ShearTransform/MeshInstance3D
@onready var avoidance_disabled : Timer = $AvoidanceDisabled
@onready var avoidance_detector = $AvoidanceDetector

enum states {IDLE, JUMP, RAGDOLL}
var state := states.IDLE

func _input(event):
	if event.is_action_pressed("Action"):
		if animation_player:
			animation_player.play("attack")

func _ready():
	Signals.finished_drawing.connect(self._on_finished_drawing)
	navigation_agent.max_speed = SPEED

func _physics_process(delta):
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	if is_selected and Input.is_action_just_pressed("ui_accept") and Global.player_selected and is_on_floor():
		velocity.y = JUMP_VELOCITY
	
	if Global.is_drawing:
		detect_selection()
	else:
		is_paused = false
	#var final := navigation_agent.get_final_position()
	#var target_reached = Vector2(position.x, position.z).distance_to(Vector2(final.x, final.z)) < Vector2(linear_velocity.x, linear_velocity.z).length()/2
	
	if navigation_agent.is_navigation_finished() and navigation_agent.distance_to_target() > navigation_agent.radius * 2:
		navigation_agent.target_position = navigation_agent.target_position
	
#	var direction: Vector3 = navigation_agent.get_next_path_position() - global_position
#	if is_paused or navigation_agent.is_navigation_finished():
#		direction = avoid_bodies.get_avoidance_vector(Vector3.ZERO)
#	else:
#		direction = avoid_bodies.get_avoidance_vector(direction.normalized())
#
#	var new_velocity: Vector3 = direction * SPEED
#	velocity.x = new_velocity.x
#	velocity.z = new_velocity.z
#	move_and_slide()

	navigation_agent.agent_height_offset = -position.y
	var direction: Vector3 = navigation_agent.get_next_path_position() - global_position
	direction.y = 0
	var new_velocity: Vector3 = direction.normalized() * SPEED
	if is_paused or navigation_agent.is_navigation_finished():
		new_velocity.x = move_toward(velocity.x, 0, SPEED)
		new_velocity.z = move_toward(velocity.z, 0, SPEED)
	if navigation_agent.avoidance_enabled:
		navigation_agent.set_velocity(new_velocity)
		var contacts : int = avoidance_detector.get_overlapping_bodies().size()
		if navigation_agent.is_navigation_finished() or contacts <= 1:
			if avoidance_disabled.is_stopped():
				avoidance_disabled.start()
		elif contacts > 5:
			avoidance_disabled.stop()
			disable_avoidance()
			
	else:
		_on_navigation_agent_3d_velocity_computed(new_velocity)
		if avoidance_detector.get_overlapping_bodies().size() > 1:
			if Global.avoidance_enabled_count < Global.avoidance_enabled_max:
				navigation_agent.avoidance_enabled = true
				navigation_agent.radius = 2
				Global.avoidance_enabled_count += 1

func _on_navigation_agent_3d_velocity_computed(safe_velocity: Vector3):
	# Move CharacterBody3D with the computed `safe_velocity` to avoid dynamic obstacles.
	#movement_physics.update(delta, safe_velocity)
	#navigation_agent.avoidance_enabled = false
	velocity.x = safe_velocity.x
	velocity.z = safe_velocity.z
	if !is_on_floor() or avoidance_detector.get_overlapping_bodies().size() <= 5:
		move_and_slide()
	
func detect_selection():
	var new_is_selected : bool = Global.SelectionTool.in_selection(position)
	if new_is_selected == is_selected:
		return
	else:
		is_selected = new_is_selected
		navigation_agent.enabled = is_selected
		if is_selected:
			mesh_instance_3d.material_override.set_shader_parameter("color_mix", Color.RED)
			is_paused = true
		else:
			mesh_instance_3d.material_override.set_shader_parameter("color_mix", Color.BLUE)

func _on_finished_drawing():
	if navigation_agent.enabled:
		navigation_agent.target_position = position


func _on_avoidance_disabled_timeout():
	disable_avoidance()

func disable_avoidance():
	navigation_agent.avoidance_enabled = false
	navigation_agent.radius = 1
	Global.avoidance_enabled_count -= 1
