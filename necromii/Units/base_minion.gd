extends RigidBody3D

var is_selected := false
var is_paused := false
var delta := 0.0

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var movement_physics = $MovementPhysics

enum states {IDLE, JUMP, RAGDOLL}
var state := states.IDLE

func _ready():
	Signals.finished_drawing.connect(self._on_finished_drawing)
	navigation_agent.max_speed = movement_physics.max_speed
	navigation_agent.enabled = false
	navigation_agent.target_position = position

func _physics_process(delta):
	if Global.is_drawing:
		detect_selection()
	else:
		is_paused = false
	
	#var final := navigation_agent.get_final_position()
	#var target_reached = Vector2(position.x, position.z).distance_to(Vector2(final.x, final.z)) < Vector2(linear_velocity.x, linear_velocity.z).length()/2
	if !is_paused and !navigation_agent.is_navigation_finished():
		var direction := navigation_agent.get_next_path_position() - global_transform.origin
		direction.y = 0
		var new_velocity: Vector3 = direction.normalized() * navigation_agent.max_speed
		navigation_agent.agent_height_offset = -position.y
		#movement_physics.update(delta, new_velocity)
		self.delta = delta
		navigation_agent.avoidance_enabled = true
		navigation_agent.set_velocity(new_velocity)
		#above function leads to _on_navigation_agent_3d_veocity_computed signal 
	else:
		movement_physics.update(delta, Vector3.ZERO)

	if is_selected and Input.is_action_just_pressed("ui_accept") and Global.player_selected:
		movement_physics.jump()

	#update_animation()
	#rotate_wheel()

func _on_navigation_agent_3d_velocity_computed(safe_velocity: Vector3):
	# Move CharacterBody3D with the computed `safe_velocity` to avoid dynamic obstacles.
	movement_physics.update(delta, safe_velocity)
	navigation_agent.avoidance_enabled = false
	
func detect_selection():
	var new_is_selected : bool = Global.SelectionTool.in_selection(position)
	if new_is_selected == is_selected:
		return
	else:
		is_selected = new_is_selected
		navigation_agent.enabled = is_selected
		if is_selected:
			$MeshInstance3D.material_overlay.set_shader_parameter("on", true)
			is_paused = true
		else:
			$MeshInstance3D.material_overlay.set_shader_parameter("on", false)

func _on_finished_drawing():
	if navigation_agent.enabled:
		navigation_agent.target_position = position

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
