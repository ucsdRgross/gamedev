# world_settings.gd
class_name WorldSettings
extends Resource

@export_group("Map Layout")
@export var map_width: int = 768
@export var map_height: int = 768
@export var path_steps: int = 15

@export_group("Generation Seeds")
@export var main_seed: int = 42

@export_group("Terrain Weights")
@export var continent_frequency: float = 0.004
@export var detail_frequency: float = 0.04
@export var ridge_frequency: float = 0.012
@export var ocean_threshold: float = 0.38
@export var mountain_threshold: float = 0.65

@export_group("Tectonics Simulation")
@export var plate_count: int = 5
@export var drift_intensity: float = 0.22

@export_group("Path Choice Rules")
@export var min_path_dist: float = 20.0
@export var max_path_dist: float = 140.0
@export var max_path_search_dist: float = 240.0
@export var min_choices: int = 2
@export var max_choices: int = 3

@export_group("Pathfinding Penalties")
@export var mountain_penalty: float = 200.0
@export var water_penalty: float = 9000.0 # Bumps penalty to avoid crossing water entirely

@export_group("Civilization")
@export var min_city_dist: float = 24.0
@export var max_city_count: int = 150
