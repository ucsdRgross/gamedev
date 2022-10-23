extends Item

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
			stop_cooking()
		#RECIPE LOGIC
		var hand = PlayerHolding.path.get_child(0)
		if id == "Pot" and hand.id == "Sugar":
			hand.queue_free()
			new_id("Pot + Sugar")
			$ProgressBar.value = 0
			if get_parent().get_parent().id == "Stove":
				start_cook()

func start_cook():
	$ProgressBar.show()
	$Timer.start()
	
func stop_cooking():
	$Timer.stop()
	if $ProgressBar.value > 14:
		$ProgressBar.hide()
	
func _on_Timer_timeout():
	$ProgressBar.value+=1
	if $ProgressBar.value > 14:
		new_id("Pot + Cooked Sugar")
	if $ProgressBar.value > 25:
		new_id("Pot + Goop")
		$ProgressBar.hide()
		return
	$Timer.start()
