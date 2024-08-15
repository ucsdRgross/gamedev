extends Node2D
class_name TextPopup

const TEXT_POPUP = preload("res://text_popup.tscn")

@onready var label : Label = $Label

static func new_popup(text:String, glo_pos: Vector2) -> TextPopup:
	var new_popup : TextPopup = TEXT_POPUP.instantiate()
	set_data(new_popup, text, glo_pos)
	return new_popup

#private
static func set_data(new_popup:TextPopup, text:String, glo_pos: Vector2) -> void:
	await new_popup.ready
	new_popup.label.text = text
	new_popup.global_position = glo_pos
