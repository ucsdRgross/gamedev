# world_settings.gd
class_name WorldSettings
extends Resource

@export_group("Map Layout")
## Map width in pixels. Drives every buffer + SubViewport size. Maps are assumed
## square by the viewer; changing this needs a fresh generator.
@export var map_width: int = 512
## Map height in pixels (keep equal to map_width for the square assumption).
@export var map_height: int = 512

## Map diagonal in px -- the scale that pixel-free "ratio" params multiply against
## so distances are resolution-independent (a ratio tuned on one map size transfers
## to any other). 512x512 -> ~724 px.
func map_diag() -> float:
	return sqrt(float(map_width * map_width + map_height * map_height))

@export_group("Generation Seeds")
## Master seed. Every noise map derives from this + its own offset below, so one
## seed fully determines a world. Randomize rolls this each run.
@export var main_seed: int = 42
## Offset added to main_seed for the base landmass noise.
@export var landmass_seed_offset: int = 0
## Offset for tectonic plate placement / drift + warp noise.
@export var tectonic_seed_offset: int = 1
## Offset for the peaks ridged/billow noise.
@export var peaks_seed_offset: int = 2
## Offset for the ridged erosion-channel noise.
@export var erosion_seed_offset: int = 3
## Offset for erosion's own humidity map.
@export var erosion_humidity_seed_offset: int = 4
## Offset for the climate temperature map.
@export var temperature_seed_offset: int = 5
## Offset for the climate humidity map (rivers deliberately reuse this same map).
@export var humidity_seed_offset: int = 6

@export_group("Terrain Weights")
## Base continent scale (lower = larger, fewer continents). Frequency of the
## landmass fBm noise.
@export var continent_frequency: float = 0.004
## Fine surface-detail noise scale layered on the continents (higher = busier).
@export var detail_frequency: float = 0.04
## Ridged-noise scale used for highland/mountain shaping (higher = tighter ridges).
@export var ridge_frequency: float = 0.012
## Sea level. Height below this is ocean. Also the reference the elevation gates,
## biome height bands, and river normalization key off -- nudging it shifts a lot.
@export var ocean_threshold: float = 0.38
## Height above which terrain reads as mountain (used by coloring + graph routing).
@export var mountain_threshold: float = 0.65
## Central island-mask radius. Bigger = land reaches further from center (more land).
@export var island_radius: float = 0.72
## Contrast applied around sea level: >1 pushes noise toward lowlands/highlands
## (more land + sharper coasts), <1 flattens toward mid. Big lever for coast steepness.
@export var land_contrast: float = 1.25
## Lowland flatten curve. 1.0 = off. Higher (2-4) compresses the above-sea height
## band with a power curve so basins/plains go broad and flat while relief stays
## concentrated in the highlands. The main "give me flat plains" lever.
@export var lowland_flatten: float = 1.0
## Island-mask falloff exponent. <1 (e.g. 0.5) = fuller island with a quick edge
## drop; >1 = land concentrated in the center with a long gentle coastal slope.
@export var island_falloff: float = 0.5
## Hard outer cutoff radius: no land past this (keeps land off the screen edges).
@export var boundary_radius: float = 0.46
## Width of the soft fade at boundary_radius (smaller = harder map-edge coastline).
@export var boundary_falloff: float = 0.04
## Warps the island/edge cutoffs (UV) so coastlines are jagged, not circular.
@export var edge_jag: float = 0.06
## How much ridge noise lifts highlands into mountains (0 = no peaks).
@export var peak_uplift: float = 0.25
## Height band above sea over which peak uplift ramps in (smaller = abrupt mountains).
@export var highland_range: float = 0.25
## Amplitude of the fine detail noise added on highlands (texture on peaks).
@export var peak_detail_strength: float = 0.12
## Ceiling on peak height. High (default) = no flattening; lower it to deliberately
## plateau peaks. Replaces the old hard 1.2 clamp.
@export var peak_height_cap: float = 4.0
## Detail noise is suppressed below this height so coasts/plains stay flat; it ramps
## in above. Raise to widen the flat lowland band.
@export var peak_detail_min_elevation: float = 0.5
## Height band over which the detail noise ramps from off to full.
@export var peak_detail_falloff: float = 0.12

@export_group("Noise Shaping")
## All maps use OpenSimplex2. fBm sums octaves with fixed weights; multifractal
## modulates each octave by the running lower-octave sum so detail concentrates on
## high ground. Domain warp perturbs sample coords so features meander.
## Continent fBm octave count (more = more detail/roughness on land; fewer = flatter).
@export_range(1, 8) var continent_octaves: int = 4
## Continent persistence: per-octave amplitude falloff (lower = smoother land).
@export_range(0.0, 1.0) var continent_gain: float = 0.5
## Continent per-octave frequency growth.
@export_range(1.0, 4.0) var continent_lacunarity: float = 2.0
## Domain-warp strength (px) on the continent noise (0 = off; higher = swirlier).
@export var continent_warp_amp: float = 0.0
## Domain-warp frequency for the continent warp.
@export var continent_warp_freq: float = 0.01
## Peaks (ridged + billow) octave count.
@export_range(1, 8) var peaks_octaves: int = 5
## Peaks per-octave amplitude falloff.
@export_range(0.0, 1.0) var peaks_gain: float = 0.5
## Peaks per-octave frequency growth.
@export_range(1.0, 4.0) var peaks_lacunarity: float = 2.0
## Ridged-multifractal fold offset (higher = fatter, more rounded ridges).
@export_range(0.5, 1.5) var ridge_offset: float = 1.0
## Domain-warp strength (px) applied to ridge+billow for organic ridgelines.
@export var peaks_warp_amp: float = 30.0
## Domain-warp frequency for the peaks warp.
@export var peaks_warp_freq: float = 0.01
## Billow (rounded foothill) noise scale.
@export var billow_frequency: float = 0.02
## Foothill (billow) amplitude; peaks at mid elevations.
@export var peak_billow_strength: float = 0.12

@export_group("Tectonics Simulation")
## Number of tectonic plates.
@export var plate_count: int = 7
## Strength of boundary-collision relief (mountains where plates converge, rifts
## where they diverge). 0 = no tectonic relief.
@export var drift_intensity: float = 0.25
## UV distance each plate physically slides along its drift vector.
@export var plate_move: float = 0.03
## Width (px) of the boundary mountain/rift band along plate edges.
@export var tectonic_band: float = 55.0
## Organic edge distortion (px). Also caps the warp so coordinate space can't fold.
@export var warp_strength: float = 55.0
## Frequency of the tectonic warp noise.
@export var warp_frequency: float = 5.0
## Per-plate chance of being continental vs oceanic (seeded).
@export_range(0.0, 1.0) var land_plate_ratio: float = 0.5
## When two continental plates diverge, land drops only this fraction of the
## ocean's drop (keeps continents from rifting into sea).
@export var land_rift_damping: float = 0.5
## Ceiling on the deformed height. High (default) = boundary mountains keep full
## height; lower to plateau them. Replaces the old hard 1.5 clamp.
@export var tectonic_height_cap: float = 4.0

@export_group("Climate")
## Temperature noise scale (higher = smaller, more varied biome patches).
@export var temp_frequency: float = 0.022
## Humidity noise scale.
@export var humid_frequency: float = 0.026
## Temperature lapse rate: how much temperature drops per unit elevation above sea
## (higher = colder mountains). Was hardcoded 0.5.
@export var temp_lapse_rate: float = 0.5
## Humidity added to cells next to a river (wetter riverbanks). Was hardcoded 0.35.
@export var river_humidity_boost: float = 0.35
## Number of height bands for biome classification. Max land biomes =
## height_bands * temp_bands * humid_bands (default 27 = a 3x3x3 scheme).
@export_range(1, 6) var height_bands: int = 3
## Number of temperature bands.
@export_range(1, 6) var temp_bands: int = 3
## Number of humidity bands.
@export_range(1, 6) var humid_bands: int = 3

@export_group("Erosion (Gabor Branching Noise)")
## Single-pass GPU directional-gabor erosion: branching gullies/ridges steered by
## the terrain's own slope. The source technique was authored for a huge world, so
## set steepness_scale FIRST (watch the Erosion debug cell), then amplitude, then
## frequency.
## Number of erosion octaves.
@export_range(1, 8) var erosion_octaves: int = 4
## Height the erosion field adds/subtracts (in the 0..1-ish height scale).
@export var erosion_amplitude: float = 0.08
## Gabor cell fineness (higher = finer gullies; voronoi shift = 28 - floor(freq)).
@export var erosion_frequency: float = 24.0
## Per-octave amplitude falloff.
@export_range(0.0, 1.0) var erosion_gain: float = 0.5
## Per-octave frequency growth (ADDED, not multiplied).
@export var erosion_lacunarity: float = 1.2
## How sharply tributaries fork each octave (degrees).
@export var erosion_branch_angle_deg: float = 36.0
## Rounding of ridge crests in the slope mask.
@export_range(0.0, 1.0) var erosion_ridge_rounding: float = 0.1
## Rounding of gully bottoms in the slope mask.
@export_range(0.0, 1.0) var erosion_gully_rounding: float = 0.1
## Slope-mask sharpening between octaves.
@export var erosion_detail: float = 1.2
## Master scale folding the source's MAX_HEIGHT * steepness. TUNE THIS FIRST.
@export var erosion_steepness_scale: float = 100.0
## Erosion is suppressed below this height (keeps coasts/plains flat) and ramps in
## above it. Set near ocean_threshold.
@export var erosion_min_elevation: float = 0.42
## Height band over which erosion ramps from off to full.
@export var erosion_elevation_falloff: float = 0.12

@export_group("River Generation")
## Hydrology grid downscale (1 = full res/no pixelation; higher = faster but blocky).
@export_range(1, 6) var river_resolution_divisor: int = 1
## Exponent: wetter cells source more water (0 = humidity ignored).
@export_range(0.0, 8.0) var river_source_humidity_bias: float = 3.0
## Exponent: higher cells source more water.
@export_range(0.0, 8.0) var river_source_elevation_bias: float = 1.0
## Min flow accumulation for a cell to count as a river (lower = denser network).
@export var river_accum_threshold: float = 60.0
## Max channel depth carved below land (scaled by river size).
@export var river_carve_depth: float = 0.02
## How strongly large rivers widen (hydrology-px radius).
@export_range(0.0, 6.0) var river_width_gain: float = 2.0
## MFD flow spread: low = braided/deltas on flats, high = crisp single rivers.
@export_range(0.5, 8.0) var river_flow_exponent: float = 4.0
## 3x3 blur passes on the hydrology grid ONLY (kills erosion speck pits); does NOT
## touch the final heightmap.
@export_range(0, 6) var river_smooth_passes: int = 1

@export_group("Lakes")
## Min depression-fill above terrain to count as a lake.
@export var lake_min_depth: float = 0.01
## Min connected hydrology cells for a lake (drops 1-px speck pits).
@export var lake_min_area: int = 4
## How far below the spill level the lake surface sits.
@export var lake_carve_depth: float = 0.02
## Dilate lakes outward by this many hydrology px (0 = none).
@export_range(0, 6) var lake_width: int = 0

@export_group("Graph Spec (Step A: abstract rule-correct DAG)")
## Topology authored directly (no map). A layered DAG: cities on every
## (spec_nodes_between_cities+1)-th rank, spec_graph_width lanes per interior rank.
## Cities visited per path, including start & end.
@export var spec_cities: int = 5
## Travel nodes between consecutive cities.
@export var spec_nodes_between_cities: int = 2
## Min distinct cities a city can reach next (graph width).
@export var spec_graph_width: int = 3
## Forward edges per node before trimming.
@export var spec_outgoing: int = 3
## Variety-trim floor (never orphans a node).
@export var spec_min_outgoing_after_trim: int = 1
## Chance to drop a surplus edge during the spec trim.
@export_range(0.0, 1.0) var spec_edge_trim_chance: float = 0.3

@export_group("Path Choice Rules")
## Layered DAG over travel_nodes (cities are anchors). Nodes bucket into layer_count
## bands along the start->end axis; edges only go forward.
## Number of forward layers nodes are bucketed into.
@export var layer_count: int = 14
## Target min forward edges per node when building.
@export var min_outgoing: int = 2
## Max forward edges per node.
@export var max_outgoing: int = 3
## Variety trim may reduce a node down to this (below min_outgoing) but never orphan.
@export var min_outgoing_after_trim: int = 1
## Min travel nodes between consecutive cities on a path.
@export var min_nodes_between_cities: int = 1
## Max travel nodes between consecutive cities on a path.
@export var max_nodes_between_cities: int = 4
## Min cities visited along a start->end path.
@export var min_cities_visited: int = 3
## Max cities visited along a start->end path.
@export var max_cities_visited: int = 8
## How strictly city layers bottleneck paths. 1 = every path forced through a city
## per city-layer; 0 = cities are ordinary anchors paths may bypass (freer/wider).
@export_range(0.0, 1.0) var city_bottleneck_strength: float = 0.5
## Min number of other cities a single city must directly reach (city-graph branchiness).
@export var min_graph_width: int = 3
## Min distinct biomes a path should traverse (contiguous same-biome runs).
@export var min_biomes_per_path: int = 2
## Max distinct biomes a path should traverse.
@export var max_biomes_per_path: int = 6
## How many continents keep nodes (top-N by size) for inter-landmass travel.
@export var max_landmasses: int = 4
## Max INCOMING cross-ocean edges a band may receive (must land on a coastal city).
@export var max_cross_ocean_per_band: int = 1
## Longest allowed cross-ocean edge as a fraction of the map diagonal (water reach).
@export var water_crossing_ratio: float = 0.30
## Penalty discouraging start/end on small landmasses.
@export var start_end_island_penalty: float = 4000.0
## Start/end must have >= this many nearby nodes (else heavily penalized).
@export var start_end_min_connections: int = 2
## >0 routes mountain travel through lower/closer-height passes.
@export var mountain_pass_bias: float = 1.5
## Penalty on edges that beeline at the goal (higher = more winding).
@export var graph_anti_straight: float = 0.8
## Penalty for crossing back over the spine centerline (commit to a side -> bulges
## instead of zig-zags).
@export var graph_zigzag_penalty: float = 40.0
## Chance to drop a surplus edge (keeps min_outgoing, never orphans) so the graph
## isn't a perfect NxN lattice.
@export_range(0.0, 1.0) var edge_trim_chance: float = 0.3
## Max sideways bow of a cosmetic curved road, as a fraction of the map diagonal.
@export var path_curve_max_ratio: float = 0.076
## Gentle bow applied to even clear edges so every road curves slightly.
@export var path_curve_min_ratio: float = 0.008
## Nodes the failsafe may create to keep paths valid.
@export var failsafe_max_injected_nodes: int = 40
## Cap on start->end paths walked for stats/validation.
@export var max_paths_enumerated: int = 4000
## build, diagnose+modify nodes, rebuild (1 = single pass).
@export_range(1, 4) var graph_build_passes: int = 2

@export_group("Civilization")
## Min city spacing as a fraction of the map diagonal.
@export var city_dist_ratio: float = 0.033
## Hard cap on number of cities.
@export var max_city_count: int = 150
## Min travel-node spacing as a fraction of the map diagonal.
@export var travel_dist_ratio: float = 0.012
## Cap on dense travel nodes.
@export var max_travel_count: int = 700
## Ring radius (fraction of map diagonal) sampled to score coastalness (cities
## prefer coasts).
@export var coast_radius_ratio: float = 0.014
