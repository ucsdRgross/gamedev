@tool
class_name TriangleMap
extends Container

signal card_clicked(card_data: CardData)
signal card_hovered(card_data: CardData)
signal deck_clicked(card_data: CardData)

# --- Configuration Options ---
@export_range(2, 10) var height_rows: int = 4:
	set(value):
		height_rows = max(value, 2)
		queue_sort()

@export var choices_width: int = 3 # Elements in the bottom selection row
@export var h_separation: float = 8.0
@export var v_separation: float = 12.0

# --- Core Matrix Registries ---
var _data_matrix: Array[Array] = []

var ui_data: Dictionary[Control, CardData]
var data_ui: Dictionary[CardData, Control]
var data_card: Dictionary[CardData, CardVisual]

var _is_shifting_anim: bool = false

func _ready() -> void:
	for child: Node in get_children():
		child.queue_free()
	_clear_all_registries()

func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		if not _is_shifting_anim:
			_apply_triangular_layout(false)

# ==========================================
# 📥 DATA INPUT STORAGE ENGINE
# ==========================================

func push_row_data(row_array: Array[CardData]) -> void:
	var total_stored: int = _data_matrix.size()
	
	if total_stored >= height_rows:
		print("Triangle Container Full: New entry block ignored.")
		return
		
	var target_row_idx: int = total_stored
	var valid_width: int = _get_row_capacity_for_load(target_row_idx)

	var clean_row: Array[CardData] = []
	for i: int in range(valid_width):
		if i < row_array.size():
			clean_row.append(row_array[i])
		else:
			clean_row.append(null)
			
	_data_matrix.append(clean_row)
	
	if _is_shifting_anim:
		_rebuild_physical_grid()

func finalize_map_generation() -> void:
	_rebuild_physical_grid()

## Calculates baseline width rules assuming the pyramid scales from top to bottom
func _get_row_capacity_for_load(row_index: int) -> int:
	return choices_width + ((height_rows - 1 - row_index) * 2)

## Calculates current width capacities based dynamically on how many layers remain active
func _get_active_row_capacity(row_index: int) -> int:
	var active_layers: int = _data_matrix.size()
	return choices_width + ((active_layers - 1 - row_index) * 2)

# ==========================================
# 📐 GRID CONSTRUCTION & CALCULATIONS
# ==========================================

func _clear_all_registries() -> void:
	ui_data.clear()
	data_ui.clear()
	for visual: CardVisual in data_card.values():
		if is_instance_valid(visual): 
			visual.queue_free()
	data_card.clear()

func _rebuild_physical_grid() -> void:
	var old_visuals: Dictionary[CardData, CardVisual] = data_card.duplicate()
	
	for card_data: CardData in old_visuals:
		var visual: CardVisual = old_visuals[card_data]
		if is_instance_valid(visual) and visual.get_parent() == self:
			remove_child(visual)
			
	ui_data.clear()
	data_ui.clear()
	data_card.clear()
	
	for child: Node in get_children():
		child.queue_free()
		
	for r: int in range(_data_matrix.size()):
		var current_row_data: Array = _data_matrix[r]
		# Use the active row width math to allocate the correct slot count
		var active_width: int = _get_active_row_capacity(r)
		
		for c: int in range(active_width):
			var card_data: CardData = null
			if c < current_row_data.size():
				card_data = current_row_data[c]
				
			var slot: Control = Control.new()
			slot.custom_minimum_size = CardVisual.card_size_play
			slot.size = CardVisual.card_size_play
			slot.add_to_group("TriangleGridSlot")
			
			slot.name = "Slot_R%d_C%d" % [r, c]
			add_child(slot)
			
			if card_data != null:
				ui_data[slot] = card_data
				data_ui[card_data] = slot
				slot.focus_mode = Control.FOCUS_ALL
				_wire_slot_input_events(slot, r, c)
				
				if card_data in old_visuals and is_instance_valid(old_visuals[card_data]):
					data_card[card_data] = old_visuals[card_data]
					data_card[card_data].control_anchor = slot
					add_child(data_card[card_data])
				else:
					var visual: CardVisual = CardVisual.add_child_card_visual(self, card_data, CardVisual.DisplayContext.MAP, slot)
					data_card[card_data] = visual
					visual.global_position = size / 2.0
					visual.can_rot_anim = false
					
	queue_sort()

func _apply_triangular_layout(animate: bool) -> void:
	# Filter only the valid slots, ignoring any lingering Node2D sibling nodes
	var slots: Array[Node] = get_children().filter(func(c: Node) -> bool: return c.is_in_group("TriangleGridSlot"))
	if slots.is_empty(): return
	
	var slot_ptr: int = 0
	var card_size: Vector2 = CardVisual.card_size_play
	var scale_factor: float = SettingsManager.settings.card_scale
	
	var total_pyramid_height: float = (height_rows * card_size.y) + ((height_rows - 1) * v_separation * scale_factor)
	var start_y_origin: float = size.y - total_pyramid_height
	
	# Centering override rule if rows drop below the height initialization configuration limits
	if _data_matrix.size() < height_rows:
		var active_height: float = (_data_matrix.size() * card_size.y) + ((_data_matrix.size() - 1) * v_separation * scale_factor)
		start_y_origin = (size.y - active_height) / 2.0

	for r: int in range(_data_matrix.size()):
		# Fix: Use active layout capacities to track row placement metrics perfectly
		var row_width_capacity: int = _get_active_row_capacity(r)
		var total_row_width: float = (row_width_capacity * card_size.x) + ((row_width_capacity - 1) * h_separation * scale_factor)
		var start_x: float = (size.x - total_row_width) / 2.0
		
		for c: int in range(row_width_capacity):
			if slot_ptr >= slots.size(): break
			var slot: Control = slots[slot_ptr] as Control
			
			var x_pos: float = start_x + (c * (card_size.x + h_separation * scale_factor))
			var y_pos: float = start_y_origin + (r * (card_size.y + v_separation * scale_factor))
			var target_pos: Vector2 = Vector2(x_pos, y_pos)
			
			if animate:
				var tween: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				tween.tween_property(slot, "position", target_pos, 0.3)
			else:
				fit_child_in_rect(slot, Rect2(target_pos, card_size))
				
			slot_ptr += 1
			
	_wire_focus_neighbors(slots)

func _wire_slot_input_events(slot: Control, row: int, col: int) -> void:
	slot.gui_input.connect(func(event: InputEvent) -> void:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event and mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_on_bottom_card_clicked(slot, row, col)
	)
	slot.mouse_entered.connect(func() -> void:
		slot.grab_focus()
		if slot in ui_data: 
			card_hovered.emit(ui_data[slot])
	)

# ==========================================
# ✂️ TRINARY CHOICE TRIMMING ENGINE
# ==========================================

func _on_bottom_card_clicked(slot: Control, row_idx: int, choice_col: int) -> void:
	if row_idx != _data_matrix.size() - 1:
		print("Interaction Rejected: Not a bottom row option.")
		return
		
	var selected_data: CardData = ui_data[slot]
	card_clicked.emit(selected_data)
	_is_shifting_anim = true
	
	selected_data.stage = CardData.Stage.DISCARD
	if selected_data in data_card:
		data_card[selected_data].floating = false
	
	var left_crop_offset: int = 0
	match choice_col:
		0: left_crop_offset = 0
		1: left_crop_offset = 1
		2: left_crop_offset = 2
		
	var next_matrix: Array[Array] = []
	
	for r: int in range(_data_matrix.size() - 1):
		var old_row: Array = _data_matrix[r]
		# Fix: Use active row indexing boundaries during structural trim operations
		var next_row_capacity: int = _get_active_row_capacity(r + 1)
		
		var sliced_row: Array[CardData] = []
		for c: int in range(next_row_capacity):
			var source_col: int = left_crop_offset + c
			if source_col >= 0 and source_col < old_row.size():
				sliced_row.append(old_row[source_col] as CardData)
			else:
				sliced_row.append(null)
		next_matrix.append(sliced_row)
		
	_data_matrix = next_matrix

	_resolve_empty_layer_cascades()

	_rebuild_physical_grid()
	_apply_triangular_layout(true)
	
	#await get_tree().create_timer(0.32).timeout
	_is_shifting_anim = false
	queue_sort()

func _resolve_empty_layer_cascades() -> void:
	while !_data_matrix.is_empty():
		var bottom_row: Array = _data_matrix[-1]
		var row_has_options: bool = false
		
		for item: CardData in bottom_row:
			if item != null:
				row_has_options = true
				break
				
		if not row_has_options:
			_data_matrix.pop_back()
			print("Dead layer detected: Collapsing row downward.")
		else:
			break

func _wire_focus_neighbors(slots: Array[Node]) -> void:
	var row_map: Array[Array] = []
	var child_idx: int = 0
	
	for row: int in range(_data_matrix.size()):
		var row_elements: Array[Control] = []
		var count: int = _get_active_row_capacity(row)
		for i: int in range(count):
			if child_idx < slots.size():
				row_elements.append(slots[child_idx] as Control)
				child_idx += 1
		row_map.append(row_elements)
		
	for r: int in range(row_map.size()):
		var current_row: Array = row_map[r]
		for c: int in range(current_row.size()):
			var node: Control = current_row[c] as Control
			if not is_instance_valid(node): continue
			
			if c > 0 and is_instance_valid(current_row[c - 1] as Control):
				node.focus_neighbor_left = (current_row[c - 1] as Control).get_path()
			if c < current_row.size() - 1 and is_instance_valid(current_row[c + 1] as Control):
				node.focus_neighbor_right = (current_row[c + 1] as Control).get_path()
				
			if r < row_map.size() - 1:
				var next_row: Array = row_map[r + 1]
				if !next_row.is_empty():
					var clamped_col: int = clamp(c, 0, next_row.size() - 1)
					var target_bottom: Control = next_row[clamped_col] as Control
					if is_instance_valid(target_bottom):
						node.focus_neighbor_bottom = target_bottom.get_path()
					
			if r > 0:
				var prev_row: Array = row_map[r - 1]
				if !prev_row.is_empty():
					var parent_col: int = clamp(c, 0, prev_row.size() - 1)
					var target_top: Control = prev_row[parent_col] as Control
					if is_instance_valid(target_top):
						node.focus_neighbor_top = target_top.get_path()

func _get_minimum_size() -> Vector2:
	var card_size: Vector2 = CardVisual.card_size_play
	var scale_factor: float = SettingsManager.settings.card_scale
	var max_capacity: int =  _get_row_capacity_for_load(0)
	var max_width: float = (max_capacity * card_size.x) + ((max_capacity - 1) * h_separation * scale_factor)
	var total_height: float = (height_rows * card_size.y) + ((height_rows - 1) * v_separation * scale_factor)
	return Vector2(max_width, total_height)
