extends RigidBody3D

@onready var _movement_physics = $MovementPhysics
@onready var _camera_controller: CameraController = $CameraController

@onready var _ground_height: float = 0.0

@onready var health_bar : HealthBar = $HealthBar
@export var health_manager : HealthManager

func _ready():
	_camera_controller.setup(self)
	health_bar.set_max_health(health_manager.max_health)
	health_bar.set_health(health_manager.health)
	health_manager.health_changed.connect(health_bar.set_health)

func _input(event):
	if event.is_action_pressed("LClick"):
		$PunchCard.execute(self)
		health_manager.damage(1)
	
func _physics_process(delta):
	# Calculate ground height for camera controller
	if _movement_physics.ground_ray.is_colliding():
		_ground_height = _movement_physics.ground_ray.get_collision_point().y
	if _movement_physics.ground_ray.global_position.y < _ground_height:
		_ground_height = global_position.y
	if _movement_physics.ground_ray.global_position.y > _ground_height + 5:
		_ground_height = global_position.y
	
	#calculate movement
	var input_dir := Input.get_vector("Right", "Left", "Back", "Forward")
	var direction := Vector3(input_dir.x, 0, input_dir.y)
	direction = _camera_controller.global_transform.basis * direction
	direction.y = 0
	_movement_physics.update(delta, direction * _movement_physics.max_speed)
	
	if Input.is_action_just_pressed("Jump"):
		_movement_physics.jump()
