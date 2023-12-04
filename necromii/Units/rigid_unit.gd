extends RigidBody3D

@export var SPEED = 5.0
@export var JUMP_VELOCITY = 6
@export var acceleration : float = 200
@export var max_acceleration_force :float = 150

var is_selected := false
var is_paused := false

@onready var collision_shape_3d : CollisionShape3D = $CollisionShape3D
@onready var navigation_agent : NavigationAgent3D = $NavigationAgent3D
@onready var health_bar : Sprite3D = $HealthBar
@onready var mesh_instance_3d : MeshInstance3D = $ShearTransform/MeshInstance3D
@onready var shape_cast_3d = $ShapeCast3D

var gravity = ProjectSettings.get_setting(&"physics/3d/default_gravity")

func _ready():
	Signals.finished_drawing.connect(self._on_finished_drawing)
	navigation_agent.max_speed = SPEED
	await get_tree().physics_frame

func _physics_process(delta):
	if is_selected and Input.is_action_just_pressed(&"ui_accept") and Global.player_selected and shape_cast_3d.is_colliding():
		linear_velocity.y = JUMP_VELOCITY
		#apply_central_impulse(Vector3.UP * JUMP_VELOCITY * 2 * mass + Vector3.UP * gravity)
	
	if Global.is_drawing:
		detect_selection()
	else:
		is_paused = false
	
	#stay attached to navigation surface when jumping
	navigation_agent.agent_height_offset = clamp(-position.y, -5, 0)
	#if pushed out of place, return to it
	if navigation_agent.is_navigation_finished() and navigation_agent.distance_to_target() > navigation_agent.radius * 2:
		navigation_agent.target_position = navigation_agent.target_position
		
	if is_paused or navigation_agent.is_navigation_finished():
		move(delta, Vector3.ZERO)
	else:
		var direction: Vector3 = navigation_agent.get_next_path_position() - global_position
		direction.y = 0
		if direction.length_squared() > 1:
			direction = direction.normalized()	
		move(delta, direction)

func move(delta : float, direction : Vector3):
	var cur_vel := Vector3(linear_velocity.x, 0, linear_velocity.z)
	var goal_vel : Vector3 = direction * SPEED
	goal_vel = cur_vel.move_toward(goal_vel, acceleration * delta)
	navigation_agent.set_velocity(goal_vel)
	goal_vel = await navigation_agent.velocity_computed
	var needed_accel : Vector3 = (goal_vel - cur_vel) / delta
	needed_accel = needed_accel.limit_length(max_acceleration_force)
	apply_force(needed_accel * mass)
	#vel dot
#	var cur_vel := Vector3(linear_velocity.x, 0, linear_velocity.z)
#	var vel_dot := direction.dot(cur_vel.normalized())
#	vel_dot = -sin(vel_dot*PI + PI/2)/2 + 1.5 if vel_dot < 0 else 1
#	var goal_vel : Vector3 = direction * SPEED
#	goal_vel = cur_vel.move_toward(goal_vel, acceleration * vel_dot * delta)
#	navigation_agent.set_velocity(goal_vel)
#	goal_vel = await navigation_agent.velocity_computed
#	var needed_accel : Vector3 = (goal_vel - cur_vel) / delta
#	needed_accel = needed_accel.limit_length(max_acceleration_force * vel_dot)
#	apply_force(needed_accel * mass)
	
func detect_selection():
	var new_is_selected : bool = Global.SelectionTool.in_selection(global_position)
	if new_is_selected == is_selected:
		return
	else:
		is_selected = new_is_selected
		navigation_agent.enabled = is_selected
		if is_selected:
			mesh_instance_3d.material_override.set_shader_parameter(&"color_mix", Color.RED)
			is_paused = true
		else:
			mesh_instance_3d.material_override.set_shader_parameter(&"color_mix", Color.BLUE)

func _on_finished_drawing():
	if navigation_agent.enabled:
		navigation_agent.target_position = global_position
