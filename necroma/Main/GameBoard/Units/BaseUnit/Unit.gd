tool
class_name Unit
extends Node2D

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
var move_duration : float = 0.5
#tween original value reference
const default_scale = Vector2(1,1)

var target : Unit = null
var will_attack : bool = false
var attack_cd_base : float = 1.0
var attack_cd_modifier : float = 0.0

onready var _hexmap: HexMap 
onready var sprite: Sprite = $Sprite
onready var detection: Area2D = $Detection
onready var hurtbox: Area2D = $HurtBox
onready var attack := $Independents/Attack
onready var line = $Independents/Line2D
onready var default_offset = sprite.offset


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
		add_to_group("enemies")
		#detection.set_collision_layer_bit(1, true)
		detection.set_collision_mask_bit(0, true)
		hurtbox.set_collision_layer_bit(1, true)
	else:
		add_to_group("friends")
		#detection.set_collision_layer_bit(0, true)
		detection.set_collision_mask_bit(1, true)
		hurtbox.set_collision_layer_bit(0, true)

func ready_in_scene() -> void:
	#allows placing directly on board
	_hexmap = $"../../HexMap"
	self.setup(_hexmap.world_to_map(position))
	

func action(beat: int) -> void:
#beat 1 occurs before jump ends so it cant be used for anything
#	if beat == 1:				
#		match state:
#			IDLE:
#				print("beat 1")
#				can_attack()
	if beat == 2:
		match state:
			IDLE:
				if will_attack:
					can_attack()
				elif is_in_group("enemies"):
					var closest_cell_with_enemy = get_closest_occupied_cell(get_tree().get_nodes_in_group("friends"))
					add_point(closest_cell_with_enemy)
					face_direction()
			MOVE:
				face_direction()	
	elif beat == 3:
		match state:
			MOVE:
				prep_move_state()
	elif beat == 0:
		match state:
			IDLE:
				if sprite.scale != Vector2(1,1):
					move_fail()
			MOVE:
				move_state()

func get_closest_occupied_cell(enemies: Array) -> Vector2:
	if enemies.empty():
		return cell
	var smallest_distance : float = position.distance_squared_to(enemies[0].position)
	var closest_cell : Vector2 = enemies[0].cell
	for enemy in enemies:
		var distance = position.distance_squared_to(enemy.position)
		if distance < smallest_distance:
			smallest_distance = distance
			closest_cell = enemy.cell
	return closest_cell

func face_direction() -> void:
	if current_path.size() > 1:
		self.facing_direction = position.direction_to(_hexmap.map_to_world(current_path[1]))
				
func prep_move_state() -> void:
	var squat = create_tween()
	var default_scale = scale
	squat.tween_property(sprite, "scale", default_scale*Vector2(1.1,0.8), move_duration)

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
	jump.connect("finished", self, "_on_jump_finished")
	jump.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	jump.tween_property(sprite, "offset", default_offset+Vector2(0,-10), move_duration/2)
	jump.parallel().tween_property(sprite, "scale", default_scale*Vector2(0.95,1.05), move_duration/2)
	jump.set_ease(Tween.EASE_IN)
	jump.tween_property(sprite, "offset", default_offset, move_duration/2)
	jump.parallel().tween_property(sprite, "scale", default_scale, move_duration/2)
	jump.set_trans(Tween.TRANS_QUAD)
	jump.set_ease(Tween.EASE_OUT)
	jump.tween_property(sprite, "scale", default_scale*Vector2(1.05,0.95), move_duration/4)
	jump.set_ease(Tween.EASE_IN)
	jump.tween_property(sprite, "scale", default_scale, move_duration/4)

func _on_jump_finished() -> void:
	#for friends, check if next path is blocked by an enemy, and attack if it is
	if is_in_group("friends"):
		if is_walking:
			if not _astar.can_move_to(self,self, current_path[1]):
				if will_attack:
					can_attack()
	elif is_in_group("enemies"):
		if will_attack:
			can_attack()

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
		
	var new_path : PoolVector2Array = _astar.path_between(current_path[-1],new_cell,is_in_group("friends"))
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
		flip.tween_property(sprite, "scale", default_scale*Vector2(0.5,1), move_duration/2)
	facing_direction = value

func _on_flip_finished() -> void:
	var flip = create_tween()
	flip.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	flip.tween_property(sprite, "scale", default_scale, move_duration/2)
	if facing_direction.x <= 0:
		sprite.flip_h = true
	else:
		sprite.flip_h = false

func death() -> void:
	_astar.unclaim(current_path[1])



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
	var new_path : PoolVector2Array = _astar.path_between(line_path[-1],new_cell,is_in_group("friends"))
	if not new_path.empty():
		new_path.remove(0)
	line_path.append_array(new_path)
	for point in line_path:
			line.add_point(_hexmap.map_to_world(point))
	line.show()


func _on_Detection_area_entered(area):
	if target == null:
		target = area.get_parent()
#	if detection.get_overlapping_areas().empty():
#		target = area.get_parent()	
	#logic to reset current path if unit in middle of moving
	#switch to attack state when not moving
	if state == IDLE:
		can_attack()
	else:
		will_attack = true

#code should be after attack ends
#func _on_Detection_area_exited(area):
#	if area.get_parent() == target:
#		var in_range = detection.get_overlapping_areas()
#		if in_range.empty():
#			target = null
#			state = IDLE
#		else:
#			target = in_range[0].get_parent()

func can_attack():
	will_attack = false
	self.is_walking = false
	if is_in_group("enemies"):
		current_path.resize(0)
	state = ATTACK
	start_attack()
	
func start_attack():
	var attack_rate = attack_cd_base * (100.0/(100.0+ attack_cd_modifier))
	var attack = create_tween()
	attack.connect("finished", self, "_on_attack_finished")
	attack.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	attack.tween_property(sprite, "rotation_degrees", 10.0, attack_rate/2)
	attack.tween_property(sprite, "rotation_degrees", 0.0, attack_rate/2)
	#start attack tween
	#attack animation
	
func _on_attack_finished():
	#spawn actual projectile
	spawn_attack()
	
	#for friends, if friend still has path to walk, stop attacking and switch back to moving,
	#continue walking path instead while ignoring nearby enemies
	if is_in_group("friends") and current_path.size() > 1 and _astar.can_move_to(self,self, current_path[1]):
		is_walking = true
		target = null
		return
	
	#if target is still within range, attack again
	#else, look for more targets within detection range
	#otherwise switch states to idle
	var areas_in_range = detection.get_overlapping_areas()
	for area in areas_in_range:
		print(area)
		print(area.get_parent())
		if target == area.get_parent():
			start_attack()
			return
	if not areas_in_range.empty():
		target = areas_in_range[0].get_parent()
		start_attack()
	else:
		target = null
		state = IDLE
	
func spawn_attack():
	#spawn damaging projectile
	var projectile = attack.create_instance()
	projectile.setup(self, target)



