extends Item

var cook_time = 0

func setup():
	id = "Pot"

func _on_Hitbox_input_event(viewport, event, shape_idx):
	#generic pick up stuff
	if event.is_action_pressed("click") and interactable:
		if PlayerHolding.is_empty():
			enable_detection(false)
			get_parent().remove_child(self)
			PlayerHolding.path.add_child(self)
			self.global_position = PlayerHolding.path.global_position
		#RECIPE LOGIC
		var hand = PlayerHolding.path.get_child(0)
		if hand.id == "Sugar":
			hand.queue_free()
			id = "Pot + Sugar"
	
	
