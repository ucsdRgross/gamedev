class_name BigNumberLabel
extends AutosizeLabel

var current_num : BigNumber:
	set(value):
		current_num = value
		if current_num.is_equal_to(0.0):
			text = ""
		else: text = current_num.to_metric_symbol(true)
		
func update_score_anim(num:BigNumber) -> void:
	current_num = num
	anim_pop()

var anim_tween : Tween:
	set(value):
		if anim_tween and anim_tween.is_running():
			anim_tween.custom_step(INF)
		anim_tween = value
		
func anim_pop() -> void:
	var delay := Game.CURRENT.get_delay()
	var new_tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	new_tween.tween_property(self, "scale", Vector2.ONE * 1.15, delay * .3)
	new_tween.tween_property(self, "scale", Vector2.ONE, delay * .2)
	anim_tween = new_tween

#func anim_reset() -> void:
	#var delay := Game.CURRENT.get_delay()
	#var new_tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	#new_tween.tween_property(self, "scale", Vector2.ONE, delay * .4)
	#new_tween.tween_property(self, "position", Vector2.ZERO, delay * .4)
	#anim_tween = new_tween
