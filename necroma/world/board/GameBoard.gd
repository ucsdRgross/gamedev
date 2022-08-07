class_name GameBoard
extends Node2D

#export var grid: Resource = preload("res://resources/Grid.tres")
#onready var grid_border = $GridBorder

onready var hexmap = $HexMap

#dictionary matching cell rowcol keys to unit values
var units := {}
var selected_unit: Unit
var hovered_unit: Unit
var hovered_cell : Vector2


func _ready() -> void:
	initialize()


func initialize() -> void:
	units.clear()
	for child in get_children():
		var unit := child as Unit
		if not unit:
			continue
		#remove stacked units on same cell
		if units.has(unit.cell):
			units[unit.cell].queue_free()
		units[unit.cell] = unit

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("left_mouse_button"):
		on_left_click()
	elif event.is_action_pressed("right_mouse_button"):
		on_right_click()
	if selected_unit and event.is_action_pressed("ui_cancel"):
		deselect_unit()

func select_unit(cell: Vector2) -> void:
	if not units.has(cell):
		return
	selected_unit = units[cell]
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
		selected_unit.show_path_to(new_cell)
		return
	if hovered_unit:
		hovered_unit.hide_path()
		hovered_unit = null	
	if not units.has(new_cell):
		return
	else:
		hovered_unit = units[hovered_cell]
		hovered_unit.show_path()


func on_left_click() -> void:
	if not selected_unit:
		select_unit(hovered_cell)
	elif selected_unit.is_selected:
		selected_unit.set_path()
		deselect_unit()

func on_right_click() -> void:
	if selected_unit:
		selected_unit.add_point(hovered_cell)

func _on_Unit_moved(old_cell: Vector2, new_cell: Vector2) -> void:
	var unit = units[old_cell]
	units.erase(old_cell)
	units[new_cell] = unit


func _on_Unit_removed(cell: Vector2) -> void:
	units.erase(cell)




