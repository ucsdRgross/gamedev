extends CharacterBody3D


const SPEED = 20.0
const JUMP_VELOCITY = 4.5
var is_selected := false
var goal_position
var paused := false

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready():
	Signals.new_selection.connect(self._on_new_selection)
	Signals.selection_changed.connect(self._on_selection_changed)

func _physics_process(delta):
	
	# Add the gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle Jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
	
func _on_new_selection(polygon):
	is_selected = Global.SelectionTool.in_selection(position)
	if is_selected:
		$MeshInstance3D.material_overlay.set_shader_parameter("on", true)
		paused = true
	else:
		$MeshInstance3D.material_overlay.set_shader_parameter("on", false)
		
func _on_selection_changed(move_type : int, change, center : Vector2):
	if is_selected:
		match move_type:
			0: #translational
				pass
			1: #scale
				pass
			2: #rotational
				pass
	else:
		paused = false