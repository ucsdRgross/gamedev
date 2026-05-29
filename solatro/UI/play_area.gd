extends Control
class_name PlayArea

signal data_selected(data : CardData)

var focused_control : Control = null
var moused_hovered_control : Control = null
var selected_cards : Array[CardData] = []

#@export var card_scale : float = 1:
	#set(value):
		#card_scale = value
		#if not is_node_ready():
			#await ready
		#for c : CardVisual in get_tree().get_nodes_in_group("CardVisual"):
			#c.scale = Vector2.ONE * card_scale
		#for c : Control in get_tree().get_nodes_in_group("CardVisualControl"):
			#c.custom_minimum_size = card_min_size * card_scale
		#set_seperation()
		#middle_zone_left.custom_minimum_size = Vector2(card_stacked_seperation,card_stacked_seperation)
#var card_min_size : Vector2 = Vector2(38,50):
	#get():
		#return card_min_size * card_scale
#var card_stacked_seperation : int = 14:
	#set(value):
		#card_stacked_seperation = value
		#update_play_area()
	#get():
		#return card_stacked_seperation * card_scale
var seperation : int = 4: 
	set(value):
		seperation = value
		set_seperation()
	get():
		return seperation * SettingsManager.settings.card_scale

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
	SettingsManager.settings.settings_changed.connect(update_gui)
	update_gui()
	update_play_area()

func update_gui() -> void:
	set_seperation()
	#update_play_area()
	update_score_controls()
	middle_zone_left.custom_minimum_size = Vector2.ONE * CardVisual.card_seperation

func _on_gui_input(event: InputEvent) -> void:
	# Mouse
	if event is InputEventMouseButton:
		var mouse_event : InputEventMouseButton = event
		# left click
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			if (focused_control == moused_hovered_control 
					and focused_control in ui_data):
					#and not focused_control.is_in_group("CardVisualZoneControl")):
				data_selected.emit(ui_data[focused_control])
	# Controller
	if event.is_action_pressed("ui_accept"):
		if focused_control in ui_data:
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
	ungrab_cards()
	selected_cards = datas
	for index in selected_cards.size():
		var data := selected_cards[index]
		if data in data_card: 
			var card_visual := data_card[data]
			card_visual.held = index + 1
			card_visual.z_index = get_tree().get_nodes_in_group("CardVisualControl").size() + index + 1
			var card_control := data_ui[data]
			card_control.mouse_filter = Control.MOUSE_FILTER_IGNORE

func ungrab_cards() -> void:
	for data in selected_cards:
		if data in data_card: 
			var card_visual := data_card[data]
			card_visual.held = 0
			var card_control := data_ui[data]
			card_control.mouse_filter = Control.MOUSE_FILTER_PASS
	selected_cards = []

func _process(delta: float) -> void:
	#since we cannot directly detect if array contents have changed
	#getting rid of process would require adding update to every function
	#where we modify the data arrays in some way
	update_play_area()

func set_seperation() -> void:
	for container : Control in containers:
		container.add_theme_constant_override("Seperation", seperation)
	for container : HBoxContainer in [upper_zone_right, lower_zone_right]:
		for vbox : Control in container.get_children():
			vbox.add_theme_constant_override("Seperation", seperation)

# need to seperate node creation from cosmetic size updates
func update_play_area() -> void:
	ui_data.clear()
	data_ui.clear()
	# Set correct amount of controls, equal to card array size + 1 for zone
	# controls need correct focus mode
	var game_state := Game.CURRENT.state
	set_card_zone(upper_zone_right, game_state.upper_zone_type, game_state.upper_zone)
	set_card_zone(lower_zone_right, game_state.lower_zone_type, game_state.lower_zone)
	# Do same for score rows and columns, and buffers
	# update_score_controls()
	data_card = new_data_card
	new_data_card = {}

func set_card_zone(hbox:HBoxContainer, type: Array[CardData], datas : Array[ArrayCardData]) -> void:
	var card_columns := type.size()
	var column_diff : int = card_columns - hbox.get_child_count()
	# first setup correct amount of columns
	if column_diff > 0:
		for i in column_diff:
			var new_vbox := VBoxContainer.new()
			new_vbox.add_theme_constant_override("Seperation", seperation)
			hbox.add_child(new_vbox)
	elif column_diff < 0:
		for i in absi(column_diff):
			var child : Control = hbox.get_child(-1)
			hbox.remove_child(child)
			child.queue_free()
	var card_count : int = 0
	# second setup correct amount of rows per column
	for i in type.size():
		var card_rows := datas[i].datas.size() + 1 # +1 for zone/type
		var vbox : VBoxContainer = hbox.get_child(i)
		var row_diff : int = card_rows - vbox.get_child_count()
		if row_diff > 0:
			for j in row_diff:
				var new_control := create_card_control()
				vbox.add_child(new_control)
		elif row_diff < 0:
			for j in absi(row_diff):
				var child : Control = vbox.get_child(-1)
				vbox.remove_child(child)
				child.queue_free()
		# setup card min sizes and dictionary
		var c : Control = vbox.get_child(0)
		#c.add_to_group("CardVisualZoneControl")
		c.custom_minimum_size = Vector2(CardVisual.card_size.x, 0)
		c.focus_mode = Control.FOCUS_ALL
		if selected_cards:
			if c == focused_control:
				c.custom_minimum_size = Vector2(CardVisual.card_size.x, CardVisual.card_seperation_custom)
			elif vbox.get_child_count() > 1 and vbox.get_child(1) == focused_control:
				c.custom_minimum_size = Vector2(CardVisual.card_size.x, CardVisual.card_seperation_custom/2.5)
		elif vbox.get_child_count() != 1:
			c.focus_mode = Control.FOCUS_NONE
		var connected_data : CardData = type[i]
		ui_data[c] = connected_data
		data_ui[connected_data] = c
		if connected_data in data_card: 
			new_data_card[connected_data] = data_card[connected_data]
		else: new_data_card[connected_data] = CardVisual.add_child_card_visual(self,connected_data)
		card_count += 1
		var card_visual := new_data_card[connected_data]
		if connected_data not in selected_cards:
			card_visual.z_index = card_count
		for j in range(1, vbox.get_child_count()):
			c = vbox.get_child(j)
			c.custom_minimum_size = Vector2(CardVisual.card_size.x, CardVisual.card_seperation_custom)
			connected_data = datas[i].datas[j-1]
			ui_data[c] = connected_data
			data_ui[connected_data] = c
			if connected_data in data_card: 
				new_data_card[connected_data] = data_card[connected_data]
			else: new_data_card[connected_data] = CardVisual.add_child_card_visual(self,connected_data)
			card_count += 1
			card_visual = new_data_card[connected_data]
			if connected_data not in selected_cards:
				card_visual.z_index = card_count
		(vbox.get_child(-1) as Control).custom_minimum_size = CardVisual.card_size
	#set correct focus neighbors for hidden zone cards
	for i in type.size() - 1:
		var left : Control = hbox.get_child(i).get_child(0)
		var right : Control = hbox.get_child(i+1).get_child(0)
		left.focus_neighbor_right = right.get_path()
		right.focus_neighbor_left = left.get_path()
	#when picking up stack, previous parent card needs its zone expanded
	if selected_cards and selected_cards[0] in data_ui:
		var selected_control := data_ui[selected_cards[0]]
		var control_index := selected_control.get_index()
		if selected_control.get_index() > 0:
			var vbox : Control = selected_control.get_parent()
			(vbox.get_child(control_index - 1) as Control).custom_minimum_size = CardVisual.card_size
			if selected_control.get_index() == 1:
				(vbox.get_child(-1) as Control).custom_minimum_size = Vector2(CardVisual.card_size.x, 0)
			else:
				(vbox.get_child(-1) as Control).custom_minimum_size = Vector2(CardVisual.card_size.x, CardVisual.card_seperation_custom)

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
			#data_selected.emit(Game.CURRENT.upper_zone_type[column_index])
		#else:
			#data_selected.emit(Game.CURRENT.upper_zone[column_index].datas[row_index - 1])
	#elif zone_level == lower_zone_right:
		#if row_index == 0:
			#data_selected.emit(Game.CURRENT.lower_zone_type[column_index])
		#else:
			#data_selected.emit(Game.CURRENT.lower_zone[column_index].datas[row_index - 1])
	# resize zone control so it is possible to place card behind first card
	if focused_control and focused_control.get_index() == 0:
		focused_control.custom_minimum_size = Vector2(CardVisual.card_size.x, 0)
		(focused_control.get_parent().get_child(-1) as Control).custom_minimum_size = CardVisual.card_size
	if row_index == 0:
		(column_node.get_child(0) as Control).custom_minimum_size = Vector2(CardVisual.card_size.x, CardVisual.card_seperation_custom/1.5)
		(column_node.get_child(-1) as Control).custom_minimum_size = CardVisual.card_size
	elif row_index == 1:
		(column_node.get_child(0) as Control).custom_minimum_size = Vector2(CardVisual.card_size.x, CardVisual.card_seperation_custom/2.5)
		(column_node.get_child(-1) as Control).custom_minimum_size = CardVisual.card_size
	focused_control = control

func update_score_controls() -> void:
	var game_state := Game.CURRENT.state
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
			label.custom_minimum_size = Vector2.ONE * CardVisual.card_seperation
		else:
			label.custom_minimum_size = Vector2(CardVisual.card_size.x, CardVisual.card_seperation)
		if i < scores.size():
			label.current_num = scores[i]
		else: label.text = ""

func update_score(zone:Array[BigNumber], index:int, score:BigNumber) -> void:	
	# syncs to game data
	update_score_controls()
	var label : BigNumberLabel
	if zone == Game.CURRENT.state.scores_row_lower:
		label = lower_zone_left.get_child(index)
	elif zone == Game.CURRENT.state.scores_col:
		label = middle_zone_right.get_child(index)
	elif zone == Game.CURRENT.state.scores_row_upper:
		label = upper_zone_left.get_child(index)
	if label: label.update_score_anim(score)
		
#func get_control_from_data(data : CardData) -> Control:
	#if data in data_ui:
		#return data_ui[data]
	#return null
#
func get_data_from_control(control : Control) -> CardData:
	if control in ui_data:
		return ui_data[control]
	return null

#func get_card_from_data(data : CardData) -> CardVisual:
	#if data in data_card:
		#return data_card[data]
	#return null
	
func popup_meld(result : Scoring.Result) -> void:
	var wait_time : float = 0
	for data in result.meld:
		if data in data_card:
			var anim_time := data_card[data].anim_jump()
			wait_time = anim_time if anim_time > wait_time else wait_time
	await get_tree().create_timer(wait_time).timeout
	
func reset_meld(result : Scoring.Result) -> void:
	for data in result.meld:
		if data in data_card:
			data_card[data].anim_reset()

func popup_score(result : Scoring.Result) -> void:
	if not result.meld: return
	var combo_pos : Vector2 = Vector2.ZERO
	var meld_size : int = 0
	for card in result.meld:
		if card in data_card:
			meld_size += 1
			combo_pos += data_card[card].global_position
	combo_pos /= meld_size
	combo_pos.y -= CardVisual.card_size.y * 1.5
	var score_name_popup := TextPopup.new_popup(result.name + "\n" + str(result.score), combo_pos)
	add_child(score_name_popup)
	await get_tree().create_timer(Game.CURRENT.get_delay()*.3).timeout
	score_name_popup.queue_free()
