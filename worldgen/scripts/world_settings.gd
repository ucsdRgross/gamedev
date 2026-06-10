# world_settings.gd
class_name WorldSettings
extends Resource

@export_group("Map Layout")
@export var map_width: int = 512
@export var map_height: int = 512
@export var path_steps: int = 15

@export_group("Generation Seeds")
@export var main_seed: int = 4242

@export_group("Terrain")
@export var continent_frequency: float = 0.005
@export var detail_frequency: float = 0.05
@export var mountain_threshold: float = 0.7
@export var ocean_threshold: float = 0.3

@export_group("Civilization")
@export var min_city_dist: float = 40.0
@export var max_city_count: int = 50
