extends Area2D

@export var to : float = 1

var can_grab = false
var dragging = false

func _ready():
	if to <= 0:
		modulate = Color('ff21ff')
	else:
		modulate = Color('2bffff')

func _process(delta):
	if Input.is_action_pressed('leftclick') and can_grab:
		dragging = true
	
	if Input.is_action_just_released('leftclick'):
		can_grab = false
		dragging = false

	if dragging:
		position = get_global_mouse_position() 

func _on_mouse_entered():
	can_grab = true
