extends RigidBody2D
class_name Card

var rank : int = 0
var suit : int = 0
var held := false

@onready var back_face: Sprite2D = $CollisionShape2D/BackFace
@onready var front_face: Sprite2D = $CollisionShape2D/FrontFace

signal clicked

func _ready() -> void:
	show_back()

func _physics_process(_delta:float) -> void:
	if held:
		pass

func _on_input_event(_viewport:Node, event:InputEvent, _shape_idx:int) -> void:
	if event is InputEventMouseButton:
		var mouse_event : InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			print("clicked")
			clicked.emit(self)

func pickup() -> void:
	if held:
		return
	held = true

func drop(impulse:=Vector2.ZERO) -> void:
	if held:
		held = false

func show_front()  -> void:
	front_face.show()
	back_face.hide()

func show_back()  -> void:
	front_face.hide()
	back_face.show()
