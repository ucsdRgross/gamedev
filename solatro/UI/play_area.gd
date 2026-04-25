extends Control
class_name PlayArea

const CARD_VISUAL = preload("uid://bynh2btoahe5i")

signal data_selected(data : CardData)

var focused_control : Control = null

var card_min_size := Vector2(38,50)
var card_stacked_seperation : int = 14:
	set(value):
		card_stacked_seperation = value
		update_play_area()
var buffer_min_size := Vector2(14,14)
var seperation : int = 4: 
	set(value):
		seperation = value
		set_seperation()

var ui_data : Dictionary[Control, CardData]
var data_ui : Dictionary[CardData, Control]
var data_card : Dictionary[CardData, CardVisual]

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
	self.custom_minimum_size = card_min_size * 10
	set_seperation()

func _process(delta: float) -> void:
	update_play_area()

func set_seperation() -> void:
	for container : Control in containers:
		container.add_theme_constant_override("Seperation", seperation)
	for container : HBoxContainer in [upper_zone_right, lower_zone_right]:
		for vbox : Control in container.get_children():
			vbox.add_theme_constant_override("Seperation", seperation)

func update_play_area() -> void:
	# Set correct amount of controls, equal to card array size + 1 for zone
	# controls need correct focus mode
	set_card_zone(upper_zone_right, Game.CURRENT.upper_zone_type, Game.CURRENT.upper_zone)
	set_card_zone(lower_zone_right, Game.CURRENT.lower_zone_type, Game.CURRENT.lower_zone)
	focused_control = null
	# Do same for score rows and columns, and buffers
	update_score_controls()
	
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
			hbox.remove_child(hbox.get_child(-1))
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
				vbox.remove_child(hbox.get_child(-1))
		# setup card min sizes and dictionary
		ui_data.clear()
		data_ui.clear()
		var new_data_card : Dictionary[CardData,CardVisual]
		var c : Control = vbox.get_child(0)
		c.custom_minimum_size = Vector2(card_min_size.x, 0)
		var connected_data : CardData = type[i]
		ui_data[c] = connected_data
		data_ui[connected_data] = c
		if connected_data in data_card: new_data_card[connected_data] = data_card[connected_data]
		else: new_data_card[connected_data] = create_card_visual(connected_data)
		for j in range(1, vbox.get_child_count()):
			c = vbox.get_child(j)
			c.custom_minimum_size = Vector2(card_min_size.x, card_stacked_seperation)
			connected_data = datas[i].datas[j-1]
			ui_data[c] = connected_data
			data_ui[connected_data] = c
			if connected_data in data_card: new_data_card[connected_data] = data_card[connected_data]
			else: new_data_card[connected_data] = create_card_visual(connected_data)
		(vbox.get_child(-1) as Control).custom_minimum_size = card_min_size
		data_card = new_data_card

func create_card_control() -> Control:
	var new_control := Control.new()
	new_control.focus_mode = Control.FOCUS_ALL
	new_control.focus_entered.connect(func()->void:on_control_focus_entered(new_control))
	new_control.mouse_entered.connect(func()->void:new_control.grab_focus())
	return new_control

func create_card_visual(connected_data:CardData) -> CardVisual:
	var card : CardVisual = (CARD_VISUAL.instantiate() as CardVisual).with_data(connected_data)
	return card

func on_control_focus_entered(control:Control) -> void:
	var row_index := control.get_index()
	var column_node : Control = control.get_parent()
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
		focused_control.custom_minimum_size = Vector2(card_min_size.x, 0)
		(focused_control.get_parent().get_child(-1) as Control).custom_minimum_size = card_min_size
	if row_index <= 1:
		(column_node.get_child(0) as Control).custom_minimum_size = Vector2(card_min_size.x, card_stacked_seperation)
		(column_node.get_child(-1) as Control).custom_minimum_size = card_min_size
	focused_control = control
	data_selected.emit(get_data_from_control(control))

func update_score_controls() -> void:
	middle_zone_left.custom_minimum_size = buffer_min_size
	set_score_zone_row(upper_zone_left, Game.CURRENT.scores_row_upper.size())
	set_score_zone_row(lower_zone_left, Game.CURRENT.scores_row_lower.size())
	set_score_zone_col(middle_zone_right, Game.CURRENT.scores_col.size())
	
func set_score_zone_row(zone:VBoxContainer, scores:int) -> void:
	if scores == 0: scores += 1 # there should always be at least 1 control as buffer
	var row_diff : int = scores - zone.get_child_count()
	if row_diff > 0:
		for i in row_diff:
			zone.add_child(Control.new())
	elif row_diff < 0:
		for i in absi(row_diff):
			zone.remove_child(zone.get_child(-1))
	for control : Control in zone.get_children():
		control.custom_minimum_size = Vector2(buffer_min_size.x, card_stacked_seperation)

func set_score_zone_col(zone:HBoxContainer, scores:int) -> void:
	var col_diff : int = scores - zone.get_child_count()
	if col_diff > 0:
		for i in col_diff:
			zone.add_child(Control.new())
	elif col_diff < 0:
		for i in absi(col_diff):
			zone.remove_child(zone.get_child(-1))
	for control : Control in zone.get_children():
		control.custom_minimum_size = Vector2(card_min_size.x, buffer_min_size.y)

func get_control_from_data(data : CardData) -> Control:
	if data in data_ui:
		return data_ui[data]
	return null

func get_data_from_control(control : Control) -> CardData:
	if control in ui_data:
		return ui_data[control]
	return null

func get_card_from_data(data : CardData) -> CardVisual:
	if data in data_card:
		return data_card[data]
	return null
