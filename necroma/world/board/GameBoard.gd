class_name GameBoard
extends Node2D

onready var _astar: Resource = preload("res://resources/PathFinder.tres")

onready var hexmap = $HexMap
onready var units = $Units
onready var spawner = $Spawner

var selected_unit: Unit
var hovered_unit: Unit
var hovered_cell : Vector2


func _ready() -> void:
	$Conductor.play_with_beat_offset(4)
	for child in units.get_children():
		child.ready_in_scene()
	spawner.setup(hexmap.edge_tiles, units)
	
	spawner.spawn()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("left_mouse_button"):
		on_left_click()
	if event.is_action_pressed("right_mouse_button"):
		on_right_click()
	if selected_unit and event.is_action_pressed("ui_cancel"):
		deselect_unit()

func select_unit(cell: Vector2) -> void:
	if not _astar.units.has(cell):
		return
	var clicked_unit = _astar.units[cell]
	if clicked_unit.is_in_group("friends"):
		selected_unit = clicked_unit
		selected_unit.is_selected = true
		
	
	#selected_unit.draw_path(true)
	#grid_border.show()


func deselect_unit() -> void:
	selected_unit.is_selected = false
	#selected_unit.draw_path(false)
	selected_unit.hide_path()
	selected_unit = null
	#grid_border.hide()


func _on_Hexmap_moved(new_cell) -> void:
	hovered_cell = new_cell
	if selected_unit:
		selected_unit.show_path_to(hovered_cell)
		#draw path
		if Input.is_action_pressed("left_mouse_button"):
			selected_unit.add_point(hovered_cell)
		return
	
	if hovered_unit:
		hovered_unit.hide_path()
		hovered_unit = null	
	if not _astar.units.has(hovered_cell):
		return
	else:
		hovered_unit = _astar.units[hovered_cell]
		hovered_unit.show_path()


func on_left_click() -> void:
	if not selected_unit:
		select_unit(hovered_cell)
	elif selected_unit.is_selected:
		selected_unit.add_point(hovered_cell)
#		selected_unit.set_path()
#		deselect_unit()

func on_right_click() -> void:
	if selected_unit:
		deselect_unit()
#	if selected_unit:
#		selected_unit.add_point(hovered_cell)


func _on_Conductor_beat(position):
	for child in units.get_children():
		child.action(position % 4)
#	if position % 4 == 0:
#		spawner.spawn()
