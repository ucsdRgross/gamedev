extends Node2D

var interactable = false

var id = "Table Top"

onready var inventory = $Inventory

func _on_Area2D_area_entered(area):
	if area.name == "Detector":
		interactable = true

func _on_Area2D_area_exited(area):
	if area.name == "Detector":
		interactable = false

var goop = preload("res://Main/Game/Items/Goop/Goop.tscn")

func _on_Area2D_input_event(viewport, event, shape_idx):
	if event.is_action_pressed("click") and interactable:
		if inventory.get_child_count() == 0:
			if not PlayerHolding.is_empty():
				var hand = PlayerHolding.path
				var item : Item = hand.get_child(0)
				if "Goop" in item.id:
					var new_goop  = goop.instance()
					inventory.add_child(new_goop)
					if "Pot" in item.id:
						item.new_id("Pot")
				else:
					hand.remove_child(item)
					inventory.add_child(item)
		else:
			if PlayerHolding.is_empty():
				var item : Item = inventory.get_child(0)
				inventory.remove_child(item)
				PlayerHolding.path.add_child(item)
