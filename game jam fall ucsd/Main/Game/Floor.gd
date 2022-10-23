extends Node2D

var interactable = false

onready var entities = $"../YSort"

func _on_Area2D_area_entered(area):
	if area.name == "Detector":
		interactable = true

func _on_Area2D_area_exited(area):
	if area.name == "Detector":
		interactable = false


func _on_Area2D_input_event(viewport, event, shape_idx):
	if event.is_action_pressed("click") and interactable:
		if not PlayerHolding.is_empty():
			var hand = PlayerHolding.path
			var item : Item = hand.get_child(0)
			
			hand.remove_child(item)
			entities.add_child(item)
			item.global_position = get_global_mouse_position()
			item.enable_detection(true)
			

