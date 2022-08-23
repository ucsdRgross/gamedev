class_name HexMap
extends Node2D

onready var astar: Resource = preload("res://resources/PathFinder.tres")
onready var cellectable: PackedScene = preload("res://resources/Cellectable.tscn")

onready var highlight = $Highlight
onready var selectable_tiles = $Selectable
onready var background_tiles = $Background
var edge_tiles : PoolVector2Array
var cur_cell := Vector2.ZERO

signal moved(new_cell)


func _ready() -> void:
	highlight.position = selectable_tiles.map_to_world(selectable_tiles.get_used_cells()[0])	
	#you can only ever select inside of selectable bounds, but enemies can pathfind outside of bounds
	_add_mouse_detection(selectable_tiles.get_used_cells())
	_add_astar_pathfinding(background_tiles.get_used_cells())
	_find_edge_tiles(background_tiles.get_used_cells())


func _add_mouse_detection(tiles:PoolVector2Array) -> void:
	for tile in tiles:
		var new_cell = cellectable.instance()
		new_cell.position = selectable_tiles.map_to_world(tile)
		add_child(new_cell)
		new_cell.setup(tile)


func _add_astar_pathfinding(tiles:PoolVector2Array) -> void:
	astar.setup(tiles)

func _find_edge_tiles(tiles:PoolVector2Array) -> void:
	var even_neighbors = astar.even_row_neighbors
	var odd_neighbors = astar.odd_row_neighbors
	for tile in tiles:
		var directions : PoolVector2Array
		var empty_neighbors : int = 0
		if int(tile.y) % 2 == 0:
			directions = even_neighbors
		else:
			directions = odd_neighbors
		for neighbor in directions:
			var cur_neighbor = tile + neighbor
			if not cur_neighbor in tiles:
				empty_neighbors += 1
			if empty_neighbors >= 2:
				edge_tiles.append(tile)
				break

#center of hex given row and col of tile
func map_to_world(rowcol : Vector2) -> Vector2:
	var left_corner : Vector2 = selectable_tiles.map_to_world(rowcol)
	var x : int = left_corner.x + selectable_tiles.cell_size.x/2
	#the 2 is to account for how hexagon is slightly flattened
	var y : int = left_corner.y + selectable_tiles.cell_size.x/2 - 2
	return Vector2(x,y)


func world_to_map(world_pos : Vector2) -> Vector2:
	return selectable_tiles.world_to_map(world_pos)


func on_hex_hovered(rowcol : Vector2) -> void:
	cur_cell = rowcol
	highlight.position = selectable_tiles.map_to_world(rowcol)
	emit_signal('moved', rowcol)

