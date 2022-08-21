tool
class_name Unit
extends Sprite


#onready var _grid: Resource = preload("res://world/board/HexMap.tres")
onready var _astar: Resource = preload("res://resources/PathFinder.tres")
#time in seconds between tiles
export var travel_time : float = 1 setget set_travel_time

var cell := Vector2.ZERO setget set_cell
var is_selected := false setget set_is_selected
var is_walking := false setget set_is_walking
#guarenteed to move next beat
var will_move := false
var to_next_tile : float = 0
var current_path : PoolVector2Array = []
var facing_direction := Vector2.ZERO setget set_facing_direction
#tween time limit for moving, should be set to time per beat
var move_duration : float = 0.5217
#points_added_path added in case needed for the future, high chance of removal
#var points_added_path : PoolVector2Array = []

onready var _hexmap: HexMap = $"../../HexMap"
onready var _anim_player: AnimationPlayer = $AnimationPlayer

enum {
	IDLE, #stays still and looks for enemies in range
	MOVE, #attempts to attack after moving
	ATTACK #will repeatedly attack enemy and switch to new targets
}
var state : int = IDLE


func _ready() -> void:
	#allows placing directly on board
	cell = _hexmap.world_to_map(position)
	position = _hexmap.map_to_world(cell)
	_astar.set_point_disabled(cell, true)
	_astar.unit_enter(self)
	#self.connect('removed', get_parent(), '_on_Unit_removed')

func action(beat: int) -> void:
	if beat == 3:
		match state:
			MOVE:
				if not is_walking:
					return
				var dest = current_path[1]
				if _astar.can_move_to(dest):
					_astar.claim(dest)
					will_move = true
				prep_move_state()
				pass
			ATTACK:
				#prep_attack_state()
				pass
	if beat == 0:
		match state:
			IDLE:
				#idle_state()
				pass
			MOVE:
				if not is_walking:
					return
				if will_move:
					move_succeed()
				else:
					move_fail()
				will_move = false
				pass
			ATTACK:
				#attack_state()
				pass
				
const default_scale = Vector2(1,1)
const default_offset = Vector2(0,-8)
				
func prep_move_state() -> void:
	self.facing_direction = position.direction_to(_hexmap.map_to_world(current_path[1]))
	var squat = create_tween()
	var default_scale = scale
	var duration : float = 0.5217
	squat.tween_property(self, "scale", default_scale*Vector2(1.1,0.8), duration)

func move_succeed() -> void:
	var move = create_tween()
	var to : Vector2 = _hexmap.map_to_world(current_path[1])
	move.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	move.tween_property(self, "position", to, move_duration)
	jump()	
	self.cell = current_path[1]
	_astar.unclaim(cell)
	current_path.remove(0)
	line.remove_point(0)
	print(current_path)
	if current_path.size() < 2:
		self.is_walking = false
		current_path.resize(0)

func move_fail() -> void:
	jump()

func jump() -> void:
	var jump = create_tween()
	jump.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	jump.tween_property(self, "offset", default_offset+Vector2(0,-10), move_duration/2)
	jump.parallel().tween_property(self, "scale", default_scale*Vector2(0.95,1.05), move_duration/2)
	jump.set_ease(Tween.EASE_IN)
	jump.tween_property(self, "offset", default_offset, move_duration/2)
	jump.parallel().tween_property(self, "scale", default_scale, move_duration/2)
	jump.set_trans(Tween.TRANS_QUAD)
	jump.set_ease(Tween.EASE_OUT)
	jump.tween_property(self, "scale", default_scale*Vector2(1.05,0.95), move_duration/4)
	jump.set_ease(Tween.EASE_IN)
	jump.tween_property(self, "scale", default_scale, move_duration/4)

#func _physics_process(delta: float) -> void:
#	if is_walking:
#		walk_along(delta)

func add_point(new_cell: Vector2) -> void:
	#add starting cell to start
	if current_path.empty():
		current_path.append(cell)
		
	#dont add duplicate points
	if current_path[-1] == new_cell:
		return
	#points_added_path.append(new_cell)
		
	var new_path : PoolVector2Array = _astar.path_between(current_path[-1],new_cell)
	#trims duplicate point at start
	if new_path:
		new_path.remove(0)
	current_path.append_array(new_path)
	self.is_walking = true


#func walk_along(delta : float) -> void:
#	to_next_tile += delta
#	var update_cell := false
#	while to_next_tile > travel_time and current_path.size() > 2:
#		if _astar.is_point_disabled(current_path[2]):
#			to_next_tile = travel_time
#		else:
#			to_next_tile -= travel_time
#			if points_added_path[0] == current_path[0]:
#				points_added_path.remove(0)
#			current_path.remove(0)
#			line.remove_point(0)
#			update_cell = true
#	if update_cell:
#		self.cell = current_path[1]
#	var from : Vector2 = _hexmap.map_to_world(current_path[0])
#	var to : Vector2 = _hexmap.map_to_world(current_path[1])
#	position = from.linear_interpolate(to, min(to_next_tile/travel_time, 1))
#	if line.points:		
#		line.set_point_position(0, position)
#	#reached destination, reset everything
#	if to_next_tile > travel_time:
#		is_walking = false
#		current_path.resize(0)
#		points_added_path.resize(0)
#		to_next_tile = 0
#
#
#recalculates to_next_tile for maintaining correct position when interpolating
func set_travel_time(value: float) -> void:
	to_next_tile *= value/travel_time 
	travel_time = value
	

#tells the gameboard unit has moved
func set_cell(value : Vector2) -> void:
	_astar.unit_moved(cell, value)
	#old cell
	#_astar.set_point_disabled(cell, false)
	#new cell
	#_astar.set_point_disabled(value, true)
	cell = value


#func set_path():
#	if potential_path.size() >= 2:
#		#if still finishing walking to tile
#		if not current_path.empty():
#			potential_path.remove(0)
#			current_path.append_array(potential_path)
#		else:
#			current_path = potential_path
#			self.cell = current_path[1]
#			potential_path.resize(0)
#			is_walking = true


func set_is_walking(value: bool) -> void:
	is_walking = value
	if is_walking:
		state = MOVE
		_astar.set_point_disabled(cell, false)
#		_anim_player.play("walking")
	else:
		state = IDLE
		_astar.set_point_disabled(cell, true)
#		_anim_player.play("idle")


func set_is_selected(value: bool) -> void:
	is_selected = value
	if is_selected and not will_move:
		current_path.resize(0)
	elif is_selected and not current_path.empty():
		current_path.resize(2)
		#points_added_path.resize(0)
#	if is_selected and not current_path.empty():
#		current_path.resize(2)
#	elif not is_selected:
#		current_path.resize(0)
#	if is_selected:
#		_anim_player.play("selected")
#	else:
#		_anim_player.play("idle")

onready var line = $Node/Line2D

func hide_path() -> void:
	line.hide()
	
func show_path() -> void:
	line.clear_points()
	if current_path:
		for point in current_path:
			line.add_point(_hexmap.map_to_world(point))
	line.show()
	
func show_path_to(new_cell : Vector2) -> void:
	line.clear_points()
	var line_path = current_path
	if line_path.empty():
		line_path.append(cell)
	var new_path : PoolVector2Array = _astar.path_between(line_path[-1],new_cell)
	if not new_path.empty():
		new_path.remove(0)
	line_path.append_array(new_path)
	for point in line_path:
			line.add_point(_hexmap.map_to_world(point))
	line.show()


func set_facing_direction(value:Vector2) -> void:
	facing_direction = value
	if facing_direction.x <= 0:
		flip_h = true
	else:
		flip_h = false

func death() -> void:
	_astar.unclaim(current_path[1])
