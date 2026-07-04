# world_settings.gd
# Parameters are grouped by the generation STEP that consumes them, matching
# PresetIO.STEP_PARAMS so the per-step record/randomize workflow lines up with the
# inspector sections. "Map Layout" and "Generation Seeds" are global (not tuned).
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
## seed fully determines a world. Randomize base rolls this.
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

@export_group("Step 1 - Landmass")
## Base continent scale (lower = larger, fewer continents). Frequency of the
## landmass fBm noise.
@export var continent_frequency: float = 0.004
## Sea level. Height below this is ocean. Also the reference the elevation gates,
## biome height bands, and river normalization key off -- nudging it shifts a lot.
@export var ocean_threshold: float = 0.38
## Central island-mask radius. Bigger = land reaches further from center (more land).
@export var island_radius: float = 0.72
## Contrast applied around sea level: >1 pushes noise toward lowlands/highlands
## (more land + sharper coasts), <1 flattens toward mid. Big lever for coast steepness.
@export var land_contrast: float = 1.25
## Island-mask falloff exponent. <1 (e.g. 0.5) = fuller island with a quick edge
## drop; >1 = land concentrated in the center with a long gentle coastal slope.
@export var island_falloff: float = 0.5
## Warps the island/edge cutoffs (UV) so coastlines are jagged, not circular.
@export var edge_jag: float = 0.06
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

@export_group("Step 2 - Tectonics")
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

@export_group("Step 3a - Peaks Ridges")
## The ridged mountain system + overall peak profile. Tune this half first (the big
## structural shape), then Step 3b for fine detail/foothills.
## Ridged-noise scale used for highland/mountain shaping (higher = tighter ridges).
@export var ridge_frequency: float = 0.012
## Ridged-multifractal fold offset (higher = fatter, more rounded ridges).
@export_range(0.5, 1.5) var ridge_offset: float = 1.0
## Peaks (ridged + billow) octave count.
@export_range(1, 8) var peaks_octaves: int = 5
## Peaks per-octave amplitude falloff.
@export_range(0.0, 1.0) var peaks_gain: float = 0.5
## Peaks per-octave frequency growth.
@export_range(1.0, 4.0) var peaks_lacunarity: float = 2.0
## Domain-warp strength (px) applied to ridge+billow for organic ridgelines.
@export var peaks_warp_amp: float = 30.0
## Domain-warp frequency for the peaks warp.
@export var peaks_warp_freq: float = 0.01
## How much ridge noise lifts highlands into mountains (0 = no peaks).
@export var peak_uplift: float = 0.25
## Height band above sea over which peak uplift ramps in (smaller = abrupt mountains).
@export var highland_range: float = 0.25
## Ceiling on peak height. High (default) = no flattening; lower it to deliberately
## plateau peaks. Replaces the old hard 1.2 clamp.
@export var peak_height_cap: float = 4.0
## Height above which terrain reads as mountain (used by coloring + graph routing).
@export var mountain_threshold: float = 0.65

@export_group("Step 3b - Peaks Detail")
## Fine detail, billow foothills, lowland flattening and the outer coastline -- the
## surface texture + lowland shaping, tuned after the Step 3a mountain structure.
## Fine surface-detail noise scale layered on the highlands (higher = busier).
@export var detail_frequency: float = 0.04
## Amplitude of the fine detail noise added on highlands (texture on peaks).
@export var peak_detail_strength: float = 0.12
## Detail noise is suppressed below this height so coasts/plains stay flat; it ramps
## in above. Raise to widen the flat lowland band.
@export var peak_detail_min_elevation: float = 0.5
## Height band over which the detail noise ramps from off to full.
@export var peak_detail_falloff: float = 0.12
## Billow (rounded foothill) noise scale.
@export var billow_frequency: float = 0.02
## Foothill (billow) amplitude; peaks at mid elevations.
@export var peak_billow_strength: float = 0.12
## Lowland flatten curve. 1.0 = off. Higher (2-4) compresses the above-sea height
## band with a power curve so basins/plains go broad and flat while relief stays
## concentrated in the highlands. The main "give me flat plains" lever.
@export var lowland_flatten: float = 1.0
## Hard outer cutoff radius: no land past this (keeps land off the screen edges).
@export var boundary_radius: float = 0.46
## Width of the soft fade at boundary_radius (smaller = harder map-edge coastline).
@export var boundary_falloff: float = 0.04

@export_group("Step 4 - Erosion")
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

@export_group("Step 5 - Rivers & Lakes")
## Hydrology grid downscale (1 = full res/no pixelation; higher = faster but blocky).
@export_range(1, 1) var river_resolution_divisor: int = 1
## Exponent: wetter cells source more water (0 = humidity ignored).
@export_range(0.0, 2.0) var river_source_humidity_bias: float = 1.0
## Exponent: higher cells source more water.
@export_range(0.0, 2.0) var river_source_elevation_bias: float = 1.0
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
## Min depression-fill above terrain to count as a lake.
@export var lake_min_depth: float = 0.01
## Min connected hydrology cells for a lake (drops 1-px speck pits).
@export var lake_min_area: int = 4
## How far below the spill level the lake surface sits.
@export var lake_carve_depth: float = 0.02
## Dilate lakes outward by this many hydrology px (0 = none).
@export_range(0, 0) var lake_width: int = 0

@export_group("Step 6 - Climate")
## Temperature noise scale (higher = smaller, more varied biome patches).
@export var temp_frequency: float = 0.022
## Humidity noise scale.
@export var humid_frequency: float = 0.026
## Temperature lapse rate: how much temperature drops per unit elevation above sea
## (higher = colder mountains).
@export var temp_lapse_rate: float = 0.5
## Humidity added to cells next to a river (wetter riverbanks).
@export var river_humidity_boost: float = 0.35
## Number of height bands for biome classification. Max land biomes =
## height_bands * temp_bands * humid_bands (default 27 = a 3x3x3 scheme).
@export_range(1, 6) var height_bands: int = 3
## Number of temperature bands.
@export_range(1, 6) var temp_bands: int = 3
## Number of humidity bands.
@export_range(1, 6) var humid_bands: int = 3

@export_group("Step 7 - Graph")
## Cities visited per path, including start & end (abstract spec). Sets the rung
## count together with spec_nodes_between_cities.
@export var spec_cities: int = 5
## Travel nodes between consecutive cities (abstract spec).
@export var spec_nodes_between_cities: int = 2
## Min distinct cities a city can reach next (graph width, abstract spec).
@export var spec_graph_width: int = 3
## Max forward edges per node (the placement edge cap).
@export var spec_outgoing: int = 3
## Variety-trim floor (never orphans a node, abstract spec).
@export var spec_min_outgoing_after_trim: int = 1
## Chance to drop a surplus edge during the spec trim.
@export_range(0.0, 1.0) var spec_edge_trim_chance: float = 0.3
# --- ladder placement (GraphPlacement opts; see place_opts()) ---
## Sections (nodes) per rung where the land is THINNEST.
@export var graph_min_width: int = 1
## Sections (nodes) per rung where the land is WIDEST.
@export var graph_max_width: int = 5
## Node jitter as a fraction of the rung spacing (0 = rigid lattice).
@export_range(0.0, 1.0) var graph_jitter: float = 0.5
## Ignore landmasses smaller than this fraction of the largest one.
@export_range(0.0, 1.0) var graph_landmass_min_frac: float = 0.12
## Branch locality: extra forward links allowed only within this x the nearest
## forward node's distance (scale-free ratio).
@export var graph_lane_tol: float = 1.8
## Isolation cutoff for branching, in rung pitches: a node whose nearest forward
## node is farther than this emits only its single required edge.
@export var graph_branch_local_mul: float = 2.5
## Clearance kept around the start/end poles, in sample spacings.
@export var graph_pole_sep: float = 1.5
## Coastal test radius (fraction of the map diagonal): a node within this of open
## water counts as coastal and may ferry.
@export var coast_radius_ratio: float = 0.014

## Ladder-placement options consumed by GraphPlacement.place().
func place_opts() -> Dictionary:
	return {
		"min_width": graph_min_width,
		"max_width": graph_max_width,
		"jitter": graph_jitter,
		"landmass_min_frac": graph_landmass_min_frac,
		"lane_tol": graph_lane_tol,
		"branch_local_mul": graph_branch_local_mul,
		"pole_sep": graph_pole_sep,
	}
