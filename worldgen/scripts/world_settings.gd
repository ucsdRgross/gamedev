# world_settings.gd
class_name WorldSettings
extends Resource

@export_group("Map Layout")
@export var map_width: int = 768
@export var map_height: int = 768
@export var path_steps: int = 15

@export_group("Generation Seeds")
## Each noise map gets its own offset from main_seed so all are independently
## tunable. Rivers deliberately reuse the climate humidity map (humidity_seed_offset).
@export var main_seed: int = 42
@export var landmass_seed_offset: int = 0
@export var tectonic_seed_offset: int = 15
@export var peaks_seed_offset: int = 2
@export var erosion_seed_offset: int = 5            # ridged erosion channel noise
@export var erosion_humidity_seed_offset: int = 100 # erosion's own humidity map
@export var temperature_seed_offset: int = 3
@export var humidity_seed_offset: int = 4           # climate humidity (rivers reuse this map)

@export_group("Terrain Weights")
@export var continent_frequency: float = 0.004
@export var detail_frequency: float = 0.04
@export var ridge_frequency: float = 0.012
@export var ocean_threshold: float = 0.38
@export var mountain_threshold: float = 0.65
@export var island_radius: float = 0.72   # central mask radius (bigger = more land)
@export var land_contrast: float = 1.25    # spreads noise away from sea level
@export var boundary_radius: float = 0.46  # hard edge clamp: no land beyond this (keeps land off screen edges)
@export var peak_uplift: float = 0.25      # how much ridge noise raises highlands into mountains
@export var highland_range: float = 0.25   # height band above sea over which uplift ramps in
@export var peak_detail_strength: float = 0.12  # fine surface-detail noise amplitude

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

@export_group("Erosion (Light Channels)")
@export var erosion_frequency: float = 0.03         # ridged Perlin channel scale (noisier than peaks)
@export_range(1, 8) var erosion_octaves: int = 4    # ridged-noise detail octaves (more = finer channels)
@export var erosion_strength: float = 0.05          # max height subtracted (light; well under peaks' uplift)
@export var erosion_humidity_frequency: float = 0.026  # erosion's own humidity map scale
@export_range(0.0, 1.0) var erosion_channel_threshold: float = 0.5  # crest cutoff: lower = wider/more channels
@export_range(0.0, 6.0) var erosion_height_bias: float = 2.0   # exponent: carve more in taller terrain
@export_range(0.0, 6.0) var erosion_humidity_bias: float = 2.0 # exponent: carve more in wetter terrain

@export_group("River Generation")
@export_range(1, 6) var river_resolution_divisor: int = 1  # hydrology grid downscale (1=full res/no pixelation, higher=faster but blocky)
@export_range(0.0, 8.0) var river_source_humidity_bias: float = 3.0  # exponent: wetter cells source more water
@export_range(0.0, 8.0) var river_source_elevation_bias: float = 1.0  # exponent: higher cells source more water
@export var river_accum_threshold: float = 60.0       # min flow accumulation for a river (lower = denser network)
@export var river_carve_depth: float = 0.02           # max channel depth below land (scaled by river size)
@export_range(0.0, 6.0) var river_width_gain: float = 2.0  # how strongly large rivers widen (hydrology-px radius)

@export_group("Lakes")
@export var lake_min_depth: float = 0.01              # min depression-fill above terrain to count as a lake
@export var lake_carve_depth: float = 0.02            # how far below the spill level the lake surface sits
@export_range(0, 6) var lake_width: int = 0           # dilate lakes outward by this many hydrology px

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
