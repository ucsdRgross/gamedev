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
@export var island_radius: float = 0.72   # central mask radius (bigger = more land)
@export var land_contrast: float = 1.25    # spreads noise away from sea level
@export var boundary_radius: float = 0.46  # hard edge clamp: no land beyond this (keeps land off screen edges)

@export_group("Tectonics Simulation")
@export var plate_count: int = 7
@export var drift_intensity: float = 0.25   # boundary collision relief strength
@export var plate_move: float = 0.03        # UV distance plates physically slide
@export var tectonic_band: float = 55.0     # px width of boundary mountain/rift band
@export var warp_strength: float = 55.0    # px of organic edge distortion (also caps warp so space can't fold)
@export var warp_frequency: float = 5.0
@export_range(0.0, 1.0) var land_plate_ratio: float = 0.5  # chance each plate is continental (seeded)
@export var land_rift_damping: float = 0.5  # land-land divergence drops only this fraction of ocean's drop

@export_group("Climate")
@export var temp_frequency: float = 0.022   # higher = smaller, more varied biome patches
@export var humid_frequency: float = 0.026

@export_group("Hydraulic Erosion")
@export var erosion_carve_threshold: float = 30.0  # flow above which terrain is carved
@export var river_flow_threshold: float = 220.0    # flow above which a cell becomes a river

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
