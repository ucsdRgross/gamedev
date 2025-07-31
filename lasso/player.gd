extends RigidBody2D

var initial_mass 

func _ready() -> void:
	initial_mass = mass

func _physics_process(delta: float):
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		mass = initial_mass / 5
	else:
		mass = initial_mass
