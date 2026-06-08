extends CardEnvironment
class_name Map

signal enter_game

@onready var triangle_map: TriangleMap = %TriangleMap
@onready var preview_label: Label = %PreviewLabel
@onready var flow_container: FlowContainer = %FlowContainer
@onready var layer_label: Label = %LayerLabel

func get_card_collections() -> Array:
	return [
		Main.save_info.card_datas,
		Main.save_info.rule_datas
	]

func get_rules_collections() -> Array:
	return [Main.save_info.rule_datas]

func _ready() -> void:
	# Force show/hide on startup to sync FlowContainer caches and drop initialization race conditions
	
	triangle_map.card_clicked.connect(_on_card_clicked)
	triangle_map.card_hovered.connect(_on_card_hover_entered)
	
	preview_label.text = ""
	update_layer(0)
	
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
	card.flipped = false
	return card

func _on_deck_clicked(card_data: CardData) -> void:
	var data_array: Array[CardData] = []
	if Main.save_info and "card_datas" in Main.save_info:
		data_array = Main.save_info.card_datas
	DeckViewer.show_deck(self, data_array)

#func _on_margin_container_gui_input(event: InputEvent) -> void:
	#var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	#if mouse_event and mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
		#deck_viewer.hide()

func _on_button_pressed() -> void:
	enter_game.emit()
