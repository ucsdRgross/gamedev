@abstract class_name CardModifier
extends Resource

enum Rarity {COMMON, UNCOMMON, RARE, EPIC, LEGENDARY}

#export makes no sense here, should be abstract methods
#@export var name : StringName
#@export var description : StringName
#@export var frame : int
#@export var rarity : Rarity
#@export var tags : Dictionary
@export_storage var data : CardData

@abstract func get_str() -> String
@abstract func get_description() -> String
@abstract func get_frame() -> int
@abstract func set_texture(polygon2d:Polygon2D) -> void

func with_data(data:CardData) -> CardModifier:
	self.data = data
	return self

func set_material(polygon2d:Polygon2D) -> void: polygon2d.material = null

## Robust runtime UV framing method that automatically adapts to ANY texture size
static func update_polygon_uv_frame(polygon2d: Polygon2D, source_sheet: Texture2D, h_frame: int, v_frame: int, target_frame: int) -> void:
	if not polygon2d or polygon2d.polygon.is_empty():
		return
		
	if polygon2d.texture != source_sheet:
		polygon2d.texture = source_sheet
		
	# 1. Dynamically read the incoming texture sizing
	var sheet_size := source_sheet.get_size()
	var frame_w := sheet_size.x / h_frame
	var frame_h := sheet_size.y / v_frame
	
	# 2. Find row, column, and pixel offset positions for the new layout
	var col := target_frame % h_frame
	var row := target_frame / h_frame
	var u_left := col * frame_w
	var v_top := row * frame_h
	
	var base_points := polygon2d.polygon
	var shifted_uvs := PackedVector2Array()
	shifted_uvs.resize(base_points.size())
	
	# 3. Dynamically find the min/max bounds of the physical mesh shape
	var min_p := base_points[0]
	var max_p := base_points[0]
	for idx in range(1, base_points.size()):
		var pt := base_points[idx]
		min_p.x = min(min_p.x, pt.x)
		min_p.y = min(min_p.y, pt.y)
		max_p.x = max(max_p.x, pt.x)
		max_p.y = max(max_p.y, pt.y)
		
	var poly_w := max_p.x - min_p.x
	var poly_h := max_p.y - min_p.y
	
	if poly_w == 0.0: poly_w = 1.0
	if poly_h == 0.0: poly_h = 1.0
	
	# 4. Map the physical vertices directly to the newly calculated texture coordinates
	for i in range(base_points.size()):
		var p := base_points[i]
		
		# Normalize the physical coordinate space to a clean 0.0 - 1.0 range
		var norm_x := (p.x - min_p.x) / poly_w
		var norm_y := (p.y - min_p.y) / poly_h
		
		# Translate normalized space into the exact pixel window of the new frame
		var uv_x := u_left + (norm_x * frame_w)
		var uv_y := v_top + (norm_y * frame_h)
		
		shifted_uvs[i] = Vector2(uv_x, uv_y)
		
	polygon2d.uv = shifted_uvs


# Implementable conditions. Kept as comments here for reference so has_method works as tagging
#func on_active() -> void
#func on_deactive() -> void
#func on_stack_card(target: Card) -> void
#func on_append(deck:Array[CardData], data:CardData) -> void
#func on_trigger(data:CardData, mod:Callable) -> void
#func on_card_dropped_on(bot_card:CardData, top_card:CardData) -> void
#func on_game_end() -> void
#func on_score(target:Card) -> void
#func on_after_score() -> void
#func on_next() -> void
#func on_can_grab_stack(target : CardData) -> Array[CardData]
#func on_can_place_stack(stack: Array[CardData], target: CardData) -> Array[CardData]
#func on_run_scorer() -> void
#func on_score_row(zone : Array[ArrayCardData], row : int) -> void
#func on_score_col(zone : Array[ArrayCardData], col : int) -> void


#func on_cannot_stack(stack : CardData, to_stack : CardData) -> bool

#func on_round_start() -> void:
	#pass
#func on_round_end() -> void:
	#pass
#func on_card_enter_game(target:Card) -> void:
	#pass
#func on_card_leave_game(target:Card) -> void:
	#pass
#func stack_rule(target:Card) -> bool:
	#return false
#func on_stack_card(target:Card) -> void:
	#pass
#func pickup_rule(target:Card) -> bool:
	#return true
#func on_pickup(target:Card) -> void:
	#pass
#func on_submit(target:Card) -> void:
	#pass
#func on_card_click(target:Card) -> void:
	#pass
#func on_skill_activated(target:Card) -> void:
	#pass
#func score_rule() -> void:
	#pass
#func on_score(target:Card) -> void:
	#pass
#func on_after_score() -> void:
	#pass
#func on_game_start() -> void:
	#pass
#func on_game_win() -> void:
	#pass
#func on_game_loss() -> void:
	#pass
#func on_game_end() -> void:
	#pass
#func on_deck_enter(target:Card) -> void:
	#pass
#func on_discard(target:Card) -> void:
	#pass
#func on_delete(target:Card) -> void:
	#pass
#func on_draw(target:Card) -> void:
	#pass
#func on_append(deck:Array[CardData], data:CardData) -> void:
	#pass
#func on_trigger(data:CardData, mod:Callable) -> void:
	#pass	
#func on_card_dropped_on(bot_card:CardData, top_card:CardData) -> void:
	#pass

func is_active() -> bool:
	if CardEnvironment.CURRENT and CardEnvironment.CURRENT.is_data_in_rules(data):
		return true
	if data.stamp is StampGlobal:
		return true
	if data.stamp is StampRevealing:
		return true
	return false

#func card_shake(card_effect:Callable) -> void:
	#await card_raise()
	#await card_effect.call()
	#await card_lower()
		#
#func card_raise() -> void:
	#await _do_popup(&"card_raise")
#
#func card_lower() -> void:
	#await _do_popup(&"card_lower")
#
#func card_shrink() -> void:
	#await _do_popup(&"card_shrink")
#
#func _do_popup(method:StringName) -> void:
	#var popup_card : CardVisual
	#var temp_card := false
	##if data.card:
		##popup_card = data.card
	#if method == &"card_raise":
		#match data.stage:
			#data.Stage.DRAW:
				#popup_card = CardEnvironment.CURRENT.deck_popup
			#data.Stage.DISCARD:
				#popup_card = CardEnvironment.CURRENT.discard_popup
		#if not popup_card:
			#return
		#var new_popup_card := popup_card.duplicate(8)
		#popup_card.get_parent().add_child(new_popup_card)
		#popup_card = new_popup_card
		#popup_card.data = data
		#temp_card = true
		#popup_card.flipped = !popup_card.flipped
		#popup_card.show()
	#else:
		#return
	#await Callable(CardEnvironment.CURRENT, method).call(popup_card)
	#if temp_card:
		#await Callable(CardEnvironment.CURRENT, &"card_lower").call(popup_card)
		#popup_card.queue_free()
			
