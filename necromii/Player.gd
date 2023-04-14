extends CharacterBody3D


const SPEED = 20.0
const JUMP_VELOCITY = 4.5
var is_selected := false
var goal_position := Vector3.ZERO
var paused := false
var reset_goal := true

#@onready var navigation_agent_3d = $NavigationAgent3D

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready():
	Signals.new_selection.connect(self._on_new_selection)
	Signals.selection_changed.connect(self._on_selection_changed)
	navigation_agent.target_desired_distance = 0.001

#func _physics_process(delta):
#
#	# Add the gravity.
#	if not is_on_floor():
#		velocity.y -= gravity * delta
#
#	# Handle Jump.
#	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
#		velocity.y = JUMP_VELOCITY
#
#	# Get the input direction and handle the movement/deceleration.
#	# As good practice, you should replace UI actions with custom gameplay actions.
#	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
#	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
#	if direction:
#		velocity.x = direction.x * SPEED
#		velocity.z = direction.z * SPEED
#	else:
#		velocity.x = move_toward(velocity.x, 0, SPEED)
#		velocity.z = move_toward(velocity.z, 0, SPEED)
#
#	move_and_slide()

@export var movement_speed: float = 1000.0
@onready var navigation_agent: NavigationAgent3D = get_node("NavigationAgent3D")
var movement_delta: float

func _physics_process(delta):
	if navigation_agent.is_navigation_finished():
		return
		
	if paused:
		return
	
	movement_delta = movement_speed * delta
	var next_path_position: Vector3 = navigation_agent.get_next_path_position()
	var current_agent_position: Vector3 = global_transform.origin
	var new_velocity: Vector3 = (next_path_position - current_agent_position).normalized() * movement_delta
	navigation_agent.set_velocity(new_velocity)

func _on_navigation_agent_3d_velocity_computed(safe_velocity: Vector3):
	# Move CharacterBody3D with the computed `safe_velocity` to avoid dynamic obstacles.
	velocity = safe_velocity
	move_and_slide()
	
func _on_new_selection(polygon):
	is_selected = Global.SelectionTool.in_selection(position)
	if is_selected:
		$MeshInstance3D.material_overlay.set_shader_parameter("on", true)
		paused = true
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
				var xyz : Vector3 = Global.SelectionTool.viewport_to_global(center)
				print(xyz)
			2: #rotational
				var angle : float = change
	paused = false

