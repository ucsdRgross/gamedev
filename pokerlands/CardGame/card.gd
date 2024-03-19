extends Node2D
class_name Card

var rank : int = 0
var suit : int = 0

@onready var back_face: Sprite2D = $BackFace
@onready var front_face: Sprite2D = $FrontFace

func _ready() -> void:
	show_back()
	
func show_front()  -> void:
	front_face.show()
	back_face.hide()

func show_back()  -> void:
	front_face.hide()
	back_face.show()
