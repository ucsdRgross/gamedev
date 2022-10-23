extends Node2D


onready var popup = $GridContainer

func _on_Area2D_area_entered(area):
	popup.visible = true


func _on_Area2D_area_exited(area):
	popup.visible = false


func _on_Button_pressed():
	if PlayerHolding.is_empty():
		var button = $GridContainer/Button
		var instance = button.get_child(0).create_instance()
		give_item(button, instance)
	

func _on_Button2_pressed():
	if PlayerHolding.is_empty():
		var button = $GridContainer/Button2
		var instance = button.get_child(0).create_instance()
		give_item(button, instance)


func _on_Button3_pressed():
	if PlayerHolding.is_empty():
		var button = $GridContainer/Button3
		var instance = button.get_child(0).create_instance()
		give_item(button, instance)
		
func give_item(parent, instance):
	parent.remove_child(instance)
	PlayerHolding.path.add_child(instance)
	instance.enable_detection(false)
