class_name Main
extends Node

const MENU = preload("res://Levels/menu.tscn")
const MAP = preload("res://Levels/map.tscn")
const GAME = preload("res://Levels/game.tscn")

var menu_scene : Menu = MENU.instantiate()
var map_scene : Map = MAP.instantiate()
var current_scene : Node = null
static var save_info : PlayerSave = PlayerSave.new()
var save_history : Array[GameData] = []

#@onready var level: Node = $Level
#@onready var level: Control = $CanvasLayer/Level

func _ready() -> void:
	map_scene.enter_game.connect(enter_game)
	menu_scene.play_pressed.connect(enter_map)
	switch_scene(menu_scene)

func enter_map() -> void:
	switch_scene(map_scene)

func enter_game() -> void:
	var new_game : Game = GAME.instantiate()
	switch_scene(new_game)
	new_game.game_ended.connect(game_ended)
	new_game.save_state.connect(clone_game)
	new_game.undo_button.pressed.connect(undo_pressed)
	
func game_ended() -> void:
	switch_scene(map_scene)

func clone_game() -> void:
	var current_game : Game = current_scene
	var current_game_data : GameData = GameData.new().create_save_state(current_game)
	save_history.append(current_game_data)
	
	#await get_tree().process_frame
	#var scn : PackedScene = PackedScene.new()
	#var current_game : Game = current_scene
	#scn.pack(current_scene)
	#ResourceSaver.save(scn, "user://current_game_state.tscn")
	#add_child((load("user://current_game_state.tscn") as PackedScene).instantiate())
	#var game_copy : Game = scn.instantiate()
	#add_child(game_copy)
	#Duplicator.deep_copy_game(current_game, game_copy)
	#scn.pack(game_copy)
	#remove_child(game_copy)
	#game_copy.queue_free()
	#save_history.append(scn)

func undo_pressed() -> void:
	if save_history.size() > 1:
		save_history.resize(save_history.size() - 1) # latest saved state will current scene
		var prev_game_data : GameData = save_history[-1]
		var current_game : Game = current_scene
		prev_game_data.load_game(current_game)
		#var game_copy : Game = save_history[-1].instantiate()
		#var current_game : Game = current_scene
		#switch_scene(game_copy)
		#Duplicator.deep_copy_game(current_game, game_copy)
		#game_copy.game_ended.connect(game_ended)
		#game_copy.save_state.connect(clone_game)
		#game_copy.undo_button.pressed.connect(undo_pressed)
		#current_game.queue_free()

func switch_scene(new_scene : Node) -> void:
	if new_scene.is_inside_tree():
		return

	#Add new scene below old scene to keep 
	#the same index once old_scene is removed
	if current_scene and current_scene.is_inside_tree():
		current_scene.add_sibling(new_scene)
		remove_child(current_scene)
	else:
		add_child(new_scene)
	current_scene = new_scene
