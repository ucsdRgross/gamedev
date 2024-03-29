extends Node2D
class_name Card

var rank : int = 0
var suit : int = 0
var moused_hovered := false
var dragging := false

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

func _on_mouse_button_1_pressed():
	if moused_hovered:
		dragging = true

func _on_mouse_button_1_not_pressed():
	dragging = false

func _on_area_2d_mouse_entered():
	moused_hovered = true

func _on_area_2d_mouse_exited():
	moused_hovered = false
