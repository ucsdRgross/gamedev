extends Control
class_name PlayArea

signal data_selected(data : CardData)

var focused_control : Control = null
var moused_hovered_control : Control = null
var selected_cards : Array[CardData] = []

var separation : int = 4: 
	set(value):
		separation = value
		set_separation()
	get():
		return separation * SettingsManager.settings.card_scale

var ui_data : Dictionary[Control, CardData]
var data_ui : Dictionary[CardData, Control]
var data_card : Dictionary[CardData, CardVisual]
var new_data_card : Dictionary[CardData, CardVisual]

@onready var containers : Array[Control] = [%TopLevelVBox, %UpperZone, %UpperZoneLeft, 
								%UpperZoneRight, %MiddleZone, %MiddleZoneRight, 
								%LowerZone, %LowerZoneLeft, %LowerZoneRight]
@onready var upper_zone_left: VBoxContainer = %UpperZoneLeft
@onready var lower_zone_left: VBoxContainer = %LowerZoneLeft
@onready var upper_zone_right: HBoxContainer = %UpperZoneRight
@onready var lower_zone_right: HBoxContainer = %LowerZoneRight
@onready var middle_zone_left: Control = %MiddleZoneLeft
@onready var middle_zone_right: HBoxContainer = %MiddleZoneRight

func _ready() -> void:
	SettingsManager.settings_changed.connect(update_gui)
	setup_gui()

func setup_gui() -> void:
	set_separation()
	set_card_zones()
	update_score_controls()
	middle_zone_left.custom_minimum_size = Vector2.ONE * CardVisual.card_separation_play

func update_gui() -> void:
	set_separation()
	set_card_zones_visuals()
	update_score_controls()
	middle_zone_left.custom_minimum_size = Vector2.ONE * CardVisual.card_separation_play

func _on_gui_input(event: InputEvent) -> void:
	flush_rebuild() #reads ui_data
	# Mouse
	if event is InputEventMouseButton:
		var mouse_event : InputEventMouseButton = event
		# left click
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			# is_instance_valid guard: a board rebuild (e.g. submit clearing the board)
			# can free the control this still points at, and `freed in typed_dict` errors.
			if (is_instance_valid(focused_control)
					and focused_control == moused_hovered_control
					and focused_control in ui_data):
					#and not focused_control.is_in_group("CardVisualZoneControl")):
				data_selected.emit(ui_data[focused_control])
	# Controller
	if event.is_action_pressed("ui_accept"):
		if is_instance_valid(focused_control) and focused_control in ui_data:
			data_selected.emit(ui_data[focused_control])
	if event.is_action_pressed("ui_cancel"):
		ungrab_cards()

# since clicks outside of play area can happen
func _input(event: InputEvent) -> void:
	# Mouse
	if event is InputEventMouseButton:
		var mouse_event : InputEventMouseButton = event
		# right click / cancel
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			ungrab_cards()
			
func grab_cards(datas:Array[CardData]) -> void:
	flush_rebuild() #reads data_card / data_ui
	ungrab_cards()
	selected_cards = datas
	set_card_zones_visuals()
	for index in selected_cards.size():
		var data := selected_cards[index]
		if data in data_card: 
			var card_visual := data_card[data]
			card_visual.held = index + 1
			card_visual.z_index = get_tree().get_nodes_in_group("CardVisualControl").size() + index + 1
			var card_control := data_ui[data]
			card_control.mouse_filter = Control.MOUSE_FILTER_IGNORE

func ungrab_cards() -> void:
	flush_rebuild() #reads data_card / data_ui
	for data in selected_cards:
		if data in data_card: 
			var card_visual := data_card[data]
			card_visual.held = 0
			var card_control := data_ui[data]
			card_control.mouse_filter = Control.MOUSE_FILTER_PASS
	selected_cards = []
	set_card_zones_visuals()

#No per-frame processing: Game relays GameData.board_changed (emitted by every
#revision bump, i.e. every board mutation) to queue_rebuild(). Focus/selection
#changes don't touch the board and call set_card_zones_visuals() directly.

#Any number of rebuild requests within one frame collapse into a single
#set_card_zones() at end of frame (call_deferred). A direct synchronous
#set_card_zones() (setup_gui/undo) clears the pending request instead.
var _rebuild_queued := false

func queue_rebuild() -> void:
	if _rebuild_queued: return
	_rebuild_queued = true
	_deferred_rebuild.call_deferred()

func _deferred_rebuild() -> void:
	if not _rebuild_queued: return #a direct rebuild already happened this frame
	set_card_zones()

#GUARD RULE: ui_data / data_ui / data_card and the control tree are only valid for
#the CURRENT revision. Anything that reads them must flush the queued rebuild first,
#or it operates on a stale layout (out-of-bounds crashes, missing visuals).
func flush_rebuild() -> void:
	if _rebuild_queued:
		set_card_zones()

func set_separation() -> void:
	for container : Control in containers:
		container.add_theme_constant_override("separation", separation)

func set_card_zones() -> void:
	_rebuild_queued = false #this rebuild satisfies any queued request
	var game := CardEnvironment.get_current_game()
	if not game: return
	ui_data.clear()
	data_ui.clear()
	var game_state := game.state
	# Handles structural validation, instantiations, and dictionary mapping
	set_card_zone(upper_zone_right, game_state.upper_zone_type, game_state.upper_zone)
	set_card_zone(lower_zone_right, game_state.lower_zone_type, game_state.lower_zone)
	data_card = new_data_card
	new_data_card = {}
	set_card_zones_visuals()

func set_card_zones_visuals() -> void:
	#a queued rebuild means the control tree is STALE vs the state arrays — running
	#the visual pass against it can index out of bounds. Flush the rebuild instead
	#(set_card_zones ends with the visual pass anyway).
	if _rebuild_queued:
		flush_rebuild()
		return
	var game := CardEnvironment.get_current_game()
	if not game: return
	var game_state := game.state
	# Handles sizing, Z-indexing, style overrides, and focus logic safely
	update_card_zone_visuals(upper_zone_right, game_state.upper_zone_type, game_state.upper_zone)
	update_card_zone_visuals(lower_zone_right, game_state.lower_zone_type, game_state.lower_zone)

func set_card_zone(hbox: HBoxContainer, type: Array[CardData], datas: Array[ArrayCardData]) -> void:
	var card_columns := type.size()
	var column_diff: int = card_columns - hbox.get_child_count()
	
	# Structure layout columns
	if column_diff > 0:
		for i in column_diff:
			var new_vbox := VBoxContainer.new()
			new_vbox.add_theme_constant_override("separation", separation)
			hbox.add_child(new_vbox)
	elif column_diff < 0:
		for i in absi(column_diff):
			var child: Control = hbox.get_child(-1)
			hbox.remove_child(child)
			child.queue_free()

	# Structure rows per column and register data mappings
	for i in type.size():
		var card_rows := datas[i].datas.size() + 1 # +1 for zone/type
		var vbox: VBoxContainer = hbox.get_child(i)
		var row_diff: int = card_rows - vbox.get_child_count()
		
		if row_diff > 0:
			for j in row_diff:
				var new_control := create_card_control()
				vbox.add_child(new_control)
		elif row_diff < 0:
			for j in absi(row_diff):
				var child: Control = vbox.get_child(-1)
				vbox.remove_child(child)
				child.queue_free()
				
		# Map the main Zone/Type Control (Index 0)
		var c: Control = vbox.get_child(0)
		var connected_data: CardData = type[i]
		ui_data[c] = connected_data
		data_ui[connected_data] = c
		
		if connected_data in data_card and is_instance_valid(data_card[connected_data]):
			new_data_card[connected_data] = data_card[connected_data]
			new_data_card[connected_data].control_anchor = c
		else:
			new_data_card[connected_data] = CardVisual.add_child_card_visual(
				self, connected_data, CardVisual.DisplayContext.PLAY_AREA, c)			
		# Map the individual Row Cards (Index 1 onwards)
		for j in range(1, vbox.get_child_count()):
			c = vbox.get_child(j)
			connected_data = datas[i].datas[j-1]
			ui_data[c] = connected_data
			data_ui[connected_data] = c
			
			if connected_data in data_card and is_instance_valid(data_card[connected_data]):
				new_data_card[connected_data] = data_card[connected_data]
				new_data_card[connected_data].control_anchor = c
			else:
				new_data_card[connected_data] = CardVisual.add_child_card_visual(
					self, connected_data, CardVisual.DisplayContext.PLAY_AREA, c)

func update_card_zone_visuals(hbox: HBoxContainer, type: Array[CardData], datas: Array[ArrayCardData]) -> void:
	var card_count: int = 0
	
	for i in type.size():
		var vbox: VBoxContainer = hbox.get_child(i)
		vbox.add_theme_constant_override("separation", separation)
		
		# 1. Visual settings for Zone/Type Card (Index 0)
		var c: Control = vbox.get_child(0)
		c.custom_minimum_size = Vector2(CardVisual.card_size_play.x, 0)
		c.focus_mode = Control.FOCUS_ALL
		
		if selected_cards:
			if c == focused_control:
				c.custom_minimum_size = Vector2(CardVisual.card_size_play.x, CardVisual.card_separation_play_custom)
			elif vbox.get_child_count() > 1 and vbox.get_child(1) == focused_control:
				c.custom_minimum_size = Vector2(CardVisual.card_size_play.x, CardVisual.card_separation_play_custom / 2.5)
		elif vbox.get_child_count() != 1:
			c.focus_mode = Control.FOCUS_NONE
			
		var connected_data: CardData = type[i]
		card_count += 1
		
		# Safe: Reads from the active finalized visual tracker registry
		var card_visual: CardVisual = data_card.get(connected_data)
		if card_visual and connected_data not in selected_cards:
			card_visual.z_index = card_count

		# 2. Visual settings for Row Cards (Index 1 onwards)
		for j in range(1, vbox.get_child_count()):
			c = vbox.get_child(j)
			c.custom_minimum_size = Vector2(CardVisual.card_size_play.x, CardVisual.card_separation_play_custom)

			connected_data = datas[i].datas[j-1]
			card_count += 1

			card_visual = data_card.get(connected_data)
			if card_visual and connected_data not in selected_cards:
				card_visual.z_index = card_count
				
		(vbox.get_child(-1) as Control).custom_minimum_size = CardVisual.card_size_play

	# 3. Focus neighborhood linking
	for i in type.size() - 1:
		var left: Control = hbox.get_child(i).get_child(0)
		var right: Control = hbox.get_child(i+1).get_child(0)
		left.focus_neighbor_right = right.get_path()
		right.focus_neighbor_left = left.get_path()

	# 4. Held stack expansion logic
	if selected_cards and selected_cards[0] in data_ui:
		var selected_control := data_ui[selected_cards[0]]
		var control_index := selected_control.get_index()
		if selected_control.get_index() > 0:
			var vbox: Control = selected_control.get_parent()
			(vbox.get_child(control_index - 1) as Control).custom_minimum_size = CardVisual.card_size_play
			if selected_control.get_index() == 1:
				(vbox.get_child(-1) as Control).custom_minimum_size = Vector2(CardVisual.card_size_play.x, 0)
			else:
				(vbox.get_child(-1) as Control).custom_minimum_size = Vector2(CardVisual.card_size_play.x, CardVisual.card_separation_play_custom)

func create_card_control() -> Control:
	var new_control := Control.new()
	new_control.add_to_group("CardVisualControl")
	new_control.focus_mode = Control.FOCUS_ALL
	new_control.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_ENABLED
	new_control.focus_entered.connect(func()->void:on_control_focus_entered(new_control))
	new_control.mouse_entered.connect(func()->void:
			new_control.grab_focus()
			moused_hovered_control = new_control)
	new_control.mouse_exited.connect(func()->void:
			if moused_hovered_control == new_control: moused_hovered_control = null)
	return new_control

var focused_visual : CardVisual
func on_control_focus_entered(control:Control) -> void:
	flush_rebuild() #reads ui_data / data_card
	var row_index := control.get_index()
	var column_node : Control = control.get_parent()
	if focused_visual: focused_visual.focused = false
	if ui_data.has(control) and data_card.has(ui_data[control]):
		focused_visual = data_card[ui_data[control]]
		focused_visual.focused = true
	
	#var column_index := column_node.get_index()
	#var zone_level : Control = column_node.get_parent()
	#if zone_level == upper_zone_right:
		#if row_index == 0:
			#data_selected.emit(CardEnvironment.CURRENT.upper_zone_type[column_index])
		#else:
			#data_selected.emit(CardEnvironment.CURRENT.upper_zone[column_index].datas[row_index - 1])
	#elif zone_level == lower_zone_right:
		#if row_index == 0:
			#data_selected.emit(CardEnvironment.CURRENT.lower_zone_type[column_index])
		#else:
			#data_selected.emit(CardEnvironment.CURRENT.lower_zone[column_index].datas[row_index - 1])
	# resize zone control so it is possible to place card behind first card
	if focused_control and focused_control.get_index() == 0:
		focused_control.custom_minimum_size = Vector2(CardVisual.card_size_play.x, 0)
		(focused_control.get_parent().get_child(-1) as Control).custom_minimum_size = CardVisual.card_size_play
	if row_index == 0:
		(column_node.get_child(0) as Control).custom_minimum_size = Vector2(CardVisual.card_size_play.x, CardVisual.card_separation_play_custom/1.5)
		(column_node.get_child(-1) as Control).custom_minimum_size = CardVisual.card_size_play
	elif row_index == 1:
		(column_node.get_child(0) as Control).custom_minimum_size = Vector2(CardVisual.card_size_play.x, CardVisual.card_separation_play_custom/2.5)
		(column_node.get_child(-1) as Control).custom_minimum_size = CardVisual.card_size_play
	focused_control = control
	set_card_zones_visuals()

func update_score_controls() -> void:
	var game := CardEnvironment.get_current_game()
	if not game: return
	var game_state := game.state
	set_score_zone(true, upper_zone_left, game_state.scores_row_upper)
	set_score_zone(true, lower_zone_left, game_state.scores_row_lower)
	set_score_zone(false, middle_zone_right, game_state.scores_col)
	
func set_score_zone(is_row:bool, zone:BoxContainer, scores:Array[BigNumber]) -> void:
	var scores_size := scores.size()
	if is_row and scores_size == 0: scores_size += 1 # there should always be at least 1 control as buffer
	var row_diff : int = scores_size - zone.get_child_count()
	if row_diff > 0:
		for i in row_diff:
			zone.add_child(BigNumberLabel.new())
	elif row_diff < 0:
		for i in absi(row_diff):
			var child : BigNumberLabel = zone.get_child(-1)
			zone.remove_child(child)
			child.queue_free()
	for i in zone.get_child_count():
		var label : BigNumberLabel = zone.get_child(i)
		if is_row:
			label.custom_minimum_size = Vector2(CardVisual.card_separation_play, CardVisual.card_separation_play_custom)
		else:
			label.custom_minimum_size = Vector2(CardVisual.card_size_play.x, CardVisual.card_separation_play)
		if i < scores.size():
			label.current_num = scores[i]
		else: label.text = ""

func update_score(zone:Array[BigNumber], index:int, score:BigNumber) -> void:
	var game := CardEnvironment.get_current_game()
	if not game: return
	# syncs to game data
	update_score_controls()
	var label : BigNumberLabel
	if zone == game.state.scores_row_lower:
		label = lower_zone_left.get_child(index)
	elif zone == game.state.scores_col:
		label = middle_zone_right.get_child(index)
	elif zone == game.state.scores_row_upper:
		label = upper_zone_left.get_child(index)
	if label: label.update_score_anim(score)
		
#func get_control_from_data(data : CardData) -> Control:
	#if data in data_ui:
		#return data_ui[data]
	#return null
#
func get_data_from_control(control : Control) -> CardData:
	flush_rebuild() #reads ui_data
	if control in ui_data:
		return ui_data[control]
	return null

#func get_card_from_data(data : CardData) -> CardVisual:
	#if data in data_card:
		#return data_card[data]
	#return null
	
func popup_meld(result : Scoring.Result) -> void:
	flush_rebuild() #reads data_card
	var wait_time : float = 0
	for data in result.meld:
		if data in data_card:
			var anim_time := data_card[data].anim_jump()
			wait_time = anim_time if anim_time > wait_time else wait_time
	await get_tree().create_timer(wait_time).timeout
	
func reset_meld(result : Scoring.Result) -> void:
	flush_rebuild() #reads data_card
	for data in result.meld:
		if data in data_card:
			data_card[data].anim_reset()

func popup_score(result : Scoring.Result) -> void:
	flush_rebuild() #reads data_card
	if not result.meld: return
	var combo_pos : Vector2 = Vector2.ZERO
	var meld_size : int = 0
	for card in result.meld:
		if card in data_card:
			meld_size += 1
			combo_pos += data_card[card].global_position
	if meld_size == 0: return
	combo_pos /= meld_size
	combo_pos.y -= CardVisual.card_size_play.y * 0.5
	var score_name_popup := TextPopup.new_popup(result.name + "\n" + str(result.score), combo_pos)
	add_child(score_name_popup)
	await get_tree().create_timer(CardEnvironment.CURRENT.get_delay()*.3).timeout
	score_name_popup.queue_free()
