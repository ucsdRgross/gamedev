extends Node2D
class_name TextPopup

const TEXT_POPUP = preload("res://text_popup.tscn")

@onready var label : Label = $Label
@onready var timer : Timer = $Timer

static func new_popup(text:String, glo_pos: Vector2, lifetime:float=1.0) -> TextPopup:
	var new_popup : TextPopup = TEXT_POPUP.instantiate()
	set_data(new_popup, text, glo_pos, lifetime)
	return new_popup

#private
static func set_data(new_popup:TextPopup, text:String, glo_pos: Vector2, lifetime:float) -> void:
	await new_popup.ready
	new_popup.label.text = text
	new_popup.timer.wait_time = lifetime
	new_popup.global_position = glo_pos
	
func _on_timer_timeout() -> void:
	queue_free()
