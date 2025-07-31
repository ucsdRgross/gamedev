extends RigidBody2D

var mouse_motion_delta := Vector2.ZERO
var mouse_motion_delta_count : int = 0
var mouse_sensitivity := 0.5
var move_speed = 200
@onready var node_2d: Node2D = $Node2D
@onready var body: RigidBody2D = $"../Body"

func _input(event):
	if event is InputEventMouseMotion:
		mouse_motion_delta += event.relative
		mouse_motion_delta_count += 1
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if lock_rotation == false:
			print(Vector2(cos(rotation), sin(rotation)))
			apply_central_impulse(Vector2(-sin(rotation), cos(rotation)) * (abs(angular_velocity) ** 2.5) * mass * 10)
		lock_rotation = true
	else:
		lock_rotation = false

func _physics_process(delta):
	var motion : Vector2
	if mouse_motion_delta != Vector2.ZERO:
		motion = mouse_motion_delta / mouse_motion_delta_count # * mouse_sensitivity
	motion *= abs(Vector2(cos(rotation), sin(rotation)))
	apply_force(motion * delta * 60 * 50, Vector2.DOWN)
	mouse_motion_delta = Vector2.ZERO
	mouse_motion_delta_count = 0
	node_2d.scale.y = sqrt(abs(angular_velocity) + 1)
