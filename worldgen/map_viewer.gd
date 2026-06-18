@tool
extends Node3D

const MAP_SLICE = preload("uid://dog1nnckhxf65")

@export_tool_button("Rebuild", "Callable") var reset_button = rebuild_map
@export var resolution : int = 100
@export var cube_height_ratio : float = 1.0
@export var heightmap : Image
@export var colored_map : Image

@export var min_zoom : float
@export var nax_zoom : float

func _ready() -> void:
	rebuild_map()

func rebuild_map():
	for child in get_children():
		child.queue_free()
	# on rebuild map, clear all children
	# resolution will be number of map slices spawned in
	# by default we assume we are viewing at a 1x1x1 cube with the slices filling it in
	# height of each slice will be 1/resolution
	# chaning cube_height_ratio to something like 0.5 will scale overall visual half as tall

# add code to automatically center camera around 0,0. scrolling zooms in and out on fixed distances
# grabbing screen and spanning left or right rotates the 3d map viewer, up or down as well.
