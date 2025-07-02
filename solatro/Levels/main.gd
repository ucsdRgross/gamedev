class_name Main
extends Node

const MENU = preload("res://Levels/menu.tscn")
const MAP = preload("res://Levels/map.tscn")
const GAME = preload("res://Levels/game.tscn")

var menu_scene : Menu = MENU.instantiate()
var map_scene : Map = MAP.instantiate()
var current_scene : Node = null
static var save_info : PlayerSave = PlayerSave.new()

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
	new_game.undo_button.pressed.connect(clone_game)
	

func game_ended() -> void:
	switch_scene(map_scene)

func clone_game() -> void:
	var scn : PackedScene = PackedScene.new()
	var current_game : Game = current_scene
	scn.pack(current_scene)
	#ResourceSaver.save(scn, "user://current_game_state.tscn")
	#add_child((load("user://current_game_state.tscn") as PackedScene).instantiate())
	add_child(scn.instantiate())

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
