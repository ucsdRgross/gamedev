tool
class_name Cursor
extends Node2D

export var grid: Resource = preload("res://resources/Grid.tres")
export var cell: PackedScene = preload("res://resources/Cellectable.tscn")

onready var highlight = $Highlight
var cur_cell := Vector2.ZERO

signal accept_clicked(cur_cell)
signal moved(new_cell)


func _ready() -> void:
	grid.set_world_pos(position)
	create_grid()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("left_mouse_button"):
		emit_signal("accept_clicked", cur_cell)

func create_grid() -> void:
	for col in grid.size.x:
		for row in grid.size.y:
			var cell_pos = Vector2(row,col)
			var new_cell = cell.instance()
			new_cell.position = grid.rowcol_to_world(cell_pos)
			add_child(new_cell)
			new_cell.setup(cell_pos)		

func on_hex_hovered(rowcol : Vector2) -> void:
	cur_cell = rowcol
	highlight.position = grid.rowcol_to_world(rowcol)
	emit_signal('moved', rowcol)
