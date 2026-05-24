@tool
extends Node2D
class_name CardVisual

const card_size := Vector2(38,50)

var focused : bool = false:
	set(value):
		focused = value
		if focused: modulate = Color(1.825, 1.825, 1.825)
		else: modulate = Color(1.0, 1.0, 1.0)
var data : CardData:
	set(value):
		data = value
		update_visual()
		if not is_node_ready():
			await ready
		match data.previous_stage:
			data.Stage.PLAY, data.Stage.ZONE:
				if Game.CURRENT:
					global_position = get_card_control_center(Game.CURRENT.play_area.data_ui[data])
			data.Stage.DRAW:
				if Game.CURRENT:
					global_position = get_control_center(Game.CURRENT.deck_ui)
			data.Stage.DISCARD:
				if Game.CURRENT:
					global_position = get_control_center(Game.CURRENT.discard_ui)
			data.Stage.RULES:
				if Game.CURRENT:
					global_position = get_control_center(Game.CURRENT.rules_ui)
		on_stage_changed()
var can_move_anim := true
var can_rot_anim := true
var floating : bool = true:
	set(value):
		floating = value
		if not floating:
			if not is_node_ready():
				await ready
			basis3d = Basis.looking_at(Vector3(0, 0, -3.5 * (-1 if data and data.flipped else 1)))
			if Engine.is_editor_hint():
				front.position.y = 0

var basis3d : Basis = Basis(Vector3(-1,0,0), Vector3(0,1,0), Vector3(0,0,-1)):
	set(value):
		basis3d = value
		front.transform.x = Vector2(basis3d.x[0], basis3d.x[1])
		front.transform.y = Vector2(basis3d.y[0], basis3d.y[1])
		show_front = basis3d.z[2] > 0
#change flipped instead
var show_front := false :
	set(value):
		if value != show_front:
			show_front = value
			update_visual()

#func set_flipped_instant(flip:bool) -> void:
	#flipped = flip
	#basis3d = Basis.looking_at(Vector3(0, 0, -3.5 * (-1 if flip else 1)))

func update_visual() -> void:
	if show_front and data:
		if data.rank:
			data.rank.set_texture(rank)
			rank.show()
		else: rank.hide()
		if data.suit:
			data.suit.set_texture(suit)
			data.suit.set_material(suit)
			data.suit.set_material(rank)
			suit.show()
		else: suit.hide()
			
		if data.type:
			front.frame = data.type.get_frame()
		else:
			front.frame = 2
			
		if data.stamp:
			stamp.frame = data.stamp.get_frame()
			stamp.show()
		else:
			stamp.hide()
			
		if data.skill:
			data.skill.set_texture(art)
			data.skill.set_material(art)
			art.show()
		elif data.suit:
			data.suit.set_art_texture(art, data.rank)
			data.suit.set_material(art)
			art.show()
		else: art.hide()

	else:
		if not is_node_ready():
			await ready
		front.frame = 3
		rank.hide()
		stamp.hide()
		suit.hide()
		art.hide()

#static var num_cards : int = 0
#static var child_offset : Vector2 = Vector2(0, 55)
var num : int = 0
var move_tween : Tween
var tilt_tween : Tween
var held : int = 0
var hover : bool = false

@onready var offset: Node2D = $Offset
@onready var front: Sprite2D = $Offset/Front
@onready var rank: Sprite2D  = $Offset/Front/Rank
@onready var stamp: Sprite2D = $Offset/Front/Stamp
@onready var suit: Sprite2D  = $Offset/Front/Suit
@onready var art: Sprite2D = $Offset/Front/Art

func _ready() -> void:
	rank.hide()
	stamp.hide()
	suit.hide()
	art.hide()
	if not (data and data.stage == CardData.Stage.ZONE):
		front.frame = 3
		#num_cards += 1
		#num = num_cards
	else:
		front.frame = 0
		#child_offset = Vector2(0,0)
		basis3d = Basis(Vector3(-1,0,0), Vector3(0,1,0), Vector3(0,0,-1))

func on_stage_changed() -> void:
	if data.stage == data.previous_stage: return
	match data.stage:
		data.Stage.PLAY, data.Stage.ZONE:
			var target_pos := get_card_control_center(Game.CURRENT.play_area.data_ui[data])
			create_move_tween(target_pos)
		data.Stage.DRAW:
			var target_pos := get_control_center(Game.CURRENT.discard_ui)
			create_move_tween(target_pos).tween_callback(queue_free)
		data.Stage.DISCARD:
			var target_pos := get_control_center(Game.CURRENT.discard_ui)
			create_move_tween(target_pos).tween_callback(queue_free)
		data.Stage.RULES:
			var target_pos := get_control_center(Game.CURRENT.rules_ui)
			create_move_tween(target_pos).tween_callback(queue_free)

func get_card_control_center(control:Control) -> Vector2:
	return control.global_position + Vector2(control.size.x/2, card_size.y * scale.y / 2)

func get_control_center(control:Control) -> Vector2:
	return control.global_position + control.size/2

var rot_delta : float
var y_delta : float
func _process(delta: float) -> void:
	# Needs state check, if discard then discard animation first before free
	if Game.CURRENT and data not in Game.CURRENT.play_area.data_ui: queue_free()
	elif (not (move_tween and move_tween.is_running())
			and data and (data.stage == data.Stage.PLAY or data.stage == data.Stage.ZONE)):		
		var target : Vector2 = get_card_control_center(Game.CURRENT.play_area.data_ui[data])
		if held:
			#where card orients itself relative to mouse
			var offset : int =  Game.CURRENT.play_area.card_min_size.y/2 - Game.CURRENT.play_area.card_stacked_seperation/2
			offset += (held - 1) * Game.CURRENT.play_area.card_stacked_seperation
			target = get_global_mouse_position() + Vector2(0, offset)
		#if held or not bot_card:
			#target = target_pos
		#else:
			#target = bot_card.global_position
			#if not bot_card.is_zone:
				#target += bot_card.child_offset.rotated(bot_card.global_rotation*1.75)
			#y_delta += bot_card.y_delta * 0.5
			
		target.y -= y_delta
		var move : Vector2 = target - global_position
		# lerp is bad, frame dependent
		# should be a tween instead when data is moving slots
		# still need something to keep card attached to control though
		# probably some sort of flag to trigger on next move instead of attach
		# global_position = global_position.lerp(target, .2)
		global_position = target + (global_position - target) * exp(-5 * delta)
		
		if data.stage != data.Stage.ZONE:
			y_delta = lerpf(y_delta, move.y, 15 * delta)
			y_delta = clampf(y_delta, -4, 4)
			
			rot_delta = lerpf(rot_delta, move.x, 15 * delta)
			var clamp_degree : float = sqrt(abs(rot_delta) as float) * 5
			rot_delta = clampf(rot_delta, -clamp_degree, clamp_degree)
			rotation_degrees = rot_delta

	if floating:
		var x : float = sin(num + float(Time.get_ticks_msec()) / 2000) * (0.3 if hover else 0.6)
		var y : float = cos(num + float(Time.get_ticks_msec()) / 2000) * (0.3 if hover else 0.6)
		
		if hover:
			var mouse_pos : Vector2 = -get_local_mouse_position().normalized()
			x += mouse_pos.x/1.5
			y += mouse_pos.y/1.5
		var bobbing := sin(2 * num + float(Time.get_ticks_msec()) / 2000)
		if data and data.stage == data.Stage.ZONE:
			x = 0
			y = 0
			bobbing = 0
		var drift : Vector3 = Vector3(x, y, -3.5 * (-1 if data and data.flipped else 1))
		basis3d = basis3d.slerp(Basis.looking_at(drift), 6.5 * delta)
		front.position.y = lerpf(front.position.y, bobbing, 10 * delta)

func with_data(data:CardData) -> CardVisual:
	self.data = data
	data.data_changed.connect(update_visual)
	data.stage_changed.connect(on_stage_changed)
	return self

func reset_tween(tween:Tween) -> void:
	if tween and tween.is_running():
		tween.custom_step(INF)

func create_move_tween(target_pos:Vector2) -> Tween:
	reset_tween(move_tween)
	var delay := Game.CURRENT.get_delay()
	move_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
	move_tween.tween_property(self, "global_position", target_pos, delay*0.3)
	if target_pos.x - global_position.x > 10:
		move_tween.parallel().tween_property(self, "rotation_degrees", 10, delay*0.2)
	elif global_position.x - target_pos.x > 10:
		move_tween.parallel().tween_property(self, "rotation_degrees", -10, delay*0.2)
	#tween.set_ease(Tween.EASE_OUT)
	move_tween.tween_property(self, "rotation_degrees", 0, delay*0.1)
	return move_tween

func anim_jump() -> float:
	reset_tween(move_tween)
	var delay := Game.CURRENT.get_delay()
	move_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	move_tween.tween_callback(func()->void: floating = false)
	move_tween.tween_property(offset, "position:y", -card_size.y / 5.0, delay * .4)
	move_tween.tween_property(offset, "scale", Vector2.ONE * 1.15, delay * .3)
	move_tween.tween_property(offset, "scale", Vector2.ONE, delay * .2)
	return delay #* .4

func anim_reset() -> void:
	reset_tween(move_tween)
	var delay := Game.CURRENT.get_delay()
	move_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	move_tween.tween_property(offset, "position:y", 0, delay * .4)
	move_tween.tween_callback(func()->void: floating = true)

#print(result.score_name, "\nscore: ", result.score)
				##tween = create_tween().set_parallel(true)
				##tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_BACK)
				#for c:Card in result.card_combo:
					#var card_tween : Tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
					#c.floating = false
					#card_tween.tween_property(c.front, "position:y", -7 * 1.5, base_delay * .5)
					#card_tween.tween_property(c.front, "position:y", -7, base_delay * .5)
					#print('suit: ', c.data.suit.get_str(), c.data.suit.value, ' rank: ', c.data.rank.get_str(), c.data.rank.value)
				#for c:Card in last_scored_cards:
					#if c not in result.card_combo:
						#var card_tween : Tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
						#card_tween.tween_property(c.front, "position:y", 0, base_delay)
						#card_tween.tween_callback(func()->void: c.floating = true)
						##card_tween.tween_property(c, "floating", true, base_delay * .1)
				#
				##tween.tween_interval(score_delay)
				#last_scored_cards = result.card_combo
				#var combo_pos : Vector2 = Vector2.ZERO
				#for card in result.card_combo:
					#combo_pos += card.global_position
				#combo_pos /= result.card_combo.size()
				#var score_name_popup := TextPopup.new_popup(result.score_name, combo_pos)
				#game_container.add_child(score_name_popup)
				#
				#row_add_score(row_to_score, result.score)
				##var popup := (TEXT_POPUP.instantiate() as TextPopup).with(result.score_name, score_delay)
				##popup.global_position = combo_pos
				##add_child(popup)
				#await get_tree().create_timer(base_delay).timeout
				#for card in result.card_combo:
					#await run_all_mods(&"on_score", card)
				#await run_all_mods(&"on_after_score")
				#
				##await get_tree().create_timer(score_delay).timeout
				#score_name_popup.queue_free()
				#
