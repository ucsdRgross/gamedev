class_name HexMap
extends Node2D

onready var astar: Resource = preload("res://resources/PathFinder.tres")
onready var cellectable: PackedScene = preload("res://resources/Cellectable.tscn")

onready var highlight = $Highlight
onready var selectable_tiles = $Selectable
var cur_cell := Vector2.ZERO

signal moved(new_cell)


func _ready() -> void:
	highlight.position = selectable_tiles.map_to_world(selectable_tiles.get_used_cells()[0])
	_add_mouse_detection()
	_add_astar_pathfinding()


func _add_mouse_detection() -> void:
	var tiles : PoolVector2Array = selectable_tiles.get_used_cells()
	for tile in tiles:
		var new_cell = cellectable.instance()
		new_cell.position = selectable_tiles.map_to_world(tile)
		add_child(new_cell)
		new_cell.setup(tile)


func _add_astar_pathfinding() -> void:
	astar.setup(selectable_tiles.get_used_cells())

#center of hex given row and col of tile
func map_to_world(rowcol : Vector2) -> Vector2:
	var left_corner : Vector2 = selectable_tiles.map_to_world(rowcol)
	var x : int = left_corner.x + selectable_tiles.cell_size.x/2
	var y : int = left_corner.y + selectable_tiles.cell_size.x/2 - 2
	return Vector2(x,y)


func world_to_map(world_pos : Vector2) -> Vector2:
	return selectable_tiles.world_to_map(world_pos)


func on_hex_hovered(rowcol : Vector2) -> void:
	cur_cell = rowcol
	highlight.position = selectable_tiles.map_to_world(rowcol)
	emit_signal('moved', rowcol)
