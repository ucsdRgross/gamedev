extends RigidBody3D

var is_selected := false

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var movement_physics = $MovementPhysics

func _ready():
	navigation_agent.max_speed = movement_physics.max_speed
	navigation_agent.enabled = true
	navigation_agent.target_position = position

func _physics_process(_delta):	
	detect_selection()
	
	var final := navigation_agent.get_final_position()
	var target_reached = Vector2(position.x, position.z).distance_to(Vector2(final.x, final.z)) < Vector2(linear_velocity.x, linear_velocity.z).length()/2
	if !navigation_agent.is_navigation_finished():
		var direction := navigation_agent.get_next_path_position() - global_transform.origin
		direction.y = 0
		var new_velocity: Vector3 = direction.normalized() * navigation_agent.max_speed
		#new_velocity.y = 0
		#movement_physics.update(new_velocity)
		navigation_agent.agent_height_offset = -position.y
		navigation_agent.set_velocity(new_velocity)
		#above function leads to _on_navigation_agent_3d_veocity_computed signal 
	else:
		movement_physics.update(Vector3.ZERO)

	if is_selected and Input.is_action_just_pressed("ui_accept") :
		print(Time.get_ticks_msec())
		movement_physics.jump()

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