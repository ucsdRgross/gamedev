tool
class_name Unit
extends Node2D


onready var _grid: Resource = preload("res://resources/Grid.tres")
onready var _astar: Resource = preload("res://resources/PathFinder.tres")
#time in seconds between tiles
export var travel_time : float = 1 setget set_travel_time

var cell := Vector2.ZERO setget set_cell
var is_selected := false setget set_is_selected
var is_walking := false setget set_is_walking
var to_next_tile : float = 0
var current_path : PoolVector2Array = []
var potential_path : PoolVector2Array = []

onready var _sprite: Sprite = $Sprite
onready var _anim_player: AnimationPlayer = $AnimationPlayer

signal moved(old_cell, new_cell)
#signal removed(cell)

func _ready() -> void:
	cell = _grid.world_to_rowcol(position)
	position = _grid.rowcol_to_world(cell)
	self.connect('moved', get_parent(), '_on_Unit_moved')
	#self.connect('removed', get_parent(), '_on_Unit_removed')

func _physics_process(delta: float) -> void:
	if is_walking:
		walk_along(delta)

func add_point(new_cell: Vector2) -> void:
	if potential_path.empty():
		potential_path.append(cell)
	var new_path : PoolVector2Array = _astar.path_between(potential_path[-1],new_cell)
	new_path.remove(0)
	potential_path.append_array(new_path)


func walk_along(delta : float) -> void:
	to_next_tile += delta
	var update_cell := false
	while to_next_tile >= travel_time and current_path.size() > 2:
		to_next_tile -= travel_time
		current_path.remove(0)
		update_cell = true
	if update_cell:
		self.cell = current_path[1]
	var from : Vector2 = _grid.rowcol_to_world(current_path[0])
	var to : Vector2 = _grid.rowcol_to_world(current_path[1])
	position = from.linear_interpolate(to, min(to_next_tile/travel_time, 1))
	if to_next_tile >= travel_time:
		is_walking = false
		current_path.resize(0)
		to_next_tile = 0


#recalculates to_next_tile for maintaining correct position when interpolating
func set_travel_time(value: float) -> void:
	to_next_tile *= value/travel_time 
	travel_time = value
	

#tells the gameboard unit has moved
func set_cell(value : Vector2) -> void:
	emit_signal("moved", cell, value)
	cell = value


func set_path():
	if potential_path.size() >= 2:
		#if still finishing walking to tile
		print(current_path)
		if not current_path.empty():
			potential_path.remove(0)
			current_path.append_array(potential_path)
			print(current_path)
		else:
			current_path = potential_path
			self.cell = current_path[1]
			potential_path.resize(0)
			is_walking = true


func set_is_walking(value: bool) -> void:
	is_walking = value
#	if is_walking:
#		_anim_player.play("walking")
#	else:
#		_anim_player.play("idle")


func set_is_selected(value: bool) -> void:
	is_selected = value
	if is_selected and not current_path.empty():
		current_path.resize(2)
	elif not is_selected:
		potential_path.resize(0)
#	if is_selected:
#		_anim_player.play("selected")
#	else:
#		_anim_player.play("idle")
