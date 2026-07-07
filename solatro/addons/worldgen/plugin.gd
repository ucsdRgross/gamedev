@tool
extends EditorPlugin

## Registers WorldMap2D as a creatable node so it can be dropped into any scene.
## The pipeline classes (WorldGenerator, WorldSettings, GraphPlacement, ...) are
## global via their `class_name`, so only the node deliverable needs registering.

const ICON := "res://addons/worldgen/icon.svg"
const MAP_SCRIPT := preload("res://addons/worldgen/world_map_2d.gd")


func _enter_tree() -> void:
	# load() (not preload) for the icon so an un-imported SVG can't break plugin
	# load; add_custom_type tolerates a null icon (falls back to the Node2D icon).
	add_custom_type("WorldMap2D", "Node2D", MAP_SCRIPT, load(ICON))


func _exit_tree() -> void:
	remove_custom_type("WorldMap2D")
