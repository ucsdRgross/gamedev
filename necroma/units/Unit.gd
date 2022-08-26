tool
class_name Unit
extends Sprite

onready var _astar: Resource = preload("res://resources/PathFinder.tres")

var cell := Vector2.ZERO setget set_cell
var is_selected := false setget set_is_selected
var is_walking := false setget set_is_walking
#guarenteed to move next beat
var will_move := false
var to_next_tile : float = 0
var current_path : PoolVector2Array = []
var facing_direction := Vector2(1,0) setget set_facing_direction
#tween time limit for moving, should be set to time per beat
var move_duration : float = 0.5217
#tween original value reference
const default_scale = Vector2(1,1)
onready var default_offset = offset


onready var _hexmap: HexMap 
onready var _anim_player: AnimationPlayer = $AnimationPlayer

enum {
	IDLE, #stays still and looks for enemies in range
	MOVE, #attempts to attack after moving
	ATTACK #will repeatedly attack enemy and switch to new targets
}
var state : int = IDLE

func setup(entry_cell : Vector2, enemy=false):
	cell = entry_cell
	_hexmap = $"../../HexMap"
	position = _hexmap.map_to_world(cell)
	_astar.set_point_disabled(cell, true)
	_astar.unit_enter(self)
	if enemy == true:
		add_to_group("enemy")
	else:
		add_to_group("friend")

func ready_in_scene() -> void:
	#allows placing directly on board
	_hexmap = $"../../HexMap"
	self.setup(_hexmap.world_to_map(position))
	

func action(beat: int) -> void:
	if beat == 1:				
		pass
	elif beat == 2:
		match state:
			IDLE:
				if is_in_group("enemy"):
					var target = get_parent().get_node("Necromancer")
					add_point(target.cell)
					face_direction()
			MOVE:
				face_direction()	
	elif beat == 3:
		match state:
			MOVE:
				prep_move_state()
				pass
			ATTACK:
				#prep_attack_state()
				pass
	elif beat == 0:
		match state:
			IDLE:
				if scale != Vector2(1,1):
					move_fail()
			MOVE:
				move_state()
			ATTACK:
				#attack_state()
				pass

func face_direction() -> void:
	if current_path.size() > 1:
		self.facing_direction = position.direction_to(_hexmap.map_to_world(current_path[1]))
				
func prep_move_state() -> void:
	var squat = create_tween()
	var default_scale = scale
	squat.tween_property(self, "scale", default_scale*Vector2(1.1,0.8), move_duration)

func move_state() -> void:
	var dest = current_path[1]
	if _astar.can_move_to(self, self, dest):
		_astar.claim(dest)
		will_move = true
	#face_direction()
	if will_move:
		move_succeed()
	else:
		move_fail()

func move_succeed() -> void:
	var move = create_tween()
	move.connect("finished", self, "_on_move_finished")
	var to : Vector2 = _hexmap.map_to_world(current_path[1])
	move.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	move.tween_property(self, "position", to, move_duration)
	jump()	
	
func _on_move_finished() -> void:
	self.cell = current_path[1]
	_astar.unclaim(cell)
	will_move = false
	current_path.remove(0)
	if line.get_point_count() > 0:
		line.remove_point(0)
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


func add_point(new_cell: Vector2) -> void:
	#cap on maximum path
	if current_path.size() > 100:
		return
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
		self.is_walking = true
	current_path.append_array(new_path)


#tells the gameboard unit has moved
func set_cell(value : Vector2) -> void:
	_astar.unit_moved(self, cell, value)
	cell = value


func set_is_walking(value: bool) -> void:
	is_walking = value
	if is_walking:
		state = MOVE
		_astar.set_point_disabled(cell, false)
#		_anim_player.play("walking")
	else:
		state = IDLE
		print("stop!")
		_astar.set_point_disabled(cell, true)
#		_anim_player.play("idle")


func set_is_selected(value: bool) -> void:
	is_selected = value
	if is_selected and not will_move:
		self.is_walking = false
		current_path.resize(0)
	elif is_selected and not current_path.empty():
		current_path.resize(2)
#	if is_selected:
#		_anim_player.play("selected")
#	else:
#		_anim_player.play("idle")


func set_facing_direction(value:Vector2) -> void:
	if sign(facing_direction.x) != sign(value.x):
		var flip = create_tween()
		flip.connect("finished",self,"_on_flip_finished")
		flip.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		flip.tween_property(self, "scale", default_scale*Vector2(0.5,1), move_duration/2)
	facing_direction = value

func _on_flip_finished() -> void:
	var flip = create_tween()
	flip.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	flip.tween_property(self, "scale", default_scale, move_duration/2)
	if facing_direction.x <= 0:
		flip_h = true
	else:
		flip_h = false

func death() -> void:
	_astar.unclaim(current_path[1])

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


