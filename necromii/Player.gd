extends RigidBody3D

var is_selected := false
var goal_position := Vector3.ZERO
var paused := false
var reset_goal := true
var is_navigating := false

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
	Signals.new_selection.connect(self._on_new_selection)
	Signals.selection_changed.connect(self._on_selection_changed)
	navigation_agent.max_speed = movement_physics.max_speed


func _physics_process(delta):	
	match state:
		STATES.IDLE:
			pass
	
	var input_dir := Input.get_vector("Left", "Right", "Forward", "Back")
	var direction := Vector3(input_dir.x, 0, input_dir.y).normalized()
	if direction:
		is_navigating = false
	if paused:
		movement_physics.update(Vector3.ZERO)
	elif !is_navigating:
		movement_physics.update(direction * movement_physics.max_speed)
	else:
		var final := navigation_agent.get_final_position()
		var target_reached = Vector2(position.x, position.z).distance_to(Vector2(final.x, final.z)) < Vector2(linear_velocity.x, linear_velocity.z).length()/4
		if !target_reached and !navigation_agent.is_navigation_finished():
			direction = navigation_agent.get_next_path_position() - global_transform.origin
			direction.y = 0
			var new_velocity: Vector3 = direction.normalized() * navigation_agent.max_speed
			#new_velocity.y = 0
			#movement_physics.update(new_velocity)
			navigation_agent.agent_height_offset = -position.y
			navigation_agent.set_velocity(new_velocity)
			#above function leads to _on_navigation_agent_3d_velocity_computed signal 
		else:
			movement_physics.update(Vector3.ZERO)
	if Input.is_action_just_pressed("ui_accept"):
		movement_physics.jump()
		
	#update_animation()
	#rotate_wheel()

func _on_navigation_agent_3d_velocity_computed(safe_velocity: Vector3):
	# Move CharacterBody3D with the computed `safe_velocity` to avoid dynamic obstacles.
	movement_physics.update(safe_velocity)
	
func _on_new_selection(polygon):
	is_selected = Global.SelectionTool.in_selection(position)
	if is_selected:
		$MeshInstance3D.material_overlay.set_shader_parameter("on", true)
		paused = true
		is_navigating = true
		goal_position = position
	else:
		$MeshInstance3D.material_overlay.set_shader_parameter("on", false)
		reset_goal = true
		paused = false
		
func _on_selection_changed(move_type : int, change, center : Vector2):
	if is_selected:
		if reset_goal:
			goal_position = position
			goal_position.y = 0
			reset_goal = false
		match move_type:
			0: #translational
				var xyz : Vector3 = Global.SelectionTool.pixel_to_global(change)
				goal_position += xyz
				navigation_agent.set_target_position(goal_position)
			1: #scale
				var factor : Vector2 = change
				var origin : Vector3 = Global.SelectionTool.viewport_to_global(center)
				var vector := goal_position - origin
				goal_position = vector * Vector3(factor.x, 0, factor.y) + origin
				navigation_agent.set_target_position(goal_position)
			2: #rotational
				var angle : float = change
				var origin : Vector3 = Global.SelectionTool.viewport_to_global(center)
				var vector := goal_position - origin
				var vector2 : Vector2 = Vector2(vector.x, vector.z).rotated(angle)
				goal_position = Vector3(vector2.x, 0, vector2.y) + origin
				navigation_agent.set_target_position(goal_position)
	paused = false
