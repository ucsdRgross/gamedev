extends Node3D
class_name Map

signal enter_game

@onready var triangle_map: TriangleMap = $TiltedGUI/SubViewport/TriangleMap
@onready var preview_label: Label = $Preview/Label
@onready var flow_container: FlowContainer = %FlowContainer
@onready var deck_viewer: DeckViewer = $DeckViewer
@onready var layer_label: Label = $Layer

func _ready() -> void:
	# Force show/hide on startup to sync FlowContainer caches and drop initialization race conditions
	deck_viewer.show()
	deck_viewer.hide()
	
	triangle_map.card_clicked.connect(_on_card_clicked)
	triangle_map.card_hovered.connect(_on_card_hover_entered)
	
	preview_label.text = ""
	update_layer(0)
	
	#_sync_flow_container_with_saved_deck()
	_initialize_triangle_map_data()

func _on_card_clicked(card_data: CardData) -> void:
	if not card_data: 
		return
		
	update_layer(1)
	add_card_data_to_deck(card_data)

func update_layer(i: int) -> void:
	if Main.save_info:
		Main.save_info.layer += i
		layer_label.text = "Layer: " + str(Main.save_info.layer)

func _on_card_hover_entered(card_data: CardData) -> void:
	if not card_data: 
		return
		
	var description: String = ""
	if card_data.skill:
		description += card_data.skill.get_str() + "\n" + card_data.skill.get_description() + "\n"
	if card_data.stamp:
		description += card_data.stamp.get_str() + "\n" + card_data.stamp.get_description() + "\n"
	if card_data.type:
		description += card_data.type.get_str() + "\n" + card_data.type.get_description() + "\n"
		
	preview_label.text = description

func add_card_data_to_deck(data: CardData) -> void:
	if not Main.save_info: 
		return
		
	Main.save_info.card_datas.append(data)
	#
	#var control_slot: Control = CARD_CONTROL.instantiate() as Control
	#flow_container.add_child(control_slot)
	#
	#var card_visual: CardVisual = CardVisual.add_child_card_visual(
		#control_slot, 
		#data, 
		#CardVisual.DisplayContext.PREVIEW, 
		#control_slot
	#)
	#card_visual.can_move_anim = false
	#card_visual.floating = false
	#card_visual.show_front = true

#func _sync_flow_container_with_saved_deck() -> void:
	#if not Main.save_info or not "card_datas" in Main.save_info: 
		#return
		#
	#for child: Node in flow_container.get_children():
		#flow_container.remove_child(child)
		#child.queue_free()
		#
	#for data: CardData in Main.save_info.card_datas:
		#var control_slot: Control = CARD_CONTROL.instantiate() as Control
		#flow_container.add_child(control_slot)
		#
		#var card_visual: CardVisual = CardVisual.add_child_card_visual(
			#control_slot, 
			#data, 
			#CardVisual.DisplayContext.PREVIEW, 
			#control_slot
		#)
		#card_visual.can_move_anim = false
		#card_visual.floating = false
		#card_visual.show_front = true

# ==========================================
# 📐 TRIANGLE DATA INITIALIZATION SEED
# ==========================================

func _initialize_triangle_map_data() -> void:
	# Keep row iteration simple and uniform: processes cleanly from Top to Bottom
	for current_row_idx: int in range(triangle_map.height_rows):
		var row_capacity: int = triangle_map.choices_width + ((triangle_map.height_rows - 1 - current_row_idx) * 2)
		var generated_row_data: Array[CardData] = []
		
		for slot_idx: int in range(row_capacity):
			var card_data: CardData = _generate_random_map_card()
			generated_row_data.append(card_data)
			
		triangle_map.push_row_data(generated_row_data)
		
	# Finalize data mapping and load layout configurations once
	triangle_map.finalize_map_generation()

func _generate_random_map_card() -> CardData:
	var card: CardData = CardData.new()
	card.with_rank(PipRank.Numeral.new().with_random())
	card.with_suit(PipSuit.Standard.new().with_random())
	#card.stage = CardData.Stage.ZONE
	card.flipped = false
	return card

func _on_deck_clicked(card_data: CardData) -> void:
	var data_array: Array[CardData] = []
	if Main.save_info and "card_datas" in Main.save_info:
		data_array = Main.save_info.card_datas
	deck_viewer.show_with_deck(data_array)

func _on_margin_container_gui_input(event: InputEvent) -> void:
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event and mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
		deck_viewer.hide()

func _on_button_pressed() -> void:
	enter_game.emit()
