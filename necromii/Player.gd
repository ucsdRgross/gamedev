extends RigidBody3D

var is_selected := false
var last_pos : Vector3

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var movement_physics = $MovementPhysics

enum STATES {
	IDLE,
	WALK,
	RUN,
	JUMP
}

var state = STATES.IDLE

func _ready():
	navigation_agent.max_speed = movement_physics.max_speed


func _physics_process(_delta):	
	detect_selection()
	
	match state:
		STATES.IDLE:
			pass
	
	var input_dir := Input.get_vector("Left", "Right", "Forward", "Back")
	var direction := Vector3(input_dir.x, 0, input_dir.y).normalized()
	movement_physics.update(direction * movement_physics.max_speed)

	if Input.is_action_just_pressed("ui_accept"):
		movement_physics.jump()
	
	if is_selected and Global.is_modifying:
		if not Global.SelectionTool.is_mouse_held:
			var change : Vector2 = Global.SelectionTool.global_to_viewport_relative(position - last_pos)
			Signals.player_move_selection.emit(change, direction != Vector3.ZERO)
	
	last_pos = position
	#update_animation()
	#rotate_wheel()

func _on_navigation_agent_3d_velocity_computed(safe_velocity: Vector3):
	# Move CharacterBody3D with the computed `safe_velocity` to avoid dynamic obstacles.
	movement_physics.update(safe_velocity)
	
func detect_selection():
	var new_is_selected : bool = Global.SelectionTool.in_selection(position)
	if new_is_selected == is_selected:
		return
	else:
		is_selected = new_is_selected
		
	if is_selected:
		$MeshInstance3D.material_overlay.set_shader_parameter("on", true)
		
	else:
		$MeshInstance3D.material_overlay.set_shader_parameter("on", false)

##	if paused:
##		movement_physics.update(Vector3.ZERO)
#	if !is_navigating:
#		movement_physics.update(direction * movement_physics.max_speed)
#	else:
#		var final := navigation_agent.get_final_position()
#		var target_reached = Vector2(position.x, position.z).distance_to(Vector2(final.x, final.z)) < Vector2(linear_velocity.x, linear_velocity.z).length()/2
#		if !target_reached and !navigation_agent.is_navigation_finished():
#			direction = navigation_agent.get_next_path_position() - global_transform.origin
#			direction.y = 0
#			var new_velocity: Vector3 = direction.normalized() * navigation_agent.max_speed
#			#new_velocity.y = 0
#			#movement_physics.update(new_velocity)
#			navigation_agent.agent_height_offset = -position.y
#			navigation_agent.set_velocity(new_velocity)
#			#above function leads to _on_navigation_agent_3d_velocity_computed signal 
#		else:
#			movement_physics.update(Vector3.ZERO)
