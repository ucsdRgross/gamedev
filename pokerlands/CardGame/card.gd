extends RigidBody2D
class_name Card

var rank : int = 0
var suit : int = 0
var held := false
var in_play := true
var goal_position : Vector2
var tween : Tween

@onready var back_face: Sprite2D = $CollisionShape2D/BackFace
@onready var front_face: Sprite2D = $CollisionShape2D/FrontFace

signal clicked

func _ready() -> void:
	show_back()

func _physics_process(_delta:float) -> void:
	if held:
		pass

func _on_control_gui_input(event: InputEvent) -> void:
	process_event(event)

			
func process_event(event:InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event : InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			#print("clicked")
			if in_play:
				clicked.emit(self)

func pickup() -> void:
	if held:
		return
	held = true

func drop() -> void:
	if held:
		held = false

func show_front()  -> void:
	front_face.show()
	back_face.hide()

func show_back()  -> void:
	front_face.hide()
	back_face.show()

