# world_settings.gd
class_name WorldSettings
extends Resource

@export_group("Map Layout")
@export var map_width: int = 512
@export var map_height: int = 512

## Map diagonal in px -- the scale that pixel-free "ratio" params multiply against
## so distances are resolution-independent (a ratio tuned on one map size transfers
## to any other). 512x512 -> ~724 px.
func map_diag() -> float:
	return sqrt(float(map_width * map_width + map_height * map_height))

@export_group("Generation Seeds")
## Each noise map gets its own offset from main_seed so all are independently
## tunable. Rivers deliberately reuse the climate humidity map (humidity_seed_offset).
@export var main_seed: int = 42
@export var landmass_seed_offset: int = 0
@export var tectonic_seed_offset: int = 1
@export var peaks_seed_offset: int = 2
@export var erosion_seed_offset: int = 3            # ridged erosion channel noise
@export var erosion_humidity_seed_offset: int = 4 # erosion's own humidity map
@export var temperature_seed_offset: int = 5
@export var humidity_seed_offset: int = 6           # climate humidity (rivers reuse this map)

@export_group("Terrain Weights")
@export var continent_frequency: float = 0.004
@export var detail_frequency: float = 0.04
@export var ridge_frequency: float = 0.012
@export var ocean_threshold: float = 0.38
@export var mountain_threshold: float = 0.65
@export var island_radius: float = 0.72   # central mask radius (bigger = more land)
@export var land_contrast: float = 1.25    # spreads noise away from sea level
@export var boundary_radius: float = 0.46  # hard edge clamp: no land beyond this (keeps land off screen edges)
@export var edge_jag: float = 0.06         # warps the island/edge cutoffs (UV) so coastlines are jagged, not circular
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
## Biome variety lever: land biomes are classified by banding three noise axes.
## Max possible land biomes = height_bands * temp_bands * humid_bands (default 27,
## the original 3x3x3 scheme). Set an axis to 1 to drop it (e.g. 2/2/1 -> max 4).
@export_range(1, 6) var height_bands: int = 3
@export_range(1, 6) var temp_bands: int = 3
@export_range(1, 6) var humid_bands: int = 3

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
## Layered DAG over travel_nodes (cities are anchors). Nodes are bucketed into
## layer_count bands along the start->end spread axis; edges only go forward
## (no backtracking, no revisits) and pick min..max_outgoing targets by score.
@export var layer_count: int = 14
@export var min_outgoing: int = 2                 # target min forward edges per node when building
@export var max_outgoing: int = 3                 # max forward edges per node
@export var min_outgoing_after_trim: int = 1      # variety trim may reduce a node down to this (below min_outgoing)
## Cities visited along a path + travel nodes between consecutive cities.
@export var min_nodes_between_cities: int = 1
@export var max_nodes_between_cities: int = 4
@export var min_cities_visited: int = 3
@export var max_cities_visited: int = 8
## How strictly city layers act as bottlenecks. 1.0 = every path forced through a
## city per city-layer (strict; nodes-between-cities/cities-visited hard). 0.0 =
## cities are ordinary anchors and paths may bypass them via travel nodes (those
## windows become soft, but routing is much freer/wider).
@export_range(0.0, 1.0) var city_bottleneck_strength: float = 0.5
## "Graph width": min number of other cities a single city must directly reach
## (following travel nodes, stopping at the next cities). Branchiness of the
## city-to-city graph.
@export var min_graph_width: int = 3
## Biome variety traversed by a path (contiguous same-biome runs).
@export var min_biomes_per_path: int = 2
@export var max_biomes_per_path: int = 6
## Inter-landmass (water) travel. Treated as edges between nearest nodes on
## different continents; the straight line may touch land only at its endpoints.
@export var max_landmasses: int = 4               # how many continents keep nodes (top-N by size)
@export var max_cross_ocean_per_band: int = 1     # max INCOMING cross-ocean edges a band may receive (must land on a coastal city). Replaces the old per-landmass cap; applies to same- AND cross-landmass water crossings
@export var water_crossing_ratio: float = 0.30   # longest allowed cross-ocean edge as a fraction of the map diagonal (water travel reach)
@export var start_end_island_penalty: float = 4000.0 # discourage start/end on small landmasses
@export var start_end_min_connections: int = 2     # start/end must have >= this many nearby nodes (else heavily penalized -> avoids tiny isolated endpoints)
@export var mountain_pass_bias: float = 1.5       # >0 routes mountain travel through lower/closer-height passes
@export var graph_anti_straight: float = 0.8      # penalty on edges that run straight at the goal (higher = more winding, less beeline)
@export var graph_zigzag_penalty: float = 40.0    # penalty for crossing back over the spine centerline (commit to a side; rarely rejoin -> bulges instead of zig-zags)
@export_range(0.0, 1.0) var edge_trim_chance: float = 0.3 # chance to drop a surplus edge (keeps min_outgoing, never orphans) so the graph isn't a perfect NxN lattice
@export var path_curve_max_ratio: float = 0.076   # max sideways bow of a cosmetic curved road, as a fraction of the map diagonal (beyond this it goes straight)
@export var path_curve_min_ratio: float = 0.008   # gentle bow applied to even clear edges so every road curves slightly (fraction of map diagonal)
@export var failsafe_max_injected_nodes: int = 40 # nodes the failsafe may create to keep paths valid
@export var max_paths_enumerated: int = 4000      # cap on start->end paths walked for stats/validation
@export_range(1, 4) var graph_build_passes: int = 2 # build, diagnose+modify nodes, rebuild (1 = single pass)

@export_group("Civilization")
@export var city_dist_ratio: float = 0.033     # min city spacing as a fraction of the map diagonal
@export var max_city_count: int = 150
@export var travel_dist_ratio: float = 0.012   # min travel-node spacing as a fraction of the map diagonal
@export var max_travel_count: int = 700        # cap on dense travel nodes
@export var coast_radius_ratio: float = 0.014  # ring radius (fraction of map diagonal) sampled to score coastalness (cities prefer coasts)
