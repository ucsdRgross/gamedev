extends Node2D

var interactable = false

onready var label = $Label
onready var inventory = $Inventory

func _on_Area2D_area_entered(area):
	if area.name == "Detector":
		interactable = true

func _on_Area2D_area_exited(area):
	if area.name == "Detector":
		interactable = false


func _on_Area2D_input_event(viewport, event, shape_idx):
	if event.is_action_pressed("click") and interactable:
		if inventory.get_child_count() == 0:
			if not PlayerHolding.is_empty():
				var hand = PlayerHolding.path
				var item : Item = hand.get_child(0)
				if "Pot" in item.id:
					item.enable_detection(false)
					hand.remove_child(item)
					inventory.add_child(item)
					print("add cooking")
		else:
			if PlayerHolding.is_empty():
				var item : Item = inventory.get_child(0)
				inventory.remove_child(item)
				PlayerHolding.path.add_child(item)
			

func _on_Area2D_mouse_entered():
	label.visible = true

func _on_Area2D_mouse_exited():
	label.visible = false
