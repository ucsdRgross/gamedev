extends RigidBody3D

@export var SPEED = 5.0
@export var JUMP_VELOCITY = 4.5

var is_selected := false
var is_paused := false

@onready var collision_shape_3d : CollisionShape3D = $CollisionShape3D
@onready var navigation_agent : NavigationAgent3D = $NavigationAgent3D
@onready var health_bar : Sprite3D = $HealthBar
@onready var mesh_instance_3d : MeshInstance3D = $ShearTransform/MeshInstance3D
@onready var shape_cast_3d = $ShapeCast3D

func _ready():
	Signals.finished_drawing.connect(self._on_finished_drawing)
	navigation_agent.max_speed = SPEED

func _physics_process(delta):
	if is_selected and Input.is_action_just_pressed("ui_accept") and Global.player_selected and shape_cast_3d.is_colliding():
		linear_velocity.y = JUMP_VELOCITY
	
	if Global.is_drawing:
		detect_selection()
	else:
		is_paused = false

	if navigation_agent.is_navigation_finished() and navigation_agent.distance_to_target() > navigation_agent.radius * 2:
		navigation_agent.target_position = navigation_agent.target_position

	navigation_agent.agent_height_offset = -position.y
	var direction: Vector3 = navigation_agent.get_next_path_position() - global_position
	direction.y = 0
	var new_velocity: Vector3 = direction.normalized() * SPEED
	if is_paused or navigation_agent.is_navigation_finished():
		new_velocity.x = 0
		new_velocity.z = 0
	navigation_agent.set_velocity(new_velocity)

func _on_navigation_agent_3d_velocity_computed(safe_velocity: Vector3):
	apply_force(safe_velocity * SPEED * mass)
	#print(linear_velocity.length())
	
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
