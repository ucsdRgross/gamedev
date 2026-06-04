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
var character_slot: Control = null

func _ready() -> void:
	for child: Node in get_children():
		child.queue_free()
	_clear_all_registries()

func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		if not _is_shifting_anim:
			_apply_triangular_layout(false, false)

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

## Calculates width capacities for a hypothetical matrix size
func _get_row_capacity_at_size(row_index: int, total_rows: int) -> int:
	return choices_width + ((total_rows - 1 - row_index) * 2)

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

func _rebuild_physical_grid(temp_matrix: Array = []) -> void:
	# 1. Map current data to their current visual positions to preserve slide origin
	var data_to_old_pos: Dictionary[CardData, Vector2] = {}
	for card_data in data_ui:
		var old_slot: Control = data_ui[card_data]
		if is_instance_valid(old_slot):
			data_to_old_pos[card_data] = old_slot.position
			
	var old_visuals: Dictionary[CardData, CardVisual] = data_card.duplicate()
	
	# Detach visuals to allow re-anchoring
	for card_data: CardData in old_visuals:
		var visual: CardVisual = old_visuals[card_data]
		if is_instance_valid(visual) and visual.get_parent() == self:
			remove_child(visual)
			
	ui_data.clear()
	data_ui.clear()
	data_card.clear()
	
	# 2. Collect all existing slots for recycling
	var slot_pool: Array[Node] = get_children().filter(func(child: Node) -> bool:
		return child.is_in_group("TriangleGridSlot") and child != character_slot
	)
	for slot: Control in slot_pool:
		slot.hide()
		# Clear old connections to prevent signal stacking
		for connection : Dictionary in slot.gui_input.get_connections():
			slot.gui_input.disconnect(connection.callable as Callable)
		for connection : Dictionary in slot.mouse_entered.get_connections():
			slot.mouse_entered.disconnect(connection.callable as Callable)

	var matrix_to_use: Array = temp_matrix if not temp_matrix.is_empty() else _data_matrix
	var matrix_size: int = matrix_to_use.size()
	
	var slot_ptr: int = 0
	for r: int in range(matrix_size):
		var current_row_data: Array = matrix_to_use[r]
		var total_width: int = current_row_data.size() if not temp_matrix.is_empty() else _get_active_row_capacity(r)
		
		for c: int in range(total_width):
			var card_data: CardData = null
			if c < current_row_data.size():
				card_data = current_row_data[c]
				
			var slot: Control
			if slot_ptr < slot_pool.size():
				slot = slot_pool[slot_ptr] as Control
				slot.show()
			else:
				slot = Control.new()
				slot.custom_minimum_size = CardVisual.card_size_play
				slot.size = CardVisual.card_size_play
				slot.add_to_group("TriangleGridSlot")
				add_child(slot)
			
			slot.name = "Slot_R%d_C%d" % [r, c]
			slot.set_meta("row", r)
			slot.set_meta("col", c)
			
			var is_invisible_edge: bool = false
			if not temp_matrix.is_empty() and (c < 2 or c >= total_width - 2):
				is_invisible_edge = true
				
			slot.visible = not is_invisible_edge
			
			if card_data != null:
				if not is_invisible_edge:
					ui_data[slot] = card_data
					data_ui[card_data] = slot
					slot.focus_mode = Control.FOCUS_ALL
					_wire_slot_input_events(slot, r, c)
				
				# CRITICAL: Initialize recycled slot position to the card's old position
				if card_data in data_to_old_pos:
					slot.position = data_to_old_pos[card_data]
				
				if card_data in old_visuals and is_instance_valid(old_visuals[card_data]):
					data_card[card_data] = old_visuals[card_data]
					data_card[card_data].control_anchor = slot
					add_child(data_card[card_data])
				else:
					var visual: CardVisual = CardVisual.add_child_card_visual(self, card_data, CardVisual.DisplayContext.MAP, slot)
					data_card[card_data] = visual
					visual.global_position = size / 2.0
					visual.can_rot_anim = false
			
			slot_ptr += 1

	# 3. Handle character slot
	if not character_slot or not is_instance_valid(character_slot):
		character_slot = Control.new()
		character_slot.custom_minimum_size = CardVisual.card_size_play
		character_slot.size = CardVisual.card_size_play
		character_slot.add_to_group("TriangleGridSlot")
		character_slot.name = "Slot_Character"
		add_child(character_slot)
	
	character_slot.set_meta("row", matrix_size)
	character_slot.set_meta("col", 0)
	character_slot.visible = false
					
	queue_sort()

func get_slot_position(r: int, c: int, matrix_size: int, has_invisible_edges: bool) -> Vector2:
	var card_size: Vector2 = CardVisual.card_size_play
	var scale_factor: float = SettingsManager.settings.card_scale
	
	var total_pyramid_height: float = ((height_rows + 1) * card_size.y) + (height_rows * v_separation * scale_factor)
	var start_y_origin: float = size.y - total_pyramid_height
	
	if matrix_size < height_rows:
		var active_height: float = ((matrix_size + 1) * card_size.y) + (matrix_size * v_separation * scale_factor)
		start_y_origin = (size.y - active_height) / 2.0

	var row_width_capacity: int = 1
	if r < matrix_size:
		row_width_capacity = choices_width + ((matrix_size - 1 - r) * 2)
		if has_invisible_edges:
			row_width_capacity += 4
	elif has_invisible_edges and r == matrix_size:
		# Keep the old bottom row's width stable during the slide
		row_width_capacity = choices_width + 4
	
	var total_row_width: float = (row_width_capacity * card_size.x) + ((row_width_capacity - 1) * h_separation * scale_factor)
	var start_x: float = (size.x - total_row_width) / 2.0
	
	var x_pos: float = start_x + (c * (card_size.x + h_separation * scale_factor))
	var y_pos: float = start_y_origin + (r * (card_size.y + v_separation * scale_factor))
	return Vector2(x_pos, y_pos)

func get_slot_control(r: int, c: int, has_invis: bool) -> Control:
	var slots: Array[Node] = get_children().filter(func(node:Node)->bool: return node.is_in_group("TriangleGridSlot"))
	var slot_idx: int = 0
	for row in range(r):
		var count: int = _get_active_row_capacity(row)
		if has_invis:
			count += 2
		slot_idx += count
	slot_idx += c
	if slot_idx < slots.size():
		return slots[slot_idx] as Control
	return null

func _apply_triangular_layout(animate: bool, has_invisible_edges: bool = false) -> void:
	# Filter only the valid slots, ignoring any lingering Node2D sibling nodes
	var slots: Array[Node] = get_children().filter(func(c: Node) -> bool: return c.is_in_group("TriangleGridSlot"))
	if slots.is_empty(): return
	
	var card_size: Vector2 = CardVisual.card_size_play
	var active_layers: int = _data_matrix.size()
	
	for slot: Control in slots:
		var r: int = slot.get_meta("row", -1)
		var c: int = slot.get_meta("col", -1)
		
		if r == -1: continue
		
		var target_pos: Vector2 = get_slot_position(r, c, active_layers, has_invisible_edges)
		fit_child_in_rect(slot, Rect2(target_pos, card_size))
				
	if not has_invisible_edges:
		var active_slots: Array[Node] = slots.filter(func(s: Control) -> bool: return s.visible)
		_wire_focus_neighbors(active_slots)

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
	if _is_shifting_anim:
		return
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
		
	var current_matrix: Array = _data_matrix.duplicate(true)
	var current_size: int = current_matrix.size()
	var next_size: int = current_size - 1
	
	# 1. Build the next state matrix (the final destination data)
	var next_matrix: Array[Array] = []
	for r: int in range(next_size):
		var old_row: Array = current_matrix[r]
		var active_width: int = _get_row_capacity_at_size(r, next_size)
		var sliced_row: Array[CardData] = []
		for c: int in range(active_width):
			var source_col: int = left_crop_offset + c
			if source_col >= 0 and source_col < old_row.size():
				sliced_row.append(old_row[source_col])
			else:
				sliced_row.append(null)
		next_matrix.append(sliced_row)
	
	# 2. Build the temp matrix for the transition animation.
	# It must have the same number of rows as the CURRENT matrix so the bottom row can animate.
	var temp_matrix: Array[Array] = []
	for r: int in range(current_size):
		var old_row: Array = current_matrix[r]
		# The slots in the temp matrix should be wide enough to accommodate diagonal shifts.
		# We add 4 slots (2 on each side) to provide a sufficient buffer.
		var row_width: int = _get_row_capacity_at_size(r, next_size) if r < next_size else choices_width
		var total_width: int = row_width + 4
		
		# Calculate where the center of this row is in the new transition grid
		var target_center: int = (total_width - 1) / 2
		# Calculate which index in the OLD row corresponds to the selected path
		var old_center_path: int = (current_size - r) + choice_col - 1
		
		var temp_row: Array[CardData] = []
		temp_row.resize(total_width)
		temp_row.fill(null)
		
		for old_c: int in range(old_row.size()):
			var card_data: CardData = old_row[old_c] as CardData
			if card_data != null:
				# Map cards such that the old_center_path aligns with the target_center
				var new_c: int = old_c - old_center_path + target_center
				if new_c >= 0 and new_c < total_width:
					temp_row[new_c] = card_data
					
		temp_matrix.append(temp_row)
		
	_data_matrix = next_matrix
	_resolve_empty_layer_cascades()
	
	# NEW: Identify and handle cards being removed from the map
	var kept_cards: Dictionary[CardData, bool] = {}
	for row in _data_matrix:
		for card :CardData in row:
			if card: kept_cards[card] = true
	
	for r: int in range(current_size):
		for card_data: CardData in current_matrix[r]:
			if card_data and not card_data in kept_cards:
				# This card is being removed. 
				# You can trigger exit animations on data_card[card_data] here.
				if card_data in data_card:
					var visual: CardVisual = data_card[card_data]
					# Placeholder for your animation logic:
					pass
	
	# 3. Rebuild physical grid using the temp matrix (new slots start at old positions)
	_rebuild_physical_grid(temp_matrix)
	
	# 4. Trigger slide transition
	_apply_triangular_layout(true, true)
	
	# 5. Wait for the transition to finish
	await get_tree().create_timer(0.3).timeout
	
	# 6. Rebuild physical grid for real (cleans up invisible edge slots and frees their card visuals)
	_rebuild_physical_grid()
	_apply_triangular_layout(false, false)
	
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
	var total_height: float = ((height_rows + 1) * card_size.y) + (height_rows * v_separation * scale_factor)
	return Vector2(max_width, total_height)
