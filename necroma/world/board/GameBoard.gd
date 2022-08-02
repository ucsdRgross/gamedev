class_name GameBoard
extends Node2D

export var grid: Resource = preload("res://resources/Grid.tres")

onready var grid_border = $GridBorder

#dictionary matching cell rowcol keys to unit values
var units := {}
var selected_unit: Unit


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


func select_unit(cell: Vector2) -> void:
	if not units.has(cell):
		return
	selected_unit = units[cell]
	selected_unit.is_selected = true
	selected_unit.draw_path(true)
	grid_border.show()


func deselect_unit() -> void:
	selected_unit.is_selected = false
	selected_unit.draw_path(false)
	selected_unit = null
	grid_border.hide()


func _on_Cursor_moved(new_cell: Vector2) -> void:
	if selected_unit:
		selected_unit.add_point(new_cell)


func _on_Cursor_accept_clicked(cell: Vector2) -> void:
	if not selected_unit:
		select_unit(cell)
	elif selected_unit.is_selected:
		selected_unit.move()
		deselect_unit()


func _on_Unit_moved(old_cell: Vector2, new_cell: Vector2) -> void:
	var unit = units[old_cell]
	units.erase(old_cell)
	units[new_cell] = unit


func _on_Unit_removed(cell: Vector2) -> void:
	units.erase(cell)


func _unhandled_input(event: InputEvent) -> void:
	if selected_unit and event.is_action_pressed("ui_cancel"):
		deselect_unit()
