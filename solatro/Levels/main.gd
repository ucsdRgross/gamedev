extends Node

var scene_map := preload("res://Levels/map.tscn").instantiate()
var scene_game := preload("res://Levels/game.tscn")#.instantiate()
var current_scene : Node = null

#@onready var level: Node = $Level
#@onready var level: Control = $CanvasLayer/Level

func _ready() -> void:
	(scene_map as Map).card_clicked.connect(enter_game)
	switch_scene(scene_map)

func enter_game(card:Card) -> void:
	var new_game : Game = scene_game.instantiate()
	new_game.game_ended.connect(game_ended)
	switch_scene(new_game)

func game_ended() -> void:
	switch_scene(scene_map)

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
