class_name Main
extends Node

## Scene orchestrator: Menu -> Map -> Game and back. Owns the pre-instantiated menu/map
## scenes and exposes the current run as the static save_info alias (kept for the many
## existing Main.save_info call sites; it always mirrors RunManager.run).

const MENU = preload("res://Levels/menu.tscn")
const MAP = preload("res://Levels/map.tscn")
const GAME = preload("res://Levels/game.tscn")

var menu_scene : Menu = MENU.instantiate()
var map_scene : Map = MAP.instantiate()
var current_scene : Node = null
## Alias of RunManager.run (never null so call sites skip guards; empty between runs).
static var save_info : RunState = RunState.new()

func _ready() -> void:
	map_scene.enter_game.connect(enter_game)
	menu_scene.new_run_requested.connect(_on_new_run)
	menu_scene.continue_requested.connect(_on_continue)
	switch_scene(menu_scene)

func _on_new_run(cards: Array[CardData], rules: Array[CardData]) -> void:
	save_info = RunManager.new_run(cards, rules)
	map_scene.start_run(save_info)
	enter_map()

func _on_continue() -> void:
	save_info = RunManager.load_run()
	map_scene.start_run(save_info)
	# A pending_node_id means the player quit mid-show — resume into that game instead of
	# the free-roam map (otherwise they could walk past the un-played node). The show
	# restarts fresh (mid-game board state isn't persisted); on win/loss the map (already
	# prepared via start_run) resolves the node as usual.
	if save_info.pending_node_id >= 0:
		enter_game()
	else:
		enter_map()

func enter_map() -> void:
	switch_scene(map_scene)

func enter_game() -> void:
	var new_game : Game = GAME.instantiate()
	switch_scene(new_game)
	new_game.game_ended.connect(game_ended)
	new_game.run_lost.connect(_on_run_lost)

## Won game handing back: return to the map and let it resolve the node (fame HUD, lap
## completion, save).
func game_ended() -> void:
	var old_game : Node = current_scene
	switch_scene(map_scene)
	if old_game is Game:
		old_game.queue_free()
	map_scene.returned_from_game()

## Lost game = run over: discard the save, rebuild the map scene so the next run starts
## clean, and fall back to the menu.
func _on_run_lost() -> void:
	RunManager.clear_save()
	save_info = RunState.new()
	var old_game : Node = current_scene
	map_scene.queue_free()
	map_scene = MAP.instantiate()
	map_scene.enter_game.connect(enter_game)
	switch_scene(menu_scene)
	if old_game is Game:
		old_game.queue_free()
	menu_scene.refresh_continue()

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
